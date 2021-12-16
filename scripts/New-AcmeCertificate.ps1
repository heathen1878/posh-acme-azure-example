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
    [bool]$staging=$true,
    [Parameter(Mandatory=$false)]
    [bool]$Auto=$true
)

#Requires -Version 6.1
#Requires -Modules @{ModuleName="Az.Accounts"; ModuleVersion="2.5.2"}
#Requires -Modules @{ModuleName="Az.Storage"; ModuleVersion="3.10.0"}
#Requires -Modules @{ModuleName="Posh-ACME"; ModuleVersion="4.9.0"}
#Requires -Modules @{ModuleName="Az.KeyVault"; ModuleVersion="3.4.5"}
#Requires -Modules @{ModuleName="Az.Resources"; ModuleVersion="4.3.0"}

# Create working directory
$wd = Join-Path -Path "." -ChildPath "LE"
Write-Verbose ('Creating working directory: {0}' -f $wd)
New-Item -Path $wd -ItemType Directory -Force | Out-Null
Write-Verbose ('working directory: {0} created' -f $wd)

# Get the storage account SAS token
# requires New-SASToken function.
$rg = $storageAccountId.Split('/')[4]
$storageAccount = $storageAccountId.Split('/')[8]
$blobEndpoint, $sasToken = New-SASToken -containerName 'letsencrypt' -storageAccountName $storageAccount -resourceGroupName $rg -perms 'rwdl'
Write-Verbose ('Generating a SAS token for: {0}' -f $blobEndpoint)

# Sync contents of storage container to working directory
azcopy sync (-join($blobEndpoint,$sasToken)) $wd | Out-Null
Write-Verbose ('Blobs being synched from storage account: {0} at {1}' -f $blobEndpoint, (-Join((get-date).DayOfWeek, ' ', (Get-Date).TimeOfDay.Hours, ':', (Get-Date).TimeOfDay.Minutes)))
Write-ToLog -LogFile (-join($wd, '\le.log')) -LogContent ('Blobs being synched from storage account: {0} at {1}' -f $blobEndpoint, (-Join((get-date).DayOfWeek, ' ', (Get-Date).TimeOfDay.Hours, ':', (Get-Date).TimeOfDay.Minutes)))

# Supress progress messages. Azure DevOps doesn't format them correctly (used by New-PACertificate)
Write-Verbose ('Setting progress preference to silently continue to support DevOps')
Write-ToLog -LogFile (-join($wd, '\le.log')) -LogContent ('Setting progress preference to silently continue to support DevOps')
$global:ProgressPreference = 'SilentlyContinue'

# The certificate name is always the first name passed into the string array
Write-Verbose ('{0} being assigned the certificate name' -f $domainNames[0])
Write-ToLog -LogFile (-join($wd, '\le.log')) -LogContent ('{0} being assigned the certificate name' -f $domainNames[0])
$certificateName = $domainNames[0]

# Posh-ACME replaces the * in a wildcard certificate with a !
$certificateName = $certificateName.Replace('*','!')
Write-Verbose ('{0} being renamed to {1}' -f $domainNames[0], $certificateName)
Write-ToLog -LogFile (-join($wd, '\le.log')) -LogContent ('{0} being renamed to {1}' -f $domainNames[0], $certificateName)

# Set Posh-ACME working directory
Write-Verbose ('Setting POSHACME_HOME to {0}' -f $wd)
Write-ToLog -LogFile (-join($wd, '\le.log')) -LogContent ('Setting POSHACME_HOME to {0}' -f $wd)
$env:POSHACME_HOME = $wd
Import-Module Posh-ACME -Force

# Configure ACME server type
If ($staging){
    
    Write-Verbose ('Using staging directory LE_STAGE')
    Write-ToLog -LogFile (-join($wd, '\le.log')) -LogContent ('Using staging directory LE_STAGE')
    Set-PAServer -DirectoryUrl LE_STAGE
    
} Else {
    
    Write-Verbose ('Using production directory LE_PROD')
    Write-ToLog -LogFile (-join($wd, '\le.log')) -LogContent ('Using production directory LE_PROD')
    Set-PAServer -DirectoryUrl LE_PROD

}

