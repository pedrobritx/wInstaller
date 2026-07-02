namespace WInstaller.Core;

/// <summary>
/// The typed state machine behind the assistant flow (BOOTABLE_USB_ENGINE.md).
/// Pure logic only: analysis and planning never touch a real disk, so every
/// safety gate is unit-testable. This is the Windows-native port of the macOS
/// <c>BootableUSBEngine</c>; the OS-specific commands it plans differ, the
/// detection logic and safety rules do not.
/// </summary>
public sealed class BootableUsbEngine
{
    public EngineState State { get; private set; } = EngineState.Idle;

    public void Reset() => State = EngineState.Idle;

    /// <summary>
    /// Classifies an ISO from its directory listing. Detection is marker-based:
    /// Windows media must expose setup.exe / boot.wim / install.wim|esd /
    /// bootx64.efi; Linux media is recognized by its boot loaders and metadata.
    /// </summary>
    public InstallerIso AnalyzeIso(
        string path,
        long size,
        string? volumeLabel,
        IReadOnlyList<string> directoryEntries,
        IReadOnlyDictionary<string, long> fileSizes)
    {
        State = EngineState.AnalyzingIso;

        var normalized = directoryEntries.Select(Normalize).ToHashSet();
        var bootFiles = normalized
            .Where(p => p.Contains("boot") || p.Contains("efi") || p.Contains("isolinux") || p.Contains("syslinux"))
            .OrderBy(p => p, StringComparer.Ordinal)
            .ToList();

        string[] windowsMarkers =
        [
            "setup.exe",
            "sources/boot.wim",
            "sources/install.wim",
            "sources/install.esd",
            "efi/boot/bootx64.efi",
        ];
        var windowsMatches = windowsMarkers.Count(normalized.Contains);

        string[] linuxMarkers = ["efi", "isolinux", "syslinux", "casper", ".disk/info"];
        var hasLinuxMarkers = linuxMarkers.Any(marker =>
            normalized.Contains(marker) || normalized.Any(entry => entry.StartsWith(marker + "/", StringComparison.Ordinal)));

        DetectedOperatingSystem detectedOs;
        DetectionConfidence confidence;
        WindowsImageInfo? windowsImageInfo;

        if (windowsMatches >= 3)
        {
            detectedOs = DetectedOperatingSystem.Windows();
            confidence = windowsMatches >= 4 ? DetectionConfidence.High : DetectionConfidence.Medium;
            long? wimSize = fileSizes.TryGetValue("sources/install.wim", out var natural)
                ? natural
                : fileSizes.TryGetValue("SOURCES/INSTALL.WIM", out var upper) ? upper : null;
            windowsImageInfo = new WindowsImageInfo(wimSize, normalized.Contains("sources/install.esd"));
        }
        else if (hasLinuxMarkers)
        {
            detectedOs = DetectedOperatingSystem.Linux(volumeLabel);
            confidence = DetectionConfidence.Medium;
            windowsImageInfo = null;
        }
        else
        {
            detectedOs = DetectedOperatingSystem.Unknown;
            confidence = DetectionConfidence.Low;
            windowsImageInfo = null;
        }

        var iso = new InstallerIso(
            Path: path,
            DisplayName: System.IO.Path.GetFileName(path),
            Size: size,
            VolumeLabel: volumeLabel,
            DetectedOs: detectedOs,
            Confidence: confidence,
            BootFiles: bootFiles,
            WindowsImageInfo: windowsImageInfo);

        if (confidence == DetectionConfidence.Low)
        {
            State = EngineState.Failed;
            throw new BootableUsbException(UsbErrorKind.UnsupportedIso);
        }

        State = EngineState.WaitingForUsb;
        return iso;
    }

