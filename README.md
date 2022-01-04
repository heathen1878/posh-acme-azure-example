# Lets Encrypt Automation

I've taken inspiration from this [article:](https://medium.com/@brentrobinson5/automating-certificate-management-with-azure-and-lets-encrypt-fee6729e2b78) and built the resources and tooling to generate certificates and store them in a Key Vault for consumption by Azure App Service, Azure Application Gateway...etc.

The service principal can be created by running this [PowerShell](https://github.com/heathen1878/ARM-QuickStarts/tree/master/AzureDevOps) script. The service principal will need the following roles: Key Vault Certificates Officer and Key Vault Secrets Officer.

## Infrastructure components

[![Build Status](https://dev.azure.com/heathen1878/MSDN/_apis/build/status/Arm-LetsEncrypt-Infra?branchName=main)](https://dev.azure.com/heathen1878/MSDN/_build/latest?definitionId=6&branchName=main)

[![Visualize](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/1-CONTRIBUTION-GUIDE/images/visualizebutton.svg?sanitize=true)](http://armviz.io/#/?load=https%3A%2F%2Fraw.githubusercontent.com%2Fheathen1878%2Fposh-acme-azure-example%2Fmaster%2Ftemplates%2Fazuredeploy.json)

You must supply at the least the following parameters:

```json
    "location": {
        "value": ""
    },
    "RBAC": {
        "value": [
            {
                "roleId": "acdd72a7-3385-48ef-bd42-f606fba81ae7",
                "principalId": "00000000-0000-0000-0000-000000000000"
            }
        ]
    },

    "certificatesOfficerGroup": {
        "value": ""
    },
    "secretsOfficerGroup": {
        "value": ""
    },
    "microsoftAzureAppService": {
        "value": ""
    },
    "DNSTXTContributorsgroup": {
        "value": ""
    },
```
* Location - a valid Azure region
* RBAC - an array of roles and principals the example shows a the reader role and a fictitious principal id.
* Certificate Officers - A user or group GUID. The user or group is assigned the Key Vault Certificates Officer role at the Key Vault resource.
* Secrets Officers - A user or group GUID. The user or group is assigned the Key Vault Secrets Officer role at the Key Vault resource.
* Microsoft Azure App Service - the object GUID of the Microsoft Azure Websites Enterprise Application associated with your AAD tenant. 
* DNS TXT Contributors - A user or group GUID. The user or group is assigned the custom role 'DNS TXT Contributor' at the DNS zone resource.

Add the GUIDs of the groups above into the parameters.json

### Manual deployment

Create the custom DNS role
```PowerShell
New-RoleDefinition.ps1
```

NOTE: The 'dnstxtcontributorId' is the output from the PowerShell script: New-RoleDefinition.ps1

Deploying through PowerShell 
```PowerShell
New-AzSubscriptionDeployment `
-Name 'LE' `
-Location 'North Europe' `
-TemplateFile .\templates\azuredeploy.json `
-TemplateParameterFile .\templates\azuredeploy.parameters.json `
-dnstxtcontributorId 0000000-0000-0000-0000-000000000000
```

### Continuous Delivery

The pipeline le_infra.yml will create the role and resources but requires the following variables be defined in the variables.yml.

```yaml
azure_region: 'North Europe'
serviceConn: 'LE'
```

The stage name and environment are provided within le_infra.yml, the environment defined within the pipeline will override that defined within the azuredeploy.parameters.json file.

```yaml
stage_name: DeployToTesting
environment: Testing
```

###  ARM outputs
Regardless of which method you opt for you'll need to configure Name Server records to point to Azure. The actual values will be provided as outputs of the ARM deployment. The output name is dnsZone_NSRecords - note this output is an array as its possible to deploy more than one zone. 

## Certificate renewal

[![Build Status](https://dev.azure.com/heathen1878/MSDN/_apis/build/status/Pwsh-LetsEncrypt-Cert?branchName=main)](https://dev.azure.com/heathen1878/MSDN/_build/latest?definitionId=8&branchName=main)

The certificate renewal script uses two functions which are hosted within a private PowerShell gallery - using an Azure DevOps Artifacts [feed](https://github.com/heathen1878/PowerShellModules#readme). The pipeline installs these modules on the Microsoft hosted agent, alongside other required modules for example:

```PowerShell
    $modules = @{
        'Az.Accounts' = '2.5.2'
        'Az.KeyVault' = '3.4.5'
        'Az.Resources' = '4.3.0'
        'Az.Storage' = '3.10.0'
        'Posh-ACME' = '4.9.0'
    }
    ...
     $Modules.Keys | Foreach-Object {
        ...
        Install-Module -Repository PSGallery -Name $_ -MinimumVersion $Modules[$_] -scope CurrentUser...
        ...    
    }
    ...
    Register-PackageSource -Name AzDoRepo -ProviderName 'PowerShellGet' -Location ${{ parameters.azdofeed }} -Trusted -Credential $devOpsCred
    ...
    Install-Module -Name Dom.Logging -Repository AzDoRepo -Credential $devOpsCreds
    Install-Module -Name Dom.Storage -Repository AzDoRepo -Credential $devOpsCred
    ...
```