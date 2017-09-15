Function New-ExceptionDetail {
	
    [CmdletBinding()]
    param (

        [Parameter(Mandatory=$true)]
        [System.Management.Automation.ErrorRecord]$exception,

        [Parameter(Mandatory=$true)]
        [hashtable]$parameters

    )

    Write-Host ("Running function: {0}" -f $MyInvocation.MyCommand.Name) -ForegroundColor Yellow

    Write-Warning ("{0}`nHEADERS{1}`nBODY`n{2}`n" -f ($parameters | Out-String), ($parameters.headers | Out-String), $parameters.body)
    
    Write-Warning $exception
}