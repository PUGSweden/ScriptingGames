using namespace System.Management.Automation
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
   Short description
.DESCRIPTION
   Long description
.EXAMPLE
   Example of how to use this cmdlet
.EXAMPLE
   Another example of how to use this cmdlet
.INPUTS
   Inputs to this cmdlet (if any)
.OUTPUTS
   Output from this cmdlet (if any)
.NOTES
   General notes
.COMPONENT
   The component this cmdlet belongs to
.ROLE
   The role this cmdlet belongs to
.FUNCTIONALITY
   The functionality that best describes this cmdlet
#>
function Get-Uptime
{
    [CmdletBinding()]
    [OutputType([UptimeStatus])]
    [Alias('gut')]
    Param
    (
        # Param3 help description
        [Parameter(ValueFromPipeline,ValueFromPipelineByPropertyName, Position=0)]
        [Alias('cn')]
        [String[]]
        $ComputerName,
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
            if($Credential -ne $null)
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
        }

    }
    End
    {
    }
}