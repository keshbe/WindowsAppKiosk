Function Get-BuiltInAdministratorSid {
    <#
    .SYNOPSIS
        Gets the SID of the built-in Administrator account.
    .DESCRIPTION
        This function retrieves the SID of the local built-in Administrator account.
        The built-in administrator account always has a RID of 500.
    .EXAMPLE
        $AdminSid = Get-BuiltInAdministratorSid
    #>
    [CmdletBinding()]
    Param()

    Process {
        try {
            # The built-in Administrator account always has a RID of 500
            $AdminAccount = Get-CimInstance -ClassName Win32_UserAccount -Filter "LocalAccount=True AND SID LIKE '%-500'" -ErrorAction Stop
            return $AdminAccount.SID
        }
        catch {
            Write-Error "Unable to determine the built-in Administrator SID. Error: $_"
        }
    }
}
