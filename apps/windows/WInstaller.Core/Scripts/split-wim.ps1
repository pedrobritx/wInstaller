# Splits an install.wim that exceeds the FAT32 single-file limit into
# setup-compatible .swm parts using DISM (which ships with Windows).
# Reads the source image from the read-only ISO mount; writes only to the
# installer USB volume.
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ImageFile,

    [Parameter(Mandatory = $true)]
    [string]$SwmFile,

    [int]$PartSizeMB = 3800,

    # Where to write the JSON result; elevation cannot redirect stdout.
    [string]$ResultPath = ''
)

$ErrorActionPreference = 'Stop'

try {
    $dism = Join-Path $env:SystemRoot 'System32\Dism.exe'
    & $dism /Split-Image "/ImageFile:$ImageFile" "/SWMFile:$SwmFile" "/FileSize:$PartSizeMB" | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "DISM /Split-Image failed with exit code $LASTEXITCODE."
    }

    $json = ConvertTo-Json -InputObject ([pscustomobject]@{ Status = 'ok' }) -Compress
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
