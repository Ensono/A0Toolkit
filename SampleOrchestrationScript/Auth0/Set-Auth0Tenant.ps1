Function Set-Auth0Tenant {
	
    [CmdletBinding()]
    param (		
        
        [Parameter(Mandatory=$true)]
        [string]$targetEnvironment,

        [Parameter(Mandatory=$false)]
        [string]$configurationFile = "Auth0\powershell.auth0.config.json",

        [Parameter(Mandatory=$false)]
        [switch]$enableDeletions
    )
   
    Write-Host ("`nRunning function: {0}" -f $MyInvocation.MyCommand.Name) -ForegroundColor Yellow

    
    # // START setup //

    $InformationPreference = "Continue"
    Write-Information "Setup"

    If (-not (Test-Path $configurationFile)) {
        
        Throw ("Missing PowerShell ({0}) configuration file" -f $configurationFile)
    
    }

    If ((Get-Command *-A0*).Name -eq $null) {
        
        Throw "Missing PowerShell module 'A0Toolkit'"
    }

    $runtimeConfig = @{}
    $runtimeConfig.Add("headers", @{"content-type" = "application/json"})

    # // END setup //

    
    # // START loading configuration files //

    Write-Information "`nLoading configuration files"
    $psConfiguration = Get-Content -Path $configurationFile | ConvertFrom-Json

    Write-Information ("`nBuild {0} environment runtime configuration from json file" -f $targetEnvironment)    
    If ($psConfiguration.Environments.Name -contains $targetEnvironment) {
        $excludedPSOverrides = ""
        
        $envConfiguration = ($psConfiguration.environments | Where-Object {$_.Name -eq $targetEnvironment}).Auth0        
        $envConfiguration | Get-Member -MemberType Properties | ForEach-Object {
        
            $name = $_.Name
        
            If (($excludedPSOverrides -notcontains $name)) {
            
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

    # // END loading configuration files //


    # // START acquire an Auth0 Management Token //

    Write-Information "`nNew management token"
    $response = New-A0Token -headers $runtimeConfig.headers -baseURL $runtimeConfig.domain -clientId $runtimeConfig.ClientId -clientSecret $runtimeConfig.clientSecret

    If ($response.StatusCode -ne 200) {

        Write-Warning $response.StatusCode
        Write-Warning ($response.content | ConvertFrom-Json | Out-String)
        Throw ("Error acquiring {0}: {1} ({2})" -f "management token", $runtimeConfig.domain, $runtimeConfig.ClientId)

    }
    
    $runtimeConfig.headers.Add("authorization",("bearer {0}" -f (($response.Content | ConvertFrom-Json).access_token)))

    # // END acquire an Auth0 Management Token //


    # // START update Auth0 tenant settings //
    
    Write-Information ("`nUpdate tenant settings: {0}" -f $runtimeConfig.domain)
    $response = Set-A0Tenant -headers $runtimeConfig.headers -baseURL $runtimeConfig.domain -payload $runtimeConfig.account.payload
    
    If ($response.StatusCode -ne 200) {

        Write-Warning $response.StatusCode
        Write-Warning ($response.content | ConvertFrom-Json | Out-String)
        Throw ("Error updating {0}: {1}" -f "tenant settings", $runtimeConfig.domain)

    }

    # // END update Auth0 tenant settings //

   
    # // START update rule configuration //

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

    # // END update rule configuration //

    
    # // START update email configuration //
    
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

    # // END update email configuration //

    
    # // START get all applications/clients and maps name and Id into a hash table //

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

    # // END get all applications/clients and maps name and Id into a hash table //

    
    # // START get all connections and maps name and Id into a hash table //
    
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

    # // END get all connections and maps name and Id into a hash table //


    # // START get all resource servers and maps name and Id into a hash table //
    
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

    # // END get all resource servers and maps name and Id into a hash table //


    # // START get all client grants //

    Write-Information "`nGet all client grants"
    $response = Get-A0ClientGrant -headers $runtimeConfig.headers -baseURL $runtimeConfig.domain
    $allClientGrants = ($response.Content | ConvertFrom-Json)

    # // END get all client grants //


    # // START remove client grants that do not exist in the PowerShell JSON configuration file //

    Write-Information ("`nDelete client grants:")
    Write-Warning ("Enable Deletions is set to: {0}" -f $enableDeletions)

    $clientNameToIdMapping.GetEnumerator() | ForEach-Object {

        $clientMapping = $_
        $grants = $allClientGrants | Where-Object {$_.client_id -eq $clientMapping.Value}

        If ((-not $grants) -or ($runtimeConfig.protectedClients -contains $clientMapping.Name)) {

            Return

        } Else {

            If (($runtimeConfig.clients | Where-Object {$_.Name -eq $clientMapping.Name}).clientGrants.payload.audience) {

                $audiencestoDelete = Compare-Object -ReferenceObject $grants.audience -DifferenceObject ($runtimeConfig.clients | Where-Object {$_.Name -eq $clientMapping.Name}).clientGrants.payload.audience -PassThru

            } Else {

                $audiencestoDelete = $grants.audience

            }
                
            $audiencestoDelete | ForEach-Object {
                    
                $audience = $_
                $grantId = ($grants | Where-Object {$_.audience -eq $audience}).Id

                If ([string]::IsNullOrEmpty($grantId)) {
                    
                    Write-Warning ("Missing grantId for client: {0} and audience: {1}" -f $clientMapping.Name, $audience)
                    Return

                }

                Write-Warning ("{0}: {1} ({2})" -f $clientMapping.Name, $audience, $grantId)
                    
                If ($enableDeletions) {
                    
                    $response = Remove-A0ClientGrant -headers $runtimeConfig.headers -baseURL $runtimeConfig.Domain -grantId $grantId

                    If ($response.StatusCode -ne 204) {

                        Write-Warning $response.StatusCode
                        Write-Warning ($response.content | ConvertFrom-Json | Out-String)
                        Throw ("Error deleting Auth0 {0}" -f "clientgrant")

                    }
                }
            }
        }
    }

    # // END remove client grants that do not exist in the PowerShell JSON configuration file //


    # // START processing clients in the PowerShell JSON configuration file //
    
    Write-Information "`nProcess clients in ps configuration"
    Write-Warning ("Enable Deletions is set to: {0}" -f $enableDeletions)

    $runtimeConfig.clients | ForEach-Object {
        $client = $_

        Write-Information ("`n{0}" -f $client.Name)
        $clientId = $clientNameToIdMapping.($client.Name)

        If ($clientNameToIdMapping.ContainsKey($client.Name)) {
            
            # // if the client has the 'Delete' property set to true, delete the client and return //
            If (($client.Delete -eq $true) -and ($runtimeConfig.protectedClients-notcontains $client.Name) -and ($enableDeletions)) {
                Write-Information "Remove client"
                
                $clientNameToIdMapping.Remove($client.Name)
                
                $response = Remove-A0Client -headers $runtimeConfig.headers -baseURL $runtimeConfig.domain -clientId $clientId

                If ($response.StatusCode -ne 204) {

                    Write-Warning $response.StatusCode
                    Write-Warning ($response.content | ConvertFrom-Json | Out-String)
                    Throw ("Error deleting {0}: {1} ({2})" -f "client", $client.Name, $clientId)

                }
                
                Return
            }


            Write-Information "Client grants:"
          
            $grants = $allClientGrants | Where-Object {$_.client_id -eq $clientId}
            
            # // processing client grants //
            If ($client.clientGrants) {
  
                $client.clientGrants | ForEach-Object {
                    
                    $clientGrant = $_

                    If ($resourceServers.identifier -contains $clientGrant.payload.audience) {

                        # // if scope property missing from client grants payload in ps configuration dynamically add all API scopes
                        If (-not $clientGrant.payload.scope) {
                            
                            $scope = ($resourceServers | Where-Object {$_.identifier -eq $clientGrant.payload.audience}).scopes.value

                            If (-not $scope) {$scope = @()}

                            $clientGrant.payload | Add-Member -MemberType NoteProperty -Name "scope" -Value $scope

                        } 

                    } Else {

                        Write-Warning ("Missing Audience in Auth0: {0}" -f $clientGrant.payload.audience)
                        Return
                    }
                    
                    
                    If ($grants.audience -contains $clientGrant.payload.audience) {

                        Write-Information ("`nUpdate client grant: {0}" -f $clientGrant.payload.audience)
                        
                        $grantId = ($grants | Where-Object {$_.audience -eq $clientGrant.payload.audience}).id
                        $clientGrant.payload.PSObject.Properties.Remove("audience")         
                        
                        $response = Set-A0ClientGrant -headers $runtimeConfig.headers -baseURL $runtimeConfig.domain -grantId $grantId -payload $clientGrant.payload

                        If ($response.StatusCode -ne 200) {

                            Write-Warning $response.StatusCode
                            Write-Warning ($response.content | ConvertFrom-Json | Out-String)
                            Throw ("Error updating {0}" -f "clientgrant")

                        }

                    } Else {

                        Write-Information ("`nCreating client grant: {0}" -f $clientGrant.payload.audience)

                        $clientGrant.payload | Add-Member -MemberType NoteProperty -Name "client_id" -Value $clientId

                        $response = New-A0ClientGrant -headers $runtimeConfig.headers -baseURL $runtimeConfig.domain -payload $clientGrant.payload

                        If ($response.StatusCode -ne 201) {

                            Write-Warning $response.StatusCode
                            Write-Warning ($response.content | ConvertFrom-Json | Out-String)
                            Throw ("Error creating {0}" -f "clientgrant")
                        }
                    }
                }
            }
        }
    }

    # // END processing clients in the PowerShell JSON configuration file //


    # // START processing connections in the PowerShell JSON configuration file //
    
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

    # // END processing connections in the PowerShell JSON configuration file //


    # // START updating email templates //

    Write-Information "`nProcess email templates in ps configuration"
    Foreach ($template in $runtimeConfig.emailTemplates) {
        
        $body = Get-Content -Path (".\Auth0\email-templates\{0}.html" -f $template.payload.template) -ErrorAction Stop | Out-String
        $template.payload | Add-Member -MemberType NoteProperty -Name "body" -Value $body

         Write-Information ("`nupdate email template: {0}" -f $template.payload.template)
         $response = Set-A0EmailTemplate -headers $runtimeConfig.headers -baseURL $runtimeConfig.domain -templateName $template.payload.template -payload $template.payload

        If ($response.StatusCode -ne 200) {
    
            Write-Warning $response.StatusCode
            Write-Warning ($response.content | ConvertFrom-Json | Out-String)
            Throw ("Error updating {0}: {1}" -f "email template", $template.payload.template)
    
        }

    }

    # // END updating email templates //


    # // START remove connections that are not protected or exist in the PowerShell JSON configuration file //
    
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

    # // END remove connections that are not protected or exist in the PowerShell JSON configuration file //   
    
    
    # // START remove client that are not listed in the Auth0 Deploy CLI folder structure //

    # // ** dependency on Auth0 Deploy CLI folder structure ** //
    
    Write-Information "`nDelete client"
    Write-Warning ("Enable Deletions is set to: {0}" -f $enableDeletions)
    
    $auth0DeployClients = (Get-ChildItem -Path "Auth0\clients").BaseName

    $clientsToDelete = $clientNameToIdMapping.Keys | Where-Object {($runtimeConfig.clients.Name -notcontains $_) -and ($auth0DeployClients -notcontains $_) -and ($runtimeConfig.protectedClients -notcontains $_)}
    
    Foreach ($clientName in $clientsToDelete) {                
            
        $clientId = $clientNameToIdMapping.$clientName
            
        Write-Warning ("{0} ({1})" -f $clientName, $clientId)

        If ($enableDeletions) {
            
            $response = Remove-A0Client -headers $runtimeConfig.headers -baseURL $runtimeConfig.domain -clientId $clientId

            If ($response.StatusCode -ne 204) {

                Write-Warning $response.StatusCode
                Write-Warning ($response.content | ConvertFrom-Json | Out-String)
                Throw ("Error deleting Auth0 {0}" -f "client")

            }

        }
    }

    # // END remove client that are not listed in the Auth0 Deploy CLI folder structure //


    # // START remove resource servers that are not listed in the Auth0 Deploy CLI folder structure //

    # // ** dependency on Auth0 Deploy CLI folder structure ** //
    
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
                Throw ("Error deleting Auth0 {0}" -f "resource server")

            }
            
        }
    }

    # // END remove resource servers that are not listed in the Auth0 Deploy CLI folder structure //


    # // START remove rule configuration that do not exist in the PowerShell JSON configuration file //

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

    # // END remove rule configuration that do not exist in the PowerShell JSON configuration file //
}