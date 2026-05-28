function Get-AssignedAccessCspBridgeWmi {
    $NameSpace = "root\cimv2\mdm\dmmap"
    $Class = "MDM_AssignedAccess"
    return Get-CimInstance -Namespace $NameSpace -ClassName $Class
}

function Set-AssignedAccessShellLauncher {
    param (
        [Parameter(Mandatory=$True)]
        [String] $FilePath
    )

    $Xml = Get-Content -Path $FilePath
    $EscapedXml = [System.Security.SecurityElement]::Escape($Xml)
    $AssignedAccessCsp = Get-AssignedAccessCspBridgeWmi
    # MDM_* CIM classes only accept writes via property assignment + -CimInstance.
    # The pipeline form ($obj | Set-CimInstance -Property @{...}) is a SILENT no-op on these classes.
    $AssignedAccessCsp.ShellLauncher = $EscapedXml
    Set-CimInstance -CimInstance $AssignedAccessCsp

    # get a new instance and print the value
    (Get-AssignedAccessCspBridgeWmi).ShellLauncher
}

function Clear-AssignedAccessShellLauncher {
    $AssignedAccessCsp = Get-AssignedAccessCspBridgeWmi
    $AssignedAccessCsp.ShellLauncher = $null
    Set-CimInstance -CimInstance $AssignedAccessCsp
}

function Get-AssignedAccessShellLauncher {
    (Get-AssignedAccessCspBridgeWmi).ShellLauncher
}

function Get-AssignedAccessConfiguration {
    (Get-AssignedAccessCspBridgeWmi).Configuration
}

function Set-AssignedAccessConfiguration {
    param (
        [Parameter(Mandatory=$True)]
        [string] $FilePath
    )

    $Xml = Get-Content -Path $FilePath
    $AssignedAccessCsp = Get-AssignedAccessCspBridgeWmi
    $EncodedXml = [System.Net.WebUtility]::HtmlEncode($Xml)
    # MDM_* CIM classes only accept writes via property assignment + -CimInstance.
    # The pipeline form ($obj | Set-CimInstance -Property @{...}) is a SILENT no-op on these classes.
    $AssignedAccessCsp.Configuration = $EncodedXml
    Set-CimInstance -CimInstance $AssignedAccessCsp
    (Get-AssignedAccessCspBridgeWmi).Configuration
}

function Clear-AssignedAccessConfiguration {
    $AssignedAccessCsp = Get-AssignedAccessCspBridgeWmi
    $AssignedAccessCsp.Configuration = $null
    Set-CimInstance -CimInstance $AssignedAccessCsp
}