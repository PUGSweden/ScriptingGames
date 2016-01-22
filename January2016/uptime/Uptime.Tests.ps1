Import-Module $PSScriptRoot -Force

Describe "Uptime" {
    InModuleScope -ModuleName Uptime {
        Mock New-CimSession -ParameterFilter {$ComputerName -eq 'ERRORCOMPUTER'} {
                Write-Error -Category PermissionDenied -Message 'Access is denied'
        }
    }
    
    It "Returns OFFLINE status for nonexisting computer" {
        $Uptime = Get-Uptime -ComputerName NONEXISTING
        $Uptime.Status | Should be 'OFFLINE'
    }

    It "Returns OK status for existing computer" {
        $Uptime = Get-Uptime -ComputerName $env:COMPUTERNAME
        $Uptime.Status | Should be 'OK'
    }

    It "Returns ERROR status for accessdenied computer" {
        $Uptime = Get-Uptime -ComputerName ERRORCOMPUTER
        $Uptime.Status | Should be 'ERROR'
        $Uptime.StartTime | Should be $null
        $Uptime.Uptime | Should be $null
            
    }
}
