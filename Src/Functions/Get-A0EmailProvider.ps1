Function Get-A0EmailProvider {
	
    [CmdletBinding()]
    param (

        [Parameter(Mandatory=$false)]
        [hashtable]$headers = @{"content-type" = "application/json"},

        [Parameter(Mandatory=$true)]
        [ValidateScript({            
            If ([uri]::IsWellFormedUriString($_,[urikind]::Absolute)) {Return $true}
        })]
        [string]$baseURL,

        [Parameter(Mandatory=$false)]
        [string]$apiVersion = "v2"
    )

    Write-Host ("Running function: {0}" -f $MyInvocation.MyCommand.Name) -ForegroundColor Yellow

    
    # // building path //
    $path = ("api/{0}/emails/provider" -f $apiVersion)

    
    # // using splatting //
    $params = @{

        "uri" = "{0}/{1}" -f $baseURL, $path
        "method" = "GET"

        "headers" = $headers
    }

    Write-Verbose ("Parameters:`n{0}`nHeaders:`n{1}" -f ($params | Out-String), ($params.headers | Out-String))

    
    # //sending request //
    Try {
        
        $response = Invoke-WebRequest @params -UseBasicParsing -ErrorAction Stop
    }
    
    Catch {

        $response = $_ | ConvertFrom-Json -ErrorAction Continue
        
        # // catching 404 for when there are no email providers //
        Switch ($response.statusCode) {

            404 {

                Write-Warning ("Status code {0} ({1}) {2}" -f $response.statusCode, $response.error, $response.message)
                Return
            }
        }

        New-ExceptionDetail -exception $_ -parameters $params

        Throw $_.Exception
    }

    Return $response
}