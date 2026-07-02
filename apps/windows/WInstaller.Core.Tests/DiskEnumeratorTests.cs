using Xunit;

namespace WInstaller.Core.Tests;

public class DiskEnumeratorTests
{
    private const string ListFixture = """
        [
          {
            "Number": 0,
            "FriendlyName": "Samsung SSD 980 PRO 1TB",
            "Size": 1000204886016,
            "BusType": "NVMe",
            "IsBoot": true,
            "IsSystem": true,
            "IsRemovableMedia": false,
            "PartitionStyle": "GPT",
            "Volumes": [
              { "DriveLetter": "C", "FileSystemLabel": "Windows", "FileSystem": "NTFS" }
            ]
          },
          {
            "Number": 3,
            "FriendlyName": "Kingston DataTraveler 3.0",
            "Size": 61530439680,
            "BusType": "USB",
            "IsBoot": false,
            "IsSystem": false,
            "IsRemovableMedia": true,
            "PartitionStyle": "MBR",
            "Volumes": [
              { "DriveLetter": "E", "FileSystemLabel": "UNTITLED", "FileSystem": "exFAT" }
            ]
          }
        ]
        """;

    [Fact]
    public void ParseDiskList_MapsBothDisks()
    {
        var disks = DiskEnumerator.ParseDiskList(ListFixture);

        Assert.Equal(2, disks.Count);

        var system = disks[0];
        Assert.True(system.IsSystemDisk);
        Assert.False(system.IsRemovable);
        Assert.Equal("GPT", system.PartitionScheme);
        Assert.Equal("NTFS", system.FileSystem);
        Assert.Equal(["Windows"], system.Volumes);

        var usb = disks[1];
        Assert.Equal(3, usb.DiskNumber);
        Assert.Equal("Disk 3", usb.Identifier);
        Assert.True(usb.IsRemovable);
        Assert.False(usb.IsSystemDisk);
        Assert.Equal(61_530_439_680, usb.Size);
        Assert.Equal("Kingston DataTraveler 3.0", usb.DisplayName);
    }

    [Fact]
    public void ParseDiskList_AcceptsSingleObject()
    {
        // ConvertTo-Json collapses single-element arrays to a bare object.
        const string fixture = """
            { "Number": 2, "FriendlyName": "SanDisk Ultra", "Size": 32000000000, "BusType": "USB",
              "IsBoot": false, "IsSystem": false, "IsRemovableMedia": true, "PartitionStyle": "RAW", "Volumes": [] }
            """;
        var disks = DiskEnumerator.ParseDiskList(fixture);

        var disk = Assert.Single(disks);
        Assert.Equal("SanDisk Ultra", disk.DisplayName);
        Assert.Equal("Unformatted", disk.PartitionScheme);
        Assert.Equal("Unformatted", disk.FileSystem);
    }

    [Fact]
    public void ParseDriveInfo_FallsBackToDriveLetterWhenUnlabeled()
    {
        const string fixture = """
            { "Number": 4, "FriendlyName": "Generic Flash Disk", "Size": 8000000000, "BusType": "USB",
              "IsBoot": false, "IsSystem": false, "IsRemovableMedia": true, "PartitionStyle": "MBR",
              "Volumes": [ { "DriveLetter": "F", "FileSystemLabel": "", "FileSystem": "FAT32" } ] }
            """;
        var drive = DiskEnumerator.ParseDriveInfo(fixture);

        Assert.Equal(["F:"], drive.Volumes);
        Assert.Equal("FAT32", drive.FileSystem);
    }

    [Fact]
    public async Task RemovableDrives_FiltersOutSystemDisks()
    {
        var runner = new FakeCommandRunner();
        runner.RespondToScript("list-disks.ps1", ListFixture);
        var enumerator = new DiskEnumerator(runner);

        var drives = await enumerator.RemovableDrivesAsync();

        var drive = Assert.Single(drives);
        Assert.Equal(3, drive.DiskNumber);
    }

    [Fact]
    public async Task RemovableDrives_EmptyOnCommandFailure()
    {
        var runner = new FakeCommandRunner();
        runner.RespondToScript("list-disks.ps1", "", exitCode: 1);
        var enumerator = new DiskEnumerator(runner);

        var drives = await enumerator.RemovableDrivesAsync();

        Assert.Empty(drives);
    }

    [Theory]
    [InlineData("GPT", "GPT")]
    [InlineData("MBR", "MBR")]
    [InlineData("RAW", "Unformatted")]
    [InlineData(null, "Unknown")]
    [InlineData("Weird", "Weird")]
    public void PartitionScheme_Mapping(string? style, string expected)
    {
        Assert.Equal(expected, DiskEnumerator.PartitionScheme(style));
    }
}
