namespace WInstaller.Core;

public enum OperatingSystemKind
{
    Windows,
    Linux,
    Unknown,
}

/// <summary>The operating system detected inside an installer ISO.</summary>
public sealed record DetectedOperatingSystem(OperatingSystemKind Kind, string? Detail)
{
    public static DetectedOperatingSystem Windows(string? version = null) => new(OperatingSystemKind.Windows, version);
    public static DetectedOperatingSystem Linux(string? distribution = null) => new(OperatingSystemKind.Linux, distribution);
    public static readonly DetectedOperatingSystem Unknown = new(OperatingSystemKind.Unknown, null);

    public string DisplayName => Kind switch
    {
        OperatingSystemKind.Windows when !string.IsNullOrEmpty(Detail) => $"Windows {Detail}",
        OperatingSystemKind.Windows => "Windows installer",
        OperatingSystemKind.Linux when !string.IsNullOrEmpty(Detail) => Detail!,
        OperatingSystemKind.Linux => "Linux installer",
        _ => "Unknown installer",
    };
}

public enum DetectionConfidence
{
    Low = 0,
    Medium = 1,
    High = 2,
}

public sealed record WindowsImageInfo(long? InstallWimSize, bool HasInstallEsd)
{
    /// <summary>FAT32 cannot store a file of 4 GiB or larger.</summary>
    public const long Fat32SingleFileLimit = 4_294_967_295;

    public bool RequiresSplit => InstallWimSize is > Fat32SingleFileLimit;
}

public sealed record InstallerIso(
    string Path,
    string DisplayName,
    long Size,
    string? VolumeLabel,
    DetectedOperatingSystem DetectedOs,
    DetectionConfidence Confidence,
    IReadOnlyList<string> BootFiles,
    WindowsImageInfo? WindowsImageInfo);

/// <summary>
/// A physical disk as surfaced by the Windows storage stack (Get-Disk).
/// <see cref="IsSystemDisk"/> mirrors the macOS "internal" concept: a disk that
/// hosts the boot or system volumes and must never be offered as an erase target.
/// </summary>
public sealed record UsbDrive(
    int DiskNumber,
    string DisplayName,
    string MediaName,
    long Size,
    bool IsRemovable,
    bool IsSystemDisk,
    string ConnectionType,
    string PartitionScheme,
    string FileSystem,
    IReadOnlyList<string> Volumes)
{
    /// <summary>Stable identifier shown to the user next to the friendly name.</summary>
    public string Identifier => $"Disk {DiskNumber}";
}

public enum EngineState
{
    Idle,
    AnalyzingIso,
    WaitingForUsb,
    AnalyzingUsb,
    Planning,
    AwaitingEraseConfirmation,
    PreparingDrive,
    CopyingFiles,
    SplittingWim,
    Validating,
    Ejecting,
    Completed,
    Failed,
    Cancelled,
}

public enum UsbErrorKind
{
    UnsupportedIso,
    DiskNotRemovable,
    DiskIsSystem,
    InsufficientCapacity,
    MissingTool,
    ConfirmationMismatch,
    InvalidState,
}

public sealed class BootableUsbException : Exception
{
    public UsbErrorKind Kind { get; }

    public BootableUsbException(UsbErrorKind kind, string? detail = null)
        : base(detail ?? UserMessageFor(kind, detail))
    {
        Kind = kind;
    }

    public string UserMessage => UserMessageFor(Kind, Message);

    private static string UserMessageFor(UsbErrorKind kind, string? detail) => kind switch
    {
        UsbErrorKind.UnsupportedIso => "wInstaller could not identify this ISO as supported installation media.",
        UsbErrorKind.DiskNotRemovable => "The selected drive is not marked as removable.",
        UsbErrorKind.DiskIsSystem => "wInstaller refuses to erase the Windows system disk or any internal disk.",
        UsbErrorKind.InsufficientCapacity => "The selected USB drive does not have enough capacity.",
        UsbErrorKind.MissingTool => $"A required tool is not available: {detail}.",
        UsbErrorKind.ConfirmationMismatch => "The confirmation does not match the selected drive.",
        UsbErrorKind.InvalidState => "The operation cannot continue from the current state.",
        _ => "An unexpected error occurred.",
    };
}

public enum OperationKind
{
    AnalyzeIso,
    VerifyUsb,
    EraseDisk,
    CopyFiles,
    SplitWim,
    ValidateBootFiles,
    EjectDisk,
}

public sealed record PlannedCommand(
    string Executable,
    IReadOnlyList<string> Arguments,
    bool IsDestructive,
    bool RequiresElevation = false);

public sealed record OperationStep(
    string Id,
    string Title,
    string Detail,
    OperationKind Kind,
    PlannedCommand? Command);

public sealed record BootStrategy(
    string TargetPartitionScheme,
    string TargetFileSystem,
    bool RequiresErase,
    bool RequiresWimSplit,
    IReadOnlyList<string> Warnings);

public sealed record OperationPlan(
    InstallerIso Iso,
    UsbDrive Drive,
    BootStrategy Strategy,
    IReadOnlyList<OperationStep> Steps,
    bool RequiresAuthorization,
    long EstimatedBytesToCopy,
    IReadOnlyList<string> ValidationChecks)
{
    public IReadOnlyList<OperationStep> DestructiveSteps =>
        Steps.Where(step => step.Command?.IsDestructive == true).ToList();
}

public enum ChecklistStatus
{
    Waiting,
    Running,
    Complete,
    Warning,
    Failed,
}

public sealed record EngineEvent(
    string Id,
    EngineState State,
    string Title,
    string Detail,
    ChecklistStatus Status);

/// <summary>
/// Windows ships every tool the pipeline needs; the flags exist so tests can
/// exercise the missing-tool guidance paths.
/// </summary>
public sealed record ToolAvailability(
    bool PowerShell = true,
    bool Robocopy = true,
    bool Dism = true);

public static class ByteFormat
{
    /// <summary>Human-readable size in decimal units (matches Finder/Explorer style).</summary>
    public static string Bytes(long value)
    {
        string[] units = ["bytes", "KB", "MB", "GB", "TB"];
        double size = value;
        var unit = 0;
        while (size >= 1000 && unit < units.Length - 1)
        {
            size /= 1000;
            unit += 1;
        }
        return unit == 0
            ? $"{value} {units[unit]}"
            : string.Create(System.Globalization.CultureInfo.InvariantCulture, $"{size:0.#} {units[unit]}");
    }
}
