# Mounts an ISO strictly read-only and reports its drive letter as JSON.
# The image is never modified (REQ-ISO-003, REQ-ISO-007).
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$IsoPath
)

$ErrorActionPreference = 'Stop'

try {
    $image = Mount-DiskImage -ImagePath $IsoPath -Access ReadOnly -PassThru

    # The volume can take a moment to surface after the mount call returns.
    $volume = $null
    for ($attempt = 0; $attempt -lt 20; $attempt++) {
        $volume = $image | Get-Volume -ErrorAction SilentlyContinue
        if ($volume -and $volume.DriveLetter) { break }
        Start-Sleep -Milliseconds 500
        $image = Get-DiskImage -ImagePath $IsoPath
    }

    if (-not $volume -or -not $volume.DriveLetter) {
        Dismount-DiskImage -ImagePath $IsoPath | Out-Null
        throw 'The ISO mounted but no drive letter was assigned.'
    }

    $result = [pscustomobject]@{
        DriveLetter = [string]$volume.DriveLetter
        VolumeLabel = [string]$volume.FileSystemLabel
    }
    ConvertTo-Json -InputObject $result -Compress
    exit 0
}
catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
