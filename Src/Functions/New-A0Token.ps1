Function New-A0Token {
	
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

        [Parameter(Mandatory=$false)]
        [pscustomobject]$payload,
		
        [Parameter(Mandatory=$true)]
        [string]$clientId,

        [Parameter(Mandatory=$true)]
        [string]$clientSecret,			
        
        [Parameter(Mandatory=$false)]
        [ValidateSet("client_credentials")]
        [string]$grantType = "client_credentials"
    )

    Write-Host ("Running function: {0}" -f $MyInvocation.MyCommand.Name) -ForegroundColor Yellow

    
    # // building path //
    $path = "oauth/token"

    
    # // building request body //
    If (-not $payload) {  

        $body = @{

            "audience" = ("{0}/{1}/" -f $baseURL, ("api/{0}" -f $apiVersion))
	        "client_id" = $clientId
	        "client_secret" = $clientSecret
	        "grant_type" = $grantType
    
        }
    
    } Else {

        $body = $payload
    }

    
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