    /// <summary>
    /// Builds the full operation plan and enforces every pre-flight safety gate.
    /// Planned commands are argv arrays (never shell strings) and destructive
    /// steps are marked explicitly (TERMINAL_AUTOMATION.md).
    /// </summary>
    public OperationPlan MakePlan(InstallerIso iso, UsbDrive drive, ToolAvailability? tools = null)
    {
        tools ??= new ToolAvailability();
        State = EngineState.Planning;

        if (!drive.IsRemovable)
        {
            State = EngineState.Failed;
            throw new BootableUsbException(UsbErrorKind.DiskNotRemovable);
        }
        if (drive.IsSystemDisk)
        {
            State = EngineState.Failed;
            throw new BootableUsbException(UsbErrorKind.DiskIsSystem);
        }
        if (drive.Size < iso.Size)
        {
            State = EngineState.Failed;
            throw new BootableUsbException(UsbErrorKind.InsufficientCapacity);
        }
        if (!tools.PowerShell)
        {
            State = EngineState.Failed;
            throw new BootableUsbException(UsbErrorKind.MissingTool, "powershell.exe");
        }
        if (!tools.Robocopy)
        {
            State = EngineState.Failed;
            throw new BootableUsbException(UsbErrorKind.MissingTool, "robocopy.exe");
        }

        var requiresWimSplit = iso.WindowsImageInfo?.RequiresSplit == true;
        if (requiresWimSplit && !tools.Dism)
        {
            State = EngineState.Failed;
            throw new BootableUsbException(UsbErrorKind.MissingTool, "dism.exe");
        }

        var strategy = new BootStrategy(
            TargetPartitionScheme: "GPT",
            TargetFileSystem: "FAT32",
            RequiresErase: true,
            RequiresWimSplit: requiresWimSplit,
            Warnings: StrategyWarnings(iso, drive, requiresWimSplit));

        var diskNumber = drive.DiskNumber.ToString(System.Globalization.CultureInfo.InvariantCulture);
        var steps = new List<OperationStep>
        {
            new(
                "mount-iso", "Mount ISO read-only", "Inspect the installer without modifying it.",
                OperationKind.AnalyzeIso,
                WindowsCommands.Script("mount-iso.ps1", ["-IsoPath", iso.Path], isDestructive: false)),
            new(
                "verify-usb", "Re-check USB identity", $"Confirm {drive.DisplayName} is still {drive.Identifier}.",
                OperationKind.VerifyUsb,
                WindowsCommands.Script("disk-info.ps1", ["-DiskNumber", diskNumber], isDestructive: false)),
            new(
                "prepare-usb", "Erase and format USB drive", "Clean the disk, create a GPT/FAT32 installer volume.",
                OperationKind.EraseDisk,
                WindowsCommands.Script(
                    "prepare-usb.ps1",
                    ["-DiskNumber", diskNumber, "-Label", OperationExecutor.TargetVolumeLabel],
                    isDestructive: true,
                    requiresElevation: true)),
            new(
                "copy-files", "Copy installer files", "Preserve the ISO directory structure on the target volume.",
                OperationKind.CopyFiles,
                new PlannedCommand(
                    WindowsCommands.SystemExecutable("robocopy.exe"),
                    ["<mounted-iso>", "<target-volume>", "/E"],
                    IsDestructive: false)),
        };

        if (requiresWimSplit)
        {
            steps.Add(new(
                "split-wim", "Split oversized Windows image", "Create setup-compatible SWM parts below the FAT32 file limit.",
                OperationKind.SplitWim,
                WindowsCommands.Script(
                    "split-wim.ps1",
                    ["-ImageFile", @"<mounted-iso>\sources\install.wim", "-SwmFile", @"<target-volume>\sources\install.swm", "-PartSizeMB", "3800"],
                    isDestructive: false,
                    requiresElevation: true)));
        }

        steps.Add(new(
            "validate", "Validate boot files", "Check required boot folders and Windows source files.",
            OperationKind.ValidateBootFiles, Command: null));
        steps.Add(new(
            "eject", "Eject USB safely", "Finish only after Windows releases the drive.",
            OperationKind.EjectDisk,
            WindowsCommands.Script("eject-disk.ps1", ["-DriveLetter", "<target-letter>"], isDestructive: false)));

        State = EngineState.AwaitingEraseConfirmation;

        return new OperationPlan(
            Iso: iso,
            Drive: drive,
            Strategy: strategy,
            Steps: steps,
            RequiresAuthorization: true,
            EstimatedBytesToCopy: iso.Size,
            ValidationChecks: ValidationChecks(iso));
    }

