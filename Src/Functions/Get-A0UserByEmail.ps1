Function Get-A0UserByEmail {
	
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
        [string]$email
    )
    
    Write-Host ("Running function: {0}" -f $MyInvocation.MyCommand.Name) -ForegroundColor Yellow


    # // building path //
    $path = ("api/{0}/users-by-email?email={1}" -f $apiVersion, $email.ToLower())


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

        New-ExceptionDetail -exception $_ -parameters $params

        Throw $_.Exception
    }

    Return $response
}