# Configure Posh-ACME account
Write-Verbose ('Checking for a Lets Encrypt account in the working directory {0}' -f $wd)
Write-ToLog -LogFile (-join($wd, '\le.log')) -LogContent ('Checking for a Lets Encrypt account in the working directory {0}' -f $wd)
if (-not (Get-PAAccount)) {
    
    # New account
    New-PAAccount -Contact $contactEmailAddress -AcceptTOS
    Write-Verbose ('New account {0} with id: {1} created' -f $((Get-PAAccount).Contact), (Get-PAAccount).Id)
    Write-ToLog -LogFile (-join($wd, '\le.log')) -LogContent ('New account {0} with id: {1} created' -f $((Get-PAAccount).Contact), (Get-PAAccount).Id)

} Else {

    Write-Verbose ('Found account {0} with id: {1}' -f $(Get-PAAccount).Contact, (Get-PAAccount).Id)
    Write-ToLog -LogFile (-join($wd, '\le.log')) -LogContent ('Found account {0} with id: {1}' -f $((Get-PAAccount).Contact), (Get-PAAccount).Id)

}

# Get the expiry of the current order, if it exists
$certificateDirectory = (-join($wd, '\', (Get-PAServer).Name, '\', (Get-PAAccount).Id, '\', $certificateName))
Write-Verbose ('Checking for certificate directory {0}' -f $certificateDirectory)
Write-ToLog -LogFile (-join($wd, '\le.log')) -LogContent ('Checking for certificate directory {0}' -f $certificateDirectory)
If (Test-Path $certificateDirectory){

    Write-Verbose ('Checking certificate directory {0} for order.json' -f $certificateDirectory)
    If (Test-Path (-join($certificateDirectory, '\order.json'))){

        Write-Verbose ('Found order.json')
        $order = Get-Content (-join($certificateDirectory, '\order.json')) | ConvertFrom-Json

        If ($order.status -ne 'invalid'){
            Write-Verbose ('Status: {0}' -f $order.status)
            Write-Verbose ('Checking whether certificate is near expiry')
            If ((Get-Date).Date -ge $order.CertExpires.AddDays(-20)){

                Write-Verbose ('Expiry: {0}' -f $order.CertExpires)
                If ($Auto){

                    $azureAccessToken = (Get-AzAccessToken).Token
                
                    $paPluginArgs = @{
                        AZSubscriptionId = (Get-AzContext).Subscription.Id
                        AZAccessToken    = $azureAccessToken;
                    }

                    Write-Verbose ('Automatically renewing certificate for {0}' -f $order.MainDomain)
                    Submit-Renewal -PluginArgs $paPluginArgs

                } Else {

                    Write-Verbose ('Manual renewal for certificate {0}' -f $order.MainDomain)
                    Submit-Renewal -NoSkipManualDns

                }           

            } Else {

                Write-Verbose ('Certificate for {0} valid until {1}' -f $order.MainDomain, $order.CertExpires)

            }

        } Else {

            Write-Verbose ('Current order {0}, forcing creation of new certificate' -f $order.status)
            $azureAccessToken = (Get-AzAccessToken).Token

            $paPluginArgs = @{
                AZSubscriptionId = (Get-AzContext).Subscription.Id
                AZAccessToken    = $azureAccessToken;
            }
        
            Write-Verbose ('Forcing cration of certificate for {0}' -f $order.MainDomain)
            New-PACertificate -Domain $certDomainNames -DnsPlugin Azure -PluginArgs $paPluginArgs

        }

    }

} Else {

    Write-Verbose ('No existing certificate directory found for {0}' -f $certificateNames)
    $azureAccessToken = (Get-AzAccessToken).Token

    $paPluginArgs = @{
        AZSubscriptionId = (Get-AzContext).Subscription.Id
        AZAccessToken    = $azureAccessToken;
    }

    If ($Auto){

        Write-Verbose ('Automatically creating certificate for {0}' -f $domainNames[0])
        New-PACertificate -Domain $domainNames -DnsPlugin Azure -PluginArgs $paPluginArgs

    } Else {

        Write-Verbose ('Manual renewal for certificate {0}' -f $domainNames[0])
        New-PACertificate -Domain $domainNames

    }

}

# Get the pfx password
Write-Verbose ('Retrieving password for certificate {0}' -f $certificateName)
$pfxPass = (Get-PAOrder -Name $certificateName).PfxPass

# Convert the pfx password to a secure string
$pfxPass = ConvertTo-SecureString -String $pfxPass -AsPlainText -Force

# Load the pfx
Write-Verbose ('Loading pfx')
$certificate = Get-PfxCertificate -FilePath (-join($certificateDirectory, '\fullchain.pfx')) -Password $pfxPass

# Get Base64 certificate encoding
Write-Verbose ('Generating BASE64 for certificate {0}' -f $certificate.Thumbprint )
$pfxBytes = Get-Content -Path (-join($certificateDirectory, '\fullchain.pfx')) -AsByteStream
$certificateBase64 = [System.Convert]::ToBase64String($pfxBytes)
$certificateBase64 = ConvertTo-SecureString -String $certificateBase64 -AsPlainText -Force

# Get the current certificate from key vault (if any)
$KeyVaultCertificateName = $certificateName.Replace(".", "-").Replace("!", "wildcard")
$KeyVaultSecretName = (-Join($certificateName.Replace(".", "-").Replace("!", "wildcard"),'-base64'))
$keyVaultResource = Get-AzResource -ResourceId $keyVaultId

# Check whether there is a certifcate already stored in Key Vault
Write-Verbose ('Checking for certificate {0} in Key Vault {1}' -f $KeyVaultCertificateName, $keyVaultResource.Name)
If ($KeyVaultCertificate = Get-AzKeyVaultCertificate -VaultName $keyVaultResource.Name -Name $KeyVaultCertificateName) {

    # Certificate already exists...Check the thumbprint
    Write-Verbose ('Checking thumbprints of {0} and {1}' -f $KeyVaultCertificateName, $certificateName)
    If ($KeyVaultCertificate.Thumbprint -ne $certificate.Thumbprint) {

        Write-Verbose ('Replacing {0} into the key vault {1}' -f $KeyVaultCertificateName, $keyVaultResource.Name)
        Import-AzKeyVaultCertificate -VaultName $keyVaultResource.Name -Name $KeyVaultCertificateName -FilePath (-join($certificateDirectory, '\fullchain.pfx')) -Password $pfxPass | Out-Null    
    
    }

} Else {

    Write-Verbose ('Adding {0} into the key vault {1}' -f $KeyVaultCertificateName, $keyVaultResource.Name)
    Import-AzKeyVaultCertificate -VaultName $keyVaultResource.Name -Name $KeyVaultCertificateName -FilePath (-join($certificateDirectory, '\fullchain.pfx')) -Password $pfxPass | Out-Null

}

# Check whether the secret exists
Write-Verbose ('Checking for BASE64 secret {0} in Key Vault {1}' -f $KeyVaultSecretName, $keyVaultResource.Name)
If (Get-AzKeyVaultSecret -VaultName $keyVaultResource.Name -Name $KeyVaultSecretName) {

    # Secret exists, is it ready for renewal?
    Write-Verbose ('Checking expiry date of {0}' -f $KeyVaultCertificate)
    If ((Get-Date).Date -ge $KeyVaultCertificate.Expires.AddDays(-20)) {

        Write-Verbose ('Updating {0} secret in key vault {1}' -f $KeyVaultSecretNames, $keyVaultResource.Name)
        Update-AzKeyVaultSecret -VaultName $keyVaultResource.Name -Name $KeyVaultSecretName -SecretValue $certificateBase64 -ContentType base64 | Out-Null

    }

} Else {

    Write-Verbose ('Adding {0} secret into the key vault {1}' -f $KeyVaultSecretName, $keyVaultResource.Name)
    Set-AzKeyVaultSecret -VaultName $keyVaultResource.Name -Name $KeyVaultSecretName -SecretValue $certificateBase64 -ContentType base64 | Out-Null

}

Write-Verbose ('Blobs being synched to storage account: {0} at {1}' -f $blobEndpoint, (-Join((get-date).DayOfWeek, ' ', (Get-Date).TimeOfDay.Hours, ':', (Get-Date).TimeOfDay.Minutes)))
Write-ToLog -LogFile (-join($wd, '\le.log')) -LogContent ('Blobs being synched to storage account: {0} at {1}' -f $blobEndpoint, (-Join((get-date).DayOfWeek, ' ', (Get-Date).TimeOfDay.Hours, ':', (Get-Date).TimeOfDay.Minutes)))
# Sync working directory back to storage container
azcopy sync $wd (-join($blobEndpoint,$sasToken)) | Out-Null