    /// <summary>The high-friction gate: the typed name must match the drive exactly.</summary>
    public void ConfirmErase(UsbDrive drive, string typedName)
    {
        if (State != EngineState.AwaitingEraseConfirmation)
        {
            throw new BootableUsbException(UsbErrorKind.InvalidState);
        }
        if (!string.Equals(typedName, drive.DisplayName, StringComparison.Ordinal))
        {
            throw new BootableUsbException(UsbErrorKind.ConfirmationMismatch);
        }
        State = EngineState.PreparingDrive;
    }

    public IReadOnlyList<EngineEvent> DryRunEvents(OperationPlan plan)
    {
        var events = new List<EngineEvent>
        {
            new("iso", EngineState.AnalyzingIso, "ISO verified", plan.Iso.DetectedOs.DisplayName, ChecklistStatus.Complete),
            new("usb", EngineState.AnalyzingUsb, "USB selected", $"{plan.Drive.DisplayName} ({plan.Drive.Identifier})", ChecklistStatus.Complete),
            new("erase", EngineState.PreparingDrive, "USB erase planned", "Requires explicit confirmation before execution.", ChecklistStatus.Waiting),
            new("copy", EngineState.CopyingFiles, "Files ready to copy", ByteFormat.Bytes(plan.EstimatedBytesToCopy), ChecklistStatus.Waiting),
        };

        if (plan.Strategy.RequiresWimSplit)
        {
            events.Add(new("wim", EngineState.SplittingWim, "WIM split required", "DISM will create SWM parts.", ChecklistStatus.Waiting));
        }

        events.Add(new("validate", EngineState.Validating, "Boot validation planned", string.Join(", ", plan.ValidationChecks), ChecklistStatus.Waiting));
        events.Add(new("eject", EngineState.Ejecting, "Safe eject planned", plan.Drive.Identifier, ChecklistStatus.Waiting));

        return events;
    }

    private static IReadOnlyList<string> StrategyWarnings(InstallerIso iso, UsbDrive drive, bool requiresWimSplit)
    {
        var warnings = new List<string>();
        if (!string.Equals(drive.FileSystem, "FAT32", StringComparison.OrdinalIgnoreCase))
        {
            warnings.Add("The USB drive will be reformatted as FAT32 for UEFI boot compatibility.");
        }
        if (drive.Size > OperationExecutor.MaxFat32PartitionBytes)
        {
            warnings.Add("Windows formats FAT32 volumes up to 32 GB, so a 32 GB installer partition will be created and the rest left unallocated.");
        }
        if (requiresWimSplit)
        {
            warnings.Add("The Windows image is larger than FAT32 allows and must be split.");
        }
        if (iso.Confidence == DetectionConfidence.Medium)
        {
            warnings.Add("ISO detection confidence is medium; validation must pass before success.");
        }
        return warnings;
    }

    private static IReadOnlyList<string> ValidationChecks(InstallerIso iso) => iso.DetectedOs.Kind switch
    {
        OperatingSystemKind.Windows when iso.WindowsImageInfo?.RequiresSplit == true =>
            ["boot directory", "efi directory", @"sources\boot.wim", @"sources\install.swm"],
        OperatingSystemKind.Windows =>
            ["boot directory", "efi directory", @"sources\boot.wim", @"sources\install.wim or install.esd"],
        OperatingSystemKind.Linux => ["EFI or boot directory", "copy completed", "safe eject"],
        _ => ["copy completed", "safe eject"],
    };

    private static string Normalize(string path) =>
        path.Replace('\\', '/').Trim('/').ToLowerInvariant();
}
