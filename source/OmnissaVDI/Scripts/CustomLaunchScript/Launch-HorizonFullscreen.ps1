<#
.SYNOPSIS
    Kiosk fullscreen maximizer for the Omnissa Horizon Client.

.DESCRIPTION
    Runs hidden in the kiosk user's session for the whole logon. It does NOT start the client - the
    client is launched by its own shortcut (which targets horizon-client.exe directly so the running
    window shares the pinned taskbar button). This watcher only:
      1. Maximizes the Horizon Client window whenever it appears, because the client ignores the
         "start maximized" hint. It covers both the logon auto-start and a manual relaunch from the
         taskbar pin. The window is maximized only when it is NOT already maximized (IsZoomed guard),
         so the loop never re-activates an already-maximized window - that would steal focus from and
         dismiss the Quick Settings / Wi-Fi flyout.
      2. Sets the taskbar to auto-hide once the shell taskbar (Shell_TrayWnd) is up.

.NOTES
    Removing the title bar / minimize-maximize-close buttons from outside the process is not possible
    (the Horizon Client is a WPF window that rejects external style/region changes). The kiosk lockdown
    makes those buttons harmless (minimize -> locked desktop, close -> relaunch via the taskbar pin).
#>
[CmdletBinding()]
param(
    [int]$PollSeconds = 2
)

Add-Type @"
using System;
using System.Runtime.InteropServices;
[StructLayout(LayoutKind.Sequential)] public struct RECT { public int left, top, right, bottom; }
[StructLayout(LayoutKind.Sequential)] public struct APPBARDATA {
    public uint cbSize; public IntPtr hWnd; public uint uCallbackMessage; public uint uEdge; public RECT rc; public IntPtr lParam;
}
public static class Win {
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern bool IsZoomed(IntPtr hWnd);
    [DllImport("user32.dll", CharSet=CharSet.Auto)] public static extern IntPtr FindWindow(string lpClassName, string lpWindowName);
    [DllImport("shell32.dll")] public static extern UIntPtr SHAppBarMessage(uint dwMessage, ref APPBARDATA pData);
}
"@

$SW_MAXIMIZE        = 3
$ABM_SETSTATE       = [uint32]0x0000000A
$ABS_AUTOHIDE_ONTOP = [IntPtr]3        # ABS_AUTOHIDE (0x1) | ABS_ALWAYSONTOP (0x2)

# Run for the whole session: maximize the client window when it appears (and only if it is not already
# maximized), and set the taskbar to auto-hide once. A relaunch from the taskbar pin is handled too.
$taskbarDone = $false
while ($true) {
    try {
        $proc = Get-Process -Name 'horizon-client' -ErrorAction SilentlyContinue |
                Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
        if ($proc -and -not [Win]::IsZoomed($proc.MainWindowHandle)) {
            [void][Win]::ShowWindow($proc.MainWindowHandle, $SW_MAXIMIZE)
        }

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
    } catch { }
    Start-Sleep -Seconds $PollSeconds
}
