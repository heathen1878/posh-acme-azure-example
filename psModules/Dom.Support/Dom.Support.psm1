function Get-SASToken {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$resourceGroupName,
        [Parameter(Mandatory)]
        [string]$storageAccountName,
        [Parameter(Mandatory)]
        [string]$containerName,
        [Parameter(Mandatory=$False)]
        [int]$timeInHours = 2,
        [Parameter(Mandatory=$False)]
        [string]$perms='r'
        )

    Try {
        $context = (Get-AzStorageAccount `
        -ResourceGroupName $resourceGroupName `
        -StorageAccountName $storageAccountName `
        -ErrorAction Stop).Context
    }
    Catch {
        Write-Warning $Error[0].Exception
        exit
    }

    Try {
        $sasToken = New-AzStorageAccountSASToken `
        -Context $context `
        -Service Blob `
        -ResourceType service,container,object `
        -Permission $perms `
        -StartTime (Get-Date).AddHours(-1) `
        -ExpiryTime (Get-Date).AddHours($timeInHours) -ErrorAction Stop
    }
    Catch {
        Write-Warning $Error[0].Exception
        exit
    }

    Return (-join($context.BlobEndPoint, $containerName)), $sasToken

}

function New-Password {
    <#
    .SYNOPSIS
        Generate a random password.
    .DESCRIPTION
        Generate a random password.
    .NOTES
        Change log:
            27/11/2017 - faustonascimento - Swapped Get-Random for System.Random.
                                            Swapped Sort-Object for Fisher-Yates shuffle.
            17/03/2017 - Chris Dent - Created.
            Taken from here: https://gist.github.com/indented-automation/2093bd088d59b362ec2a5b81a14ba84e
    #>
    [CmdletBinding()]
    [OutputType([String])]
    param (
        # The length of the password which should be created.
        [Parameter(ValueFromPipeline)]        
        [ValidateRange(8, 255)]
        [Int32]$Length = 10,
        # The character sets the password may contain. A password will contain at least one of each of the characters.
        [String[]]$CharacterSet = ('abcdefghijklmnopqrstuvwxyz',
                                   'ABCDEFGHIJKLMNOPQRSTUVWXYZ',
                                   '0123456789',
                                   '!$%&^#@*'),
                                    
        # The number of characters to select from each character set.
        [Int32[]]$CharacterSetCount = (@(1) * $CharacterSet.Count)
    )
    begin {
        $bytes = [Byte[]]::new(4)
        $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
        $rng.GetBytes($bytes)
        $seed = [System.BitConverter]::ToInt32($bytes, 0)
        $rnd = [Random]::new($seed)
        if ($CharacterSet.Count -ne $CharacterSetCount.Count) {
            throw "The number of items in -CharacterSet needs to match the number of items in -CharacterSetCount"
        }
        $allCharacterSets = [String]::Concat($CharacterSet)
    }
    process {
        try {
            $requiredCharLength = 0
            foreach ($i in $CharacterSetCount) {
                $requiredCharLength += $i
            }
            if ($requiredCharLength -gt $Length) {
                throw "The sum of characters specified by CharacterSetCount is higher than the desired password length"
            }
            $password = [Char[]]::new($Length)
            $index = 0
        
            for ($i = 0; $i -lt $CharacterSet.Count; $i++) {
                for ($j = 0; $j -lt $CharacterSetCount[$i]; $j++) {
                    $password[$index++] = $CharacterSet[$i][$rnd.Next($CharacterSet[$i].Length)]
                }
            }
            for ($i = $index; $i -lt $Length; $i++) {
                $password[$index++] = $allCharacterSets[$rnd.Next($allCharacterSets.Length)]
            }
            # Fisher-Yates shuffle
            for ($i = $Length; $i -gt 0; $i--) {
                $n = $i - 1
                $m = $rnd.Next($i)
                $j = $password[$m]
                $password[$m] = $password[$n]
                $password[$n] = $j
            }
            [String]::new($password)
        } catch {
            Write-Error -ErrorRecord $_
        }
    }
}
  

function New-P2SChildCert {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$CompanyName
    )

    # Requires New-Password
    Try {
        Get-Command New-Password -ErrorAction Stop | Out-Null
    }
    Catch {
        Write-Warning "New-Password function is missing, please import."
        Break
    }

    $RootCert = Get-ChildItem -Path 'Cert:\CurrentUser\My' | Out-GridView -Title 'Select the P2S Root Cert' -PassThru

    $CertOutput = New-SelfSignedCertificate -Type Custom -DnsName (-Join('P2S-', $CompanyName, '-Cert')) -KeySpec Signature `
    -Subject (-Join('CN=P2S-', $CompanyName, '-Cert')) -KeyExportPolicy Exportable `
    -HashAlgorithm sha256 -KeyLength 2048 -CertStoreLocation 'Cert:\CurrentUser\My' `
    -Signer $RootCert -TextExtension @("2.5.29.37={text}1.3.6.1.5.5.7.3.2")

    $Password = New-Password -Length 16
    $sPassword = ConvertTo-SecureString -String $Password -AsPlainText -Force

    $certExportName = $CertOutput.Subject.Substring(3, $CertOutput.Subject.Length -3)
    Write-Host "Exporting: $certExportName"

    Try {

        Export-PfxCertificate -Cert (-Join('Cert:\CurrentUser\My\', $CertOutput.Thumbprint)) -FilePath (-Join($certExportName, '.pfx')) -Password $sPassword | Out-Null
        Write-Output ('Certificate {0} exported to {1}' -f (-Join($certExportName, '.pfx')), $(Get-Location))
        Write-Output ('Use {0}  to import' -f $Password)

    }
    Catch {

        Write-Error $Error.Exception.Message

    }  
        
}

function Get-AuthenticationHeader {
    
    $azContext = Get-AzContext
    $azProfile = [Microsoft.Azure.Commands.Common.Authentication.Abstractions.AzureRmProfileProvider]::Instance.Profile;
    $profileClient = New-Object -TypeName Microsoft.Azure.Commands.ResourceManager.Common.RMProfileClient($azProfile);
    $token = $profileClient.AcquireAccessToken($azContext.Subscription.TenantId);
    $authH = @{
        'Content-Type'='application/json';
        'Authorization'='Bearer ' + $token.AccessToken
    }    

    Return $authH

}

function  Get-AccessToken {

    $azContext = Get-AzContext
    $azProfile = [Microsoft.Azure.Commands.Common.Authentication.Abstractions.AzureRmProfileProvider]::Instance.Profile;
    $profileClient = New-Object -TypeName Microsoft.Azure.Commands.ResourceManager.Common.RMProfileClient($azProfile)
    $accessToken = $profileClient.AcquireAccessToken($azContext.Tenant.Id).AccessToken;

    Return $accessToken
    
}

function Get-PublicIPAddress {

    Return (Invoke-RestMethod -Uri http://ipv4.icanhazip.com).Trim()

}

function Set-Subscription {
    # Check whether PowerShell is connected to a tenant
    If (Get-AzContext){
        # Output the tenant Name
        Write-Output ('Connected to {0}, getting subscriptions' -f $(Get-AzTenant).Name)
    } Else {
        Start-Process Microsoft-edge:https://microsoft.com/devicelogin;Connect-AzAccount -DeviceCode
    }
    
    $Subscription = Get-AzSubscription | Select-Object Name, SubscriptionId `
    | Out-GridView -Title "Select the subscription you want to deploy to" -PassThru

	$SubId = Set-AzContext -SubscriptionId $Subscription.SubscriptionId
	
	Write-Output ('Setting context to: {0}' -f (Get-AzSubscription -SubscriptionId $SubId.Subscription).Name)
}

function Get-ModuleVersion {

    [CmdletBinding()]
    Param
    (
        [parameter(Mandatory)]
        [string]$ModuleName
    )
    
    $module = (Get-Module -FullyQualifiedName $ModuleName)
    $Version = (-Join($module.Version.Major, '.', $module.Version.Minor,'.', $module.Version.Build))
    
    Return $version

}

Export-ModuleMember Get-SASToken
Export-ModuleMember New-Password
Export-ModuleMember New-P2SChildCert
Export-ModuleMember Get-AccessToken
Export-ModuleMember Get-AuthenticationHeader
Export-ModuleMember Set-Subscription
Export-ModuleMember Get-ModuleVersion