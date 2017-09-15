$moduleRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

# // Functions and Helpers //
$types = "Functions", "Functions\Private"

Foreach ($type in $types) {

    If (Test-Path -Path ("{0}\{1}" -f $moduleRoot, $type)) {

        Foreach ($function in Get-ChildItem -Path ("{0}\{1}\*.ps1" -f $moduleRoot, $type) -Exclude "*.Tests.ps1") {

            . $function.FullName
        
            If ($type -eq "Functions") {
            
                Export-ModuleMember -Function $function.BaseName
            }

        }
    }
}