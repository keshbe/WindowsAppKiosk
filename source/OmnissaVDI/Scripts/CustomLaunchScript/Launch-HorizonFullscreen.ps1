<#
.SYNOPSIS
    Kiosk launcher: starts the Omnissa Horizon Client, forces its window to maximize, and sets the
    taskbar to auto-hide for the kiosk session.

.DESCRIPTION
    Runs at logon in the kiosk user's own context (started by the Start Menu / Startup shortcut):
      1. Starts the Horizon Client against the configured Connection Server.
      2. Maximizes the client window via ShowWindow (the client ignores the "start maximized" hint),
         re-applying for a short period to cover the Server -> Login -> Pool transitions.
      3. Sets the taskbar to auto-hide via SHAppBarMessage(ABM_SETSTATE) - the bar slides away and is
         revealed (with the Wi-Fi flyout) by moving the mouse to the bottom edge. This runs in the
         kiosk user's session on every logon, so it works regardless of the Windows build or whether
         the profile is newly created.

    The {{...}} placeholders are replaced with real values by Set-OmnissaVDIKioskSettings.ps1 at deploy.

.NOTES
    Removing the title bar / minimize-maximize-close buttons from outside the process is not possible
    (the Horizon Client is a WPF window that rejects external style/region changes). The kiosk lockdown
    makes those buttons harmless (minimize -> locked desktop, close -> relaunch via Start pin).
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
[StructLayout(LayoutKind.Sequential)] public struct RECT { public int left, top, right, bottom; }
[StructLayout(LayoutKind.Sequential)] public struct APPBARDATA {
    public uint cbSize; public IntPtr hWnd; public uint uCallbackMessage; public uint uEdge; public RECT rc; public IntPtr lParam;
}
public static class Win {
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll", CharSet=CharSet.Auto)] public static extern IntPtr FindWindow(string lpClassName, string lpWindowName);
    [DllImport("shell32.dll")] public static extern UIntPtr SHAppBarMessage(uint dwMessage, ref APPBARDATA pData);
}
"@

$SW_MAXIMIZE        = 3
$ABM_SETSTATE       = [uint32]0x0000000A
$ABS_AUTOHIDE_ONTOP = [IntPtr]3        # ABS_AUTOHIDE (0x1) | ABS_ALWAYSONTOP (0x2)

# Start the Horizon Client against the configured Connection Server.
$clientArgs = "-serverURL `"$HorizonServerUrl`" -desktopLayout $HorizonDesktopLayout"
if ($HorizonDesktopName) { $clientArgs += " -desktopName `"$HorizonDesktopName`"" }
Start-Process -FilePath $HorizonClientPath -ArgumentList $clientArgs | Out-Null

# Maximize the client window whenever it appears, and set the taskbar to auto-hide once the shell
# taskbar (Shell_TrayWnd) is up. Re-apply maximize for a short window to cover the login -> pool flow.
$taskbarDone = $false
$deadline = (Get-Date).AddSeconds($WatchSeconds)
while ((Get-Date) -lt $deadline) {
    $proc = Get-Process -Name 'horizon-client' -ErrorAction SilentlyContinue |
            Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
    if ($proc) { [void][Win]::ShowWindow($proc.MainWindowHandle, $SW_MAXIMIZE) }

    if (-not $taskbarDone) {
        $tray = [Win]::FindWindow('Shell_TrayWnd', $null)
        if ($tray -ne [IntPtr]::Zero) {
            $abd = New-Object APPBARDATA
            $abd.cbSize = [System.Runtime.InteropServices.Marshal]::SizeOf($abd)
            $abd.hWnd   = $tray
            $abd.lParam = $ABS_AUTOHIDE_ONTOP
            [void][Win]::SHAppBarMessage($ABM_SETSTATE, [ref]$abd)
            $taskbarDone = $true
        }
    }
    Start-Sleep -Milliseconds 500
}
