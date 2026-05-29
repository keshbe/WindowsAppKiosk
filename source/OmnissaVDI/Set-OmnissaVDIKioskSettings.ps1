<#
.SYNOPSIS
    Configures Windows 11 (Enterprise / Education / IoT Enterprise / LTSC) as a locked-down
    Multi-App kiosk + AutoLogon for the Omnissa Horizon Client.

.DESCRIPTION
    Rebased from the Azure/WindowsAppKiosk "RemoteDesktopClient" (AVD) variant and reduced to a
    single scenario: Multi-App Kiosk with AutoLogon as KioskUser0. The Horizon Client auto-launches
    in fullscreen at logon; the user only sees the Horizon login, the taskbar, the Wi-Fi flyout and
    the clock. The Settings app is whitelisted so the user can switch wireless networks while mobile.

    Deliberately NOT done here (handled elsewhere):
    - The Omnissa Horizon Client is PRE-INSTALLED on all devices. This script only DETECTS it and
      aborts if missing. It never downloads or installs anything.
    - A local Administrator account for emergency access (left-shift+enter at boot breaks AutoLogon).
    - BitLocker with pre-boot PIN.
    - Smart card / Yubikey removal handling is done SERVER-SIDE on the Horizon Connection Server
      ("Disconnect user sessions on smart card removal"); there is no local watcher here.

    The smart card and FIDO2 (Yubikey) redirection plugins ship with the Horizon Client; this script
    only makes sure the kiosk does not block the helper processes (see the AssignedAccess template).

