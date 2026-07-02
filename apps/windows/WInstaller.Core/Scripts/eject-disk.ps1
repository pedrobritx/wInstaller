# Safely ejects a removable volume so it can be unplugged.
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z]$')]
    [string]$DriveLetter
)

$ErrorActionPreference = 'Stop'

try {
    $shell = New-Object -ComObject Shell.Application
    $volume = $shell.Namespace(17).ParseName("$($DriveLetter):")
    if (-not $volume) {
        throw "Volume $($DriveLetter): was not found."
    }
    $volume.InvokeVerb('Eject')

    # Give the shell a moment to flush and release the device.
    Start-Sleep -Seconds 2
    exit 0
}
catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
