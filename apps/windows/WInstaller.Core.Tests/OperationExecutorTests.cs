using Xunit;

namespace WInstaller.Core.Tests;

public class OperationExecutorTests
{
    private static (OperationPlan Plan, FakeCommandRunner Runner) HappyPathSetup(long installWimSize = 3_800_000_000)
    {
        var engine = new BootableUsbEngine();
        var iso = TestFixtures.WindowsIso(engine, installWimSize);
        var drive = TestFixtures.RemovableDrive();
        var plan = engine.MakePlan(iso, drive);
        engine.ConfirmErase(drive, drive.DisplayName);

        var runner = new FakeCommandRunner();
        runner.RespondToScript("mount-iso.ps1", """{"DriveLetter":"F","VolumeLabel":"CCCOMA_X64FRE"}""");
        runner.RespondToScript("disk-info.ps1", DiskInfoJson(drive));
        runner.RespondToScript("prepare-usb.ps1", """{"DriveLetter":"E","VolumeLabel":"WINSTALLER"}""");
        runner.RespondToExecutable("robocopy.exe", "", exitCode: 1); // 1 = files copied successfully
        return (plan, runner);
    }

    private static string DiskInfoJson(UsbDrive drive, long? sizeOverride = null, bool isSystem = false) => $$"""
        { "Number": {{drive.DiskNumber}}, "FriendlyName": "{{drive.MediaName}}", "Size": {{sizeOverride ?? drive.Size}},
          "BusType": "USB", "IsBoot": {{(isSystem ? "true" : "false")}}, "IsSystem": {{(isSystem ? "true" : "false")}},
          "IsRemovableMedia": true, "PartitionStyle": "MBR", "Volumes": [] }
        """;

    private static async Task<(List<EngineEvent> Events, Exception? Error)> Collect(OperationExecutor executor, OperationPlan plan)
    {
        var events = new List<EngineEvent>();
        try
        {
            await foreach (var engineEvent in executor.Run(plan))
            {
                events.Add(engineEvent);
            }
            return (events, null);
        }
        catch (Exception exception)
        {
            return (events, exception);
        }
    }

