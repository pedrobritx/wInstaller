namespace WInstaller.Core.Tests;

/// <summary>
/// Records every command the pipeline asks for and answers from scripted
/// responses, so executor tests never touch a real process or disk.
/// </summary>
internal sealed class FakeCommandRunner : ICommandRunner
{
    public sealed record Response(string StandardOutput = "", string StandardError = "", int ExitCode = 0);

    private readonly Dictionary<string, Response> _scriptResponses = new(StringComparer.OrdinalIgnoreCase);
    private readonly Dictionary<string, Response> _executableResponses = new(StringComparer.OrdinalIgnoreCase);

    public List<PlannedCommand> Commands { get; } = [];

    public void RespondToScript(string scriptName, string standardOutput, int exitCode = 0, string standardError = "") =>
        _scriptResponses[scriptName] = new Response(standardOutput, standardError, exitCode);

    public void RespondToExecutable(string executableName, string standardOutput, int exitCode = 0, string standardError = "") =>
        _executableResponses[executableName] = new Response(standardOutput, standardError, exitCode);

    public Task<CommandResult> RunAsync(PlannedCommand command, CommandTimeout timeout, CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        Commands.Add(command);

        var script = command.Arguments
            .Select(Path.GetFileName)
            .FirstOrDefault(name => name?.EndsWith(".ps1", StringComparison.OrdinalIgnoreCase) == true);

        Response response;
        if (script is not null && _scriptResponses.TryGetValue(script, out var scripted))
        {
            response = scripted;
        }
        else if (_executableResponses.TryGetValue(Path.GetFileName(command.Executable), out var byExecutable))
        {
            response = byExecutable;
        }
        else
        {
            response = new Response();
        }

        var now = DateTimeOffset.Now;
        return Task.FromResult(new CommandResult(
            command.Executable,
            command.Arguments,
            response.StandardOutput,
            response.StandardError,
            response.ExitCode,
            now,
            now));
    }
}
