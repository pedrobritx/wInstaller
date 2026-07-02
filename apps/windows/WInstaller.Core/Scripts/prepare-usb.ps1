# DESTRUCTIVE: cleans a removable USB disk and creates a GPT/FAT32 installer
# volume. This is the only step wInstaller runs elevated (ADR-0003) — it is
# invoked through a single UAC prompt after the user has already typed the
# drive name in the confirmation gate.
#
# Safety gates are re-checked *inside* the elevated context: the script refuses
# boot/system disks and any disk that is not on the USB bus, regardless of what
# the caller asked for.
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [int]$DiskNumber,

    [Parameter(Mandatory = $true)]
    [string]$Label,

    # Windows will not format FAT32 volumes larger than 32 GiB.
    [long]$SizeLimitBytes = 34359738368,

    # Where to write the JSON result; elevation cannot redirect stdout.
    [string]$ResultPath = ''
)

$ErrorActionPreference = 'Stop'

try {
    $disk = Get-Disk -Number $DiskNumber

    if ($disk.IsBoot -or $disk.IsSystem) {
        throw "Refusing to erase disk $DiskNumber - it hosts the running system."
    }
    if ($disk.BusType -ne 'USB') {
        throw "Refusing to erase disk $DiskNumber - it is not a USB device (BusType: $($disk.BusType))."
    }

    if ($disk.PartitionStyle -ne 'RAW') {
        Clear-Disk -Number $DiskNumber -RemoveData -RemoveOEM -Confirm:$false
    }
    Initialize-Disk -Number $DiskNumber -PartitionStyle GPT -ErrorAction SilentlyContinue | Out-Null

    $disk = Get-Disk -Number $DiskNumber
    if ($disk.Size -gt $SizeLimitBytes) {
        $partition = New-Partition -DiskNumber $DiskNumber -Size $SizeLimitBytes -AssignDriveLetter
    }
    else {
        $partition = New-Partition -DiskNumber $DiskNumber -UseMaximumSize -AssignDriveLetter
    }

    $volume = Format-Volume -Partition $partition -FileSystem FAT32 -NewFileSystemLabel $Label -Confirm:$false

    $result = [pscustomobject]@{
        DriveLetter = [string]$volume.DriveLetter
        VolumeLabel = [string]$volume.FileSystemLabel
    }
    $json = ConvertTo-Json -InputObject $result -Compress
    if ($ResultPath) {
        Set-Content -Path $ResultPath -Value $json -Encoding utf8 -NoNewline
    }
    $json
    exit 0
}
catch {
    if ($ResultPath) {
        Set-Content -Path $ResultPath -Value '' -Encoding utf8 -NoNewline
    }
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
