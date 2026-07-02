using System.Text.Json;

namespace WInstaller.Core;

public enum IsoInspectionErrorKind
{
    MountFailed,
    NoMountPoint,
}

public sealed class IsoInspectionException : Exception
{
    public IsoInspectionErrorKind Kind { get; }

    public IsoInspectionException(IsoInspectionErrorKind kind, string? detail = null)
        : base(detail ?? "")
    {
        Kind = kind;
    }

    public string UserMessage => Kind switch
    {
        IsoInspectionErrorKind.MountFailed => "wInstaller could not mount this ISO. It may be damaged or unsupported.",
        _ => "The ISO mounted but no readable volume was found.",
    };
}

/// <summary>
/// Mounts an ISO read-only through <c>mount-iso.ps1</c> (Mount-DiskImage
/// -Access ReadOnly), walks its directory tree to gather the entries and file
/// sizes that <see cref="BootableUsbEngine.AnalyzeIso"/> needs, then dismounts
/// the image. The image is never modified (REQ-ISO-003, REQ-ISO-007).
/// </summary>
public sealed class IsoInspector
{
    private readonly ICommandRunner _runner;
    private readonly BootableUsbEngine _engine;

    public IsoInspector(ICommandRunner? runner = null, BootableUsbEngine? engine = null)
    {
        _runner = runner ?? new ProcessCommandRunner();
        _engine = engine ?? new BootableUsbEngine();
    }

    public async Task<InstallerIso> InspectAsync(string isoPath, CancellationToken cancellationToken = default)
    {
        var mountResult = await _runner.RunAsync(
            WindowsCommands.Script("mount-iso.ps1", ["-IsoPath", isoPath], isDestructive: false),
            CommandTimeout.Mount,
            cancellationToken).ConfigureAwait(false);

        if (!mountResult.Succeeded)
        {
            throw new IsoInspectionException(IsoInspectionErrorKind.MountFailed, mountResult.StandardError);
        }

        var mount = ParseMount(mountResult.StandardOutput);
        if (string.IsNullOrEmpty(mount.DriveLetter))
        {
            await DismountAsync(isoPath, cancellationToken).ConfigureAwait(false);
            throw new IsoInspectionException(IsoInspectionErrorKind.NoMountPoint);
        }

        try
        {
            var mountRoot = $"{mount.DriveLetter}:{Path.DirectorySeparatorChar}";
            var scan = Scan(mountRoot);
            var size = FileSize(isoPath);
            return _engine.AnalyzeIso(
                path: isoPath,
                size: size,
                volumeLabel: mount.VolumeLabel,
                directoryEntries: scan.Entries,
                fileSizes: scan.FileSizes);
        }
        finally
        {
            // Always dismount, whether analysis succeeds or throws
            // (e.g. unsupported ISO).
            await DismountAsync(isoPath, cancellationToken).ConfigureAwait(false);
        }
    }

    private async Task DismountAsync(string isoPath, CancellationToken cancellationToken)
    {
        try
        {
            await _runner.RunAsync(
                WindowsCommands.Script("dismount-iso.ps1", ["-IsoPath", isoPath], isDestructive: false),
                CommandTimeout.Mount,
                cancellationToken).ConfigureAwait(false);
        }
        catch (Exception exception) when (exception is not OperationCanceledException)
        {
            // Best-effort cleanup; the mount is read-only either way.
        }
    }

    private static long FileSize(string path)
    {
        try
        {
            return new FileInfo(path).Length;
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            return 0;
        }
    }

    // MARK: Pure parsing / scanning

    public sealed record MountInfo(string? DriveLetter, string? VolumeLabel);

    /// <summary>Extracts the mounted volume from <c>mount-iso.ps1</c> JSON output.</summary>
    public static MountInfo ParseMount(string json)
    {
        using var document = JsonDocument.Parse(json);
        var root = document.RootElement;
        string? letter = null;
        string? label = null;
        if (root.TryGetProperty("DriveLetter", out var letterElement) && letterElement.ValueKind == JsonValueKind.String)
        {
            letter = letterElement.GetString();
        }
        if (root.TryGetProperty("VolumeLabel", out var labelElement) && labelElement.ValueKind == JsonValueKind.String)
        {
            label = labelElement.GetString();
        }
        return new MountInfo(string.IsNullOrWhiteSpace(letter) ? null : letter, label);
    }

    public sealed record ScanResult(IReadOnlyList<string> Entries, IReadOnlyDictionary<string, long> FileSizes);

    /// <summary>
    /// Walks a mounted volume and returns relative paths (normalized to forward
    /// slashes) plus file sizes. Sizes are recorded under both the natural-case
    /// and lowercased relative path so the engine's lookups resolve on any ISO
    /// layout. Hidden files are included: Linux media is detected via
    /// <c>.disk/info</c>.
    /// </summary>
    public static ScanResult Scan(string mountRoot)
    {
        var entries = new List<string>();
        var fileSizes = new Dictionary<string, long>();

        var root = new DirectoryInfo(mountRoot);
        if (!root.Exists)
        {
            return new ScanResult(entries, fileSizes);
        }

        var basePath = root.FullName.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        var options = new EnumerationOptions
        {
            RecurseSubdirectories = true,
            AttributesToSkip = 0,
            IgnoreInaccessible = true,
        };

        foreach (var info in root.EnumerateFileSystemInfos("*", options))
        {
            var fullPath = info.FullName;
            if (!fullPath.StartsWith(basePath, StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }
            var relative = fullPath[basePath.Length..]
                .TrimStart(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar)
                .Replace('\\', '/');
            if (relative.Length == 0)
            {
                continue;
            }

            entries.Add(relative);

            if (info is FileInfo file)
            {
                fileSizes[relative] = file.Length;
                fileSizes[relative.ToLowerInvariant()] = file.Length;
            }
        }

        return new ScanResult(entries, fileSizes);
    }
}
