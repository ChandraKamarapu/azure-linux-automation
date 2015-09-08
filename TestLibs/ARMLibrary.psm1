﻿Function CreateAllResourceGroupDeployments($setupType, $xmlConfig, $Distro)
{
    $resourceGroupCount = 0
    $xml = $xmlConfig
    LogMsg $setupType
    $setupTypeData = $xml.config.Azure.Deployment.$setupType
    $allsetupGroups = $setupTypeData
    if ($allsetupGroups.HostedService[0].Location -or $allsetupGroups.HostedService[0].AffinityGroup)
    {
        $isMultiple = 'True'
        $resourceGroupCount = 0
    }
    else
    {
        $isMultiple = 'False'
    }

    foreach ($newDistro in $xml.config.Azure.Deployment.Data.Distro)
    {

        if ($newDistro.Name -eq $Distro)
        {
            $osImage = $newDistro.OsImage
            $osVHD = $newDistro.OsVHD
        }
    }

    $location = $xml.config.Azure.General.Location
    $AffinityGroup = $xml.config.Azure.General.AffinityGroup

    foreach ($RG in $setupTypeData.HostedService )
    {
        $curtime = Get-Date
        $isServiceDeployed = "False"
        $retryDeployment = 0
        if ( $RG.Tag -ne $null )
        {
            $groupName = "ICA-RG-" + $RG.Tag + "-" + $Distro + "-" + $curtime.Month + "-" +  $curtime.Day  + "-" + $curtime.Hour + "-" + $curtime.Minute + "-" + $curtime.Second
        }
        else
        {
            $groupName = "ICA-RG-" + $setupType + "-" + $Distro + "-" + $curtime.Month + "-" +  $curtime.Day  + "-" + $curtime.Hour + "-" + $curtime.Minute + "-" + $curtime.Second
        }
        if($isMultiple -eq "True")
        {
            $groupName = $groupName + "-" + $resourceGroupCount
        }

        while (($isServiceDeployed -eq "False") -and ($retryDeployment -lt 5))
        {
            LogMsg "Creating Resource Group : $groupName."
            LogMsg "Verifying that Resource group name is not in use."
            $isRGDeleted = DeleteResourceGroup -RGName $groupName 
            if ($isRGDeleted)
            {    
                $isServiceCreated = CreateResourceGroup -RGName $groupName -location $location
                if ($isServiceCreated -eq "True")
                {
                    $azureDeployJSONFilePath = "$LogDir\$groupName.json"
                    $DeploymentCommand = GenerateAzureDeployJSONFile -RGName $groupName -osImage $osImage -osVHD $osVHD -RGXMLData $RG -Location $location -azuredeployJSONFilePath $azureDeployJSONFilePath
                    $DeploymentStartTime = (Get-Date)
                    $CreateRGDeployments = CreateResourceGroupDeployment -RGName $groupName -location $location -setupType $setupType -TemplateFile $azureDeployJSONFilePath
                    $DeploymentEndTime = (Get-Date)
                    $DeploymentElapsedTime = $DeploymentEndTime - $DeploymentStartTime
                    if ( $CreateRGDeployments )
                    {
                        $retValue = "True"
                        $isServiceDeployed = "True"
                        $resourceGroupCount = $resourceGroupCount + 1
                        if ($resourceGroupCount -eq 1)
                        {
                            $deployedGroups = $groupName
                        }
                        else
                        {
                            $deployedGroups = $deployedGroups + "^" + $groupName
                        }

                    }
                    else
                    {
                        LogErr "Unable to Deploy one or more VM's"
                        $retryDeployment = $retryDeployment + 1
                        $retValue = "False"
                        $isServiceDeployed = "False"
                    }
                }
                else
                {
                    LogErr "Unable to create $groupName"
                    $retryDeployment = $retryDeployment + 1
                    $retValue = "False"
                    $isServiceDeployed = "False"
                }
            }    
            else
            {
                LogErr "Unable to delete existing resource group - $groupName"
                $retryDeployment = 3
                $retValue = "False"
                $isServiceDeployed = "False"
            }
        }
    }
    return $retValue, $deployedGroups, $resourceGroupCount, $DeploymentElapsedTime
}

Function DeleteResourceGroup([string]$RGName, [switch]$KeepDisks)
{
    $ResourceGroup = Get-AzureResourceGroup -Name $RGName -ErrorAction Ignore
    if ($ResourceGroup)
    {
        $retValue =  Remove-AzureResourceGroup -Name $RGName -Force -PassThru -Verbose
    }
    else
    {
        LogMsg "$RGName does not exists."
        $retValue = $true
    }
    return $retValue
}

Function CreateResourceGroup([string]$RGName, $location)
{
    $FailCounter = 0
    $retValue = "False"
    $ResourceGroupDeploymentName = $RGName + "-deployment"

    While(($retValue -eq $false) -and ($FailCounter -lt 5))
    {
        try
        {
            $FailCounter++
            if($location)
            {
                LogMsg "Using location : $location"
                $createRG = New-AzureResourceGroup -Name $RGName -Location $location.Replace('"','') -Force -Verbose
            }
            $operationStatus = $createRG.ProvisioningState
            if ($operationStatus  -eq "Succeeded")
            {
                LogMsg "Resource Group $RGName Created."
                $retValue = $true
            }
            else 
            {
                LogErr "Failed to Resource Group $RGName."
                $retValue = $false
            }
        }
        catch
        {
            $retValue = $false
        }
    }
    return $retValue
}

Function CreateResourceGroupDeployment([string]$RGName, $location, $setupType, $TemplateFile)
{
    $FailCounter = 0
    $retValue = "False"
    $ResourceGroupDeploymentName = $RGName + "-deployment"
    While(($retValue -eq $false) -and ($FailCounter -lt 5))
    {
        try
        {
            $FailCounter++
            if($location)
            {
                LogMsg "Creating Deployment using $TemplateFile ..."
                $createRGDeployment = New-AzureResourceGroupDeployment -Name $ResourceGroupDeploymentName -ResourceGroupName $RGName -TemplateFile $TemplateFile -Verbose
            }
            $operationStatus = $createRGDeployment.ProvisioningState
            if ($operationStatus  -eq "Succeeded")
            {
                LogMsg "Resource Group Deployment Created."
                $retValue = $true
            }
            else 
            {
                LogErr "Failed to Resource Group."
                $retValue = $false
            }
        }
        catch
        {
            $retValue = $false
        }
    }
    return $retValue
}


