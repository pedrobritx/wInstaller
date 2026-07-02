# Dismounts a previously mounted ISO. Safe to call repeatedly.
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$IsoPath
)

$ErrorActionPreference = 'Stop'

try {
    Dismount-DiskImage -ImagePath $IsoPath | Out-Null
    exit 0
}
catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
