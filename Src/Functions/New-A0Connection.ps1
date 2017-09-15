Function New-A0Connection {
	
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
        [string]$apiVersion = "v2",

        [Parameter(Mandatory=$true)]
        [pscustomobject]$payload
    )
    
    Write-Host ("Running function: {0}" -f $MyInvocation.MyCommand.Name) -ForegroundColor Yellow


    # // building path //
    $path = ("api/{0}/connections" -f $apiVersion)

    
    # // building request body //
    $body = $payload


    # // using splatting //
    $params = @{

        "uri" = "{0}/{1}" -f $baseURL, $path 
        "method" = "POST"

        "headers" = $headers

        "body" = $body | Convertto-Json
    }

    Write-Verbose ("Parameters:`n{0}`nHeaders:`n{1}`nBody:`n{2}" -f ($params | Out-String), ($params.headers | Out-String), $params.body)

    
    # //sending request //
    Try {
        
        $response = Invoke-WebRequest @params -UseBasicParsing -ErrorAction Stop
    }
    
    Catch {

        New-ExceptionDetail -exception $_ -parameters $params

        Throw $_.Exception
    }

    Return $response
}