    [Fact]
    public async Task HappyPath_RunsFullChecklistInOrder()
    {
        var (plan, runner) = HappyPathSetup();
        var executor = new OperationExecutor(runner, missingFiles: _ => []);

        var (events, error) = await Collect(executor, plan);

        Assert.Null(error);
        var completedIds = events.Where(e => e.Status == ChecklistStatus.Complete).Select(e => e.Id).ToList();
        Assert.Equal(["mount-iso", "verify-usb", "prepare-usb", "copy-files", "validate", "eject", "completed"], completedIds);

        // The destructive step must come only after the identity re-check.
        var destructiveIndex = runner.Commands.FindIndex(c => c.IsDestructive);
        var identityIndex = runner.Commands.FindIndex(c => c.Arguments.Any(a => a.EndsWith("disk-info.ps1")));
        Assert.True(identityIndex >= 0 && destructiveIndex > identityIndex);

        // Robocopy copies the mounted ISO to the freshly formatted volume.
        var robocopy = runner.Commands.Single(c => c.Executable.EndsWith("robocopy.exe"));
        Assert.Equal([@"F:\", @"E:\"], robocopy.Arguments.Take(2));
        Assert.Contains("/E", robocopy.Arguments);
        Assert.DoesNotContain("/XF", robocopy.Arguments);

        // The read-only ISO mount is always released at the end.
        Assert.Contains(runner.Commands, c => c.Arguments.Any(a => a.EndsWith("dismount-iso.ps1")));
    }

    [Fact]
    public async Task OversizedWim_IsExcludedFromCopyAndSplit()
    {
        var (plan, runner) = HappyPathSetup(installWimSize: 5_100_000_000);
        runner.RespondToScript("split-wim.ps1", """{"Status":"ok"}""");
        var executor = new OperationExecutor(runner, missingFiles: _ => []);

        var (events, error) = await Collect(executor, plan);

        Assert.Null(error);
        Assert.Contains(events, e => e.Id == "split-wim" && e.Status == ChecklistStatus.Complete);

        var robocopy = runner.Commands.Single(c => c.Executable.EndsWith("robocopy.exe"));
        Assert.Contains("/XF", robocopy.Arguments);
        Assert.Contains("install.wim", robocopy.Arguments);
    }

    [Fact]
    public async Task IdentityMismatch_AbortsBeforeAnyDestructiveCommand()
    {
        var (plan, runner) = HappyPathSetup();
        // The disk shrank between confirmation and execution: someone swapped drives.
        runner.RespondToScript("disk-info.ps1", DiskInfoJson(plan.Drive, sizeOverride: 8_000_000_000));
        var executor = new OperationExecutor(runner, missingFiles: _ => []);

        var (_, error) = await Collect(executor, plan);

        var execution = Assert.IsType<ExecutionException>(error);
        Assert.Equal(ExecutionErrorKind.IdentityMismatch, execution.Kind);
        Assert.DoesNotContain(runner.Commands, c => c.IsDestructive);
    }

    [Fact]
    public async Task SystemDisk_IsRefusedBeforeAnyDestructiveCommand()
    {
        var (plan, runner) = HappyPathSetup();
        runner.RespondToScript("disk-info.ps1", DiskInfoJson(plan.Drive, isSystem: true));
        var executor = new OperationExecutor(runner, missingFiles: _ => []);

        var (_, error) = await Collect(executor, plan);

        var execution = Assert.IsType<ExecutionException>(error);
        Assert.Equal(ExecutionErrorKind.RefusedSystemDisk, execution.Kind);
        Assert.DoesNotContain(runner.Commands, c => c.IsDestructive);
    }

    [Fact]
    public async Task ValidationFailure_BlocksSuccessAndSkipsEject()
    {
        var (plan, runner) = HappyPathSetup();
        var executor = new OperationExecutor(runner, missingFiles: _ => [@"E:\sources\boot.wim"]);

        var (events, error) = await Collect(executor, plan);

        var execution = Assert.IsType<ExecutionException>(error);
        Assert.Equal(ExecutionErrorKind.ValidationFailed, execution.Kind);
        Assert.Contains(events, e => e.Id == "validate" && e.Status == ChecklistStatus.Failed);
        Assert.DoesNotContain(runner.Commands, c => c.Arguments.Any(a => a.EndsWith("eject-disk.ps1")));
    }

    [Fact]
    public async Task RobocopyInformationalExitCodesAreSuccess()
    {
        var (plan, runner) = HappyPathSetup();
        runner.RespondToExecutable("robocopy.exe", "", exitCode: 3);
        var executor = new OperationExecutor(runner, missingFiles: _ => []);

        var (_, error) = await Collect(executor, plan);
        Assert.Null(error);
    }

    [Fact]
    public async Task RobocopyFailureExitCodeAborts()
    {
        var (plan, runner) = HappyPathSetup();
        runner.RespondToExecutable("robocopy.exe", "", exitCode: 8);
        var executor = new OperationExecutor(runner, missingFiles: _ => []);

        var (_, error) = await Collect(executor, plan);

        var execution = Assert.IsType<ExecutionException>(error);
        Assert.Equal(ExecutionErrorKind.CommandFailed, execution.Kind);
    }

    [Fact]
    public async Task Simulation_CompletesWithoutRealCommands()
    {
        var engine = new BootableUsbEngine();
        var iso = TestFixtures.WindowsIso(engine);
        var drive = TestFixtures.RemovableDrive();
        var plan = engine.MakePlan(iso, drive);
        engine.ConfirmErase(drive, drive.DisplayName);

        var logger = new LocalLogger(Path.Combine(Path.GetTempPath(), $"winstaller-test-{Guid.NewGuid():N}"));
        var executor = new OperationExecutor(
            runner: new DryRunCommandRunner(plan, stepDelay: TimeSpan.FromMilliseconds(1)),
            logger: logger,
            missingFiles: _ => []);

        var (events, error) = await Collect(executor, plan);

        Assert.Null(error);
        Assert.Contains(events, e => e.Id == "completed" && e.Status == ChecklistStatus.Complete);
        Assert.NotEmpty(logger.AllEntries);
    }

    [Fact]
    public async Task Cancellation_StopsThePipeline()
    {
        var (plan, _) = HappyPathSetup();
        using var source = new CancellationTokenSource();
        var executor = new OperationExecutor(
            runner: new DryRunCommandRunner(plan, stepDelay: TimeSpan.FromSeconds(30)),
            missingFiles: _ => []);

        source.CancelAfter(TimeSpan.FromMilliseconds(50));
        var events = new List<EngineEvent>();
        Exception? error = null;
        try
        {
            await foreach (var engineEvent in executor.Run(plan, source.Token))
            {
                events.Add(engineEvent);
            }
        }
        catch (Exception exception)
        {
            error = exception;
        }

        var execution = Assert.IsType<ExecutionException>(error);
        Assert.Equal(ExecutionErrorKind.Cancelled, execution.Kind);
        Assert.DoesNotContain(events, e => e.Id == "completed");
    }
}
