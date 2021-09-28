[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [string[]]$domainNames,
    [Parameter(Mandatory)]
    [string]$contactEmailAddress,
    [Parameter(Mandatory)]
    [string]$storageAccountId,
    [Parameter(Mandatory)]
    [string]$keyVaultId,
    [Parameter(Mandatory=$false)]
    [bool]$staging=$true
)

#Requires -Version 6.1
#Requires -Modules @{ModuleName="Az.Accounts"; ModuleVersion="2.5.2"}
#Requires -Modules @{ModuleName="Az.Storage"; ModuleVersion="3.10.0"}
#Requires -Modules @{ModuleName="Posh-ACME"; ModuleVersion="4.9.0"}
#Requires -Modules @{ModuleName="Az.KeyVault"; ModuleVersion="3.4.5"}
#Requires -Modules @{ModuleName="Az.Resources"; ModuleVersion="4.3.0"}

# Supress progress messages. Azure DevOps doesn't format them correctly (used by New-PACertificate)
$global:ProgressPreference = 'SilentlyContinue'

# The certificate name is always the first name passed into the string array
$certificateName = $domainNames[0]

# Posh-ACME replaces the * in a wildcard certificate with a !
$certificateName = $certificateName.Replace('*','!')

# Create working directory
$workingDirectory = Join-Path -Path "." -ChildPath "LE"
New-Item -Path $workingDirectory -ItemType Directory -Force | Out-Null

# Get the storage account SAS token
# requires Get-SASToken function.
$rg = $storageAccountId.Split('/')[4]
$storageAccount = $storageAccountId.Split('/')[8]
$blobEndpoint, $sasToken = Get-SASToken -containerName 'letsencrypt' -storageAccountName $storageAccount -resourceGroupName $rg -perms 'rwdl'

# Sync contents of storage container to working directory
azcopy sync (-join($blobEndpoint,$sasToken)) $workingDirectory | Out-Null

# Set Posh-ACME working directory
$env:POSHACME_HOME = $workingDirectory
Import-Module Posh-ACME -Force

# Configure ACME server type
If ($staging){
    
    Set-PAServer -DirectoryUrl LE_STAGE
    
} Else {
    
    Set-PAServer -DirectoryUrl LE_PROD

}

# Configure Posh-ACME account
if (-not (Get-PAAccount)) {
    
    # New account
    New-PAAccount -Contact $contactEmailAddress -AcceptTOS

}

# Get the expiry of the current order, if it exists
If (Test-Path (-join($workingDirectory, '\', (Get-PAServer).Name, '\', (Get-PAAccount).Id, '\', $certificateName))){

    # Determine Certificate path
    $certificateDirectory = (-join($workingDirectory, '\', (Get-PAServer).Name, '\', (Get-PAAccount).Id, '\', $certificateName))
    If (Test-Path (-join($certificateDirectory, '\order.json'))){

        # Order exists, check expiry
        $order = Get-Content (-join($certificateDirectory, '\order.json')) | ConvertFrom-Json

        If ($order.CertExpires -lt (Get-Date).AddDays(76)){

            #renew cert
            Submit-Renewal

        }

    }

} Else {

    # Create a new order
    # Acquire access token for Azure (as we want to leverage the existing connection)
    $azureAccessToken = Get-AccessToken

    # Request certificate
    $paPluginArgs = @{
        AZSubscriptionId = (Get-AzContext).Subscription.Id
        AZAccessToken    = $azureAccessToken;
    }
    New-PACertificate -Domain $domainNames -DnsPlugin Azure -PluginArgs $paPluginArgs

    # Sync working directory back to storage container
    azcopy sync $workingDirectory (-join($blobEndpoint,$sasToken)) | Out-Null

    # Get the pfx password
    $pfxPass = (Get-PAOrder -Name $certificateName).PfxPass

    # Convert the pfx password to a secure string
    $pfxPass = ConvertTo-SecureString -String $pfxPass -AsPlainText -Force

    # Load the pfx
    $certificate = Get-PfxCertificate -FilePath (-join($certificateDirectory, '\fullchain.pfx')) -Password $pfxPass

    # Get the current certificate from key vault (if any)
    $azKeyVaultCertificateName = $certificateName.Replace(".", "-").Replace("!", "wildcard")
    $keyVaultResource = Get-AzResource -ResourceId $keyVaultId
    
    # Check whether there is a certifcate already stored in Key Vault
    If ($azKeyVaultCertificate = Get-AzKeyVaultCertificate -VaultName $keyVaultResource.Name -Name $azKeyVaultCertificateName){

        # Certificate already exists...Check the thumbprint
        If ($azKeyVaultCertificate.Thumbprint -ne $certificate.Thumbprint) {

            Import-AzKeyVaultCertificate -VaultName $keyVaultResource.Name -Name $azKeyVaultCertificateName -FilePath (-join($certificateDirectory, '\fullchain.pfx')) -Password $pfxPass | Out-Null    
        
        }

    } Else {

        Import-AzKeyVaultCertificate -VaultName $keyVaultResource.Name -Name $azKeyVaultCertificateName -FilePath (-join($certificateDirectory, '\fullchain.pfx')) -Password $pfxPass | Out-Null

    }

}