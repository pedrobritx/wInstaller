using System.Threading.Channels;

namespace WInstaller.Core;

public enum ExecutionErrorKind
{
    IdentityMismatch,
    RefusedSystemDisk,
    MountFailed,
    CommandFailed,
    ValidationFailed,
    Cancelled,
}

public sealed class ExecutionException : Exception
{
    public ExecutionErrorKind Kind { get; }
    public string UserMessage { get; }

    public ExecutionException(ExecutionErrorKind kind, string userMessage, string? detail = null)
        : base(detail ?? userMessage)
    {
        Kind = kind;
        UserMessage = userMessage;
    }

    public static ExecutionException IdentityMismatch(string expected, string found) => new(
        ExecutionErrorKind.IdentityMismatch,
        "The USB drive changed since it was confirmed. wInstaller stopped before erasing anything.",
        $"expected {expected}, found {found}");

    public static ExecutionException RefusedSystemDisk() => new(
        ExecutionErrorKind.RefusedSystemDisk,
        "The target became a system disk. wInstaller refuses to erase system disks.");

    public static ExecutionException MountFailed(string detail) => new(
        ExecutionErrorKind.MountFailed,
        "wInstaller could not mount the ISO to copy its files.",
        detail);

    public static ExecutionException CommandFailed(string step, int exitCode, string message) => new(
        ExecutionErrorKind.CommandFailed,
        $"A step failed while {step}. See technical details for the command output.",
        $"exit {exitCode}: {message}");

    public static ExecutionException ValidationFailed(IReadOnlyList<string> missing) => new(
        ExecutionErrorKind.ValidationFailed,
        $"The bootable USB is missing required files: {string.Join(", ", missing)}.");

    public static ExecutionException Cancelled() => new(
        ExecutionErrorKind.Cancelled,
        "The operation was cancelled.");
}

/// <summary>
/// Executes an <see cref="OperationPlan"/> for real, one step at a time,
/// through an <see cref="ICommandRunner"/>. Emits typed
/// <see cref="EngineEvent"/>s so the UI never has to infer progress from raw
/// command strings (ARCHITECTURE.md).
///
/// The destructive pipeline follows TERMINAL_AUTOMATION.md: the drive identity
/// is re-queried immediately before erase and the run aborts on any mismatch
/// or system disk. Only the erase/format step (and DISM image servicing) runs
/// elevated — a single UAC prompt scoped to that operation, per ADR-0003.
/// </summary>
public sealed class OperationExecutor
{
    public const string TargetVolumeLabel = "WINSTALLER";

    /// <summary>Windows will not format FAT32 volumes larger than 32 GiB.</summary>
    public const long MaxFat32PartitionBytes = 34_359_738_368;

    private readonly ICommandRunner _runner;
    private readonly DiskEnumerator _enumerator;
    private readonly LocalLogger? _logger;
    /// <summary>Injectable so tests can assert validation without a real volume.</summary>
    private readonly Func<IReadOnlyList<string>, IReadOnlyList<string>> _missingFiles;

    public OperationExecutor(
        ICommandRunner? runner = null,
        DiskEnumerator? enumerator = null,
        LocalLogger? logger = null,
        Func<IReadOnlyList<string>, IReadOnlyList<string>>? missingFiles = null)
    {
        _runner = runner ?? new ProcessCommandRunner();
        _enumerator = enumerator ?? new DiskEnumerator(_runner);
        _logger = logger;
        _missingFiles = missingFiles ?? (paths =>
            paths.Where(path => !File.Exists(path) && !Directory.Exists(path)).ToList());
    }

    /// <summary>Runs the plan and streams progress. Cancel via the token.</summary>
    public IAsyncEnumerable<EngineEvent> Run(OperationPlan plan, CancellationToken cancellationToken = default)
    {
        var channel = Channel.CreateUnbounded<EngineEvent>();
        _ = Task.Run(async () =>
        {
            try
            {
                await ExecuteAsync(plan, channel.Writer, cancellationToken).ConfigureAwait(false);
                channel.Writer.TryComplete();
            }
            catch (OperationCanceledException)
            {
                channel.Writer.TryComplete(ExecutionException.Cancelled());
            }
            catch (Exception exception)
            {
                channel.Writer.TryComplete(exception);
            }
        }, CancellationToken.None);
        return channel.Reader.ReadAllAsync(CancellationToken.None);
    }

    private async Task ExecuteAsync(
        OperationPlan plan,
        ChannelWriter<EngineEvent> events,
        CancellationToken cancellationToken)
    {
        var mountedIsoPath = (string?)null;

        async Task CleanupAsync()
        {
            if (mountedIsoPath is null)
            {
                return;
            }
            try
            {
                await _runner.RunAsync(
                    WindowsCommands.Script("dismount-iso.ps1", ["-IsoPath", mountedIsoPath], isDestructive: false),
                    CommandTimeout.Mount,
                    CancellationToken.None).ConfigureAwait(false);
            }
            catch
            {
                // Best-effort cleanup; the ISO mount is read-only either way.
            }
        }

        try
        {
            // 1. Mount the ISO read-only.
            var mountResult = await RunStepAsync(
                "mount-iso", EngineState.AnalyzingIso, "Mount ISO read-only",
                WindowsCommands.Script("mount-iso.ps1", ["-IsoPath", plan.Iso.Path], isDestructive: false),
                CommandTimeout.Mount, events, cancellationToken).ConfigureAwait(false);
            mountedIsoPath = plan.Iso.Path;
            var mount = IsoInspector.ParseMount(mountResult.StandardOutput);
            if (string.IsNullOrEmpty(mount.DriveLetter))
            {
                throw ExecutionException.MountFailed("no drive letter");
            }
            var isoRoot = $@"{mount.DriveLetter}:\";

            // 2. Re-check the USB identity immediately before any destructive work.
            cancellationToken.ThrowIfCancellationRequested();
            var fresh = await _enumerator.InfoAsync(plan.Drive.DiskNumber, cancellationToken).ConfigureAwait(false);
            if (fresh.IsSystemDisk)
            {
                throw ExecutionException.RefusedSystemDisk();
            }
            if (fresh.DiskNumber != plan.Drive.DiskNumber
                || fresh.Size != plan.Drive.Size
                || !string.Equals(fresh.MediaName, plan.Drive.MediaName, StringComparison.Ordinal))
            {
                throw ExecutionException.IdentityMismatch(plan.Drive.Identifier, fresh.Identifier);
            }
            await events.WriteAsync(new EngineEvent(
                "verify-usb", EngineState.AnalyzingUsb, "USB identity re-checked",
                $"{fresh.DisplayName} ({fresh.Identifier}) confirmed.", ChecklistStatus.Complete), cancellationToken).ConfigureAwait(false);

            // 3. Clean + format (DESTRUCTIVE, elevated — the single UAC prompt).
            var diskNumber = plan.Drive.DiskNumber.ToString(System.Globalization.CultureInfo.InvariantCulture);
            var prepareResult = await RunElevatedStepAsync(
                "prepare-usb", EngineState.PreparingDrive, "Erase and format USB drive",
                "prepare-usb.ps1",
                [
                    "-DiskNumber", diskNumber,
                    "-Label", TargetVolumeLabel,
                    "-SizeLimitBytes", MaxFat32PartitionBytes.ToString(System.Globalization.CultureInfo.InvariantCulture),
                ],
                isDestructive: true, CommandTimeout.Format, events, cancellationToken).ConfigureAwait(false);
            var target = IsoInspector.ParseMount(prepareResult);
            if (string.IsNullOrEmpty(target.DriveLetter))
            {
                throw ExecutionException.CommandFailed("preparing the USB drive", 0, "the formatted volume has no drive letter");
            }
            var targetRoot = $@"{target.DriveLetter}:\";

            // 4. Copy installer files. When a WIM split is required, exclude the
            //    oversized image and split it separately in step 5.
            var robocopyArgs = new List<string> { isoRoot, targetRoot, "/E", "/NFL", "/NDL", "/NJH", "/NP" };
            if (plan.Strategy.RequiresWimSplit)
            {
                robocopyArgs.Add("/XF");
                robocopyArgs.Add("install.wim");
            }
            _ = await RunStepAsync(
                "copy-files", EngineState.CopyingFiles, "Copy installer files",
                new PlannedCommand(WindowsCommands.SystemExecutable("robocopy.exe"), robocopyArgs, IsDestructive: false),
                CommandTimeout.Watched, events, cancellationToken,
                // Robocopy exit codes below 8 mean success (possibly with
                // informational flags); 8+ means at least one copy failed.
                succeeded: exitCode => exitCode < 8).ConfigureAwait(false);

            // 5. Split the Windows image when it exceeds the FAT32 file limit.
            if (plan.Strategy.RequiresWimSplit)
            {
                _ = await RunElevatedStepAsync(
                    "split-wim", EngineState.SplittingWim, "Split oversized Windows image",
                    "split-wim.ps1",
                    [
                        "-ImageFile", Path.Combine(isoRoot, "sources", "install.wim"),
                        "-SwmFile", Path.Combine(targetRoot, "sources", "install.swm"),
                        "-PartSizeMB", "3800",
                    ],
                    isDestructive: false, CommandTimeout.Watched, events, cancellationToken).ConfigureAwait(false);
            }

            // 6. Validate required boot files exist on the target.
            var missing = _missingFiles(ExpectedFiles(plan, targetRoot));
            if (missing.Count > 0)
            {
                await events.WriteAsync(new EngineEvent(
                    "validate", EngineState.Validating, "Boot validation failed",
                    string.Join(", ", missing), ChecklistStatus.Failed), cancellationToken).ConfigureAwait(false);
                throw ExecutionException.ValidationFailed(missing);
            }
            await events.WriteAsync(new EngineEvent(
                "validate", EngineState.Validating, "Boot files validated",
                string.Join(", ", plan.ValidationChecks), ChecklistStatus.Complete), cancellationToken).ConfigureAwait(false);

            // 7. Eject safely.
            _ = await RunStepAsync(
                "eject", EngineState.Ejecting, "Eject USB safely",
                WindowsCommands.Script("eject-disk.ps1", ["-DriveLetter", target.DriveLetter!], isDestructive: false),
                CommandTimeout.Eject, events, cancellationToken).ConfigureAwait(false);

            await CleanupAsync().ConfigureAwait(false);
            mountedIsoPath = null;
            await events.WriteAsync(new EngineEvent(
                "completed", EngineState.Completed, "Bootable USB ready",
                $"{plan.Iso.DetectedOs.DisplayName} on {plan.Drive.DisplayName}.", ChecklistStatus.Complete), cancellationToken).ConfigureAwait(false);
        }
        catch
        {
            await CleanupAsync().ConfigureAwait(false);
            throw;
        }
    }

