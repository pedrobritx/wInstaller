using Xunit;

namespace WInstaller.Core.Tests;

public class IsoInspectorParsingTests
{
    [Fact]
    public void ParseMount_ReadsDriveLetterAndLabel()
    {
        var mount = IsoInspector.ParseMount("""{"DriveLetter":"F","VolumeLabel":"CCCOMA_X64FRE"}""");
        Assert.Equal("F", mount.DriveLetter);
        Assert.Equal("CCCOMA_X64FRE", mount.VolumeLabel);
    }

    [Fact]
    public void ParseMount_TreatsMissingLetterAsNull()
    {
        var mount = IsoInspector.ParseMount("""{"DriveLetter":"","VolumeLabel":""}""");
        Assert.Null(mount.DriveLetter);
    }

    [Fact]
    public void Scan_NormalizesSeparatorsAndRecordsLowercasedSizes()
    {
        var root = Path.Combine(Path.GetTempPath(), $"winstaller-scan-{Guid.NewGuid():N}");
        try
        {
            Directory.CreateDirectory(Path.Combine(root, "Sources"));
            Directory.CreateDirectory(Path.Combine(root, ".disk"));
            File.WriteAllText(Path.Combine(root, "Sources", "Install.wim"), "wim-bytes");
            File.WriteAllText(Path.Combine(root, ".disk", "info"), "Ubuntu");

            var scan = IsoInspector.Scan(root);

            Assert.Contains("Sources/Install.wim", scan.Entries);
            Assert.Contains(".disk/info", scan.Entries);
            Assert.True(scan.FileSizes.ContainsKey("sources/install.wim"));
            Assert.Equal(9, scan.FileSizes["sources/install.wim"]);
        }
        finally
        {
            Directory.Delete(root, recursive: true);
        }
    }

    [Fact]
    public void Scan_MissingRootYieldsEmptyResult()
    {
        var scan = IsoInspector.Scan(Path.Combine(Path.GetTempPath(), "definitely-not-a-mount-point"));
        Assert.Empty(scan.Entries);
        Assert.Empty(scan.FileSizes);
    }
}

public class LocalLoggerTests
{
    [Fact]
    public void Redact_HidesWindowsUserPaths()
    {
        var redacted = LocalLogger.Redact(@"copy C:\Users\pedro\Downloads\win11.iso to E:\");
        Assert.DoesNotContain("pedro", redacted);
        Assert.Contains(@"C:\Users\<redacted>\Downloads\win11.iso", redacted);
    }

    [Fact]
    public void Redact_HandlesForwardSlashesAndCase()
    {
        var redacted = LocalLogger.Redact("c:/users/Pedro Brito/file.iso");
        Assert.DoesNotContain("Pedro", redacted);
    }

    [Fact]
    public void Format_IncludesOperationExitCodeAndIndentedDetail()
    {
        var entry = new LogEntry(
            OperationId: "prepare-usb",
            Tool: "powershell.exe",
            Arguments: ["-File", "prepare-usb.ps1"],
            ExitCode: 0,
            UserMessage: "Erase and format USB drive",
            TechnicalDetail: "line one\nline two");

        var formatted = LocalLogger.Format(entry);

        Assert.Contains("prepare-usb powershell.exe", formatted);
        Assert.Contains("exit=0", formatted);
        Assert.Contains("— Erase and format USB drive", formatted);
        Assert.Contains("\n    line two", formatted);
    }

    [Fact]
    public void Record_PersistsToTheLogFile()
    {
        var directory = Path.Combine(Path.GetTempPath(), $"winstaller-log-{Guid.NewGuid():N}");
        try
        {
            var logger = new LocalLogger(directory);
            logger.Record(new LogEntry("mount-iso", "powershell.exe", [], 0, "Mount ISO read-only"));

            var logFile = Path.Combine(directory, "winstaller.log");
            Assert.True(File.Exists(logFile));
            Assert.Contains("Mount ISO read-only", File.ReadAllText(logFile));
            Assert.Single(logger.AllEntries);
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }
}

public class ByteFormatTests
{
    [Theory]
    [InlineData(999, "999 bytes")]
    [InlineData(64_000_000_000, "64 GB")]
    [InlineData(6_500_000_000, "6.5 GB")]
    public void Bytes_UsesDecimalUnits(long value, string expected)
    {
        Assert.Equal(expected, ByteFormat.Bytes(value));
    }
}
