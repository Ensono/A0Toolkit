[CmdletBinding()]
param (		

    [Parameter(Mandatory=$true)]
    [ValidateSet("dev", "test", "uat", "preprod", "prod")]
    [string]$targetEnvironment,
        
    [Parameter(Mandatory=$false)]
    [switch]$enableDeletions
        
)

# // START setup //

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location -Path $here

# // END setup //


# // START importing functions //

Write-Host "Importing module from Chocolatey"
Import-Module A0Toolkit -ErrorAction Stop -Verbose


Write-Host "Importing functions"
. ".\Auth0\*-Auth0*.ps1"

# // END importing functions //


# // START invoking function with target environment as environment name - targetEnvironment name is tokenised //

If ($enableDeletions) {
    
    Set-Auth0Tenant -targetEnvironment $targetEnvironment -enableDeletions

} Else {
    
    Set-Auth0Tenant -targetEnvironment $targetEnvironment
}

# // END invoking function with target environment as environment name - targetEnvironment name is tokenised //