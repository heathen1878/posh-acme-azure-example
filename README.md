# Lets Encrypt Automation

I've taken inspiration from this [article:](https://medium.com/@brentrobinson5/automating-certificate-management-with-azure-and-lets-encrypt-fee6729e2b78) and tried to provide an environment which will build the resources and tooling to generate certificates and store them in a Key Vault for consumption by Azure App Service, Azure Application Gateway...etc.

The service principal can be created by running this [PowerShell](https://github.com/heathen1878/ARM-QuickStarts/tree/master/AzureDevOps) script. The service principal will need to be a member of the following groups: (which need creating)

* Certificate Officers - this group gets the Key vault Certificates Officer RBAC role
* DNS TXT Contributors - this group gets assigned to the custom role 'DNS TXT Contributor'

Add the GUIDs of the groups above into the parameters.json

```json
    "certificatesOfficerGroup": {
        "value": ""
    },

    "DNSTXTContributorsgroup": {
        "value": ""
    }

```

## Build status

Supporting infrastructure:

[![Build Status](https://dev.azure.com/heathen1878/MSDN/_apis/build/status/Arm-LetsEncrypt-Infra?branchName=main)](https://dev.azure.com/heathen1878/MSDN/_build/latest?definitionId=6&branchName=main)

Certificate renewal:

