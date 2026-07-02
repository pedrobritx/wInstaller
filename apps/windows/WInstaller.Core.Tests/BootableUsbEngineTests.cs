using Xunit;

namespace WInstaller.Core.Tests;

public class BootableUsbEngineTests
{
    [Fact]
    public void AnalyzeIso_DetectsWindowsWithHighConfidence()
    {
        var engine = new BootableUsbEngine();
        var iso = TestFixtures.WindowsIso(engine);

        Assert.Equal(OperatingSystemKind.Windows, iso.DetectedOs.Kind);
        Assert.Equal(DetectionConfidence.High, iso.Confidence);
        Assert.NotNull(iso.WindowsImageInfo);
        Assert.Equal(3_800_000_000, iso.WindowsImageInfo!.InstallWimSize);
        Assert.Contains("sources/boot.wim", iso.BootFiles);
        Assert.Equal(EngineState.WaitingForUsb, engine.State);
    }

    [Fact]
    public void AnalyzeIso_NormalizesBackslashesAndCase()
    {
        var engine = new BootableUsbEngine();
        var iso = engine.AnalyzeIso(
            path: @"C:\isos\win.iso",
            size: 5_000_000_000,
            volumeLabel: null,
            directoryEntries: [@"SETUP.EXE", @"sources\BOOT.WIM", @"sources\install.wim", @"efi\boot\bootx64.efi"],
            fileSizes: new Dictionary<string, long>());

        Assert.Equal(OperatingSystemKind.Windows, iso.DetectedOs.Kind);
        Assert.Equal(DetectionConfidence.High, iso.Confidence);
    }

    [Fact]
    public void AnalyzeIso_ThreeMarkersIsMediumConfidence()
    {
        var engine = new BootableUsbEngine();
        var iso = engine.AnalyzeIso(
            path: @"C:\isos\win.iso",
            size: 5_000_000_000,
            volumeLabel: null,
            directoryEntries: ["setup.exe", "sources/boot.wim", "sources/install.esd"],
            fileSizes: new Dictionary<string, long>());

        Assert.Equal(DetectionConfidence.Medium, iso.Confidence);
        Assert.True(iso.WindowsImageInfo!.HasInstallEsd);
    }

    [Fact]
    public void AnalyzeIso_DetectsLinuxFromMarkers()
    {
        var engine = new BootableUsbEngine();
        var iso = engine.AnalyzeIso(
            path: "/isos/ubuntu.iso",
            size: 4_000_000_000,
            volumeLabel: "Ubuntu 24.04 LTS amd64",
            directoryEntries: ["casper/vmlinuz", ".disk/info", "efi/boot/bootx64.efi", "boot/grub/grub.cfg"],
            fileSizes: new Dictionary<string, long>());

        Assert.Equal(OperatingSystemKind.Linux, iso.DetectedOs.Kind);
        Assert.Equal("Ubuntu 24.04 LTS amd64", iso.DetectedOs.Detail);
        Assert.Equal(DetectionConfidence.Medium, iso.Confidence);
    }

    [Fact]
    public void AnalyzeIso_UnknownMediaThrows()
    {
        var engine = new BootableUsbEngine();
        var exception = Assert.Throws<BootableUsbException>(() => engine.AnalyzeIso(
            path: @"C:\isos\data.iso",
            size: 1_000_000,
            volumeLabel: "DATA",
            directoryEntries: ["readme.txt", "photos/cat.jpg"],
            fileSizes: new Dictionary<string, long>()));

        Assert.Equal(UsbErrorKind.UnsupportedIso, exception.Kind);
        Assert.Equal(EngineState.Failed, engine.State);
    }

    [Theory]
    [InlineData(4_294_967_294, false)]
    [InlineData(4_294_967_295, false)]
    [InlineData(4_294_967_296, true)]
    public void WindowsImageInfo_SplitsOnlyAboveFat32Limit(long wimSize, bool expected)
    {
        var info = new WindowsImageInfo(wimSize, HasInstallEsd: false);
        Assert.Equal(expected, info.RequiresSplit);
    }

    [Fact]
    public void MakePlan_RefusesNonRemovableDrive()
    {
        var engine = new BootableUsbEngine();
        var iso = TestFixtures.WindowsIso(engine);
        var fixedDisk = TestFixtures.RemovableDrive() with { IsRemovable = false };

        var exception = Assert.Throws<BootableUsbException>(() => engine.MakePlan(iso, fixedDisk));
        Assert.Equal(UsbErrorKind.DiskNotRemovable, exception.Kind);
        Assert.Equal(EngineState.Failed, engine.State);
    }

    [Fact]
    public void MakePlan_RefusesSystemDisk()
    {
        var engine = new BootableUsbEngine();
        var iso = TestFixtures.WindowsIso(engine);
        var systemDisk = TestFixtures.SystemDrive() with { IsRemovable = true };

        var exception = Assert.Throws<BootableUsbException>(() => engine.MakePlan(iso, systemDisk));
        Assert.Equal(UsbErrorKind.DiskIsSystem, exception.Kind);
    }

    [Fact]
    public void MakePlan_RefusesUndersizedDrive()
    {
        var engine = new BootableUsbEngine();
        var iso = TestFixtures.WindowsIso(engine);
        var tinyDrive = TestFixtures.RemovableDrive(size: 1_000_000_000);

        var exception = Assert.Throws<BootableUsbException>(() => engine.MakePlan(iso, tinyDrive));
        Assert.Equal(UsbErrorKind.InsufficientCapacity, exception.Kind);
    }

    [Fact]
    public void MakePlan_ReportsMissingTools()
    {
        var engine = new BootableUsbEngine();
        var iso = TestFixtures.WindowsIso(engine);

        var exception = Assert.Throws<BootableUsbException>(() =>
            engine.MakePlan(iso, TestFixtures.RemovableDrive(), new ToolAvailability(Robocopy: false)));
        Assert.Equal(UsbErrorKind.MissingTool, exception.Kind);
        Assert.Contains("robocopy", exception.UserMessage);
    }

    [Fact]
    public void MakePlan_RequiresDismOnlyWhenSplitting()
    {
        var engine = new BootableUsbEngine();
        var smallWim = TestFixtures.WindowsIso(engine);
        var noDism = new ToolAvailability(Dism: false);

        // No split required: DISM absence is fine.
        var plan = engine.MakePlan(smallWim, TestFixtures.RemovableDrive(), noDism);
        Assert.False(plan.Strategy.RequiresWimSplit);

        var engine2 = new BootableUsbEngine();
        var bigWim = TestFixtures.WindowsIso(engine2, installWimSize: 5_100_000_000);
        var exception = Assert.Throws<BootableUsbException>(() =>
            engine2.MakePlan(bigWim, TestFixtures.RemovableDrive(), noDism));
        Assert.Equal(UsbErrorKind.MissingTool, exception.Kind);
    }

    [Fact]
    public void MakePlan_MarksExactlyOneDestructiveElevatedStep()
    {
        var engine = new BootableUsbEngine();
        var plan = engine.MakePlan(TestFixtures.WindowsIso(engine), TestFixtures.RemovableDrive());

        var destructive = Assert.Single(plan.DestructiveSteps);
        Assert.Equal("prepare-usb", destructive.Id);
        Assert.True(destructive.Command!.RequiresElevation);
        Assert.True(plan.RequiresAuthorization);
        Assert.Equal(EngineState.AwaitingEraseConfirmation, engine.State);
    }

    [Fact]
    public void MakePlan_AddsSplitStepAndWarningsForOversizedWim()
    {
        var engine = new BootableUsbEngine();
        var iso = TestFixtures.WindowsIso(engine, installWimSize: 5_100_000_000);
        var plan = engine.MakePlan(iso, TestFixtures.RemovableDrive());

        Assert.True(plan.Strategy.RequiresWimSplit);
        Assert.Contains(plan.Steps, step => step.Id == "split-wim");
        Assert.Contains(plan.Strategy.Warnings, warning => warning.Contains("split"));
        // 64 GB stick: warn that the FAT32 partition is capped at 32 GB.
        Assert.Contains(plan.Strategy.Warnings, warning => warning.Contains("32 GB"));
        Assert.Contains(@"sources\install.swm", plan.ValidationChecks);
    }

    [Fact]
    public void ConfirmErase_RejectsMismatchedName()
    {
        var engine = new BootableUsbEngine();
        var drive = TestFixtures.RemovableDrive();
        _ = engine.MakePlan(TestFixtures.WindowsIso(engine), drive);

        var exception = Assert.Throws<BootableUsbException>(() => engine.ConfirmErase(drive, "wrong name"));
        Assert.Equal(UsbErrorKind.ConfirmationMismatch, exception.Kind);
    }

    [Fact]
    public void ConfirmErase_RequiresPlanningFirst()
    {
        var engine = new BootableUsbEngine();
        var exception = Assert.Throws<BootableUsbException>(() =>
            engine.ConfirmErase(TestFixtures.RemovableDrive(), "Kingston DataTraveler 3.0"));
        Assert.Equal(UsbErrorKind.InvalidState, exception.Kind);
    }

    [Fact]
    public void ConfirmErase_ExactNameUnlocksExecution()
    {
        var engine = new BootableUsbEngine();
        var drive = TestFixtures.RemovableDrive();
        _ = engine.MakePlan(TestFixtures.WindowsIso(engine), drive);

        engine.ConfirmErase(drive, "Kingston DataTraveler 3.0");
        Assert.Equal(EngineState.PreparingDrive, engine.State);
    }

    [Fact]
    public void DryRunEvents_IncludeWimRowOnlyWhenSplitting()
    {
        var engine = new BootableUsbEngine();
        var plan = engine.MakePlan(TestFixtures.WindowsIso(engine), TestFixtures.RemovableDrive());
        Assert.DoesNotContain(engine.DryRunEvents(plan), e => e.Id == "wim");

        var engine2 = new BootableUsbEngine();
        var bigPlan = engine2.MakePlan(
            TestFixtures.WindowsIso(engine2, installWimSize: 5_100_000_000),
            TestFixtures.RemovableDrive());
        Assert.Contains(engine2.DryRunEvents(bigPlan), e => e.Id == "wim");
    }
}
