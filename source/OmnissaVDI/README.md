# Azure Virtual Desktop Client Kiosk

**📖 Documentation Navigation:**

| [Overview](README.md) | [Solution Overview](SOLUTION_OVERVIEW.md) | [Implementation Guide](IMPLEMENTATION.md) | [Intune Deployment](INTUNE_DEPLOYMENT.md) |
|:---:|:---:|:---:|:---:|

---

## Overview

This repository contains a script and supporting artifacts to configure a Windows client operating system to act as a custom Azure Virtual Desktop (AVD) client kiosk using the [Remote Desktop Client for Windows](https://learn.microsoft.com/en-us/azure/virtual-desktop/users/connect-remote-desktop-client?tabs=windows).

## Quick Links

- **[Solution Overview](SOLUTION_OVERVIEW.md)** - Learn about the solution architecture, prerequisites, user interface modes, and trigger/action behaviors
- **[Implementation Guide](IMPLEMENTATION.md)** - Complete parameter reference, air-gapped cloud support, manual installation steps, and troubleshooting
- **[Intune Deployment Guide](INTUNE_DEPLOYMENT.md)** - Deploy via Win32 apps in Microsoft Intune

## What's Included

The solution provides multiple deployment modes and customizable triggers:

### Deployment Modes

- **Multi-App Kiosk Mode** - A restricted Windows interface showing only Remote Desktop client and optionally Settings
- **Shell Launcher Mode** - Remote Desktop client completely replaces the Windows Explorer shell
- **AutoLogon Mode** - Automated kiosk experience with KioskUser0 account
- **Direct Logon Mode** - Users sign in with their own Entra ID credentials

### Trigger & Action System

Configure automated responses to various events:

- **Device Removal** - Smart card or FIDO2 token removal triggers lock, logoff, or client reset
- **Idle Timeout** - System inactivity triggers configured actions
- **System Disconnect** - Remote session disconnected by system (timeout, reconnect from another client)
- **User Disconnect** - User manually disconnects or signs out of remote session

## Key Features

- ✅ Multiple deployment options (manual, Intune Win32 app)
- ✅ AutoLogon support for true kiosk scenarios
- ✅ Flexible trigger-action system for security enforcement
- ✅ Smart card and FIDO2 authentication device support
- ✅ Automatic workspace subscription
- ✅ Shared PC mode support
- ✅ Support for Azure Commercial, Government, and Air-Gapped clouds
- ✅ Comprehensive troubleshooting and emergency access features

## Common Use Cases

**Scenario 1: Corporate Shared Workspace** - Users sign in with Entra ID, access their AVD resources, with automatic lock/logoff on inactivity or device removal

**Scenario 2: Public Kiosk** - AutoLogon with KioskUser0, users authenticate to AVD, client resets after session ends or device removal

## Getting Started

1. Review the [Solution Overview](SOLUTION_OVERVIEW.md) to understand the solution architecture and scenarios
2. Check the [Implementation Guide](IMPLEMENTATION.md) for detailed parameters and installation steps
3. For enterprise deployment, see the [Intune Deployment Guide](INTUNE_DEPLOYMENT.md)

## Documentation Structure

This documentation is split across four files for easier navigation:

- **README.md** (this file) - Overview and quick links
- **[SOLUTION_OVERVIEW.md](SOLUTION_OVERVIEW.md)** - Architecture, prerequisites, UI modes, and trigger/action details
- **[IMPLEMENTATION.md](IMPLEMENTATION.md)** - Parameters, installation procedures, and troubleshooting
- **[INTUNE_DEPLOYMENT.md](INTUNE_DEPLOYMENT.md)** - Intune-specific deployment guidance

## Additional Resources

- [Azure Virtual Desktop Documentation](https://learn.microsoft.com/en-us/azure/virtual-desktop/)
- [Remote Desktop Client for Windows](https://learn.microsoft.com/en-us/azure/virtual-desktop/users/connect-remote-desktop-client?tabs=windows)
- [Assigned Access Configuration](https://learn.microsoft.com/en-us/windows/configuration/assigned-access/)
- [Shell Launcher](https://learn.microsoft.com/en-us/windows/configuration/assigned-access/shell-launcher/)
- [Shared PC Configuration](https://learn.microsoft.com/en-us/windows/configuration/shared-pc/)