Function GenerateAzureDeployJSONFile ($RGName, $osImage, $osVHD, $RGXMLData, $Location, $azuredeployJSONFilePath)
{
$jsonFile = $azuredeployJSONFilePath
$StorageAccountName = $xml.config.Azure.General.ARMStorageAccount
$HS = $RGXMLData
$setupType = $Setup
$totalVMs = 0
$totalHS = 0
$extensionCounter = 0
$vmCount = 0
$indents = @()
$indent = ""
$singleIndent = ""
$indents += $indent
$RGRandomNumber = $((Get-Random -Maximum 999999 -Minimum 100000))
$RGrandomWord = ([System.IO.Path]::GetRandomFileName() -replace '[^a-z]')
$dnsNameForPublicIP = $($RGName.ToLower() -replace '[^a-z0-9]') + "$RGrandomWord"
$virtualNetworkName = "ICAVNET"
$availibilitySetName = "ICAAvailibilitySet"
$LoadBalancerName =  "FrontEndIPAddress"
$apiVersion = "2015-05-01-preview"
$PublicIPName = $($RGName -replace '[^a-zA-Z]') + "PublicIP"
$sshPath = '/home/' + $user + '/.ssh/authorized_keys'
$sshKeyData = ""
LogMsg "ARM Storage Account : $StorageAccountName"
LogMsg "Using API VERSION : $apiVersion "

#Generate Single Indent
for($i =0; $i -lt 4; $i++)
{
    $singleIndent += " "
}

#Generate Indent Levels
for ($i =0; $i -lt 30; $i++)
{
    $indent += $singleIndent
    $indents += $indent
}


LogMsg "Generating Template : $azuredeployJSONFilePath"
#region Generate JSON file
Set-Content -Value "$($indents[0]){" -Path $jsonFile -Force
    Add-Content -Value "$($indents[1])^`$schema^: ^https://schema.management.azure.com/schemas/2015-01-01/deploymentTemplate.json#^," -Path $jsonFile
    Add-Content -Value "$($indents[1])^contentVersion^: ^1.0.0.0^," -Path $jsonFile
    Add-Content -Value "$($indents[1])^parameters^: {}," -Path $jsonFile
    Add-Content -Value "$($indents[1])^variables^:" -Path $jsonFile
    Add-Content -Value "$($indents[1]){" -Path $jsonFile
        Add-Content -Value "$($indents[2])^StorageAccountName^: ^$StorageAccountName^," -Path $jsonFile
        Add-Content -Value "$($indents[2])^dnsNameForPublicIP^: ^$dnsNameForPublicIP^," -Path $jsonFile
        Add-Content -Value "$($indents[2])^adminUserName^: ^$user^," -Path $jsonFile
        Add-Content -Value "$($indents[2])^adminPassword^: ^$($password.Replace('"',''))^," -Path $jsonFile
        Add-Content -Value "$($indents[2])^sshKeyPublicThumbPrint^: ^$sshPublicKeyThumbprint^," -Path $jsonFile
        Add-Content -Value "$($indents[2])^sshKeyPath^: ^$sshPath^," -Path $jsonFile
        Add-Content -Value "$($indents[2])^sshKeyData^: ^$sshKeyData^," -Path $jsonFile
        Add-Content -Value "$($indents[2])^location^: ^$($Location.Replace('"',''))^," -Path $jsonFile
        Add-Content -Value "$($indents[2])^publicIPAddressName^: ^$PublicIPName^," -Path $jsonFile
        Add-Content -Value "$($indents[2])^virtualNetworkName^: ^$virtualNetworkName^," -Path $jsonFile
        Add-Content -Value "$($indents[2])^nicName^: ^$nicName^," -Path $jsonFile
        Add-Content -Value "$($indents[2])^addressPrefix^: ^10.0.0.0/16^," -Path $jsonFile
        Add-Content -Value "$($indents[2])^vmSourceImageName^ : ^$osImage^," -Path $jsonFile
        Add-Content -Value "$($indents[2])^CompliedSourceImageName^ : ^[concat('/',subscription().subscriptionId,'/services/images/',variables('vmSourceImageName'))]^," -Path $jsonFile
        Add-Content -Value "$($indents[2])^subnet1Name^: ^Subnet-1^," -Path $jsonFile
        Add-Content -Value "$($indents[2])^subnet2Name^: ^Subnet-2^," -Path $jsonFile
        Add-Content -Value "$($indents[2])^subnet1Prefix^: ^10.0.0.0/24^," -Path $jsonFile
        Add-Content -Value "$($indents[2])^subnet2Prefix^: ^10.0.1.0/24^," -Path $jsonFile
        Add-Content -Value "$($indents[2])^vmStorageAccountContainerName^: ^vhds^," -Path $jsonFile
        Add-Content -Value "$($indents[2])^publicIPAddressType^: ^Dynamic^," -Path $jsonFile
        Add-Content -Value "$($indents[2])^storageAccountType^: ^Standard_LRS^," -Path $jsonFile
        Add-Content -Value "$($indents[2])^vnetID^: ^[resourceId('Microsoft.Network/virtualNetworks',variables('virtualNetworkName'))]^," -Path $jsonFile
        Add-Content -Value "$($indents[2])^subnet1Ref^: ^[concat(variables('vnetID'),'/subnets/',variables('subnet1Name'))]^," -Path $jsonFile
        Add-Content -Value "$($indents[2])^subnet2Ref^: ^[concat(variables('vnetID'),'/subnets/',variables('subnet2Name'))]^," -Path $jsonFile
        Add-Content -Value "$($indents[2])^availabilitySetName^: ^$availibilitySetName^," -Path $jsonFile
        Add-Content -Value "$($indents[2])^lbName^: ^$LoadBalancerName^," -Path $jsonFile
        Add-Content -Value "$($indents[2])^lbID^: ^[resourceId('Microsoft.Network/loadBalancers',variables('lbName'))]^," -Path $jsonFile
        Add-Content -Value "$($indents[2])^frontEndIPConfigID^: ^[concat(variables('lbID'),'/frontendIPConfigurations/LoadBalancerFrontEnd')]^," -Path $jsonFile
        Add-Content -Value "$($indents[2])^lbPoolID^: ^[concat(variables('lbID'),'/backendAddressPools/BackendPool1')]^," -Path $jsonFile
        Add-Content -Value "$($indents[2])^lbProbeID^: ^[concat(variables('lbID'),'/probes/tcpProbe')]^" -Path $jsonFile
        #Add more variables here, if required..
        #Add more variables here, if required..
        #Add more variables here, if required..
        #Add more variables here, if required..
    Add-Content -Value "$($indents[1])}," -Path $jsonFile
    LogMsg "Added Variables.."

    #region Define Resources
    Add-Content -Value "$($indents[1])^resources^:" -Path $jsonFile
    Add-Content -Value "$($indents[1])[" -Path $jsonFile

    #region Common Resources for all deployments..

        #region publicIPAddresses
        Add-Content -Value "$($indents[2]){" -Path $jsonFile
            Add-Content -Value "$($indents[3])^apiVersion^: ^$apiVersion^," -Path $jsonFile
            Add-Content -Value "$($indents[3])^type^: ^Microsoft.Network/publicIPAddresses^," -Path $jsonFile
            Add-Content -Value "$($indents[3])^name^: ^[variables('publicIPAddressName')]^," -Path $jsonFile
            Add-Content -Value "$($indents[3])^location^: ^[variables('location')]^," -Path $jsonFile
            Add-Content -Value "$($indents[3])^properties^:" -Path $jsonFile
            Add-Content -Value "$($indents[3]){" -Path $jsonFile
                Add-Content -Value "$($indents[4])^publicIPAllocationMethod^: ^[variables('publicIPAddressType')]^," -Path $jsonFile
                Add-Content -Value "$($indents[4])^dnsSettings^: " -Path $jsonFile
                Add-Content -Value "$($indents[4]){" -Path $jsonFile
                    Add-Content -Value "$($indents[5])^domainNameLabel^: ^[variables('dnsNameForPublicIP')]^" -Path $jsonFile
                Add-Content -Value "$($indents[4])}" -Path $jsonFile
            Add-Content -Value "$($indents[3])}" -Path $jsonFile
        Add-Content -Value "$($indents[2])}," -Path $jsonFile
        LogMsg "Added Public IP Address $PublicIPName.."
        #endregion

        #region availabilitySets
        Add-Content -Value "$($indents[2]){" -Path $jsonFile
            Add-Content -Value "$($indents[3])^apiVersion^: ^$apiVersion^," -Path $jsonFile
            Add-Content -Value "$($indents[3])^type^: ^Microsoft.Compute/availabilitySets^," -Path $jsonFile
            Add-Content -Value "$($indents[3])^name^: ^[variables('availabilitySetName')]^," -Path $jsonFile
            Add-Content -Value "$($indents[3])^location^: ^[variables('location')]^," -Path $jsonFile
            Add-Content -Value "$($indents[3])^properties^:" -Path $jsonFile
            Add-Content -Value "$($indents[3]){" -Path $jsonFile
            Add-Content -Value "$($indents[3])}" -Path $jsonFile
        Add-Content -Value "$($indents[2])}," -Path $jsonFile
        LogMsg "Added availabilitySet $availibilitySetName.."
        #endregion

        #region virtualNetworks
        Add-Content -Value "$($indents[2]){" -Path $jsonFile
            Add-Content -Value "$($indents[3])^apiVersion^: ^$apiVersion^," -Path $jsonFile
            Add-Content -Value "$($indents[3])^type^: ^Microsoft.Network/virtualNetworks^," -Path $jsonFile
            Add-Content -Value "$($indents[3])^name^: ^[variables('virtualNetworkName')]^," -Path $jsonFile
            Add-Content -Value "$($indents[3])^location^: ^[variables('location')]^," -Path $jsonFile
            Add-Content -Value "$($indents[3])^properties^:" -Path $jsonFile
            Add-Content -Value "$($indents[3]){" -Path $jsonFile
                #AddressSpace
                Add-Content -Value "$($indents[4])^addressSpace^: " -Path $jsonFile
                Add-Content -Value "$($indents[4]){" -Path $jsonFile
                    Add-Content -Value "$($indents[5])^addressPrefixes^: " -Path $jsonFile
                    Add-Content -Value "$($indents[5])[" -Path $jsonFile
                        Add-Content -Value "$($indents[6])^[variables('addressPrefix')]^" -Path $jsonFile
                    Add-Content -Value "$($indents[5])]" -Path $jsonFile
                Add-Content -Value "$($indents[4])}," -Path $jsonFile
                #Subnets
                Add-Content -Value "$($indents[4])^subnets^: " -Path $jsonFile
                Add-Content -Value "$($indents[4])[" -Path $jsonFile
                    Add-Content -Value "$($indents[5]){" -Path $jsonFile
                        Add-Content -Value "$($indents[6])^name^: ^[variables('subnet1Name')]^," -Path $jsonFile
                        Add-Content -Value "$($indents[6])^properties^: " -Path $jsonFile
                        Add-Content -Value "$($indents[6]){" -Path $jsonFile
                            Add-Content -Value "$($indents[7])^addressPrefix^: ^[variables('subnet1Prefix')]^" -Path $jsonFile
                        Add-Content -Value "$($indents[6])}" -Path $jsonFile
                    Add-Content -Value "$($indents[5])}," -Path $jsonFile
                    Add-Content -Value "$($indents[5]){" -Path $jsonFile
                        Add-Content -Value "$($indents[6])^name^: ^[variables('subnet2Name')]^," -Path $jsonFile
                        Add-Content -Value "$($indents[6])^properties^: " -Path $jsonFile
                        Add-Content -Value "$($indents[6]){" -Path $jsonFile
                            Add-Content -Value "$($indents[7])^addressPrefix^: ^[variables('subnet2Prefix')]^" -Path $jsonFile
                        Add-Content -Value "$($indents[6])}" -Path $jsonFile
                    Add-Content -Value "$($indents[5])}" -Path $jsonFile
                Add-Content -Value "$($indents[4])]" -Path $jsonFile
            Add-Content -Value "$($indents[3])}" -Path $jsonFile
        Add-Content -Value "$($indents[2])}," -Path $jsonFile
        LogMsg "Added Virtual Network $virtualNetworkName.."
        #endregion
        
        #region LoadBalancer
        Add-Content -Value "$($indents[2]){" -Path $jsonFile
            Add-Content -Value "$($indents[3])^apiVersion^: ^$apiVersion^," -Path $jsonFile
            Add-Content -Value "$($indents[3])^type^: ^Microsoft.Network/loadBalancers^," -Path $jsonFile
            Add-Content -Value "$($indents[3])^name^: ^[variables('lbName')]^," -Path $jsonFile
            Add-Content -Value "$($indents[3])^location^: ^[variables('location')]^," -Path $jsonFile
            Add-Content -Value "$($indents[3])^dependsOn^: " -Path $jsonFile
            Add-Content -Value "$($indents[3])[" -Path $jsonFile
                Add-Content -Value "$($indents[4])^[concat('Microsoft.Network/publicIPAddresses/', variables('publicIPAddressName'))]^" -Path $jsonFile
            Add-Content -Value "$($indents[3])]," -Path $jsonFile
            Add-Content -Value "$($indents[3])^properties^:" -Path $jsonFile
            Add-Content -Value "$($indents[3]){" -Path $jsonFile
                Add-Content -Value "$($indents[4])^frontendIPConfigurations^: " -Path $jsonFile
                Add-Content -Value "$($indents[4])[" -Path $jsonFile
                    Add-Content -Value "$($indents[5]){" -Path $jsonFile
                        Add-Content -Value "$($indents[6])^name^: ^LoadBalancerFrontEnd^," -Path $jsonFile
                        Add-Content -Value "$($indents[6])^properties^:" -Path $jsonFile
                        Add-Content -Value "$($indents[6]){" -Path $jsonFile
                            Add-Content -Value "$($indents[7])^publicIPAddress^:" -Path $jsonFile
                            Add-Content -Value "$($indents[7]){" -Path $jsonFile
                                Add-Content -Value "$($indents[8])^id^: ^[resourceId('Microsoft.Network/publicIPAddresses',variables('publicIPAddressName'))]^" -Path $jsonFile
                            Add-Content -Value "$($indents[7])}" -Path $jsonFile
                        Add-Content -Value "$($indents[6])}" -Path $jsonFile
                    Add-Content -Value "$($indents[5])}" -Path $jsonFile
                Add-Content -Value "$($indents[4])]," -Path $jsonFile
                Add-Content -Value "$($indents[4])^backendAddressPools^:" -Path $jsonFile
                Add-Content -Value "$($indents[4])[" -Path $jsonFile
                    Add-Content -Value "$($indents[5]){" -Path $jsonFile
                        Add-Content -Value "$($indents[6])^name^:^BackendPool1^" -Path $jsonFile
                    Add-Content -Value "$($indents[5])}" -Path $jsonFile
                Add-Content -Value "$($indents[4])]," -Path $jsonFile
                #region Normal Endpoints

                Add-Content -Value "$($indents[4])^inboundNatRules^:" -Path $jsonFile
                Add-Content -Value "$($indents[4])[" -Path $jsonFile
$LBPorts = 0
$EndPointAdded = $false
$role = 0
foreach ( $newVM in $RGXMLData.VirtualMachine)
{
    if($newVM.RoleName)
    {
        $vmName = $newVM.RoleName
    }
    else
    {
        $vmName = $RGName+"-role-"+$role
    }
    foreach ( $endpoint in $newVM.EndPoints)
    {
        if ( !($endpoint.LoadBalanced) -or ($endpoint.LoadBalanced -eq "False") )
        { 
            if ( $EndPointAdded )
            {
                    Add-Content -Value "$($indents[5])," -Path $jsonFile            
            }
                    Add-Content -Value "$($indents[5]){" -Path $jsonFile
                        Add-Content -Value "$($indents[6])^name^: ^$vmName-$($endpoint.Name)^," -Path $jsonFile
                        Add-Content -Value "$($indents[6])^properties^:" -Path $jsonFile
                        Add-Content -Value "$($indents[6]){" -Path $jsonFile
                            Add-Content -Value "$($indents[7])^frontendIPConfiguration^:" -Path $jsonFile
                            Add-Content -Value "$($indents[7]){" -Path $jsonFile
                                Add-Content -Value "$($indents[8])^id^: ^[variables('frontEndIPConfigID')]^" -Path $jsonFile
                            Add-Content -Value "$($indents[7])}," -Path $jsonFile
                            Add-Content -Value "$($indents[7])^protocol^: ^$($endpoint.Protocol)^," -Path $jsonFile
                            Add-Content -Value "$($indents[7])^frontendPort^: ^$($endpoint.PublicPort)^," -Path $jsonFile
                            Add-Content -Value "$($indents[7])^backendPort^: ^$($endpoint.LocalPort)^," -Path $jsonFile
                            Add-Content -Value "$($indents[7])^enableFloatingIP^: false" -Path $jsonFile
                        Add-Content -Value "$($indents[6])}" -Path $jsonFile
                    Add-Content -Value "$($indents[5])}" -Path $jsonFile
                    LogMsg "Added inboundNatRule Name:$vmName-$($endpoint.Name) frontendPort:$($endpoint.PublicPort) backendPort:$($endpoint.LocalPort) Protocol:$($endpoint.Protocol)."
                    $EndPointAdded = $true
        }
        else
        {
                $LBPorts += 1
        }
    }
                $role += 1
}
                Add-Content -Value "$($indents[4])]" -Path $jsonFile
                #endregion
                
                #region LoadBalanced Endpoints
if ( $LBPorts -gt 0 )
{
                Add-Content -Value "$($indents[4])," -Path $jsonFile
                Add-Content -Value "$($indents[4])^loadBalancingRules^:" -Path $jsonFile
                Add-Content -Value "$($indents[4])[" -Path $jsonFile
$probePorts = 0
$EndPointAdded = $false
$addedLBPort = $null
$role = 0
foreach ( $newVM in $RGXMLData.VirtualMachine)
{
    if($newVM.RoleName)
    {
        $vmName = $newVM.RoleName
    }
    else
    {
        $vmName = $RGName+"-role-"+$role
    }
    
    foreach ( $endpoint in $newVM.EndPoints)
    {
        if ( ($endpoint.LoadBalanced -eq "True") -and !($addedLBPort -imatch "$($endpoint.Name)-$($endpoint.PublicPort)" ) )
        { 
            if ( $EndPointAdded )
            {
                    Add-Content -Value "$($indents[5])," -Path $jsonFile            
            }
                    Add-Content -Value "$($indents[5]){" -Path $jsonFile
                        Add-Content -Value "$($indents[6])^name^: ^$RGName-LB-$($endpoint.Name)^," -Path $jsonFile
                        Add-Content -Value "$($indents[6])^properties^:" -Path $jsonFile
                        Add-Content -Value "$($indents[6]){" -Path $jsonFile
                       
                            Add-Content -Value "$($indents[7])^frontendIPConfiguration^:" -Path $jsonFile
                            Add-Content -Value "$($indents[7]){" -Path $jsonFile
                                Add-Content -Value "$($indents[8])^id^: ^[variables('frontEndIPConfigID')]^" -Path $jsonFile
                            Add-Content -Value "$($indents[7])}," -Path $jsonFile
                            Add-Content -Value "$($indents[7])^backendAddressPool^:" -Path $jsonFile
                            Add-Content -Value "$($indents[7]){" -Path $jsonFile
                                Add-Content -Value "$($indents[8])^id^: ^[variables('lbPoolID')]^" -Path $jsonFile
                            Add-Content -Value "$($indents[7])}," -Path $jsonFile
                            Add-Content -Value "$($indents[7])^protocol^: ^$($endpoint.Protocol)^," -Path $jsonFile
                            Add-Content -Value "$($indents[7])^frontendPort^: ^$($endpoint.PublicPort)^," -Path $jsonFile
                            Add-Content -Value "$($indents[7])^backendPort^: ^$($endpoint.LocalPort)^," -Path $jsonFile
                            Add-Content -Value "$($indents[7])^enableFloatingIP^: false," -Path $jsonFile

            if ( $endpoint.ProbePort )
            {
                            $probePorts += 1
                            Add-Content -Value "$($indents[7])^probe^:" -Path $jsonFile
                            Add-Content -Value "$($indents[7]){" -Path $jsonFile
                                Add-Content -Value "$($indents[8])^id^: ^[concat(variables('lbID'),'/probes/$RGName-LB-$($endpoint.Name)-probe')]^" -Path $jsonFile
                            Add-Content -Value "$($indents[7])}," -Path $jsonFile
                            LogMsg "Enabled Probe for loadBalancingRule Name:$RGName-LB-$($endpoint.Name) : $RGName-LB-$($endpoint.Name)-probe."
            }
            else
            {
                            Add-Content -Value "$($indents[7])^idleTimeoutInMinutes^: 5" -Path $jsonFile
            }
                        Add-Content -Value "$($indents[6])}" -Path $jsonFile
                    Add-Content -Value "$($indents[5])}" -Path $jsonFile
                    LogMsg "Added loadBalancingRule Name:$RGName-LB-$($endpoint.Name) frontendPort:$($endpoint.PublicPort) backendPort:$($endpoint.LocalPort) Protocol:$($endpoint.Protocol)."
                    if ( $addedLBPort )
                    {
                        $addedLBPort += "-$($endpoint.Name)-$($endpoint.PublicPort)"
                    }
                    else
                    {
                        $addedLBPort = "$($endpoint.Name)-$($endpoint.PublicPort)"
                    }
                    $EndPointAdded = $true
        }
    }
                $role += 1            
}
                Add-Content -Value "$($indents[4])]" -Path $jsonFile
}
                #endregion

                #region Probe Ports
if ( $probePorts -gt 0 )
{
                Add-Content -Value "$($indents[4])," -Path $jsonFile
                Add-Content -Value "$($indents[4])^probes^:" -Path $jsonFile
                Add-Content -Value "$($indents[4])[" -Path $jsonFile

$EndPointAdded = $false
$addedProbes = $null
$role = 0
foreach ( $newVM in $RGXMLData.VirtualMachine)
{
    if($newVM.RoleName)
    {
        $vmName = $newVM.RoleName
    }
    else
    {
        $vmName = $RGName+"-role-"+$role
    }
    foreach ( $endpoint in $newVM.EndPoints)
    {
        if ( ($endpoint.LoadBalanced -eq "True") )
        { 
            if ( $endpoint.ProbePort -and !($addedProbes -imatch "$($endpoint.Name)-probe-$($endpoint.ProbePort)"))
            {
                if ( $EndPointAdded )
                {
                    Add-Content -Value "$($indents[5])," -Path $jsonFile            
                }
                    Add-Content -Value "$($indents[5]){" -Path $jsonFile
                        Add-Content -Value "$($indents[6])^name^: ^$RGName-LB-$($endpoint.Name)-probe^," -Path $jsonFile
                        Add-Content -Value "$($indents[6])^properties^:" -Path $jsonFile
                        Add-Content -Value "$($indents[6]){" -Path $jsonFile
                            Add-Content -Value "$($indents[7])^protocol^ : ^$($endpoint.Protocol)^," -Path $jsonFile
                            Add-Content -Value "$($indents[7])^port^ : ^$($endpoint.ProbePort)^," -Path $jsonFile
                            Add-Content -Value "$($indents[7])^intervalInSeconds^ : ^15^," -Path $jsonFile
                            Add-Content -Value "$($indents[7])^numberOfProbes^ : ^$probePorts^" -Path $jsonFile
                        Add-Content -Value "$($indents[6])}" -Path $jsonFile
                    Add-Content -Value "$($indents[5])}" -Path $jsonFile
                    LogMsg "Added probe :$RGName-LB-$($endpoint.Name)-probe Probe Port:$($endpoint.ProbePort) Protocol:$($endpoint.Protocol)."
                    if ( $addedProbes )
                    {
                        $addedProbes += "-$($endpoint.Name)-probe-$($endpoint.ProbePort)"
                    }
                    else
                    {
                        $addedProbes = "$($endpoint.Name)-probe-$($endpoint.ProbePort)"
                    }
                    $EndPointAdded = $true
            }
        }
    }

            $role += 1
}
                Add-Content -Value "$($indents[4])]" -Path $jsonFile
}
                 #endregion
            Add-Content -Value "$($indents[3])}" -Path $jsonFile
        Add-Content -Value "$($indents[2])}," -Path $jsonFile
    #endregion
    
    #endregion

    $vmAdded = $false
    $role = 0
foreach ( $newVM in $RGXMLData.VirtualMachine)
{
    $VnetName = $RGXMLData.VnetName
    $instanceSize = $newVM.ARMInstanceSize
    $SubnetName = $newVM.SubnetName
    $DnsServerIP = $RGXMLData.DnsServerIP
    if($newVM.RoleName)
    {
        $vmName = $newVM.RoleName
    }
    else
    {
        $vmName = $RGName+"-role-"+$role
    }
    $NIC = "NIC" + "-$vmName"

        if ( $vmAdded )
        {
            Add-Content -Value "$($indents[2])," -Path $jsonFile
        }

        #region networkInterfaces
        Add-Content -Value "$($indents[2]){" -Path $jsonFile
            Add-Content -Value "$($indents[3])^apiVersion^: ^$apiVersion^," -Path $jsonFile
            Add-Content -Value "$($indents[3])^type^: ^Microsoft.Network/networkInterfaces^," -Path $jsonFile
            Add-Content -Value "$($indents[3])^name^: ^$NIC^," -Path $jsonFile
            Add-Content -Value "$($indents[3])^location^: ^[variables('location')]^," -Path $jsonFile
            Add-Content -Value "$($indents[3])^dependsOn^: " -Path $jsonFile
            Add-Content -Value "$($indents[3])[" -Path $jsonFile
                Add-Content -Value "$($indents[4])^[concat('Microsoft.Network/publicIPAddresses/', variables('publicIPAddressName'))]^," -Path $jsonFile
                Add-Content -Value "$($indents[4])^[variables('lbID')]^," -Path $jsonFile
                Add-Content -Value "$($indents[4])^[concat('Microsoft.Network/virtualNetworks/', variables('virtualNetworkName'))]^" -Path $jsonFile
            Add-Content -Value "$($indents[3])]," -Path $jsonFile

            Add-Content -Value "$($indents[3])^properties^:" -Path $jsonFile
            Add-Content -Value "$($indents[3]){" -Path $jsonFile
                Add-Content -Value "$($indents[4])^ipConfigurations^: " -Path $jsonFile
                Add-Content -Value "$($indents[4])[" -Path $jsonFile
                    Add-Content -Value "$($indents[5]){" -Path $jsonFile
                        Add-Content -Value "$($indents[6])^name^: ^ipconfig1^," -Path $jsonFile
                        Add-Content -Value "$($indents[6])^properties^: " -Path $jsonFile
                        Add-Content -Value "$($indents[6]){" -Path $jsonFile
                            
                            Add-Content -Value "$($indents[7])^loadBalancerBackendAddressPools^:" -Path $jsonFile
                            Add-Content -Value "$($indents[7])[" -Path $jsonFile
                                Add-Content -Value "$($indents[8]){" -Path $jsonFile
                                    Add-Content -Value "$($indents[9])^id^: ^[concat(variables('lbID'), '/backendAddressPools/BackendPool1')]^" -Path $jsonFile
                                Add-Content -Value "$($indents[8])}" -Path $jsonFile
                            Add-Content -Value "$($indents[7])]," -Path $jsonFile

                                #region Enable InboundRules in NIC
                            Add-Content -Value "$($indents[7])^loadBalancerInboundNatRules^:" -Path $jsonFile
                            Add-Content -Value "$($indents[7])[" -Path $jsonFile
    $EndPointAdded = $false
    foreach ( $endpoint in $newVM.EndPoints)
    {
        if ( !($endpoint.LoadBalanced) -or ($endpoint.LoadBalanced -eq "False") )
        {
            if ( $EndPointAdded )
            {
                                Add-Content -Value "$($indents[8])," -Path $jsonFile            
            }
                                Add-Content -Value "$($indents[8]){" -Path $jsonFile
                                    Add-Content -Value "$($indents[9])^id^:^[concat(variables('lbID'),'/inboundNatRules/$vmName-$($endpoint.Name)')]^" -Path $jsonFile
                                Add-Content -Value "$($indents[8])}" -Path $jsonFile
                                LogMsg "Enabled inboundNatRule Name:$vmName-$($endpoint.Name) frontendPort:$($endpoint.PublicPort) backendPort:$($endpoint.LocalPort) Protocol:$($endpoint.Protocol) to $NIC."
                                $EndPointAdded = $true
        }
    }

                            Add-Content -Value "$($indents[7])]," -Path $jsonFile
                                #endregion
                            
                            Add-Content -Value "$($indents[7])^subnet^:" -Path $jsonFile
                            Add-Content -Value "$($indents[7]){" -Path $jsonFile
                                Add-Content -Value "$($indents[8])^id^: ^[variables('subnet1Ref')]^" -Path $jsonFile
                            Add-Content -Value "$($indents[7])}," -Path $jsonFile
                            Add-Content -Value "$($indents[7])^privateIPAllocationMethod^: ^Dynamic^" -Path $jsonFile
                        Add-Content -Value "$($indents[6])}" -Path $jsonFile
                    Add-Content -Value "$($indents[5])}" -Path $jsonFile
                Add-Content -Value "$($indents[4])]" -Path $jsonFile
            Add-Content -Value "$($indents[3])}" -Path $jsonFile
        Add-Content -Value "$($indents[2])}," -Path $jsonFile
        LogMsg "Added NIC $NIC.."
        #endregion

        #region virtualMachines
        Add-Content -Value "$($indents[2]){" -Path $jsonFile
            Add-Content -Value "$($indents[3])^apiVersion^: ^$apiVersion^," -Path $jsonFile
            Add-Content -Value "$($indents[3])^type^: ^Microsoft.Compute/virtualMachines^," -Path $jsonFile
            Add-Content -Value "$($indents[3])^name^: ^$vmName^," -Path $jsonFile
            Add-Content -Value "$($indents[3])^location^: ^[variables('location')]^," -Path $jsonFile
            Add-Content -Value "$($indents[3])^dependsOn^: " -Path $jsonFile
            Add-Content -Value "$($indents[3])[" -Path $jsonFile
                Add-Content -Value "$($indents[4])^[concat('Microsoft.Compute/availabilitySets/', variables('availabilitySetName'))]^," -Path $jsonFile
                Add-Content -Value "$($indents[4])^[concat('Microsoft.Network/networkInterfaces/', '$NIC')]^" -Path $jsonFile
            Add-Content -Value "$($indents[3])]," -Path $jsonFile

            #region VM Properties
            Add-Content -Value "$($indents[3])^properties^:" -Path $jsonFile
            Add-Content -Value "$($indents[3]){" -Path $jsonFile
                #region availabilitySet
                Add-Content -Value "$($indents[4])^availabilitySet^: " -Path $jsonFile
                Add-Content -Value "$($indents[4]){" -Path $jsonFile
                    Add-Content -Value "$($indents[5])^id^: ^[resourceId('Microsoft.Compute/availabilitySets',variables('availabilitySetName'))]^" -Path $jsonFile
                Add-Content -Value "$($indents[4])}," -Path $jsonFile
                #endregion

                #region Hardware Profile
                Add-Content -Value "$($indents[4])^hardwareProfile^: " -Path $jsonFile
                Add-Content -Value "$($indents[4]){" -Path $jsonFile
                    Add-Content -Value "$($indents[5])^vmSize^: ^$instanceSize^" -Path $jsonFile
                Add-Content -Value "$($indents[4])}," -Path $jsonFile
                #endregion

                #region OSProfie
                Add-Content -Value "$($indents[4])^osProfile^: " -Path $jsonFile
                Add-Content -Value "$($indents[4]){" -Path $jsonFile
                    Add-Content -Value "$($indents[5])^computername^: ^$vmName^," -Path $jsonFile
                    Add-Content -Value "$($indents[5])^adminUsername^: ^[variables('adminUserName')]^," -Path $jsonFile
                    Add-Content -Value "$($indents[5])^adminPassword^: ^[variables('adminPassword')]^" -Path $jsonFile
                    #Add-Content -Value "$($indents[5])^linuxConfiguration^:" -Path $jsonFile
                    #Add-Content -Value "$($indents[5]){" -Path $jsonFile
                    #    Add-Content -Value "$($indents[6])^ssh^:" -Path $jsonFile
                    #    Add-Content -Value "$($indents[6]){" -Path $jsonFile
                    #        Add-Content -Value "$($indents[7])^publicKeys^:" -Path $jsonFile
                    #        Add-Content -Value "$($indents[7])[" -Path $jsonFile
                    #            Add-Content -Value "$($indents[8])[" -Path $jsonFile
                    #                Add-Content -Value "$($indents[9]){" -Path $jsonFile
                    #                    Add-Content -Value "$($indents[10])^path^:^$sshPath^," -Path $jsonFile
                    #                    Add-Content -Value "$($indents[10])^keyData^:^$sshKeyData^" -Path $jsonFile
                    #                Add-Content -Value "$($indents[9])}" -Path $jsonFile
                    #            Add-Content -Value "$($indents[8])]" -Path $jsonFile
                    #        Add-Content -Value "$($indents[7])]" -Path $jsonFile
                    #    Add-Content -Value "$($indents[6])}" -Path $jsonFile
                    #Add-Content -Value "$($indents[5])}" -Path $jsonFile
                Add-Content -Value "$($indents[4])}," -Path $jsonFile
                #endregion

                #region Storage Profile
                Add-Content -Value "$($indents[4])^storageProfile^: " -Path $jsonFile
                Add-Content -Value "$($indents[4]){" -Path $jsonFile
                    Add-Content -Value "$($indents[5])^osDisk^ : " -Path $jsonFile
                    Add-Content -Value "$($indents[5]){" -Path $jsonFile
                        if ( $osVHD )
                        {
                            if ( $osImage)
                            {
                                LogMsg "Overriding ImageName with user provided VHD."
                            }
                            LogMsg "Using VHD : $osVHD"
                            Add-Content -Value "$($indents[6])^image^: " -Path $jsonFile
                            Add-Content -Value "$($indents[6]){" -Path $jsonFile
                                Add-Content -Value "$($indents[7])^uri^: ^[concat('http://',variables('StorageAccountName'),'.blob.core.windows.net/vhds/','$osVHD')]^" -Path $jsonFile
                            Add-Content -Value "$($indents[6])}," -Path $jsonFile
                            Add-Content -Value "$($indents[6])^osType^: ^Linux^," -Path $jsonFile
                        }
                        else
                        {
                            LogMsg "Using ImageName : $osImage"
                            Add-Content -Value "$($indents[6])^sourceImage^: " -Path $jsonFile
                            Add-Content -Value "$($indents[6]){" -Path $jsonFile
                                Add-Content -Value "$($indents[7])^id^: ^[variables('CompliedSourceImageName')]^" -Path $jsonFile
                            Add-Content -Value "$($indents[6])}," -Path $jsonFile
                        }
                        Add-Content -Value "$($indents[6])^name^: ^$vmName-OSDisk^," -Path $jsonFile
                        #Add-Content -Value "$($indents[6])^osType^: ^Linux^," -Path $jsonFile
                        Add-Content -Value "$($indents[6])^vhd^: " -Path $jsonFile
                        Add-Content -Value "$($indents[6]){" -Path $jsonFile
                            Add-Content -Value "$($indents[7])^uri^: ^[concat('http://',variables('StorageAccountName'),'.blob.core.windows.net/vhds/','$vmName-$RGrandomWord-osdisk.vhd')]^" -Path $jsonFile
                        Add-Content -Value "$($indents[6])}," -Path $jsonFile
                        Add-Content -Value "$($indents[6])^caching^: ^ReadWrite^," -Path $jsonFile
                        Add-Content -Value "$($indents[6])^createOption^: ^FromImage^" -Path $jsonFile
                    Add-Content -Value "$($indents[5])}" -Path $jsonFile
                Add-Content -Value "$($indents[4])}," -Path $jsonFile
                LogMsg "Added Virtual Machine $vmName"
                #endregion

                #region Network Profile
                Add-Content -Value "$($indents[4])^networkProfile^: " -Path $jsonFile
                Add-Content -Value "$($indents[4]){" -Path $jsonFile
                    Add-Content -Value "$($indents[5])^networkInterfaces^: " -Path $jsonFile
                    Add-Content -Value "$($indents[5])[" -Path $jsonFile
                        Add-Content -Value "$($indents[6]){" -Path $jsonFile
                            Add-Content -Value "$($indents[7])^id^: ^[resourceId('Microsoft.Network/networkInterfaces','$NIC')]^" -Path $jsonFile
                        Add-Content -Value "$($indents[6])}" -Path $jsonFile
                    Add-Content -Value "$($indents[5])]" -Path $jsonFile
                Add-Content -Value "$($indents[4])}" -Path $jsonFile
                #endregion

            Add-Content -Value "$($indents[3])}" -Path $jsonFile
            LogMsg "Attached Network Interface Card `"$NIC`" to Virtual Machine `"$vmName`"."
            #endregion

        Add-Content -Value "$($indents[2])}" -Path $jsonFile
        #endregion
        
        $vmAdded = $true
        $role  = $role + 1
        $vmCount = $role
}
    Add-Content -Value "$($indents[1])]" -Path $jsonFile
Add-Content -Value "$($indents[0])}" -Path $jsonFile
Set-Content -Path $jsonFile -Value (Get-Content $jsonFile).Replace("^",'"') -Force
#endregion

    LogMsg "Template generated successfully."
    return $createSetupCommand,  $RGName, $vmCount
} 

