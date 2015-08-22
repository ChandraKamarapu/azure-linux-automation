﻿<#-------------Create Deployment Start------------------#>
Import-Module .\TestLibs\RDFELibs.psm1 -Force
$result = ""
$testResult = ""
$resultArr = @()
$NumberOfSizes = $VMSizes.Count
$DeploymentCount = $currentTestData.DeploymentCount
#Test Starts Here..
	try
	{
        $count = 0
        $allowedFails = 5
        $successCount = 0
        $failCount = 0
        $VMSizeNumber = 0
        $allDeploymentStatistics = @()

        function CreateDeploymentResultObject()
        {
	        $DeploymentStatistics = New-Object -TypeName PSObject
	        Add-Member -InputObject $DeploymentStatistics -MemberType NoteProperty -Name attempt -Value $attempt -Force
            Add-Member -InputObject $DeploymentStatistics -MemberType NoteProperty -Name VMSize -Value $VMSize -Force
	        Add-Member -InputObject $DeploymentStatistics -MemberType NoteProperty -Name result -Value $result -Force
            Add-Member -InputObject $DeploymentStatistics -MemberType NoteProperty -Name DeploymentTime -Value $DeploymentTime -Force 
	        Add-Member -InputObject $DeploymentStatistics -MemberType NoteProperty -Name BootTime -Value $BootTime -Force
	        Add-Member -InputObject $DeploymentStatistics -MemberType NoteProperty -Name ProvisionTime -Value $ProvisionTime -Force
            return $DeploymentStatistics
        }
		While ($count -lt $DeploymentCount)
        {
            $count += 1
            $DeploymentStatistics = CreateDeploymentResultObject
            #Create A VM here and Wait for the VM to come up.
            if(!$UseAzureResourceManager)
            {
                $VMSizes = ($currentTestData.SubtestValues).Split(",")
                LogMsg "ATTEMPT : $count/$DeploymentCount : Deploying $($VMSizes[$VMSizeNumber]) VM.."
                $isDeployed = DeployVMS -setupType $($VMSizes[$VMSizeNumber]) -Distro $Distro -xmlConfig $xmlConfig -GetDeploymentStatistics $true
                $DeploymentStatistics.VMSize = $($VMSizes[$VMSizeNumber])
                $DeploymentStatistics.attempt = $count
                $DeploymentStatistics.DeploymentTime = $isDeployed[1].TotalSeconds
                $DeploymentStatistics.BootTime = $isDeployed[2].TotalSeconds
                $DeploymentStatistics.ProvisionTime = $isDeployed[3].TotalSeconds
                if ($isDeployed[0])
                {
                    if ( $DeploymentStatistics.BootTime -lt 300 )
                    {
                        $successCount += 1
                        LogMsg "ATTEMPT : $count/$DeploymentCount : Deploying $($VMSizes[$VMSizeNumber]) VM.. SUCCESS"
                        LogMsg "Deplyment Time = $($DeploymentStatistics.DeploymentTime)"
                        LogMsg "Boot Time = $($DeploymentStatistics.BootTime)"
                        LogMsg "Provision Time = $($DeploymentStatistics.ProvisionTime)"
                        $deployResult = "PASS"
                    }
                    else
                    {
                        $failCount += 1
                        LogErr "ATTEMPT : $count/$DeploymentCount : Deploying $($VMSizes[$VMSizeNumber]) VM.. FAIL due to exceeding boot time."
                        LogMsg "Deplyment Time/Timeout  = $($DeploymentStatistics.DeploymentTime)"
                        LogMsg "Boot Time/Timeout = $($DeploymentStatistics.BootTime)"
                        LogMsg "Provision Time/Timeout= $($DeploymentStatistics.ProvisionTime)"
                        $deployResult = "FAIL"
                        if ( $failCount -lt $allowedFails )
                        {
                            $VMSizeNumber += 1
                        }
                        else
                        {
                            break;
                        }
                    }
                    #VM is Deployed. Delete the service.. 
                }
                else
                {
                    $failCount += 1
                    LogErr "ATTEMPT : $count/$DeploymentCount : Deploying $($VMSizes[$VMSizeNumber]) VM.. FAIL"
                    LogMsg "Deplyment Time/Timeout  = $($DeploymentStatistics.DeploymentTime)"
                    LogMsg "Boot Time/Timeout = $($DeploymentStatistics.BootTime)"
                    LogMsg "Provision Time/Timeout= $($DeploymentStatistics.ProvisionTime)"

                    $deployResult = "FAIL"
                    if ( $failCount -lt $allowedFails )
                    {
                        $VMSizeNumber += 1
                    }
                    else
                    {
                        break;
                    }
                }
                $DeploymentStatistics.result = $deployResult
                if($VMSizeNumber -gt ($NumberOfSizes-2))
                {
                    $VMSizeNumber = 0
                }
                else
                {
                    $VMSizeNumber += 1
                }
                LogMsg "[PASS/FAIL/REMAINING] : $successCount/$failCount/$($DeploymentCount-$count)"
                DoTestCleanUp -result $deployResult -testName $currentTestData.testName -deployedServices $isDeployed[0]
                $allDeploymentStatistics += $DeploymentStatistics
            }
            else
            {
                $VMSizes = ($currentTestData.ARMSubtestValues).Split(",")
                LogMsg "ATTEMPT : $count/$DeploymentCount : Deploying $($VMSizes[$VMSizeNumber]) VM.."
                $isDeployed = DeployVMS -setupType $($VMSizes[$VMSizeNumber]) -Distro $Distro -xmlConfig $xmlConfig
                $DeploymentStatistics.VMSize = $($VMSizes[$VMSizeNumber])
                $DeploymentStatistics.attempt = $count
                if ($isDeployed)
                {
                    $successCount += 1
                    LogMsg "ATTEMPT : $count/$DeploymentCount : Deploying $($VMSizes[$VMSizeNumber]) VM.. SUCCESS"
                    $deployResult = "PASS"
                    #VM is Deployed. Delete the service.. 
                }
                else
                {
                    $failCount += 1
                    LogErr "ATTEMPT : $count/$DeploymentCount : Deploying $($VMSizes[$VMSizeNumber]) VM.. FAIL"
                    $deployResult = "FAIL"
                    if ( $failCount -lt $allowedFails )
                    {
                        $VMSizeNumber += 1
                    }
                    else
                    {
                        break;
                    }
                }
                $DeploymentStatistics.result = $deployResult
                if($VMSizeNumber -gt ($NumberOfSizes-2))
                {
                    $VMSizeNumber = 0
                }
                else
                {
                    $VMSizeNumber += 1
                }
                LogMsg "[PASS/FAIL/REMAINING] : $successCount/$failCount/$($DeploymentCount-$count)"
                DoTestCleanUp -result $deployResult -testName $currentTestData.testName -ResourceGroups $isDeployed
                $allDeploymentStatistics += $DeploymentStatistics
            }
        }
        if (($successCount -eq $DeploymentCount) -and ($failCount -eq 0))
        {
            $testResult = "PASS"
        }
        else
        {
            $testResult = "FAIL"
        }
        if ( $UseAzureResourceManager )
        {
            LogMsg "Attempt`tVMSize`tresult"
            $deploymentTimes=@()
            $bootTimes=@()
            $ProvisionTimes=@()
            foreach ( $value in $allDeploymentStatistics )
            {
                $deploymentTimes += $value.DeploymentTime
                $bootTimes += $value.BootTime
                $ProvisionTimes += $value.ProvisionTime
                LogMsg "$($value.attempt)`t$($value.VMSize)`t$($value.result)`t"
            }
        }
        else
        {
            LogMsg "Attempt`tVMSize`tresult`tDeployment Time`tBoot Time`tProvision Time"
            $deploymentTimes=@()
            $bootTimes=@()
            $ProvisionTimes=@()
            foreach ( $value in $allDeploymentStatistics )
            {
                $deploymentTimes += $value.DeploymentTime
                $bootTimes += $value.BootTime
                $ProvisionTimes += $value.ProvisionTime
                LogMsg "$($value.attempt)`t$($value.VMSize)`t$($value.result)`t$($value.DeploymentTime)`t$($value.BootTime)`t$($value.ProvisionTime)"
            }
            $DT = $deploymentTimes | Measure-Object -Minimum -Maximum -Average
            $BT = $bootTimes | Measure-Object -Minimum -Maximum -Average
            $PT = $ProvisionTimes | Measure-Object -Minimum -Maximum -Average
            LogMsg "Deployment Time - [MIN/AVG/MAX] - $($DT.Minimum)/$($DT.Average)/$($DT.Maximum)"
            LogMsg "Boot Time - [MIN/AVG/MAX] - $($BT.Minimum)/$($BT.Average)/$($BT.Maximum)"
            LogMsg "Provision Time - [MIN/AVG/MAX] - $($PT.Minimum)/$($PT.Average)/$($PT.Maximum)"
        }
	}
	catch
	{
		$ErrorMessage =  $_.Exception.Message
		LogMsg "EXCEPTION : $ErrorMessage"   
	}
	Finally
	{
		if (!$testResult)
		{
			$testResult = "Aborted"
		}
		$resultArr += $testResult
        $resultSummary +=  CreateResultSummary -testResult $testResult -metaData "DeploymentCount : $count/$DeploymentCount" -checkValues "PASS,FAIL,ABORTED" -testName $currentTestData.testName# if you want to publish all result then give here all test status possibilites. if you want just failed results, then give here just "FAIL". You can use any combination of PASS FAIL ABORTED and corresponding test results will be published!
	}   
$result = GetFinalResultHeader -resultarr $resultArr

#Clean up the setup
#DoTestCleanUp -result $result -testName $currentTestData.testName -deployedServices $isDeployed

#Return the result and summery to the test suite script..
return $result, $resultSummary