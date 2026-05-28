# Azure Virtual Desktop Client Kiosk - Implementation Guide

**Navigation:** [Overview](README.md) | [Solution Overview](SOLUTION_OVERVIEW.md) | Implementation Guide | [Intune Deployment](INTUNE_DEPLOYMENT.md)

---

## Table of Contents

- [Azure Virtual Desktop Client Kiosk - Implementation Guide](#azure-virtual-desktop-client-kiosk---implementation-guide)
  - [Table of Contents](#table-of-contents)
  - [Parameters](#parameters)
  - [Air-Gapped Cloud Support](#air-gapped-cloud-support)
    - [PowerShell](#powershell)
    - [Air-Gapped Cloud Documentation](#air-gapped-cloud-documentation)
  - [Manual Installation](#manual-installation)
  - [Manual Removal](#manual-removal)
  - [Troubleshooting](#troubleshooting)
    - [Logging](#logging)
    - [Emergency Access](#emergency-access)
    - [Configuration Verification](#configuration-verification)

## Parameters

The table below describes each parameter and any requirements or usage information.

**Table 1:** Set-RemoteDesktopClientKioskSettings.ps1 Parameters

| Parameter Name | Type   | Description | Notes/Requirements |
|:---------------|:------:|:------------|:-------------------|
| `Autologon` | Switch | Determines if Autologon is enabled through the Shell Launcher or Multi-App Kiosk configuration. | When configured, Windows will automatically create a new user, 'KioskUser0', which will not have a password and be configured to automatically logon when Windows starts. **This is the primary parameter used to configure the kiosk for Scenario 2**. |
| `ClientShell` | Switch | Determines whether the default Windows shell (explorer.exe) is replaced by the Remote Desktop client for Windows. | When not specified the default shell is used and, on Windows 11 22H2 and later, the Multi-App Kiosk configuration is used along with additional local group policy settings and provisioning packages to lock down the shell. On Windows 10, only local group policy settings and provisioning packages are used to lock down the shell. |
| `AutoSubscribe` | switch | Determines whether the Remote Desktop client is configured to automatically subscribe to a workspace. | |
| `Cloud` | String | Required when 'AutoSubscribe' is selected. Determines the Azure environment to which you are connecting. | Determines the Url of the Remote Desktop Feed which varies by environment by setting the '$SubscribeUrl' variable and replacing placeholders in several files during installation. The possible values are 'AzureCloud', 'AzureChina', 'AzureUSGovernment', 'AzureGovernmentSecret', and 'AzureGovernmentTopSecret'. See [Air-Gapped Cloud Support](#air-gapped-cloud-support) for updating the code to support 'AzureGovernmentSecret' and 'AzureGovernmentTopSecret'. Default is 'AzureCloud' |
| `InstallRemoteDesktopClient` | Switch | Determines if the latest Remote Desktop client for Windows and the Visual Studio C++ Redistributables are downloaded from the Internet and installed prior to configuration. | Supports both online (automatic download) and offline installation methods. For offline/air-gapped environments, see the README files in `Apps\RemoteDesktopClient\` and `Apps\VisualC++Redistributables\` folders for instructions on placing local installation files. When local files are present, no internet connection is required. |
| `SharedPC` | Switch | Determines if the computer is setup as a shared PC. The account management process is enabled and all user profiles are automatically deleted on logoff. | Only valid for direct logon mode ("Autologon" switch is not used). |
| `ShowSettings` | Switch | Determines if the Settings App and Control Panel are restricted to only allow access to the Display Settings page. If this value is not set, then the Settings app and Control Panel are not displayed or accessible. | Only valid when the `ClientShell` switch is not specified. |
| `DeviceRemovalAction` | string | determines what occurs when a FIDO Passkey device or SmartCard is removed from the system.  | The possible values are 'Lock', 'Logoff', or 'ResetClient'. |
| `DeviceVendorID` | String | Defines the Vendor ID of the hardware FIDO2 authentication token that, if removed, will trigger the action defined in `DeviceRemovalAction`. | You can find the Vendor ID by looking at the Hardware IDs property of the device in device manager. See the [example for a Yubikey](../../docs\media\HardwareIds.png). |
| `SmartCard` | Switch | Determines if SmartCard removal will trigger the action specified by `DeviceRemovalAction`. | This value is only used when `DeviceRemovalAction` is defined. |
| `IdleTimeoutAction` | string | Determines what occurs when the system is idle for a specified amount of time. | The possible values are 'Lock', 'Logoff', or 'ResetClient'. |
| `IdleTimeout` | int | Determines the number of seconds in the that system will wait before performing the action specified in the `IdleTimeoutAction` parameter. | Default is 900 seconds (15 minutes). |
| `SystemDisconnectAction` | string | Determines what occurs when the remote desktop session connection is disconnected by the system. This could be due to an IdleTimeout on the session host in the SSO scenario or the user has initiated a connection to the session host from another client. | The possible values are 'Lock', 'Logoff', or 'ResetClient'. |
| `UserDisconnectSignOutAction` | string | Determines what occurs when the user disconnects or signs out from the remote session. | The possible values are 'Lock', 'Logoff', or 'ResetClient'. |
| `ConfigureAutomaticMaintenance` | Switch | Determines if Windows automatic maintenance settings are configured via Local Group Policy. | When enabled, maintenance tasks (Windows Update, disk defragmentation, security scans) will run at the specified activation time with optional random delay to prevent multiple systems from running maintenance simultaneously. |
| `MaintenanceActivationTime` | String | Specifies the time of day when automatic maintenance should begin in HH:mm:ss format (e.g., "02:00:00" for 2:00 AM). | Default is "00:00:00" (midnight). The time is converted to ISO 8601 format internally with date 2000-01-01T for policy application. Only valid when `ConfigureAutomaticMaintenance` is specified. |
| `MaintenanceRandomDelay` | Int | Specifies the maximum random delay in hours that can be added to the maintenance activation time. | Valid values are 0-6 hours. Default is 2 hours. The value is converted to ISO 8601 duration format (PT#H) internally. Set to 0 to disable random delay. Only valid when `ConfigureAutomaticMaintenance` is specified. |
| `SetPowerPolicies` | Switch | Determines if power management policies are configured via Local Group Policy to optimize behavior for shared PC scenarios. | When enabled, configures power button, sleep button, and lid switch actions to sleep, enables energy saver settings, disables hibernation, and enables standby states while turning off hybrid sleep for both battery and plugged-in scenarios. Requires `IdleSleepTimeoutMinutes` parameter to be specified. Useful for shared PC and kiosk deployments to manage power consumption. |
| `IdleSleepTimeoutMinutes` | Int | Specifies the number of minutes of user inactivity before the system automatically goes to sleep. | Valid values are 30-1440 minutes (30 minutes to 24 hours). Required when `SetPowerPolicies` is used. Works in conjunction with SetPowerPolicies to provide complete power management for shared PC environments. |
| `Reinstall` | Switch | Allows the script to be re-run on a system that has already been configured. | When specified, triggers the removal of existing kiosk settings before applying the new configuration. Use this switch when updating or reconfiguring an already-deployed kiosk. |
| `Version` | Version |  Writes this value to a string value called 'version' at HKLM:\SOFTWARE\Kiosk registry key. | Allows tracking of the installed version using configuration management software such as Microsoft Endpoint Manager or Microsoft Endpoint Configuration Manager by querying the value of this registry value. |

## Air-Gapped Cloud Support

In order to use this solution in Microsoft's US Government Air-Gapped clouds, you'll need to get the cloud suffix from the environment. You can do this easily with PowerShell or get the information from our Air-Gapped cloud documentation.

### PowerShell

1. Connect to the Azure Environment. You may need to refer to [Get-Started PowerShell Azure Government Secret](https://review.learn.microsoft.com/en-us/microsoft-government-secret/azure/azure-government-secret/quick-starts/documentation-government-secret-get-started-azure-powershell-connect?branch=live) or [Get-Started PowerShell Azure Government Top Secret](https://review.learn.microsoft.com/en-us/microsoft-government-topsecret/azure/azure-government-top-secret/quickstarts/documentation-government-top-secret-get-started-powershell-connect?branch=live)

    ``` powershell
    Connect-AzAccount -Environment <EnvironmentName>
    ```

2. Then get the Resource Manager Url for the environment.

    ``` powershell
    $ResourceManagerUrl = (Get-AzEnvironment -Name <EnvironmentName>).ResourceManagerUrl
    ```

3. Then get the cloud suffix.

    ``` powershell
    $CloudSuffix = $ResourceManagerUrl.Replace('https://management.', '').Replace('/', '')
    ```

4. Replace the appropriate instance of '&lt;CLOUDSUFFIX&gt;' in the Set-RemoteDesktopClientKioskSettings.ps1 file with the actual value before running the script.

### Air-Gapped Cloud Documentation

1. From a corporate Microsoft laptop or AVD session, access either [Azure Government Secret Virtual Desktop Infrastructure](https://review.learn.microsoft.com/en-us/microsoft-government-secret/azure/azure-government-secret/services/virtual-desktop-infrastructure/virtual-desktop?branch=live#subscribe-to-azure-virtual-desktop-in-the-windows-client) or [Azure Government Top Secret Virtual Desktop Infrastructure](https://review.learn.microsoft.com/en-us/microsoft-government-topsecret/azure/azure-government-top-secret/services/virtual-desktop-infrastructure/virtual-desktop?branch=live#subscribe-to-azure-virtual-desktop-in-the-windows-client) and capture the value of the subscribe Url at end of the sentence: 'In the client, you can connect to AVD by subscribing to <span>https://</span>rdweb.wvd.&lt;CLOUDSUFFIX&gt;'.

2. Replace the appropriate instance of '&lt;CLOUDSUFFIX&gt;' in the Set-RemoteDesktopClientKioskSettings.ps1 file with the cloud suffix as derived from this sentence before running the script.

## Manual Installation

> [!Important]
> You need to run the PowerShell script with system privileges. The easiest way to do this is to download [PSExec](https://learn.microsoft.com/en-us/sysinternals/downloads/psexec). Then extract the Zip to a folder and open an administrative command prompt.

1. Either clone the repo or download it as a zip file. If downloading the repo as a zip file, then extract it to a new folder.

2. Execute PowerShell as SYSTEM by running the following command:

    ``` cmd
    psexec64 -s -i powershell
    ```

3. In the newly opened PowerShell window, execute the following:

    ``` powershell
    set-executionpolicy bypass -scope process
    ```

4. Change directories to the local 'source' directory.

5. Then execute the script using the correct parameters as exemplified below: (All options are not shown).

    ### Scenario 1 Options

    - Lock the workstation when a SmartCard is Removed or 15 minutes of inactivity has occurred.

      ``` powershell
      .\Set-RemoteDesktopClientKioskSettings.ps1 -DeviceRemovalAction 'Lock' -SmartCard -IdleTimeoutAction 'Lock' -IdleTimeout 900
      ```

    - Logoff the user when a Yubikey is Removed. Lock after 15 minutes of inactivity has occurred.

      ``` powershell
      .\Set-RemoteDesktopClientKioskSettings.ps1 -DeviceRemovalAction 'Logoff' -DeviceVendorID '1050' -IdleTimeoutAction 'Lock' -IdleTimeout 900
      ```

    - Logoff the user when the user disconnects or signs out of a remote session. Lock after 15 minutes of inactivity.

      ``` powershell
      .\Set-RemoteDesktopClientKioskSettings.ps1 -UserDisconnectSignOutAction 'Logoff' -IdleTimeoutAction 'Lock' -IdleTimeout 900
      ```

    ### Scenario 2 Options

    - Reset when SmartCard is Removed:
  
      ``` powershell
      .\Set-RemoteDesktopClientKioskSettings.ps1 -AutoLogon -DeviceRemovalAction 'ResetClient' -SmartCard
      ```

    - Reset when Yubikey is Removed

      ``` powershell
      .\Set-RemoteDesktopClientKioskSettings.ps1 -AutoLogon -DeviceRemovalAction 'ResetClient' -DeviceVendorID '1050'
      ```

    - Reset when Remote Sessions are disconnected

      ``` powershell
      .\Set-RemoteDesktopClientKioskSettings.ps1 -AutoLogon -SystemDisconnectAction 'ResetClient' -UserDisconnectSignOutAction 'ResetClient'
      ```

    - Reset when Remote Sessions are disconnected or 15 minutes of idle time has passed.

      ``` powershell
      .\Set-RemoteDesktopClientKioskSettings.ps1 -AutoLogon -SystemDisconnectAction 'ResetClient' -UserDisconnectSignOutAction 'ResetClient' -IdleTimeoutAction 'ResetClient' -IdleTimeout 900
      ```
  
    ### Other Parameters

    - Replace the Windows default shell with the Remote Desktop client.

      ``` powershell
      .\Set-RemoteDesktopClientKioskSettings.ps1 -ClientShell [other parameters]
      ```

    - Install the Remote Desktop client

      ``` powershell
      .\Set-RemoteDesktopClientKioskSettings.ps1 -InstallRemoteDesktopClient [other parameters]
      ```

    - Allow Display and Audio Settings modification by kiosk users.

      ``` powershell
      .\Set-RemoteDesktopClientKioskSettings.ps1 -ShowSettings [other parameters]
      ```

    - Configure automatic maintenance and power management for shared PC scenarios.

      ``` powershell
      .\Set-RemoteDesktopClientKioskSettings.ps1 -SharedPC -ConfigureAutomaticMaintenance -MaintenanceActivationTime "02:00:00" -MaintenanceRandomDelay 4 -SetPowerPolicies -IdleSleepTimeoutMinutes 120 [other parameters]
      ```

    - Reinstall/reconfigure an existing kiosk deployment.

      ``` powershell
      .\Set-RemoteDesktopClientKioskSettings.ps1 -Reinstall [other parameters]
      ```

## Manual Removal

Remove the configuration from the PowerShell prompt using:

``` powershell
.\Remove-KioskSettings.ps1
```

## Troubleshooting

### Logging

All events from the configuration scripts and scheduled tasks are logged to the **Application and Services Logs | Remote Desktop Client Kiosk** event log.

### Emergency Access

You can break autologon of the Kiosk User account during restart by holding down the **LEFT SHIFT** button down and continuously tap **ENTER** during restart all the way to the lock screen appears.

### Configuration Verification

**Quick Health Check:**

``` powershell
# Check kiosk configuration
Get-AssignedAccessConfiguration

# Verify installation
Get-ItemProperty "HKLM:\Software\Kiosk" -Name "version"

# Check Remote Desktop client settings
Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\MSIX\Apps\Microsoft.RemoteDesktop*" -ErrorAction SilentlyContinue
```
