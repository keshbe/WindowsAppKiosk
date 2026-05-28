# Azure Virtual Desktop Client Kiosk - Intune Deployment

**Navigation:** [Overview](README.md) | [Solution Overview](SOLUTION_OVERVIEW.md) | [Implementation Guide](IMPLEMENTATION.md) | Intune Deployment

---

## Win32 App Deployment

This configuration supports deployment through Intune as a Win32 App. The instructions for creating a Win32 application are available at [Intune Win32 App Management](https://learn.microsoft.com/en-us/mem/intune/apps/apps-win32-app-management).

### Command Line Examples

The command line should be similar to the following examples:

**Standard Shared PC with Device Removal Trigger:**

``` cmd
powershell.exe -executionpolicy bypass -file Set-RemoteDesktopClientKioskSettings.ps1 -SharedPC -DeviceID '1050' -Cloud AzureCloud -ShowSettings -DeviceRemovalAction 'Lock'
```

**AutoLogon Kiosk with Multiple Triggers:**

``` cmd
powershell.exe -executionpolicy bypass -file Set-RemoteDesktopClientKioskSettings.ps1 -AutoLogon -SystemDisconnectAction 'ResetClient' -UserDisconnectSignOutAction 'ResetClient' -IdleTimeoutAction 'ResetClient' -IdleTimeout 900
```

**Client Shell with Smart Card:**

``` cmd
powershell.exe -executionpolicy bypass -file Set-RemoteDesktopClientKioskSettings.ps1 -ClientShell -AutoSubscribe -Cloud AzureCloud -DeviceRemovalAction 'Lock' -SmartCard
```

**Install Client with Shared PC Configuration:**

``` cmd
powershell.exe -executionpolicy bypass -file Set-RemoteDesktopClientKioskSettings.ps1 -InstallRemoteDesktopClient -SharedPC -ShowSettings -IdleTimeoutAction 'Lock' -IdleTimeout 900
```

**Shared PC with Maintenance and Power Management:**

``` cmd
powershell.exe -executionpolicy bypass -file Set-RemoteDesktopClientKioskSettings.ps1 -SharedPC -ConfigureAutomaticMaintenance -MaintenanceActivationTime "02:00:00" -MaintenanceRandomDelay 4 -SetPowerPolicies -IdleSleepTimeoutMinutes 120 -ShowSettings
```

### Detection Methods

You have two options for detection in Intune:

#### Option 1: Custom Detection Script

You can utilize the `DetectionScript.ps1` as a custom detection script in Intune which will automatically look for all the configurations applied by the script.

#### Option 2: Registry Detection

Use a Registry detection method to read the value of `HKEY_LOCAL_MACHINE\Software\Kiosk\version` which should be equal to the value of the version parameter used in the deployment script. This would be useful for when you do not implement AutoLogon.

**Registry Detection Settings:**

- **Key path:** `HKEY_LOCAL_MACHINE\SOFTWARE\Kiosk`
- **Value name:** `version`
- **Detection method:** String comparison
- **Operator:** Equals
- **Value:** The version string used in your deployment (e.g., "1.0.0")

### Deployment Tips

1. **Test in a pilot group** - Always test your configuration on a small group of devices before wide deployment
2. **Use device filters** - Target specific device types or models that meet the prerequisites
3. **Consider user communication** - Inform users about the kiosk experience before deployment
4. **Plan for updates** - Use the `-Reinstall` parameter when updating existing deployments
5. **Monitor event logs** - Check the "Remote Desktop Client Kiosk" event log for troubleshooting

### Common Deployment Scenarios

#### Corporate Shared Workspace

Best for offices with hot-desking or shared workstations:

``` cmd
powershell.exe -executionpolicy bypass -file Set-RemoteDesktopClientKioskSettings.ps1 -SharedPC -ShowSettings -IdleTimeoutAction 'Lock' -IdleTimeout 900 -UserDisconnectSignOutAction 'Logoff'
```

#### Public Kiosk with Smart Card

Best for lobby or public access points:

``` cmd
powershell.exe -executionpolicy bypass -file Set-RemoteDesktopClientKioskSettings.ps1 -AutoLogon -ClientShell -DeviceRemovalAction 'ResetClient' -SmartCard -IdleTimeoutAction 'ResetClient' -IdleTimeout 900
```

#### Dedicated AVD Endpoint

Best for dedicated remote desktop workstations:

``` cmd
powershell.exe -executionpolicy bypass -file Set-RemoteDesktopClientKioskSettings.ps1 -AutoSubscribe -Cloud AzureCloud -SystemDisconnectAction 'Lock' -IdleTimeoutAction 'Lock' -IdleTimeout 1800
```

## Additional Resources

- [Intune Win32 App Management](https://learn.microsoft.com/en-us/mem/intune/apps/apps-win32-app-management)
- [Intune Device Configuration Profiles](https://learn.microsoft.com/en-us/mem/intune/configuration/device-profiles)
- [Azure Virtual Desktop Documentation](https://learn.microsoft.com/en-us/azure/virtual-desktop/)
- [Remote Desktop Client for Windows](https://learn.microsoft.com/en-us/azure/virtual-desktop/users/connect-remote-desktop-client?tabs=windows)
