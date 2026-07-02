using System.Text.Json;

namespace WInstaller.Core;

/// <summary>
/// Enumerates physical disks through the bundled <c>list-disks.ps1</c> /
/// <c>disk-info.ps1</c> helpers (Get-Disk + Get-Partition as JSON) and maps
/// them onto the domain <see cref="UsbDrive"/> model. System/boot disks are
/// marked unsafe for erase and filtered out by default (REQ-USB-002,
/// REQ-USB-005).
///
/// All parsing is exposed as pure static functions so it can be fixture-tested
/// without a real disk.
/// </summary>
public sealed class DiskEnumerator
{
    private readonly ICommandRunner _runner;

    public DiskEnumerator(ICommandRunner? runner = null)
    {
        _runner = runner ?? new ProcessCommandRunner();
    }

    /// <summary>Removable, non-system drives that are safe to consider as erase targets.</summary>
    public async Task<IReadOnlyList<UsbDrive>> RemovableDrivesAsync(CancellationToken cancellationToken = default)
    {
        var result = await _runner.RunAsync(
            WindowsCommands.Script("list-disks.ps1", [], isDestructive: false),
            CommandTimeout.Metadata,
            cancellationToken).ConfigureAwait(false);

        if (!result.Succeeded)
        {
            return [];
        }

        return ParseDiskList(result.StandardOutput)
            .Where(drive => drive.IsRemovable && !drive.IsSystemDisk)
            .ToList();
    }

    /// <summary>
    /// Re-reads a single disk's identity immediately before a destructive step.
    /// Used by <see cref="OperationExecutor"/> to abort if the device changed.
    /// </summary>
    public async Task<UsbDrive> InfoAsync(int diskNumber, CancellationToken cancellationToken = default)
    {
        var result = await _runner.RunAsync(
            WindowsCommands.Script(
                "disk-info.ps1",
                ["-DiskNumber", diskNumber.ToString(System.Globalization.CultureInfo.InvariantCulture)],
                isDestructive: false),
            CommandTimeout.Metadata,
            cancellationToken).ConfigureAwait(false);

        if (!result.Succeeded)
        {
            throw new CommandRunnerException(
                CommandRunnerErrorKind.LaunchFailed,
                $"Could not re-read disk {diskNumber}: {result.StandardError}");
        }

        return ParseDriveInfo(result.StandardOutput);
    }

    // MARK: Pure parsing

    /// <summary>Parses the JSON array produced by <c>list-disks.ps1</c>.</summary>
    public static IReadOnlyList<UsbDrive> ParseDiskList(string json)
    {
        using var document = JsonDocument.Parse(json);
        var root = document.RootElement;

        // ConvertTo-Json collapses single-element arrays to a bare object.
        if (root.ValueKind == JsonValueKind.Object)
        {
            return [ParseDisk(root)];
        }
        if (root.ValueKind != JsonValueKind.Array)
        {
            return [];
        }
        return root.EnumerateArray().Select(ParseDisk).ToList();
    }

    /// <summary>Parses the single JSON object produced by <c>disk-info.ps1</c>.</summary>
    public static UsbDrive ParseDriveInfo(string json)
    {
        using var document = JsonDocument.Parse(json);
        return ParseDisk(document.RootElement);
    }

    private static UsbDrive ParseDisk(JsonElement element)
    {
        var busType = GetString(element, "BusType") ?? "Unknown";
        var isRemovableMedia = GetBool(element, "IsRemovableMedia");
        var isBoot = GetBool(element, "IsBoot");
        var isSystem = GetBool(element, "IsSystem");

        var volumes = new List<string>();
        string? fileSystem = null;
        if (element.TryGetProperty("Volumes", out var volumesElement) && volumesElement.ValueKind == JsonValueKind.Array)
        {
            foreach (var volume in volumesElement.EnumerateArray())
            {
                var label = GetString(volume, "FileSystemLabel");
                var letter = GetString(volume, "DriveLetter");
                fileSystem ??= GetString(volume, "FileSystem");
                var name = !string.IsNullOrWhiteSpace(label) ? label!
                    : !string.IsNullOrWhiteSpace(letter) ? $"{letter}:" : null;
                if (name is not null)
                {
                    volumes.Add(name);
                }
            }
        }

        var friendlyName = FirstNonEmpty(
            GetString(element, "FriendlyName"),
            GetString(element, "Model"));
        var diskNumber = GetInt(element, "Number") ?? -1;

        return new UsbDrive(
            DiskNumber: diskNumber,
            DisplayName: friendlyName ?? $"Disk {diskNumber}",
            MediaName: friendlyName ?? $"Disk {diskNumber}",
            Size: GetLong(element, "Size") ?? 0,
            // The Windows storage stack reports USB thumb drives as
            // BusType=USB; card readers additionally set IsRemovableMedia.
            IsRemovable: string.Equals(busType, "USB", StringComparison.OrdinalIgnoreCase) || isRemovableMedia,
            IsSystemDisk: isBoot || isSystem,
            ConnectionType: busType,
            PartitionScheme: PartitionScheme(GetString(element, "PartitionStyle")),
            FileSystem: FirstNonEmpty(fileSystem) ?? "Unformatted",
            Volumes: volumes);
    }

    internal static string PartitionScheme(string? style) => style switch
    {
        "GPT" => "GPT",
        "MBR" => "MBR",
        "RAW" => "Unformatted",
        var value when !string.IsNullOrWhiteSpace(value) => value!,
        _ => "Unknown",
    };

    private static string? FirstNonEmpty(params string?[] values) =>
        values.FirstOrDefault(value => !string.IsNullOrWhiteSpace(value));

    private static string? GetString(JsonElement element, string name) =>
        element.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.String
            ? value.GetString()
            : null;

    private static bool GetBool(JsonElement element, string name) =>
        element.TryGetProperty(name, out var value) && value.ValueKind is JsonValueKind.True;

    private static int? GetInt(JsonElement element, string name) =>
        element.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.Number
            ? value.GetInt32()
            : null;

    private static long? GetLong(JsonElement element, string name) =>
        element.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.Number
            ? value.GetInt64()
            : null;
}
