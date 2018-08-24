Function Set-Auth0Tenant {
	
    [CmdletBinding()]
    param (		
        
        [Parameter(Mandatory=$true)]
        [ValidateSet("dev", "test", "uat", "preprod", "prod")]
        [string]$targetEnvironment,

        [Parameter(Mandatory=$false)]
        [string]$configurationFile = "Auth0\powershell.auth0.config.json",
        
        [Parameter(Mandatory=$false)]
        [switch]$enableDeletions
    )
   
    Write-Host ("`nRunning function: {0}" -f $MyInvocation.MyCommand.Name) -ForegroundColor Yellow

    
    # // setup //
    $InformationPreference = "Continue"
    Write-Information "Setup"
    
    If ((Get-Command *-A0*).Name -eq $null) {
        
        Throw "Missing PowerShell module 'A0Toolkit'"
    }

    $runtimeConfig = @{}
    $runtimeConfig.Add("headers", @{"content-type" = "application/json"})

    <# // dependency on Auth0 Deploy CLI configuration //
    If ($targetEnvironment -eq 'dev') {
        
        $a0ConfigurationFile = ("Auth0\{0}-auth0-config.json" -f $targetEnvironment)
    
    } Else {

        $a0ConfigurationFile = ("Auth0\master-auth0-config.json" -f $targetEnvironment)

    }
    
    If ((-not (Test-Path $configurationFile)) -or (-not (Test-Path $a0ConfigurationFile))) {
        
        Throw "Missing PowerShell ({0}) or Auth0 ({1}) configuration file(s)" -f $configurationFile, $a0ConfigurationFile
    
    }
    #>
    
    Write-Information "`nLoading configuration files"
    $psConfiguration = Get-Content -Path $configurationFile | ConvertFrom-Json

    Write-Information ("`nBuild {0} environment runtime configuration from json file" -f $targetEnvironment)    
    If ($psConfiguration.Environments.Name -contains $targetEnvironment) {
        $allowedPSOverrides = "clientId", "clientSecret", "clients", "account", "email", "connections", "protectedClients", "protectedConnections", "ruleConfigs"
        
        $envConfiguration = ($psConfiguration.environments | Where-Object {$_.Name -eq $targetEnvironment}).Auth0        
        $envConfiguration | Get-Member -MemberType Properties | ForEach-Object {
        
            $name = $_.Name
        
            If (($allowedPSOverrides.Contains($name))) {
            
                Write-Information $name            
                $runtimeConfig.Add($name,$envConfiguration.$name)
            }
        }
    }

    
    Write-Information "`nBuild common environment runtime configuration from json file"
    
    $commonConfiguration = ($psConfiguration.environments | Where-Object {$_.Name -eq "Common"}).Auth0
    $commonConfiguration | Get-Member -MemberType Properties | ForEach-Object {        
    
        $name = $_.Name

        If (-not $runtimeConfig.ContainsKey($name)) {
        
            Write-Information $name
            $runtimeConfig.Add($name,$commonConfiguration.$name)
        }

    }


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


    Write-Information "`nProcess rule configs in ps configuration"
    Foreach ($rule in $runtimeConfig.ruleConfigs) {

        Write-Information ("`nUpdate rule config: {0}" -f $rule.Key)

        $response = Set-A0RuleConfig -headers $runtimeConfig.headers -baseURL $runtimeConfig.domain -key $rule.Key -Value $rule.Value
        
        If ($response.StatusCode -ne 200) {
    
            Write-Warning $response.StatusCode
            Write-Warning ($response.content | ConvertFrom-Json | Out-String)
            Throw ("Error updating {0}: {1}" -f "rule config", $runtimeConfig.domain)
    
        }
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


    Write-Information "`nGet all resource servers (APIs)"
    $response = Get-A0ResourceServer -headers $runtimeConfig.headers -baseURL $runtimeConfig.domain
    $resourceServers = ($response.Content | ConvertFrom-Json)

    $resourceServerNameToIdMapping = @{}
    
    Foreach ($resourceServer in $resourceServers) {
    
        Try {
        
            $resourceServerNameToIdMapping.Add($resourceServer.name,$resourceServer.id)
        }

        Catch {
            
            Write-Warning ($resourceServers | Select-Object -Property name, id | Out-String)
            Throw "Error building resource server mapping"
        }

    }

    $resourceServerNameToIdMapping | Format-Table -AutoSize



    Write-Information "`nProcess clients in ps configuration"
    Write-Warning ("Enable Deletions is set to: {0}" -f $enableDeletions)

    Foreach ($client in $runtimeConfig.clients) {

        Write-Information ("`n{0}" -f $client.Name)
        $clientId = $clientNameToIdMapping.($client.Name)

        If ($clientNameToIdMapping.ContainsKey($client.Name)) {
            
            If ((-not $client.Delete) -and ($client.payload)) {
                
                Write-Information "Update client"
                $response = Set-A0Client -headers $runtimeConfig.headers -baseURL $runtimeConfig.domain -clientId $clientId -payload $client.payload

                If ($response.StatusCode -ne 200) {

                    Write-Warning $response.StatusCode
                    Write-Warning ($response.content | ConvertFrom-Json | Out-String)
                    Throw ("Error updating {0}: {1} ({2})" -f "client", $client.Name, $clientId)

                }
            
            } ElseIf ($client.Delete -eq $true) {
                
                Write-Information "Remove client"
                
                If ($enableDeletions) {

                    $clientNameToIdMapping.Remove($client.Name)

                    $response = Remove-A0Client -headers $runtimeConfig.headers -baseURL $runtimeConfig.domain -clientId $clientId

                    If ($response.StatusCode -ne 204) {

                        Write-Warning $response.StatusCode
                        Write-Warning ($response.content | ConvertFrom-Json | Out-String)
                        Throw ("Error deleting {0}: {1} ({2})" -f "client", $client.Name, $clientId)

                    }
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
    Write-Warning ("Enable Deletions is set to: {0}" -f $enableDeletions)

    $connectionsToDelete = $connectionNameToIdMapping.Keys | Where-Object {($runtimeConfig.connections.Name -notcontains $_) -and ($runtimeConfig.protectedConnections -notcontains $_)}

    Foreach ($connectionName in $connectionsToDelete) {
            
        $connectionId = $connectionNameToIdMapping.$connectionName
            
        Write-Warning ("`n{0} ({1})" -f $connectionName, $connectionId)
        
        If ($enableDeletions) {

            $response = Remove-A0Connection -headers $runtimeConfig.headers -baseURL $runtimeConfig.domain -connectionId $connectionId

            If ($response.StatusCode -ne 204) {

                Write-Warning $response.StatusCode
                Write-Warning ($response.content | ConvertFrom-Json | Out-String)
                Throw ("Error deleting Auth0 {0}" -f "connection", $connectionName)

            }
        }
    }

    
    <# // dependency on Auth0 Deploy CLI configuration //
    Write-Information "`nDelete client"
    Write-Warning ("Enable Deletions is set to: {0}" -f $enableDeletions)
    
    $auth0DeployClients = (Get-ChildItem -Path "Auth0\clients").BaseName

    $clientsToDelete = $clientNameToIdMapping.Keys | Where-Object {($runtimeConfig.clients.Name -notcontains $_) -and ($auth0DeployClients -notcontains $_) -and ($runtimeConfig.protectedClients -notcontains $_)}
    
    Foreach ($clientnName in $clientsToDelete) {                
            
        $clientId = $clientNameToIdMapping.$clientnName
            
        Write-Warning ("{0} ({1})" -f $clientnName, $clientId)

        If ($enableDeletions) {
            
            $response = Remove-A0Client -headers $runtimeConfig.headers -baseURL $runtimeConfig.domain -clientId $clientId

            If ($response.StatusCode -ne 204) {

                Write-Warning $response.StatusCode
                Write-Warning ($response.content | ConvertFrom-Json | Out-String)
                Throw ("Error deleting Auth0 {0}" -f "client", $clientnName)

            }

        }
    }
    #>

    <# // dependency on Auth0 Deploy CLI configuration //
    Write-Information "`nDelete resource server"
    Write-Warning ("Enable Deletions is set to: {0}" -f $enableDeletions)
    
    $auth0ResourceServers = (Get-ChildItem -Path "Auth0\resource-servers").BaseName

    $resourceServersToDelete = $resourceServerNameToIdMapping.Keys | Where-Object {($auth0ResourceServers -notcontains $_) -and ($runtimeConfig.protectedResourceServers -notcontains $_)}
    
    Foreach ($resourceServerName in $resourceServersToDelete) {                
            
        $resourceServerId = $resourceServerNameToIdMapping.$resourceServerName
            
        Write-Warning ("{0} ({1})" -f $resourceServerName, $resourceServerId)

        If ($enableDeletions) {
            
            $response = Remove-A0ResourceServer -headers $runtimeConfig.headers -baseURL $runtimeConfig.domain -resourceServerId $resourceServerId
            
            If ($response.StatusCode -ne 204) {

                Write-Warning $response.StatusCode
                Write-Warning ($response.content | ConvertFrom-Json | Out-String)
                Throw ("Error deleting Auth0 {0}" -f "resource server", $resourceServerName)

            }
            
        }
    }
    #>


    Write-Information "`nDelete rule config"
    Write-Warning ("Enable Deletions is set to: {0}" -f $enableDeletions)

    Write-Information "`nGet rule config keys"
    $response = Get-A0RuleConfig -headers $runtimeConfig.headers -baseURL $runtimeConfig.domain
    $ruleConfigKeys = ($response.Content | ConvertFrom-Json)
    $ruleConfigToDelete = $ruleConfigKeys | Where-Object {$runtimeConfig.ruleConfigs.key -notcontains $_.key}

    Foreach ($rule in $ruleConfigToDelete) {
            
        $key = $rule.key
            
        Write-Warning ("{0}" -f $key)
        
        If ($enableDeletions) {

            $response = Remove-A0RuleConfig -headers $runtimeConfig.headers -baseURL $runtimeConfig.domain -key $key

            If ($response.StatusCode -ne 204) {

                Write-Warning $response.StatusCode
                Write-Warning ($response.content | ConvertFrom-Json | Out-String)
                Throw ("Error deleting Auth0 {0}" -f "rule config")

            }
        }
    }
}