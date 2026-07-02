# Re-reads a single disk's identity as compact JSON. Used immediately before
# any destructive step so the pipeline can abort if the device changed.
# Read-only: this script never modifies any disk.
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [int]$DiskNumber
)

$ErrorActionPreference = 'Stop'

try {
    $disk = Get-Disk -Number $DiskNumber

    $partitions = @(Get-Partition -DiskNumber $disk.Number -ErrorAction SilentlyContinue)
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

    $wmiDisk = Get-CimInstance Win32_DiskDrive -Filter "Index=$($disk.Number)" -ErrorAction SilentlyContinue

    $result = [pscustomobject]@{
        Number           = [int]$disk.Number
        FriendlyName     = [string]$disk.FriendlyName
        Size             = [long]$disk.Size
        BusType          = [string]$disk.BusType
        IsBoot           = [bool]$disk.IsBoot
        IsSystem         = [bool]$disk.IsSystem
        IsRemovableMedia = [bool]($wmiDisk -and $wmiDisk.MediaType -match 'Removable')
        PartitionStyle   = [string]$disk.PartitionStyle
        Volumes          = $volumes
    }

    ConvertTo-Json -InputObject $result -Depth 4 -Compress
    exit 0
}
catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
