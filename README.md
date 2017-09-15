#### Build Status
Appveyor:  
[![Build status](https://ci.appveyor.com/api/projects/status/05kpfdxqr0fskj59?svg=true)](https://ci.appveyor.com/project/amido/a0toolkit)

**A0Toolkit** is published in the [Chocolatey packages community feed](https://chocolatey.org/packages/A0Toolkit).

As A0Tookit is a PowerShell module it will autoload when any exported functions are invoked.


---
## A0Toolkit
List of exported functions:
* Get-A0Client
* Get-A0ClientGrants
* Get-A0Connection
* Get-A0EmailProvider
* Get-A0ResourceServer
* New-A0Connection
* New-A0EmailProvider
* New-A0Token
* Remove-A0Client
* Remove-A0Connection
* Set-A0Client
* Set-A0Connection
* Set-A0EmailProvider
* Set-A0Tenant  


## Provisioning Auth0
Using a combination of the [Auth0 Deploy CLI](https://github.com/auth0/auth0-deploy-cli) node application and the above module, provisioning of Auth0 can largely be automated and integrated into a deployment pipeline. There are some gaps in the Auth0 API, most noticable are:
* Rule configuration
* Email templates
* Add Auth0 Administrators

In the folder **SampleOrchestrationScript** there is an example of how to orchestrate the functions above into a working solution.

This composes of a PowerShell script *Set-Auth0Tenant* and a json configuration file *powershell.auth0.config.json* 

The json file consist of:

*Array of Environments*  
Common can be used for shared values and overridden by other environments. If integrating into a deployment pipeline, the common environment values can be tokenised, as in the example. A token is denoted by ```#{xxx}```

*Auth0 Configuration*  
These sections closely align to Auth0 resources:
* account
* clients
* connections
* email

These sections are custom and protect the resources from being deleted by the PowerShell script:
* protectedClients
* protectedConnections

These properties are required to acquire a Auth0 Management token:
* clientId
* clientSecret


#### Example
This would load any sections/properties from the 'dev' environment and then any additional sections/properties from the common envrionment.  

```PowerShell
Set-Auth0Tenant -targetEnvironment 'dev'
```
