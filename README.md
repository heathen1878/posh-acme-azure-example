# Lets Encrypt Automation

I've taken inspiration from this [article:](https://medium.com/@brentrobinson5/automating-certificate-management-with-azure-and-lets-encrypt-fee6729e2b78) and tried to provide an environment which will build the resources and tooling to generate certificates and store them in a Key Vault for consumption by Azure App Service, Azure Application Gateway...etc.

The service principal can be created by running this [PowerShell](https://github.com/heathen1878/ARM-QuickStarts/tree/master/AzureDevOps) script. The service principal will need to be a member of the following groups: (which need creating)

## Infrastructure components

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
    "DNSTXTContributorsgroup": {
        "value": ""
    },
```

* Certificate Officers - this group gets the Key Vault Certificates Officer RBAC role assigned to at the Key Vault resource.
* Secrets Officers - this group gets tge Key Vault Secrets Officer RBAC role assigned to at the Key Vault resource.
* DNS TXT Contributors - this group gets assigned to the custom role 'DNS TXT Contributor' assigned to the DNS zone resource.

Add the GUIDs of the groups above into the parameters.json

[![Visualize](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/1-CONTRIBUTION-GUIDE/images/visualizebutton.svg?sanitize=true)](http://armviz.io/#/?load=https%3A%2F%2Fraw.githubusercontentcom%2Fheathen1878%2Fposh-acme-azure-example%2Fmaster%2Ftemplates%2Fazuredeploy.json)

## Manual deployment

Create the custom DNS role
```PowerShell
New-RoleDefinition.ps1
```

NOTE: The DNS TXT contributor Id is the output from the PowerShell script: New-RoleDefinition.ps1

Deploying through PowerShell 
```PowerShell
New-AzSubscriptionDeployment `
-Name 'LE' `
-Location 'North Europe' `
-TemplateFile .\templates\azuredeploy.json `
-TemplateParameterFile .\templates\azuredeploy.parameters.json `
-dnstxtcontributorId 0000000-0000-0000-0000-000000000000
```

## Continuous Delivery

Deploying through the pipeline
The pipeline le_infra.yml will create the role and resources but requires the following variables be defined

```yaml
azure_region: 'North Europe'
serviceConn: 'LE'
```

The stage name and environment are provided within le_infra.yml, the environment defined within the pipeline will override that defined within the azuredeploy.parameters.json file.

##  ARM outputs
Regardless of which method you opt for you'll need to configure Name Server records to point to Azure. The actual values will be provided as outputs of the ARM deployment. The output name is dnsZone_NSRecords - note this output is an array as its possible to deploy more than one zone. 





https://github.com/heathen1878/PowerShellModules#readme


## Build status

Supporting infrastructure:

[![Build Status](https://dev.azure.com/heathen1878/MSDN/_apis/build/status/Arm-LetsEncrypt-Infra?branchName=main)](https://dev.azure.com/heathen1878/MSDN/_build/latest?definitionId=6&branchName=main)

Certificate renewal:

[![Build Status](https://dev.azure.com/heathen1878/MSDN/_apis/build/status/Pwsh-LetsEncrypt-Cert?branchName=main)](https://dev.azure.com/heathen1878/MSDN/_build/latest?definitionId=8&branchName=main)
