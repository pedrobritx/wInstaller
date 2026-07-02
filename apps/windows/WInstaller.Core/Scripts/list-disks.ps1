# Lists every physical disk as compact JSON for WInstaller.Core.DiskEnumerator.
# Read-only: this script never modifies any disk.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

try {
    $disks = @(Get-Disk | ForEach-Object {
        $partitions = @(Get-Partition -DiskNumber $_.Number -ErrorAction SilentlyContinue)
        $volumes = @(foreach ($partition in $partitions) {
            $volume = Get-Volume -Partition $partition -ErrorAction SilentlyContinue
            if ($volume) {
                [pscustomobject]@{
                    DriveLetter     = if ($volume.DriveLetter) { [string]$volume.DriveLetter } else { $null }
                    FileSystemLabel = [string]$volume.FileSystemLabel
                    FileSystem      = [string]$volume.FileSystem
                }
            }
        })

        $wmiDisk = Get-CimInstance Win32_DiskDrive -Filter "Index=$($_.Number)" -ErrorAction SilentlyContinue

        [pscustomobject]@{
            Number           = [int]$_.Number
            FriendlyName     = [string]$_.FriendlyName
            Size             = [long]$_.Size
            BusType          = [string]$_.BusType
            IsBoot           = [bool]$_.IsBoot
            IsSystem         = [bool]$_.IsSystem
            IsRemovableMedia = [bool]($wmiDisk -and $wmiDisk.MediaType -match 'Removable')
            PartitionStyle   = [string]$_.PartitionStyle
            Volumes          = $volumes
        }
    })

    ConvertTo-Json -InputObject $disks -Depth 4 -Compress
    exit 0
}
catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
