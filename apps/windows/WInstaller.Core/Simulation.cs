using System.Text.Json;

namespace WInstaller.Core;

/// <summary>
/// Simulate (dry-run) support: an <see cref="OperationExecutor"/> whose runner
/// answers every planned command with a canned success and never touches a
/// disk. The UI runs the exact same pipeline, checklist, and logging as a real
/// run (USER_FLOW.md's Simulate toggle).
/// </summary>
public static class Simulation
{
    public static OperationExecutor Executor(OperationPlan plan, LocalLogger? logger = null) => new(
        runner: new DryRunCommandRunner(plan),
        logger: logger,
        missingFiles: _ => []);
}

/// <summary>
/// Answers each helper script with plausible output: the mounted ISO gets a
/// fake drive letter, the identity re-check echoes the planned drive back, and
/// destructive commands succeed without running anything.
/// </summary>
public sealed class DryRunCommandRunner : ICommandRunner
{
    private readonly OperationPlan _plan;
    private readonly TimeSpan _stepDelay;

    public DryRunCommandRunner(OperationPlan plan, TimeSpan? stepDelay = null)
    {
        _plan = plan;
        _stepDelay = stepDelay ?? TimeSpan.FromMilliseconds(400);
    }

    public async Task<CommandResult> RunAsync(PlannedCommand command, CommandTimeout timeout, CancellationToken cancellationToken = default)
    {
        await Task.Delay(_stepDelay, cancellationToken).ConfigureAwait(false);

        var startedAt = DateTimeOffset.Now;
        var output = Output(command);
        return new CommandResult(
            command.Executable,
            command.Arguments,
            output,
            StandardError: "",
            ExitCode: 0,
            startedAt,
            DateTimeOffset.Now);
    }

    private string Output(PlannedCommand command)
    {
        var script = command.Arguments
            .Select(Path.GetFileName)
            .FirstOrDefault(name => name?.EndsWith(".ps1", StringComparison.OrdinalIgnoreCase) == true);

        switch (script)
        {
            case "mount-iso.ps1":
                return """{"DriveLetter":"W","VolumeLabel":"SIMULATED"}""";
            case "disk-info.ps1":
                // Echo the planned drive so the identity safety gate passes.
                return JsonSerializer.Serialize(new
                {
                    Number = _plan.Drive.DiskNumber,
                    FriendlyName = _plan.Drive.MediaName,
                    Size = _plan.Drive.Size,
                    BusType = _plan.Drive.ConnectionType,
                    IsBoot = false,
                    IsSystem = false,
                    IsRemovableMedia = true,
                    PartitionStyle = _plan.Drive.PartitionScheme,
                    Volumes = _plan.Drive.Volumes.Select(volume => new
                    {
                        DriveLetter = (string?)null,
                        FileSystemLabel = volume,
                        FileSystem = _plan.Drive.FileSystem,
                    }),
                });
            case "prepare-usb.ps1":
                return """{"DriveLetter":"X"}""";
            default:
                return "";
        }
    }
}
