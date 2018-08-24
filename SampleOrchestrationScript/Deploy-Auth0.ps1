[CmdletBinding()]
param (		

    [Parameter(Mandatory=$false)]
    [switch]$enableDeletions
        
)

# // setting working folder //
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location -Path $here

<#

Importing A0Toolkit module directly helps speed up development
Once changes are tested they can be published as a new Chocolatey package version via Amido CI/CD

Package: https://chocolatey.org/packages/a0toolkit/
Source: https://github.com/amido/A0Toolkit
CI/CD: https://ci.appveyor.com/project/amido/a0toolkit

To import directly from source code, disable Chocolatey install package step in the identity-provisioning-cd definition

#>

If ((Get-Module A0Toolkit -ListAvailable).Name -eq $null) {
    
    Write-Host "Importing module directly from source code"
    Import-Module "..\PowerShell\Modules\A0ToolKit\Src\A0ToolKit.psm1" -Force -ErrorAction Stop -Verbose

} Else {

    Write-Host "Importing module from Chocolatey"
    Import-Module A0Toolkit -ErrorAction Stop -Verbose
}


# // dot sourcing NHH functions //
. ".\Auth0\*-Auth0*.ps1"

# // invoking function with target environment as environment name //
If ($enableDeletions) {
    
    Set-Auth0Tenant -targetEnvironment $env:RELEASE_ENVIRONMENTNAME -enableDeletions
    
    # // local testing //
    #Set-Auth0Tenant -targetEnvironment dev -configurationFile "Auth0\powershell.auth0.config.local.json" -enableDeletions

} Else {
    
    Set-Auth0Tenant -targetEnvironment $env:RELEASE_ENVIRONMENTNAME
    
    # // local testing //
    #Set-Auth0Tenant -targetEnvironment dev -configurationFile "Auth0\powershell.auth0.config.local.json"
}