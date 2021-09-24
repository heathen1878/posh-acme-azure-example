####################################################
# Create a custom role, if one doesn't already exist
####################################################
$roleDefinition = Get-AzRoleDefinition -Name 'DNS TXT Contributor'

If ($roleDefinition){

    $roleId = $roleDefinition.Id

} Else {

    $mgmtGroup = Get-AzManagementGroup | Where-Object {$_.DisplayName -eq 'Tenant Root Group'}

    $roleDefinition = Get-AzRoleDefinition -Name 'DNS Zone Contributor'
    $roleDefinition.Id = $null
    $roleDefinition.Name = "DNS TXT Contributor"
    $roleDefinition.Description = "Manage DNS TXT records only."
    $roleDefinition.Actions.RemoveRange(0, $roleDef.Actions.Count)
    $roleDefinition.Actions.Add("Microsoft.Network/dnsZones/TXT/*")
    $roleDefinition.Actions.Add("Microsoft.Network/dnsZones/read")
    $roleDefinition.Actions.Add("Microsoft.Authorization/*/read")
    $roleDefinition.Actions.Add("Microsoft.Insights/alertRules/*")
    $roleDefinition.Actions.Add("Microsoft.ResourceHealth/availabilityStatuses/read")
    $roleDefinition.Actions.Add("Microsoft.Resources/deployments/read")
    $roleDefinition.Actions.Add("Microsoft.Resources/subscriptions/resourceGroups/read")
    $roleDefinition.AssignableScopes.Clear()
    $roleDefinition.AssignableScopes.Add($mgmtGroup.Id)

    $role = New-AzRoleDefinition $roleDefinition

    ##########################################################
    # Assign the role definition Id to for use in the pipeline
    ##########################################################
    $roleId = $role.Id
    
}

Write-Host "##vso[task.setvariable variable=dnsTXTContributorRole;]$roleId"