Function DeployResourceGroups ($xmlConfig, $setupType, $Distro, $getLogsIfFailed = $false, $GetDeploymentStatistics = $false)
{
    if( (!$EconomyMode) -or ( $EconomyMode -and ($xmlConfig.config.Azure.Deployment.$setupType.isDeployed -eq "NO")))
    {
        try
        {
            $VerifiedGroups =  $NULL
            $retValue = $NULL
            #$ExistingGroups = RetryOperation -operation { Get-AzureResourceGroup } -description "Getting information of existing resource groups.." -retryInterval 5 -maxRetryCount 5
            $i = 0
            $role = 1
            $setupTypeData = $xmlConfig.config.Azure.Deployment.$setupType
            $isAllDeployed = CreateAllResourceGroupDeployments -setupType $setupType -xmlConfig $xmlConfig -Distro $Distro
            $isAllVerified = "False"
            $isAllConnected = "False"
            #$isAllDeployed = @("True","ICA-RG-IEndpointSingleHS-U1510-8-10-12-34-9","30")
            if($isAllDeployed[0] -eq "True")
            {
                $deployedGroups = $isAllDeployed[1]
                $resourceGroupCount = $isAllDeployed[2]
                $DeploymentElapsedTime = $isAllDeployed[3]
                $GroupsToVerify = $deployedGroups.Split('^')
                #if ( $GetDeploymentStatistics )
                #{
                #    $VMBooTime = GetVMBootTime -DeployedGroups $deployedGroups -TimeoutInSeconds 1800
                #    $verifyAll = VerifyAllDeployments -GroupsToVerify $GroupsToVerify -GetVMProvisionTime $GetDeploymentStatistics
                #    $isAllVerified = $verifyAll[0]
                #    $VMProvisionTime = $verifyAll[1]
                #}
                #else
                #{
                #    $isAllVerified = VerifyAllDeployments -GroupsToVerify $GroupsToVerify
                #}
                #if ($isAllVerified -eq "True")
                #{
                    $allVMData = GetAllDeployementData -ResourceGroups $deployedGroups
                    Set-Variable -Name allVMData -Value $allVMData -Force -Scope Global
                    $isAllConnected = isAllSSHPortsEnabledRG -AllVMDataObject $allVMData
                    if ($isAllConnected -eq "True")
                    {
                        $VerifiedGroups = $deployedGroups
                        $retValue = $VerifiedGroups
                        #$vnetIsAllConfigured = $false
                        $xmlConfig.config.Azure.Deployment.$setupType.isDeployed = $retValue
                        #Collecting Initial Kernel
                        $KernelLogOutput= GetAndCheckKernelLogs -allDeployedVMs $allVMData -status "Initial"
                    }
                    else
                    {
                        LogErr "Unable to connect Some/All SSH ports.."
                        $retValue = $NULL  
                    }
                #}
                #else
                #{
                #    Write-Host "Provision Failed for one or more VMs"
                #    $retValue = $NULL
                #}
                
            }
            else
            {
                LogErr "One or More Deployments are Failed..!"
                $retValue = $NULL
            }
            # get the logs of the first provision-failed VM
            #if ($retValue -eq $NULL -and $getLogsIfFailed -and $DebugOsImage)
            #{
            #    foreach ($service in $GroupsToVerify)
            #    {
            #        $VMs = Get-AzureVM -ServiceName $service
            #        foreach ($vm in $VMs)
            #        {
            #            if ($vm.InstanceStatus -ne "ReadyRole" )
            #            {
            #                $out = GetLogsFromProvisionFailedVM -vmName $vm.Name -serviceName $service -xmlConfig $xmlConfig
            #                return $NULL
            #            }
            #        }
            #    }
            #}
        }
        catch
        {
            LogMsg "Exception detected. Source : DeployVMs()"
            $retValue = $NULL
        }
    }
    else
    {
        $retValue = $xmlConfig.config.Azure.Deployment.$setupType.isDeployed
        $KernelLogOutput= GetAndCheckKernelLogs -allDeployedVMs $allVMData -status "Initial"
    }
    if ( $GetDeploymentStatistics )
    {
        return $retValue, $DeploymentElapsedTime, $VMBooTime, $VMProvisionTime
    }
    else
    {
        return $retValue
    }
}

Function isAllSSHPortsEnabledRG($AllVMDataObject)
{
    LogMsg "Trying to Connect to deployed VM(s)"
    $timeout = 0
    do
    {
        $WaitingForConnect = 0
        foreach ( $vm in $AllVMDataObject)
        {
            Write-Host "Connecting to  $($vm.PublicIP) : $($vm.SSHPort)" -NoNewline
            $out = Test-TCP  -testIP $($vm.PublicIP) -testport $($vm.SSHPort)
            if ($out -ne "True")
            { 
                Write-Host " : Failed"
                $WaitingForConnect = $WaitingForConnect + 1
            }
            else
            {
                Write-Host " : Connected"
            }
        }
        if($WaitingForConnect -gt 0)
        {
            $timeout = $timeout + 1
            Write-Host "$WaitingForConnect VM(s) still awaiting to open SSH port.." -NoNewline
            Write-Host "Retry $timeout/100"
            sleep 3
            $retValue = "False"
        }
        else
        {
            LogMsg "ALL VM's SSH port is/are open now.."
            $retValue = "True"
        }

    }
    While (($timeout -lt 100) -and ($WaitingForConnect -gt 0))

    return $retValue
}