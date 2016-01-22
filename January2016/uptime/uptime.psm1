﻿using namespace System.Management.Automation
using namespace System.Collections.Generic

class Completer : IArgumentCompleter{
   [IEnumerable[CompletionResult]] CompleteArgument(
    [string] $CommandName,
    [string] $ParameterName,
    [string] $wordToComplete,
    [Language.CommandAst] $CommandAst,
    [Collections.IDictionary] $fakeBoundParameters
   )
   {
        switch ($ParameterName)
        {
            
            'Credential' {
                $res = [List[CompletionResult]]::new(10)
                Get-variable -Scope Global | Where-Object -FilterScript {$_.Value -is [PSCredential]} | ForEach-Object{
                    $name = $_.Name
                    $list = "`$$name"
                    $res.Add([CompletionResult]::new($list, $list, [CompletionResultType]::ParameterValue, $_.Value.UserName))
                }
                return $res                        
            }
            
        }
             
        return $null
   }
}

enum StatusKind {
    UNKNOWN
    OK
    ERROR
    OFFLINE
}

class UptimeStatus
{
    [String]$ComputerName
    [DateTimeOffset]$StartTime
    [TimeSpan]$Uptime
    [StatusKind]$Status
    UptimeStatus(
        [String]$ComputerName,
        [DateTimeOffset]$StartTime,
        [TimeSpan]$Uptime,
        [StatusKind]$Status
    ) {
        $this.ComputerName = $ComputerName
        $this.StartTime    = $StartTime   
        $this.Uptime       = $Uptime      
        $this.Status       = $Status      
    }

    UptimeStatus(
        [String]$ComputerName,
        [StatusKind]$Status
    ){
        $this.ComputerName = $ComputerName
        $this.Status       = $Status      
    }
}

<#
.Synopsis
   Get uptime from local or remote computer
.DESCRIPTION
   Get uptime from local or remote computer. Module written as part of 2016 Scripting Games January challange.
   Function will try to connect using CIM over WSMAN, if that fails CIM over DCOM will get used. Computers not answering on any will be marked as OFFLINE in result. 
.EXAMPLE
   Get-Uptime
   Gets uptime for local computer
.EXAMPLE
   Get-Uptime -ComputerName Server1, Server2, Server3
   Get uptime for several remote servers.
.OUTPUTS
   UptimeStatus
#>
function Get-Uptime
{
    [CmdletBinding()]
    [OutputType([UptimeStatus])]
    [Alias('gut')]
    Param
    (
        # Specifies the computers on which the command runs. The default is the local computer.
        [Parameter(ValueFromPipeline,ValueFromPipelineByPropertyName, Position=0)]
        [Alias('cn')]
        [String[]]
        $ComputerName,
        
        # Specifies a user account that has permission to perform this action. The default is the current user.
        #
        # Type a user name, such as "User01" or "Domain01\User01", or enter a variable that contains a PSCredential object, such as 
        # one generated by the Get-Credential cmdlet. When you type a user name, you will be prompted for a password.
        [ArgumentCompleter([Completer])]
        [Parameter(ValueFromPipelineByPropertyName)]
        [PSCredential]
        $Credential
    )

    Begin
    {
        $ScriptStartTime = [DateTimeOffset]::UtcNow
    }
    Process
    {
        if(-Not($PSBoundParameters.ContainsKey('ComputerName')))
        {
            $PSBoundParameters.Add('ComputerName',$env:COMPUTERNAME)
        }
        
        # Trying to connect using WSMAN protocol first
        $Session = @(New-CimSession @PSBoundParameters -OperationTimeoutSec 1 -ErrorVariable SessionError -ErrorAction SilentlyContinue)
        $PermError,$SessionError = $SessionError.Where({$_.CategoryInfo.Category -eq [ErrorCategory]::PermissionDenied},'split')
        $PermError.Foreach{[UptimeStatus]::New($_.OriginInfo.PSComputerName,[StatusKind]::ERROR)}
        if($ErrComputerNames = $SessionError.OriginInfo.PSComputerName)
        {
            # Retrying each failed connection attempt using DCOM protocol
            $CimSessionParams = @{
                ComputerName = $ErrComputerNames
                SessionOption = (New-CimSessionOption -Protocol Dcom)
                OperationTimeoutSec = 1
            }
            if($null -ne $Credential)
            {
                $CimSessionParams.Credential = $Credential
            }
            $Session += New-CimSession @CimSessionParams -ErrorVariable DCOMSessionError -ErrorAction SilentlyContinue
            foreach($Entry in $DCOMSessionError)
            {
                $Category = $Entry.CategoryInfo.Category
                if($Category -eq [ErrorCategory]::PermissionDenied)
                {
                    $StatusKind = [StatusKind]::ERROR
                }
                else
                {
                    $StatusKind = [StatusKind]::OFFLINE
                }
                [UptimeStatus]::New($Entry.OriginInfo.PSComputerName,$StatusKind)
            }
        }
        if($Session.count -ne 0)
        {
            Get-CimInstance -ClassName Win32_OperatingSystem -CimSession $Session -Property LastBootupTime | 
                Foreach-Object -Process {
                    $CN = $_.PSComputerName
                    $StartTime = $_.LastBootUpTime
                    $Uptime = $ScriptStartTime - $_.LastBootUpTime
                    $Status = [StatusKind]::OK
                    [UptimeStatus]::New($CN,$StartTime,$Uptime,$Status)
                }
            $Session | Remove-CimSession -ErrorAction Ignore
        }
    }
    End
    {
    }
}