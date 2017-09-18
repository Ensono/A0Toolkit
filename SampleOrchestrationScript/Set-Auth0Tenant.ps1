    [CmdletBinding()]
    param (		
        
        [Parameter(Mandatory=$true)]
        [ValidateSet('dev', 'test', 'uat', 'preprod', 'prod')]
        [string]$targetEnvironment,

        [Parameter(Mandatory=$false)]
        [string]$configurationFile = "powershell.auth0.config.json"
    )
   
    Write-Host ("`nRunning function: {0}" -f $MyInvocation.MyCommand.Name) -ForegroundColor Yellow

    
    # // setup //

    $here = Split-Path -Parent $MyInvocation.MyCommand.Path
    Set-Location -Path $here

    $InformationPreference = "Continue"
    Write-Information "Setup"
    

    If (-not (Get-Module -ListAvailable A0Toolkit).Name) {

        Throw "Missing PowerShell module 'A0Toolkit'"
    }


    $runtimeConfig = @{}
    $runtimeConfig.Add("headers", @{"content-type" = "application/json"})

    
    <# // dependency on Auth0 Deploy CLI configuration //

    $a0ConfigurationFile = ("{0}-auth0-config.json" -f $targetEnvironment)
    If ((-not (Test-Path $configurationFile)) -or (-not (Test-Path $a0ConfigurationFile))) {
        
        Throw "Missing PowerShell ({0}) or Auth0 ({1}) configuration file(s)" -f $configurationFile, $a0ConfigurationFile
    
    }
    
    #>

    
    Write-Information "`nLoading configuration files"
    $psConfiguration = Get-Content -Path $configurationFile -ErrorAction Stop | ConvertFrom-Json
    #$a0Configuration = Get-Content -Path $a0ConfigurationFile -ErrorAction Stop | ConvertFrom-Json


    Write-Information ("`nBuild {0} environment runtime configuration from json file" -f $targetEnvironment)    
    If ($psConfiguration.Environments.Name -contains $targetEnvironment) {
        $allowedPSOverrides = "clientId", "clientSecret", "clients", "account", "email", "connections", "protectedClients", "protectedConnections"
        
        $envnConfiguration = ($psConfiguration.environments | Where-Object {$_.Name -eq $targetEnvironment}).Auth0        
        $envnConfiguration | Get-Member -MemberType Properties | ForEach-Object {
        
            $name = $_.Name
        
            If (($allowedPSOverrides.Contains($name))) {
            
                Write-Information $name            
                $runtimeConfig.Add($name,$envnConfiguration.$name)
            }
        }
    }

    
    Write-Information "`nBuild common environment runtime configuration from json file"
    
    $commonConfiguration = ($psConfiguration.environments | Where-Object {$_.Name -eq "Common"}).Auth0
    $commonConfiguration | Get-Member -MemberType Properties -ErrorAction Stop | ForEach-Object {        
    
        $name = $_.Name

        If (-not $runtimeConfig.ContainsKey($name)) {
        
            Write-Information $name
            $runtimeConfig.Add($name,$commonConfiguration.$name)
        }

    }

    <# // dependency on Auth0 Deploy CLI configuration //

    Write-Information "`nAdd settings from Auth0 configuration file"
    If (-not $runtimeConfig.ContainsKey("domain")) {
        
        $runtimeConfig.Add("domain",("https://{0}" -f $a0Configuration.AUTH0_DOMAIN))
    }
    
    #>


    Write-Information "`nNew management token"
    $response = New-A0Token -headers $runtimeConfig.headers -baseURL $runtimeConfig.domain -clientId $runtimeConfig.ClientId -clientSecret $runtimeConfig.clientSecret

    If ($response.StatusCode -ne 200) {

        Write-Warning $response.StatusCode
        Write-Warning ($response.content | ConvertFrom-Json | Out-String)
        Throw ("Error acquiring {0}: {1} ({2})" -f "management token", $runtimeConfig.domain, $runtimeConfig.ClientId)

    }
    
    $runtimeConfig.headers.Add("authorization",("bearer {0}" -f (($response.Content | ConvertFrom-Json).access_token)))

    
    Write-Information "`nUpdate tenant settings"
    $response = Set-A0Tenant -headers $runtimeConfig.headers -baseURL $runtimeConfig.domain -payload $runtimeConfig.account.payload
    
    If ($response.StatusCode -ne 200) {

        Write-Warning $response.StatusCode
        Write-Warning ($response.content | ConvertFrom-Json | Out-String)
        Throw ("Error updating {0}: {1}" -f "tenant settings", $runtimeConfig.domain)

    }


    Write-Information "`nGet email provider"
    $response = Get-A0EmailProvider -headers $runtimeConfig.headers -baseURL $runtimeConfig.domain

    Write-Information ("`n{0}" -f $runtimeConfig.email.payload.name)

    If (-not $response) {
    
        Write-Information "Create email provider"
        $response = New-A0EmailProvider -headers $runtimeConfig.headers -baseURL $runtimeConfig.domain -payload $runtimeConfig.email.payload

        If ($response.StatusCode -ne 201) {

            Write-Warning $response.StatusCode
            Write-Warning ($response.content | ConvertFrom-Json | Out-String)
            Throw ("Error creating {0}: {1}" -f "email provider", $runtimeConfig.email.payload.name)

        }

    } Else {

        Write-Information "Update email provider"
        $response = Set-A0EmailProvider -headers $runtimeConfig.headers -baseURL $runtimeConfig.domain -payload $runtimeConfig.email.payload
        
        If ($response.StatusCode -ne 200) {

            Write-Warning $response.StatusCode
            Write-Warning ($response.content | ConvertFrom-Json | Out-String)
            Throw ("Error updating {0}: {1}" -f "email provider", $runtimeConfig.email.payload.name)

        }
    }

    
    Write-Information "`nGet all clients"
    $response = Get-A0Client -headers $runtimeConfig.headers -baseURL $runtimeConfig.domain
    $clients = ($response.Content | ConvertFrom-Json)

    $clientNameToIdMapping = @{}
    
    Foreach ($client in $clients) {
    
        Try {
            
            $clientNameToIdMapping.Add($client.name,$client.client_id)
        }
        
        Catch {

            Write-Warning ($clients | Select-Object -Property name, client_id | Out-String)
            Throw "Error building client mapping"
        }

    }

    $clientNameToIdMapping | Format-Table -AutoSize

    
    Write-Information "`nGet all connections"
    $response = Get-A0Connection -headers $runtimeConfig.headers -baseURL $runtimeConfig.domain
    $connections = ($response.Content | ConvertFrom-Json)

    $connectionNameToIdMapping = @{}
    
    Foreach ($connection in $connections) {
    
        Try {
        
            $connectionNameToIdMapping.Add($connection.name,$connection.id)
        }

        Catch {
            
            Write-Warning ($connections | Select-Object -Property name, id | Out-String)
            Throw "Error building connections mapping"
        }

    }

    $connectionNameToIdMapping | Format-Table -AutoSize


    Write-Information "`nGet all client grants"
    $response = Get-A0ClientGrants -headers $runtimeConfig.headers -baseURL $runtimeConfig.domain


    Write-Information "`nProcess clients in ps configuration"
    Foreach ($client in $runtimeConfig.clients) {

        Write-Information ("`n{0}" -f $client.Name)
        $clientId = $clientNameToIdMapping.($client.Name)

        If ($clientNameToIdMapping.ContainsKey($client.Name)) {
            
            If (($client.Delete -eq $false) -and ($client.payload)) {
                
                Write-Information "Update client"
                $response = Set-A0Client -headers $runtimeConfig.headers -baseURL $runtimeConfig.domain -clientId $clientId -payload $client.payload

                If ($response.StatusCode -ne 200) {

                Write-Warning $response.StatusCode
                Write-Warning ($response.content | ConvertFrom-Json | Out-String)
                Throw ("Error updating {0}: {1} ({2})" -f "client", $client.Name, $clientId)

                }
            } ElseIf ($client.Delete -eq $true) {
                
                Write-Information "Remove client"

                $response = Remove-A0Client -headers $runtimeConfig.headers -baseURL $runtimeConfig.domain -clientId $clientId

                If ($response.StatusCode -ne 204) {

                Write-Warning $response.StatusCode
                Write-Warning ($response.content | ConvertFrom-Json | Out-String)
                Throw ("Error deleting {0}: {1} ({2})" -f "client", $client.Name, $clientId)

                }
            }

        }
    }


    Write-Information "`nProcess connections in ps configuration"
    Foreach ($connection in $runtimeConfig.connections) {

        $clientIds = @()
        Write-Information ("`n{0}" -f $connection.Name)
        $connectionId = $connectionNameToIdMapping.($connection.Name)

        Write-Information "Map clients to connections:"
        Foreach ($client in $connection.clients) {

            If ($clientNameToIdMapping.ContainsKey($client)) {
                
                Write-Information $client
                $clientIds += $clientNameToIdMapping.$client
            
            } Else {
                
                Write-Warning ("{0} missing from Auth0" -f $client)
            }
        }

        $connection.payload | Add-Member -MemberType NoteProperty -Name "enabled_clients" -Value $clientIds
        
        If ($connectionNameToIdMapping.ContainsKey($connection.Name)) {
           
            Write-Information "`nUpdate connection"
            $response = Set-A0Connection -headers $runtimeConfig.headers -baseURL $runtimeConfig.domain -connectionId $connectionId -payload $connection.payload

            If ($response.StatusCode -ne 200) {

                Write-Warning $response.StatusCode
                Write-Warning ($response.content | ConvertFrom-Json | Out-String)
                Throw ("Error updating {0}: {1} ({2})" -f "connection", $connection.Name, $connectionId)

            }
            
        
        } Else {

            Write-Information "`nCreate connection"
            
            $connection.payload | Add-Member -MemberType NoteProperty -Name "name" -Value $connection.Name
            $connection.payload | Add-Member -MemberType NoteProperty -Name "strategy" -Value $connection.strategy

            $response = New-A0Connection -headers $runtimeConfig.headers -baseURL $runtimeConfig.domain -payload $connection.payload
           
            If ($response.StatusCode -ne 201) {

                Write-Warning $response.StatusCode
                Write-Warning ($response.content | ConvertFrom-Json | Out-String)
                Throw ("Error creating Auth0 {0}" -f "connection", $connection.Name)

            }

        }

        Write-Information ("Provisioning URL: {0}" -f $(($response.content | ConvertFrom-Json).provisioning_ticket_url))
    }

    
    Write-Information "`nDelete connection"

    $connectionsToDelete = $connectionNameToIdMapping.Keys | Where-Object {($runtimeConfig.connections.Name -notcontains $_) -and ($runtimeConfig.protectedConnections -notcontains $_)}

    Foreach ($connectionName in $connectionsToDelete) {
            
        $connectionId = $connectionNameToIdMapping.$connectionName
            
        Write-Warning ("`n{0} ({1})" -f $connectionName, $connectionId)
        
        $response = Remove-A0Connection -headers $runtimeConfig.headers -baseURL $runtimeConfig.domain -connectionId $connectionId

        If ($response.StatusCode -ne 204) {

            Write-Warning $response.StatusCode
            Write-Warning ($response.content | ConvertFrom-Json | Out-String)
            Throw ("Error deleting Auth0 {0}" -f "connection", $connectionName)

        }
    }

    
    <# // dependency on Auth0 Deploy CLI configuration //

    Write-Information "`nDelete client"
    
    $auth0DeployClients = (Get-ChildItem -Path "Auth0\clients").BaseName

    $clientsToDelete = $clientNameToIdMapping.Keys | Where-Object {($runtimeConfig.clients.Name -notcontains $_) -and ($auth0DeployClients -notcontains $_) -and ($runtimeConfig.protectedClients -notcontains $_)}
    
    Foreach ($clientnName in $clientsToDelete) {                
            
        $clientId = $clientNameToIdMapping.$clientnName
            
        Write-Warning ("{0} ({1})" -f $clientnName, $clientId)

        $response = Remove-A0Client -headers $runtimeConfig.headers -baseURL $runtimeConfig.domain -clientId $clientId

        If ($response.StatusCode -ne 204) {

            Write-Warning $response.StatusCode
            Write-Warning ($response.content | ConvertFrom-Json | Out-String)
            Throw ("Error deleting Auth0 {0}" -f "client", $clientnName)

        }
    }

    #>
