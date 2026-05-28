<#
.SYNOPSIS
    Kiosk launcher: starts the Omnissa Horizon Client and forces its window to maximize.

.DESCRIPTION
    The Horizon Client ignores the standard "start maximized" hint (nCmdShow), so this launcher
    starts the client and then maximizes its main window via the Win32 ShowWindow API once the
    window appears. It keeps re-applying for a short period to cover the Server -> Login -> Pool
    transitions, where the client may recreate its window.

    The {{...}} placeholders are replaced with the real values by Set-OmnissaVDIKioskSettings.ps1
    when the launcher is deployed to C:\KioskSettings.

.NOTES
    Removing the title bar / minimize-maximize-close buttons from outside the process is NOT
    possible: the Horizon Client is a WPF window that rejects external window-style and window-
    region changes (verified). The kiosk lockdown makes those buttons harmless anyway
    (minimize -> locked desktop, close -> relaunch via Start pin, maximize -> already maximized).
#>
[CmdletBinding()]
param(
    [string]$HorizonClientPath    = '{{HORIZON_CLIENT_PATH}}',
    [string]$HorizonServerUrl     = '{{HORIZON_SERVER_URL}}',
    [string]$HorizonDesktopLayout = '{{HORIZON_DESKTOP_LAYOUT}}',
    [string]$HorizonDesktopName   = '{{HORIZON_DESKTOP_NAME}}',
    [int]$WatchSeconds            = 120
)

# Guard: refuse to run with unreplaced placeholders or an empty URL.
if ($HorizonServerUrl -like '*{{*' -or [string]::IsNullOrWhiteSpace($HorizonServerUrl)) {
    throw "HorizonServerUrl is not configured. Run via the kiosk (placeholders are replaced at deploy) or pass -HorizonServerUrl."
}
if (-not (Test-Path -Path $HorizonClientPath -PathType Leaf)) {
    throw "Horizon Client not found at '$HorizonClientPath'."
}

Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class Win { [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow); }
"@

$SW_MAXIMIZE = 3

# Start the Horizon Client against the configured Connection Server.
$clientArgs = "-serverURL `"$HorizonServerUrl`" -desktopLayout $HorizonDesktopLayout"
if ($HorizonDesktopName) { $clientArgs += " -desktopName `"$HorizonDesktopName`"" }
Start-Process -FilePath $HorizonClientPath -ArgumentList $clientArgs | Out-Null

# Maximize the client window once it appears, and keep re-applying for a short window to cover
# the Server -> Login -> Pool transitions (the client may recreate its top-level window).
$deadline = (Get-Date).AddSeconds($WatchSeconds)
while ((Get-Date) -lt $deadline) {
    $proc = Get-Process -Name 'horizon-client' -ErrorAction SilentlyContinue |
            Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
    if ($proc) { [void][Win]::ShowWindow($proc.MainWindowHandle, $SW_MAXIMIZE) }
    Start-Sleep -Milliseconds 500
}
