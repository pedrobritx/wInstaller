using System.Diagnostics;

namespace WInstaller.Core;

/// <summary>
/// The result of running a single command. Command output is treated as
/// untrusted input (TERMINAL_AUTOMATION.md): callers parse it defensively and
/// never evaluate it as code.
/// </summary>
public sealed record CommandResult(
    string Executable,
    IReadOnlyList<string> Arguments,
    string StandardOutput,
    string StandardError,
    int ExitCode,
    DateTimeOffset StartedAt,
    DateTimeOffset FinishedAt)
{
    public bool Succeeded => ExitCode == 0;
}

/// <summary>Timeout classes recommended by TERMINAL_AUTOMATION.md.</summary>
public readonly struct CommandTimeout
{
    public TimeSpan? Interval { get; }

    private CommandTimeout(TimeSpan? interval) => Interval = interval;

    /// <summary>Fast metadata query (generous enough for PowerShell startup).</summary>
    public static readonly CommandTimeout Metadata = new(TimeSpan.FromSeconds(30));
    /// <summary>Mount / unmount an image.</summary>
    public static readonly CommandTimeout Mount = new(TimeSpan.FromSeconds(90));
    /// <summary>Clean + format a removable disk.</summary>
    public static readonly CommandTimeout Format = new(TimeSpan.FromSeconds(300));
    /// <summary>Eject a volume.</summary>
    public static readonly CommandTimeout Eject = new(TimeSpan.FromSeconds(60));
    /// <summary>Long-running work watched by progress rather than a hard timeout.</summary>
    public static readonly CommandTimeout Watched = new(null);

    public static CommandTimeout Seconds(double seconds) => new(TimeSpan.FromSeconds(seconds));
}

public enum CommandRunnerErrorKind
{
    LaunchFailed,
    TimedOut,
    ElevationDeclined,
    Cancelled,
}

public sealed class CommandRunnerException : Exception
{
    public CommandRunnerErrorKind Kind { get; }

    public CommandRunnerException(CommandRunnerErrorKind kind, string message)
        : base(message)
    {
        Kind = kind;
    }
}

/// <summary>
/// Abstraction over command execution so the whole pipeline stays testable
/// without touching a real disk. Commands are always an executable plus an
/// argument array — never a shell-interpolated string.
/// </summary>
public interface ICommandRunner
{
    Task<CommandResult> RunAsync(PlannedCommand command, CommandTimeout timeout, CancellationToken cancellationToken = default);
}

/// <summary>Well-known executable and helper-script locations.</summary>
public static class WindowsCommands
{
    /// <summary>
    /// Absolute path of a tool under System32 (falls back to the bare name off
    /// the Windows system directory, e.g. in unit tests on other OSes).
    /// </summary>
    public static string SystemExecutable(string name)
    {
        var system = Environment.GetFolderPath(Environment.SpecialFolder.System);
        return string.IsNullOrEmpty(system) ? name : Path.Combine(system, name);
    }

    /// <summary>Windows PowerShell 5.1, present on every supported Windows install.</summary>
    public static string PowerShell => SystemExecutable(Path.Combine("WindowsPowerShell", "v1.0", "powershell.exe"));

    /// <summary>Directory holding the bundled .ps1 helpers, next to the app binaries.</summary>
    public static string ScriptsDirectory => Path.Combine(AppContext.BaseDirectory, "Scripts");

    /// <summary>
    /// Builds an argv-only PowerShell invocation of a bundled helper script.
    /// Parameters are passed as separate argv entries, never interpolated into
    /// a command string.
    /// </summary>
    public static PlannedCommand Script(
        string scriptName,
        IReadOnlyList<string> parameters,
        bool isDestructive,
        bool requiresElevation = false)
    {
        var arguments = new List<string>
        {
            "-NoProfile",
            "-NonInteractive",
            "-ExecutionPolicy", "Bypass",
            "-File", Path.Combine(ScriptsDirectory, scriptName),
        };
        arguments.AddRange(parameters);
        return new PlannedCommand(PowerShell, arguments, isDestructive, requiresElevation);
    }
}

/// <summary>
/// Runs real processes. Non-elevated commands are captured via redirected
/// stdout/stderr. Elevated commands (ADR-0003: a single UAC prompt scoped to
/// the destructive step, never the whole app) run through ShellExecute
/// "runas", which cannot redirect output — those scripts report their result
/// through a caller-provided result file instead.
/// </summary>
public sealed class ProcessCommandRunner : ICommandRunner
{
    public async Task<CommandResult> RunAsync(PlannedCommand command, CommandTimeout timeout, CancellationToken cancellationToken = default)
    {
        var startedAt = DateTimeOffset.Now;
        var info = new ProcessStartInfo
        {
            FileName = command.Executable,
            UseShellExecute = command.RequiresElevation,
            CreateNoWindow = true,
            RedirectStandardOutput = !command.RequiresElevation,
            RedirectStandardError = !command.RequiresElevation,
        };
        if (command.RequiresElevation)
        {
            info.Verb = "runas";
            info.WindowStyle = ProcessWindowStyle.Hidden;
        }
        foreach (var argument in command.Arguments)
        {
            info.ArgumentList.Add(argument);
        }

        Process process;
        try
        {
            process = Process.Start(info) ?? throw new CommandRunnerException(
                CommandRunnerErrorKind.LaunchFailed, $"Could not start {command.Executable}.");
        }
        catch (System.ComponentModel.Win32Exception exception) when (exception.NativeErrorCode == 1223)
        {
            // ERROR_CANCELLED: the user declined the UAC prompt.
            throw new CommandRunnerException(
                CommandRunnerErrorKind.ElevationDeclined,
                "The administrator prompt was declined, so the drive was not modified.");
        }
        catch (Exception exception) when (exception is not CommandRunnerException)
        {
            throw new CommandRunnerException(CommandRunnerErrorKind.LaunchFailed, exception.Message);
        }

        using (process)
        {
            var stdoutTask = command.RequiresElevation
                ? Task.FromResult(string.Empty)
                : process.StandardOutput.ReadToEndAsync(cancellationToken);
            var stderrTask = command.RequiresElevation
                ? Task.FromResult(string.Empty)
                : process.StandardError.ReadToEndAsync(cancellationToken);

            using var timeoutSource = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            if (timeout.Interval is { } interval)
            {
                timeoutSource.CancelAfter(interval);
            }

            try
            {
                await process.WaitForExitAsync(timeoutSource.Token).ConfigureAwait(false);
            }
            catch (OperationCanceledException)
            {
                try
                {
                    process.Kill(entireProcessTree: true);
                }
                catch
                {
                    // The process may have exited between the timeout and the kill.
                }

                if (cancellationToken.IsCancellationRequested)
                {
                    throw new OperationCanceledException(cancellationToken);
                }
                throw new CommandRunnerException(
                    CommandRunnerErrorKind.TimedOut,
                    $"{Path.GetFileName(command.Executable)} did not finish within {timeout.Interval?.TotalSeconds:0} seconds.");
            }

            var standardOutput = await stdoutTask.ConfigureAwait(false);
            var standardError = await stderrTask.ConfigureAwait(false);

            return new CommandResult(
                command.Executable,
                command.Arguments,
                standardOutput,
                standardError,
                process.ExitCode,
                startedAt,
                DateTimeOffset.Now);
        }
    }
}
