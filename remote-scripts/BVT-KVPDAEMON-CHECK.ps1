Import-Module .\TestLibs\RDFELibs.psm1 -Force
$result = ""
$testResult = ""
$resultArr = @()

try
{
    $isDeployed = DeployVMS -setupType $currentTestData.setupType -Distro $Distro -xmlConfig $xmlConfig
    if ($isDeployed)
    {
        foreach ($VM in $allVMData)
            {
                $ResourceGroupUnderTest = $VM.ResourceGroupName
                LogMsg "Verifying if KVP daemon is running in remote VM ...."
                $kvpOutput = RunLinuxCmd -username $user -password $password -ip $VM.PublicIP -port $VM.SSHPort -command "pgrep -lf `"hypervkvpd|hv_kvp_daemon`"" -runAsSudo
                if($kvpOutput -imatch "kvp")
                {
                    LogMsg "KVP daemon is present in remote VM"
                    $testResult = "PASS"
                }
                else 
                {
                    LogMsg "KVP daemon is NOT present in remote VM"
                    $testResult = "FAIL"
                }
                
            }
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
    }   
$result = GetFinalResultHeader -resultarr $resultArr

#Clean up the setup
DoTestCleanUp -result $result -testName $currentTestData.testName -ResourceGroups $isDeployed

#Return the result and summery to the test suite script..
return $result