    private async Task<CommandResult> RunStepAsync(
        string id,
        EngineState state,
        string title,
        PlannedCommand command,
        CommandTimeout timeout,
        ChannelWriter<EngineEvent> events,
        CancellationToken cancellationToken,
        Func<int, bool>? succeeded = null)
    {
        cancellationToken.ThrowIfCancellationRequested();
        await events.WriteAsync(new EngineEvent(id, state, title, "Running…", ChecklistStatus.Running), cancellationToken).ConfigureAwait(false);

        var result = await _runner.RunAsync(command, timeout, cancellationToken).ConfigureAwait(false);
        _logger?.Record(new LogEntry(
            OperationId: id,
            Tool: command.Executable,
            Arguments: command.Arguments,
            ExitCode: result.ExitCode,
            UserMessage: title,
            TechnicalDetail: result.StandardError));

        var isSuccess = succeeded?.Invoke(result.ExitCode) ?? result.Succeeded;
        if (!isSuccess)
        {
            await events.WriteAsync(new EngineEvent(
                id, EngineState.Failed, title, $"Failed (exit {result.ExitCode}).", ChecklistStatus.Failed), cancellationToken).ConfigureAwait(false);
            throw ExecutionException.CommandFailed(title, result.ExitCode, result.StandardError);
        }

        await events.WriteAsync(new EngineEvent(id, state, title, "Complete.", ChecklistStatus.Complete), cancellationToken).ConfigureAwait(false);
        return result;
    }

    /// <summary>
    /// Runs a helper script elevated. ShellExecute "runas" cannot redirect
    /// output, so the script writes its JSON result to a temp file the
    /// executor reads back; runners that do capture stdout (dry-run) are
    /// supported by falling back to standard output.
    /// </summary>
    private async Task<string> RunElevatedStepAsync(
        string id,
        EngineState state,
        string title,
        string scriptName,
        IReadOnlyList<string> parameters,
        bool isDestructive,
        CommandTimeout timeout,
        ChannelWriter<EngineEvent> events,
        CancellationToken cancellationToken)
    {
        var resultPath = Path.Combine(Path.GetTempPath(), $"winstaller-{id}-{Guid.NewGuid():N}.json");
        try
        {
            var arguments = new List<string>(parameters) { "-ResultPath", resultPath };
            var command = WindowsCommands.Script(scriptName, arguments, isDestructive, requiresElevation: true);
            var result = await RunStepAsync(id, state, title, command, timeout, events, cancellationToken).ConfigureAwait(false);
            return File.Exists(resultPath)
                ? await File.ReadAllTextAsync(resultPath, cancellationToken).ConfigureAwait(false)
                : result.StandardOutput;
        }
        finally
        {
            try
            {
                File.Delete(resultPath);
            }
            catch
            {
                // Leaving a stray temp file behind is harmless.
            }
        }
    }

    private static IReadOnlyList<string> ExpectedFiles(OperationPlan plan, string targetRoot)
    {
        switch (plan.Iso.DetectedOs.Kind)
        {
            case OperatingSystemKind.Windows:
                var files = new List<string>
                {
                    Path.Combine(targetRoot, "sources", "boot.wim"),
                    Path.Combine(targetRoot, "efi"),
                };
                files.Add(plan.Strategy.RequiresWimSplit
                    ? Path.Combine(targetRoot, "sources", "install.swm")
                    : Path.Combine(targetRoot, "sources", "install.wim"));
                return files;
            default:
                return [targetRoot];
        }
    }
}