.PARAMETER HorizonServerUrl
    Connection Server URL (https://...). If omitted, the value from the CONFIG region below is used.

.PARAMETER HorizonClientPath
    Full path to horizon-client.exe. Defaults to the Omnissa per-machine install location.

.PARAMETER HorizonDesktopName
    Optional pool / desktop display name to auto-connect to (passed as -desktopName).

.PARAMETER HorizonDesktopLayout
    Screen layout passed to the client: fullscreen (default), multimonitor, windowLarge, windowSmall.

.PARAMETER HorizonAllowedExtraExes
    Optional additional full EXE paths to whitelist alongside the default Horizon helper EXEs.
    Discover them with Process Monitor on a test device (USB redirection, audio, multi-monitor).

.PARAMETER ConfigureAutomaticMaintenance
    Enable Windows Automatic Maintenance via Local GPO.

.PARAMETER MaintenanceActivationTime
    HH:mm:ss start time for Automatic Maintenance. Default '02:00:00'.

.PARAMETER MaintenanceRandomDelay
    Random delay in hours (0-6) added to MaintenanceActivationTime. Default 2.

.PARAMETER SetPowerPolicies
    Enable shared-PC-style power policies. Requires IdleSleepTimeoutMinutes.

.PARAMETER IdleSleepTimeoutMinutes
    Minutes of inactivity before sleep. Required with SetPowerPolicies.

.PARAMETER Reinstall
    Remove existing kiosk settings before applying.

.PARAMETER Version
    Written to HKLM:\SOFTWARE\Kiosk\Version for SCCM/Intune detection.

.EXAMPLE
    .\Set-OmnissaVDIKioskSettings.ps1 -HorizonServerUrl 'https://horizon.firma.tld'

.EXAMPLE
    .\Set-OmnissaVDIKioskSettings.ps1   # uses HorizonServerUrl from the CONFIG region below
#>
[CmdletBinding()]
param (
    [ValidatePattern('^https?://')]
    [string]$HorizonServerUrl,

    [string]$HorizonClientPath,

    [string]$HorizonDesktopName,

    [ValidateSet('fullscreen', 'multimonitor', 'windowLarge', 'windowSmall')]
    [string]$HorizonDesktopLayout,

    [string[]]$HorizonAllowedExtraExes,

    [switch]$ConfigureAutomaticMaintenance,

    [ValidateScript({
        if ($_ -match '^\d{2}:\d{2}:\d{2}$') {
            $ts = [TimeSpan]::ParseExact($_, 'hh\:mm\:ss', $null)
            if ($ts -ge [TimeSpan]::Zero -and $ts -lt [TimeSpan]::FromHours(24)) { return $true }
            throw "Time must be between 00:00:00 and 23:59:59"
        }
        throw "Time must be in HH:mm:ss format (e.g. 02:00:00)"
    })]
    [string]$MaintenanceActivationTime = '02:00:00',

    [ValidateRange(0, 6)]
    [int]$MaintenanceRandomDelay = 2,

    [switch]$SetPowerPolicies,

    [ValidateRange(30, 1440)]
    [int]$IdleSleepTimeoutMinutes,

    [switch]$Reinstall,

    [version]$Version = '1.0.0'
)

#region ============================== CONFIG (edit here) ==============================
# Hardcode the values you want so SCCM/Intune can call this script WITHOUT arguments.
# A value passed on the command line overrides the corresponding default below.
if (-not $HorizonServerUrl)     { $HorizonServerUrl     = 'https://horizon.firma.tld' }   # <== YOUR Connection Server URL
if (-not $HorizonClientPath)    { $HorizonClientPath    = 'C:\Program Files\Omnissa\Omnissa Horizon Client\horizon-client.exe' }
if (-not $HorizonDesktopName)   { $HorizonDesktopName   = '' }                              # optional: pool/desktop name for auto-connect
if (-not $HorizonDesktopLayout) { $HorizonDesktopLayout = 'fullscreen' }
if (-not $HorizonAllowedExtraExes) { $HorizonAllowedExtraExes = @() }
$ISLLightClientPath = 'C:\Support\ISL Light Client.exe'                                      # Remote support client (allowed + pinned to Start/taskbar)
#endregion

#region Parameter Validation
if ($HorizonServerUrl -notmatch '^https?://') {
    throw "HorizonServerUrl is not set to a valid https URL. Edit the CONFIG region or pass -HorizonServerUrl."
}
if ($HorizonServerUrl -eq 'https://horizon.firma.tld') {
    throw "HorizonServerUrl is still the placeholder 'https://horizon.firma.tld'. Set your real Connection Server URL."
}
if ($SetPowerPolicies -and -not $PSBoundParameters.ContainsKey('IdleSleepTimeoutMinutes')) {
    throw "IdleSleepTimeoutMinutes is required when SetPowerPolicies is used."
}
#endregion

#region Restart in 64-bit PowerShell if necessary
If ($ENV:PROCESSOR_ARCHITEW6432 -eq "AMD64") {
    $scriptArguments = $null
    Try {
        foreach ($k in $PSBoundParameters.keys) {
            switch ($PSBoundParameters[$k].GetType().Name) {
                "SwitchParameter" { If ($PSBoundParameters[$k].IsPresent) { $scriptArguments += "-$k " } }
                "String"          { $scriptArguments += "-$k `"$($PSBoundParameters[$k])`" " }
                "String[]"        { $scriptArguments += "-$k `"$($PSBoundParameters[$k] -join '`",`"')`" " }
                "Int32"           { $scriptArguments += "-$k $($PSBoundParameters[$k]) " }
                "Boolean"         { $scriptArguments += "-$k `$$($PSBoundParameters[$k]) " }
                "Version"         { $scriptArguments += "-$k `"$($PSBoundParameters[$k])`" " }
            }
        }
        $launchArgs = If ($scriptArguments) { "-File `"$PSCommandPath`" $scriptArguments" } Else { "-File `"$PSCommandPath`"" }
        $RunScript = Start-Process -FilePath "$env:WINDIR\SysNative\WindowsPowershell\v1.0\PowerShell.exe" -ArgumentList $launchArgs -PassThru -Wait -NoNewWindow
    } Catch {
        Throw "Failed to start 64-bit PowerShell: $_"
    }
    Exit $RunScript.ExitCode
}
#endregion

$Script:FullName = $MyInvocation.MyCommand.Path
$Script:Dir      = Split-Path $Script:FullName
$EventLog        = 'Omnissa-VDI-Kiosk'
$EventSource     = 'ConfigScript'

$OS = Get-WmiObject -Class Win32_OperatingSystem
[string]$FullOSVersion = [string]$OS.Version + '.' + (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").UBR
If ($OS.Name -match 'LTSC') { $LTSC = $true }

$DirAssignedAccess   = Join-Path $Script:Dir 'AssignedAccess\MultiApp'
$DirProvisioning     = Join-Path $Script:Dir 'ProvisioningPackages'
$DirGPO              = Join-Path $Script:Dir 'gposettings'
$DirTools            = Join-Path $Script:Dir 'Tools'
$DirUserLogos        = Join-Path $Script:Dir 'UserLogos'
$DirFunctions        = Join-Path $Script:Dir 'Scripts\Functions'
$DirSchedTasksSrc    = Join-Path $Script:Dir 'Scripts\ScheduledTasks'
$DirCustomLaunch     = Join-Path $Script:Dir 'Scripts\CustomLaunchScript'
$DirKiosk            = Join-Path $env:SystemDrive 'KioskSettings'
$DirSchedTasksDst    = Join-Path $DirKiosk 'ScheduledTasks'

$HorizonDir = Split-Path -Parent $HorizonClientPath
$LnkPath    = Join-Path "$env:ProgramData\Microsoft\Windows\Start Menu\Programs" 'Omnissa Horizon Client.lnk'

#region Load Functions
If (-not (Test-Path -Path $DirFunctions)) { Write-Error "Functions directory not found: $DirFunctions"; Exit 1 }
Get-ChildItem -Path $DirFunctions -Filter '*.ps1' | ForEach-Object {
    Try { . $_.FullName } Catch { Write-Error "Failed to load $($_.FullName): $_"; Exit 1 }
}
#endregion

#region Initialise Event Log
If (-not [System.Diagnostics.EventLog]::SourceExists($EventSource) -or -not [System.Diagnostics.EventLog]::Exists($EventLog)) {
    New-EventLog -LogName $EventLog -Source $EventSource -ErrorAction SilentlyContinue
    Do { Start-Sleep -Seconds 1 } Until ([System.Diagnostics.EventLog]::SourceExists($EventSource) -and [System.Diagnostics.EventLog]::Exists($EventLog))
}
Write-Log -EventLog $EventLog -EventSource $EventSource -EntryType Information -EventId 1 -Message @"
Starting Omnissa VDI Kiosk Configuration
Script:        $($Script:FullName)
OS:            $($OS.Caption) $FullOSVersion (LTSC=$([bool]$LTSC))
HorizonServer: $HorizonServerUrl
HorizonClient: $HorizonClientPath
ExtraExes:     $(($HorizonAllowedExtraExes | Measure-Object).Count) entries
Parameters:    $($PSBoundParameters | Out-String)
"@
#endregion

#region Pre-Flight: Horizon Client must be present (it is pre-installed; we never install it)
$DetectedVersion = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Omnissa\Horizon\Client' -Name 'Version' -ErrorAction SilentlyContinue).Version
If (-not $DetectedVersion -and (Test-Path -Path $HorizonClientPath -PathType Leaf)) {
    $DetectedVersion = (Get-Item -Path $HorizonClientPath).VersionInfo.FileVersion
}
If (-not $DetectedVersion) {
    $msg = "Omnissa Horizon Client not detected (no HKLM:\SOFTWARE\Omnissa\Horizon\Client\Version and no '$HorizonClientPath'). It must be pre-installed before running this script."
    Write-Log -EventLog $EventLog -EventSource $EventSource -EntryType Error -EventId 2 -Message $msg
    Throw $msg
}
If (-not (Test-Path -Path $HorizonClientPath -PathType Leaf)) {
    $msg = "Horizon Client reported as installed ($DetectedVersion) but '$HorizonClientPath' does not exist. Check HorizonClientPath."
    Write-Log -EventLog $EventLog -EventSource $EventSource -EntryType Error -EventId 2 -Message $msg
    Throw $msg
}
Write-Log -EventLog $EventLog -EventSource $EventSource -EntryType Information -EventId 3 -Message "Detected Omnissa Horizon Client $DetectedVersion at '$HorizonClientPath'."

If (Get-PendingReboot) {
    Write-Log -EventLog $EventLog -EventSource $EventSource -EntryType Warning -EventId 4 -Message "Pending reboot detected. Restarting in 15 seconds."
    Start-Process -FilePath 'shutdown.exe' -ArgumentList '/r /t 15' -NoNewWindow
    Exit 3010
}

Copy-Item -Path "$DirTools\lgpo.exe" -Destination "$env:SystemRoot\System32" -Force
#endregion

#region Remove Previous Versions
If ($Reinstall) {
    Write-Log -EventLog $EventLog -EventSource $EventSource -EntryType Information -EventId 5 -Message "Reinstall: removing existing kiosk settings."
    & "$Script:Dir\Remove-KioskSettings.ps1" -Reinstall
}
#endregion

#region Remove Built-in Bloat
If (-not $LTSC) {
    Write-Log -EventLog $EventLog -EventSource $EventSource -EntryType Information -EventId 25 -Message "Removing built-in Windows bloat apps."
    Remove-BuiltInApps
}
If (Test-Path -Path "$env:SystemRoot\Syswow64\onedrivesetup.exe") {
    Start-Process -FilePath "$env:SystemRoot\Syswow64\onedrivesetup.exe" -ArgumentList "/uninstall" -Wait -ErrorAction SilentlyContinue
    $OneDrivePresent = $true
} ElseIf (Test-Path -Path "$env:ProgramFiles\Microsoft OneDrive") {
    $OneDriveSetup = Get-ChildItem -Path "$env:ProgramFiles\Microsoft OneDrive" -Filter 'onedrivesetup.exe' -Recurse -ErrorAction SilentlyContinue
    If ($OneDriveSetup) { Start-Process -FilePath $OneDriveSetup[0].FullName -ArgumentList "/uninstall" -Wait -ErrorAction SilentlyContinue; $OneDrivePresent = $true }
}
#endregion

#region KioskSettings Directory + ACLs
If (-not (Test-Path $DirKiosk)) { New-Item -Path $DirKiosk -ItemType Directory -Force | Out-Null }
$AdminsSID = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-544")
$Group = $AdminsSID.Translate([System.Security.Principal.NTAccount])
$ACL = Get-ACL $DirKiosk
$ACL.SetOwner($Group)
Set-ACL -Path $DirKiosk -AclObject $ACL
Update-ACL -Path $DirKiosk -Identity 'S-1-5-32-544' -FileSystemRights 'FullControl' -Type 'Allow'
Update-ACL -Path $DirKiosk -Identity 'S-1-5-32-545' -FileSystemRights 'ReadAndExecute' -Type 'Allow'
Update-ACL -Path $DirKiosk -Identity 'S-1-5-18'      -FileSystemRights 'FullControl' -Type 'Allow'
Update-ACLInheritance -Path $DirKiosk -DisableInheritance $true -PreserveInheritedACEs $false
Write-Log -EventLog $EventLog -EventSource $EventSource -EntryType Information -EventId 40 -Message "Created $DirKiosk and tightened ACLs."
#endregion

#region Deploy Horizon Shortcut, Auto-Launch, and Fullscreen Maximizer
# The pinned Start/taskbar shortcut targets horizon-client.exe DIRECTLY so the running client shares
# the same taskbar button as the pin. (A shortcut that launches the client via powershell has a
# different identity, so the running window would appear as a SECOND taskbar icon next to the pin.)
$HorizonArgs = "-serverURL `"$HorizonServerUrl`" -desktopLayout $HorizonDesktopLayout"
If ($HorizonDesktopName) { $HorizonArgs += " -desktopName `"$HorizonDesktopName`"" }

$ObjShell = New-Object -ComObject WScript.Shell
$Shortcut = $ObjShell.CreateShortcut($LnkPath)
$Shortcut.TargetPath       = $HorizonClientPath
$Shortcut.Arguments        = $HorizonArgs
$Shortcut.WorkingDirectory = $HorizonDir
$Shortcut.IconLocation     = "$HorizonClientPath,0"
$Shortcut.Description      = "Omnissa Horizon VDI Client"
$Shortcut.Save()

# Auto-start the client at logon using the SAME shortcut, so it shares the pinned taskbar button.
$DirStartup = "$env:SystemDrive\Users\Default\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup"
If (-not (Test-Path $DirStartup)) { New-Item -Path $DirStartup -ItemType Directory -Force | Out-Null }
Copy-Item -Path $LnkPath -Destination $DirStartup -Force

# Deploy the fullscreen maximizer and auto-start it hidden. It does NOT launch the client; it only keeps
# the Horizon window maximized and the taskbar auto-hidden for the whole session (covers logon AND a
# manual relaunch from the taskbar). Running hidden, it adds no taskbar icon of its own.
$LauncherDst   = Join-Path $DirKiosk 'Launch-HorizonFullscreen.ps1'
Copy-Item -Path (Join-Path $DirCustomLaunch 'Launch-HorizonFullscreen.ps1') -Destination $LauncherDst -Force
$PowerShellExe     = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$MaximizerLnk      = Join-Path $DirStartup 'Horizon Fullscreen.lnk'
$MaximizerShortcut = $ObjShell.CreateShortcut($MaximizerLnk)
$MaximizerShortcut.TargetPath  = $PowerShellExe
$MaximizerShortcut.Arguments   = "-ExecutionPolicy Bypass -WindowStyle Hidden -NonInteractive -File `"$LauncherDst`""
$MaximizerShortcut.WindowStyle = 7
$MaximizerShortcut.Save()
Write-Log -EventLog $EventLog -EventSource $EventSource -EntryType Information -EventId 45 -Message "Deployed Horizon shortcut (direct launch), logon auto-start, and the hidden fullscreen maximizer."

# Remote support client (ISL Light): create a Start menu shortcut so it can be pinned to Start/taskbar.
# Launched on demand only (not auto-started); the shortcut targets the exe directly -> single taskbar icon.
$IslLnk      = Join-Path "$env:ProgramData\Microsoft\Windows\Start Menu\Programs" 'ISL Light Client.lnk'
$IslShortcut = $ObjShell.CreateShortcut($IslLnk)
$IslShortcut.TargetPath       = $ISLLightClientPath
$IslShortcut.WorkingDirectory = Split-Path -Parent $ISLLightClientPath
$IslShortcut.IconLocation     = "$ISLLightClientPath,0"
$IslShortcut.Description      = "ISL Light remote support client"
$IslShortcut.Save()
If (-not (Test-Path -Path $ISLLightClientPath -PathType Leaf)) {
    Write-Log -EventLog $EventLog -EventSource $EventSource -EntryType Warning -EventId 47 -Message "ISL Light Client not present at '$ISLLightClientPath' yet; the Start/taskbar pin resolves once it is deployed."
}
Write-Log -EventLog $EventLog -EventSource $EventSource -EntryType Information -EventId 46 -Message "Created ISL Light Client shortcut for the Start/taskbar pin at '$IslLnk' (target '$ISLLightClientPath')."
#endregion

#region Build & Apply Multi-App Kiosk Configuration
$TemplateXml = Join-Path $DirAssignedAccess 'Horizon_Autologon.xml'
$DeployedXml = Join-Path $DirKiosk 'AssignedAccessConfiguration.xml'

$ExtraXml = ''
If ($HorizonAllowedExtraExes.Count -gt 0) {
    $ExtraXml = ($HorizonAllowedExtraExes | ForEach-Object { "          <App DesktopAppPath=`"$_`" />" }) -join "`r`n"
}

$XmlContent = Get-Content -Path $TemplateXml -Raw
$XmlContent = $XmlContent.Replace('{{HORIZON_DIR}}', $HorizonDir)
$XmlContent = $XmlContent.Replace('{{HORIZON_LNK}}', $LnkPath.Replace('\', '\\'))
$XmlContent = $XmlContent.Replace('{{HORIZON_EXTRA_APPS}}', $ExtraXml)
$XmlContent = $XmlContent.Replace('{{ISL_PATH}}', $ISLLightClientPath)
$XmlContent | Out-File -FilePath $DeployedXml -Encoding utf8 -Force

# MDM_AssignedAccess.Configuration is write-only -> no readback. Success = no exception from Set.
Try {
    Set-AssignedAccessConfiguration -FilePath $DeployedXml -ErrorAction Stop
    Write-Log -EventLog $EventLog -EventSource $EventSource -EntryType Information -EventId 50 -Message "Multi-App Kiosk configuration applied.`n-----BEGIN-----`n$(Get-Content $DeployedXml -Raw)`n-----END-----"
} Catch {
    Write-Log -EventLog $EventLog -EventSource $EventSource -EntryType Error -EventId 51 -Message "Multi-App Kiosk configuration failed: $($_.Exception.Message). Reboot and retry."
    Exit 1618
}
#endregion

#region Provisioning Packages
$ProvisioningPackages = @(
    'DisableWindowsSpotlight.ppkg'
    'DisableFirstLogonAnimation.ppkg'
    'DisableAdvertisingId.ppkg'
    'HideStartMenuElements.ppkg'
)
New-Item -Path "$DirKiosk\ProvisioningPackages" -ItemType Directory -Force | Out-Null
ForEach ($Pkg in $ProvisioningPackages) {
    $Dst = Join-Path "$DirKiosk\ProvisioningPackages" $Pkg
    Copy-Item -Path (Join-Path $DirProvisioning $Pkg) -Destination $Dst -Force
    Install-ProvisioningPackage -PackagePath $Dst -ForceInstall -QuietInstall | Out-Null
    Write-Log -EventLog $EventLog -EventSource $EventSource -EntryType Information -EventId 65 -Message "Installed provisioning package $Pkg."
}
#endregion

#region Local GPO Hardening
$null = cmd /c lgpo.exe /t "$DirGPO\computer-HideWindowsSecurityControl.txt" '2>&1'
Write-Log -EventLog $EventLog -EventSource $EventSource -EntryType Information -EventId 80 -Message "Hid Windows Security systray control. lgpo exit=[$LastExitCode]"

$null = cmd /c lgpo.exe /t "$DirGPO\disablePasswordForUnlock.txt" '2>&1'
Write-Log -EventLog $EventLog -EventSource $EventSource -EntryType Information -EventId 81 -Message "Disabled password requirement for wake/screensaver. lgpo exit=[$LastExitCode]"

$null = cmd /c lgpo.exe /t "$DirGPO\nonadmins-autologon.txt" '2>&1'
Write-Log -EventLog $EventLog -EventSource $EventSource -EntryType Information -EventId 82 -Message "Removed lock/sign-out/switch-user/change-password for non-admins. lgpo exit=[$LastExitCode]"

$null = cmd /c lgpo.exe /t "$DirGPO\nonadmins-HideAndRestrictDrives.txt" '2>&1'
Write-Log -EventLog $EventLog -EventSource $EventSource -EntryType Information -EventId 84 -Message "Hid and restricted all drives for non-admins. lgpo exit=[$LastExitCode]"

$null = cmd /c lgpo.exe /t "$DirGPO\nonadmins-DisableTaskManager.txt" '2>&1'
Write-Log -EventLog $EventLog -EventSource $EventSource -EntryType Information -EventId 85 -Message "Disabled Task Manager for non-admins. lgpo exit=[$LastExitCode]"

$null = cmd /c lgpo.exe /t "$DirGPO\computer-DisablePrivacyExperience.txt" '2>&1'
Write-Log -EventLog $EventLog -EventSource $EventSource -EntryType Information -EventId 86 -Message "Disabled OOBE Privacy Experience. lgpo exit=[$LastExitCode]"

# Wi-Fi must always be reachable on mobile devices. Settings is whitelisted (required so the network
# icon's "Network settings" link works) and locked to the Wi-Fi/network pages only.
$null = cmd /c lgpo.exe /t "$DirGPO\nonadmins-ShowSettings.txt" '2>&1'
Write-Log -EventLog $EventLog -EventSource $EventSource -EntryType Information -EventId 83 -Message "Restricted Settings to Wi-Fi pages for non-admins. lgpo exit=[$LastExitCode]"

# User logos
$null = cmd /c lgpo.exe /t "$DirGPO\computer-userlogos.txt" '2>&1'
Copy-Item -Path "$env:ProgramData\Microsoft\User Account Pictures" -Destination "$DirKiosk\UserLogos" -Recurse -Force -ErrorAction SilentlyContinue
Get-ChildItem -Path $DirUserLogos | Copy-Item -Destination "$env:ProgramData\Microsoft\User Account Pictures" -Force
Write-Log -EventLog $EventLog -EventSource $EventSource -EntryType Information -EventId 87 -Message "Configured default user logos. lgpo exit=[$LastExitCode]"

If ($ConfigureAutomaticMaintenance) {
    $MaintenanceRandomDelayPT     = "PT$($MaintenanceRandomDelay)H"
    $MaintenanceActivationTimeISO = "2000-01-01T$MaintenanceActivationTime"
    $srcFile = Join-Path $DirGPO 'AutomaticMaintenance.txt'
    $outFile = Join-Path "$env:SystemRoot\SystemTemp" 'AutomaticMaintenance.txt'
    If ($MaintenanceRandomDelay -eq 0) {
        (Get-Content -Path $srcFile).Replace('<ActivationBoundary>', $MaintenanceActivationTimeISO) | Out-File $outFile
    } Else {
        $content = (Get-Content -Path $srcFile).Replace('<ActivationBoundary>', $MaintenanceActivationTimeISO)
        $content += @('','Computer','Software\Policies\Microsoft\Windows\Task Scheduler\Maintenance','Randomized','DWORD:1',
                      '','Computer','Software\Policies\Microsoft\Windows\Task Scheduler\Maintenance','RandomDelay',"SZ:$MaintenanceRandomDelayPT")
        $content | Out-File $outFile
    }
    $null = cmd /c lgpo /s "$outFile" '2>&1'
    Remove-Item -Path $outFile -Force -ErrorAction SilentlyContinue
    Write-Log -EventLog $EventLog -EventSource $EventSource -EntryType Information -EventId 90 -Message "Configured Automatic Maintenance. lgpo exit=[$LastExitCode]"
}

If ($SetPowerPolicies) {
    $srcFile = Join-Path $DirGPO 'PowerSettings.txt'
    $outFile = Join-Path "$env:SystemRoot\SystemTemp" 'PowerSettings.txt'
    (Get-Content -Path $srcFile).Replace('<SleepTimeOut>', ($IdleSleepTimeoutMinutes * 60)) | Out-File $outFile
    $null = cmd /c lgpo /s "$outFile" '2>&1'
    Remove-Item -Path $outFile -Force -ErrorAction SilentlyContinue
    Write-Log -EventLog $EventLog -EventSource $EventSource -EntryType Information -EventId 91 -Message "Configured Power Policies (sleep=$IdleSleepTimeoutMinutes min). lgpo exit=[$LastExitCode]"
}
#endregion

#region Registry Edits (with restore CSV)
$RegValues = @(
    [PSCustomObject]@{ Path='HKLM:\SOFTWARE\Omnissa\Horizon\Client';                       Name='MRBroker';            PropertyType='String'; Value=$HorizonServerUrl; Description='Default Horizon Connection Server' }
    [PSCustomObject]@{ Path='HKLM:\SOFTWARE\Omnissa\Horizon\Client';                       Name='AutoUpdateAllowed';   PropertyType='String'; Value='false';          Description='Disable Horizon Client auto-update on the kiosk' }
    [PSCustomObject]@{ Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\WorkplaceJoin';     Name='BlockAADWorkplaceJoin'; PropertyType='DWord'; Value=1;              Description='Suppress "Stay signed in to all your apps" popup' }
    [PSCustomObject]@{ Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name='StartShownOnUpgrade'; PropertyType='DWord'; Value=1;          Description='Prevent Start menu from opening automatically' }
    # Stop the recurring "blocked by your administrator" popups by turning off Store auto-updates, so the
    # kiosk's AppLocker no longer blocks background Store app installs/updates (installed apps are kept).
    [PSCustomObject]@{ Path='HKLM:\SOFTWARE\Policies\Microsoft\WindowsStore';              Name='AutoDownload';          PropertyType='DWord';  Value=2;   Description='Turn off Microsoft Store automatic app updates' }
    # Windows AI hardening (Enterprise SKU): remove Recall and block its data capture, disable Click to Do
    # and the Settings AI agent. The Copilot app itself is additionally blocked by the kiosk AppLocker.
    [PSCustomObject]@{ Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI';         Name='AllowRecallEnablement'; PropertyType='DWord';  Value='0'; Description='Make Recall unavailable and remove its bits' }
    [PSCustomObject]@{ Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI';         Name='DisableAIDataAnalysis'; PropertyType='DWord';  Value=1;   Description='Disable saving snapshots for Recall' }
    [PSCustomObject]@{ Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI';         Name='DisableClickToDo';      PropertyType='DWord';  Value=1;   Description='Disable Click to Do' }
    [PSCustomObject]@{ Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI';         Name='DisableSettingsAgent';  PropertyType='DWord';  Value=1;   Description='Disable the Settings agentic search experience' }
    [PSCustomObject]@{ Path='HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot';    Name='TurnOffWindowsCopilot'; PropertyType='DWord';  Value=1;   Description='Turn off Windows Copilot for the kiosk user' }
)
If ($OneDrivePresent) {
    $RegValues += [PSCustomObject]@{ Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'; Name='OneDriveSetup'; PropertyType='String'; Value=''; Description='Stop per-user OneDriveSetup' }
}

$FileRestore = "$DirKiosk\RegKeyRestore.csv"
New-Item -Path $FileRestore -ItemType File -Force | Out-Null
Add-Content -Path $FileRestore -Value 'Path,Name,PropertyType,Value,Description'

If ($RegValues | Where-Object { $_.Path -like 'HKCU:*' }) {
    Start-Process -FilePath "REG.exe" -ArgumentList "LOAD", "HKLM\Default", "$env:SystemDrive\Users\default\ntuser.dat" -Wait
}
ForEach ($Entry in $RegValues) {
    $PathHKLM = If ($Entry.Path -like 'HKCU:*') { $Entry.Path.Replace("HKCU:\", "HKLM:\Default\") } Else { $Entry.Path }
    $Current  = Get-ItemProperty -Path $PathHKLM -Name $Entry.Name -ErrorAction SilentlyContinue
    If ($Current) { Add-Content -Path $FileRestore -Value "$($Entry.Path),$($Entry.Name),$($Entry.PropertyType),$($Current.$($Entry.Name))" }
    Else          { Add-Content -Path $FileRestore -Value "$($Entry.Path),$($Entry.Name),," }
    If ($null -ne $Entry.Value -and $Entry.Value -ne '') {
        Set-RegistryValue -Path $PathHKLM -Name $Entry.Name -PropertyType $Entry.PropertyType -Value $Entry.Value
        Write-Log -EventLog $EventLog -EventSource $EventSource -EntryType Information -EventId 100 -Message "Set '$($Entry.Name)' = '$($Entry.Value)' at $($Entry.Path)"
    } ElseIf ($Current) {
        Remove-ItemProperty -Path $PathHKLM -Name $Entry.Name -ErrorAction SilentlyContinue
    }
}
If (Test-Path -Path 'HKLM:\Default') {
    [GC]::Collect(); [GC]::WaitForPendingFinalizers(); Start-Sleep -Seconds 5
    $null = cmd /c REG UNLOAD "HKLM\Default" '2>&1'
}
#endregion

#region Keyboard Filter (max lockdown - blocks Win+R/F/S/X/L, Shift+Ctrl+Esc, Win+I, etc.)
Write-Log -EventLog $EventLog -EventSource $EventSource -EntryType Information -EventId 125 -Message "Enabling Keyboard Filter optional feature."
Enable-WindowsOptionalFeature -Online -FeatureName Client-KeyboardFilter -All -NoRestart | Out-Null

If (-not (Test-Path -Path $DirSchedTasksDst)) { New-Item -Path $DirSchedTasksDst -ItemType Directory -Force | Out-Null }
Copy-Item -Path (Join-Path $DirSchedTasksSrc 'Set-KeyboardFilterConfiguration.ps1') -Destination $DirSchedTasksDst -Force

$TaskName              = "(Omnissa VDI) - Configure Keyboard Filter"
$TaskScriptEventSource = 'Keyboard Filter Configuration'
New-EventLog -LogName $EventLog -Source $TaskScriptEventSource -ErrorAction SilentlyContinue
$TaskScriptFullName    = Join-Path $DirSchedTasksDst 'Set-KeyboardFilterConfiguration.ps1'
$TaskTrigger           = New-ScheduledTaskTrigger -AtStartup
$TaskScriptArgs        = "-TaskName `"$TaskName`" -EventLog `"$EventLog`" -EventSource `"$TaskScriptEventSource`""
$TaskAction            = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-ExecutionPolicy Bypass -File $TaskScriptFullName $TaskScriptArgs"
$TaskPrincipal         = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
$TaskSettings          = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 15) -MultipleInstances IgnoreNew -AllowStartIfOnBatteries
Register-ScheduledTask -TaskName $TaskName -Description "Configures Keyboard Filter after reboot, then unregisters itself." -Action $TaskAction -Settings $TaskSettings -Principal $TaskPrincipal -Trigger $TaskTrigger -Force | Out-Null
Write-Log -EventLog $EventLog -EventSource $EventSource -EntryType Information -EventId 126 -Message "Scheduled Task '$TaskName' registered (runs at next boot, then unregisters itself)."
#endregion

#region Finalise
Write-Log -EventLog $EventLog -EventSource $EventSource -EntryType Information -EventId 150 -Message "Running gpupdate /force."
$GPUpdate = Start-Process -FilePath 'GPUpdate' -ArgumentList '/force' -Wait -PassThru
Write-Log -EventLog $EventLog -EventSource $EventSource -EntryType Information -EventId 151 -Message "gpupdate exit code: $($GPUpdate.ExitCode)"

Set-RegistryValue -Path 'HKLM:\Software\Kiosk' -Name 'Version'          -PropertyType 'String' -Value $Version.ToString()
Set-RegistryValue -Path 'HKLM:\Software\Kiosk' -Name 'Variant'          -PropertyType 'String' -Value 'OmnissaVDI'
Set-RegistryValue -Path 'HKLM:\Software\Kiosk' -Name 'HorizonServerUrl' -PropertyType 'String' -Value $HorizonServerUrl

Write-Log -EventLog $EventLog -EventSource $EventSource -EntryType Information -EventId 199 -Message "Omnissa VDI Kiosk v$($Version.ToString()) configured. Exit 3010 (reboot required)."
Exit 3010
#endregion
