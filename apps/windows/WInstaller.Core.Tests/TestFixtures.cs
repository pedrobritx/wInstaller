namespace WInstaller.Core.Tests;

internal static class TestFixtures
{
    public static readonly string[] WindowsIsoEntries =
    [
        "setup.exe",
        "boot",
        "efi",
        "efi/boot",
        "efi/boot/bootx64.efi",
        "sources",
        "sources/boot.wim",
        "sources/install.wim",
    ];

    public static UsbDrive RemovableDrive(long size = 64_000_000_000) => new(
        DiskNumber: 3,
        DisplayName: "Kingston DataTraveler 3.0",
        MediaName: "Kingston DataTraveler 3.0",
        Size: size,
        IsRemovable: true,
        IsSystemDisk: false,
        ConnectionType: "USB",
        PartitionScheme: "MBR",
        FileSystem: "exFAT",
        Volumes: ["UNTITLED"]);

    public static UsbDrive SystemDrive() => new(
        DiskNumber: 0,
        DisplayName: "Samsung SSD 980",
        MediaName: "Samsung SSD 980",
        Size: 1_000_000_000_000,
        IsRemovable: false,
        IsSystemDisk: true,
        ConnectionType: "NVMe",
        PartitionScheme: "GPT",
        FileSystem: "NTFS",
        Volumes: ["Windows"]);

    public static InstallerIso WindowsIso(BootableUsbEngine? engine = null, long installWimSize = 3_800_000_000)
    {
        engine ??= new BootableUsbEngine();
        return engine.AnalyzeIso(
            path: @"C:\Users\example\Downloads\Win11_English_x64.iso",
            size: 6_500_000_000,
            volumeLabel: "CCCOMA_X64FRE",
            directoryEntries: WindowsIsoEntries,
            fileSizes: new Dictionary<string, long> { ["sources/install.wim"] = installWimSize });
    }
}
