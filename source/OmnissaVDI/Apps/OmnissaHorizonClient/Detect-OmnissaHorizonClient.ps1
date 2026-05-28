<#
.SYNOPSIS
    Detection script for the Omnissa Horizon Client for Windows.

.DESCRIPTION
    The Horizon Client is pre-installed on all target devices via a separate process; this kiosk
    solution never installs it. This script only DETECTS presence (and optionally a minimum version)
    so it can be used as an SCCM/Intune detection rule or as a pre-flight check before applying the
    kiosk configuration.

    Detection is primary via the registry key the Omnissa Client writes at install time and falls
    back to the on-disk executable version. Both were verified against client 8.18.0.

    Exit 0  = installed (and meets MinimumVersion if specified)  -> writes one STDOUT line
    Exit 1  = not installed / too old / unreadable

.PARAMETER MinimumVersion
    Optional minimum version (e.g. '8.18.0'). When omitted, any installed version satisfies detection.

.PARAMETER HorizonClientPath
    Full path to horizon-client.exe. Defaults to the Omnissa per-machine install location.
#>
[CmdletBinding()]
param(
    [version]$MinimumVersion,
    [string]$HorizonClientPath = 'C:\Program Files\Omnissa\Omnissa Horizon Client\horizon-client.exe'
)

$RegKey = 'HKLM:\SOFTWARE\Omnissa\Horizon\Client'

function Resolve-HorizonVersion {
    # 1) Registry (authoritative, fast). Value 'Version' e.g. '8.18.0'.
    $regVersion = (Get-ItemProperty -Path $RegKey -Name 'Version' -ErrorAction SilentlyContinue).Version
    if ($regVersion) {
        try { return [version]$regVersion } catch { }
    }
    # 2) Fallback: on-disk executable FileVersion.
    if (Test-Path -Path $HorizonClientPath -PathType Leaf) {
        $fileVersion = (Get-Item -Path $HorizonClientPath).VersionInfo.FileVersion
        # FileVersion can carry a long build suffix (e.g. 8.18.0.24230927696); keep the first 3 parts.
        if ($fileVersion -match '^(\d+\.\d+\.\d+)') {
            try { return [version]$Matches[1] } catch { }
        }
    }
    return $null
}

$installed = Resolve-HorizonVersion

if (-not $installed) {
    Write-Output "Omnissa Horizon Client not detected (no '$RegKey\Version' and no '$HorizonClientPath')."
    exit 1
}

if ($MinimumVersion -and $installed -lt $MinimumVersion) {
    Write-Output "Omnissa Horizon Client $installed is older than required minimum $MinimumVersion."
    exit 1
}

Write-Output "Omnissa Horizon Client $installed detected."
exit 0
