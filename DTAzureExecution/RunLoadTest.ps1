param (

    ### Azure App Registration with Contributor permissions on the Resource Group to be used for Azure resources (Storage Account, Azure Container Instance) 
    [Parameter(Mandatory = $true)][string]$SubscriptionGuid,
    [Parameter(Mandatory = $true)][string]$TenantId,
    [Parameter(Mandatory = $true)][string]$ClientId,
    [Parameter(Mandatory = $true)][string]$ClientSecret,

     ### Environment Variables
    [Parameter(Mandatory = $true)][string]$src_script,
    [Parameter(Mandatory = $true)][string]$src_users,
    [Parameter(Mandatory = $true)][string]$src_test_duration,
    [Parameter(Mandatory = $true)][string]$src_rampup_duration,
    
    ### Azure resources
    [Parameter(Mandatory = $false)][string]$loadTestResourceGroup = "SatsResource", #The name of the resource group where to create the Azure resources 
    [Parameter(Mandatory = $false)][string]$loadTestLocation = "centralindia", #Location for Azure resources
    [Parameter(Mandatory = $true)][string]$storageAccountName, #The name of the storage account that will contain the test run files and results
    [Parameter(Mandatory = $false)][string]$storageAccountKey, #The name of the file share within the storage account that will actually contain the files
    [Parameter(Mandatory = $false)][string]$storageShareName = "azurejmeterstorageaccount", #The name of the file share within the storage account that will actually contain the files
    
   
    ### Load test resources
    [Parameter(Mandatory = $false)][string]$loadTestIdentifier = $(Get-Date -format "yyyyMMddhhmmss"), #Unique identifier for each run, also used as a folder name within the Share of the storage account
    [Parameter(Mandatory = $false)][string]$loadTestScript = "$($env:Build_Repository_LocalPath)\DTAzureExecution\Scripts\$src_script", #The load test file path in K6
   
    ############## Trial starts
    [Parameter(Mandatory = $false)][string]$loadTestSourcePath = "$($env:Build_Repository_LocalPath)", #The Util path in framework   
   ############## Trial ends
   
    ### Containers info
    [Parameter(Mandatory = $false)][string]$JmeterAgentImage = "satheeshpandianj/jmeterbase", # The K6 image to use, in this case the official public one from DockerHub
    [Parameter(Mandatory = $false)][int]$JmeterAgentInstances = 1, #The number of containers to start
    [Parameter(Mandatory = $false)][int]$JmeterAgentCPU = 4, #The number of CPU cores for each Container
    [Parameter(Mandatory = $false)][int]$JmeterAgentMemory = 4, #The amount of RAM in Gb for each Container
)

### FUNCTIONS
#region "Log Analytics Workspace Ingestion Functions"

# Create the function to create the authorization signaturex\
Function Build-Signature ($customerId, $sharedKey, $date, $contentLength, $method, $contentType, $resource) {
    $xHeaders = "x-ms-date:" + $date
    $stringToHash = $method + "`n" + $contentLength + "`n" + $contentType + "`n" + $xHeaders + "`n" + $resource

    $bytesToHash = [Text.Encoding]::UTF8.GetBytes($stringToHash)
    $keyBytes = [Convert]::FromBase64String($sharedKey)

    $sha256 = New-Object System.Security.Cryptography.HMACSHA256
    $sha256.Key = $keyBytes
    $calculatedHash = $sha256.ComputeHash($bytesToHash)
    $encodedHash = [Convert]::ToBase64String($calculatedHash)
    $authorization = 'SharedKey {0}:{1}' -f $customerId, $encodedHash
    return $authorization
}

# Create the function to create and post the request
Function Post-LogAnalyticsData($customerId, $sharedKey, $body, $logType) {
    $method = "POST"
    $contentType = "application/json"
    $resource = "/api/logs"
    $rfc1123date = [DateTime]::UtcNow.ToString("r")
    $contentLength = $body.Length
    $signature = Build-Signature `
        -customerId $customerId `
        -sharedKey $sharedKey `
        -date $rfc1123date `
        -contentLength $contentLength `
        -method $method `
        -contentType $contentType `
        -resource $resource
    $uri = "https://" + $customerId + ".ods.opinsights.azure.com" + $resource + "?api-version=2016-04-01"

    $headers = @{
        "Authorization"        = $signature;
        "Log-Type"             = $logType;
        "x-ms-date"            = $rfc1123date;
        "time-generated-field" = "";
    }

    $response = Invoke-WebRequest -Uri $uri -Method $method -ContentType $contentType -Headers $headers -Body $body -UseBasicParsing
    return $response.StatusCode

}
#endregion

#region "Storage Account integration function"

# Create the function to download the json file from storage account
Function Download-JSON-From-StorageAccount($loadTestIdentifier, $fileName, $tempDownloadDirectory, $storageAccountName, $storageAccountKey, $storageShareName) {
    $currentDownloadPath = "$tempDownloadDirectory/$fileName"
    $null = az storage file download --account-name $storageAccountName --account-key $storageAccountKey --share-name $storageShareName --path "$loadTestIdentifier/$fileName" --dest $currentDownloadPath
    
    $json = Get-Content $currentDownloadPath | ConvertFrom-Json
    $json | Add-Member NoteProperty "testIdentifier" $loadTestIdentifier
    return $json
}
#endregion

### DECLARATIONS
# $AciK6AgentNamePrefix = "aci-loadtest-k6-agent-$loadTestIdentifier"
$AciJmeterAgentNamePrefix = "azurejmetercontainer"
$AciJmeterAgentLoadTestHome = "loadtest"

### ACCOUNT LOGIN
if ([string]::IsNullOrWhiteSpace($ClientId) -eq $false) {
    Write-Host "Logging into Subscription"
    az login --service-principal --username $ClientId --password $ClientSecret --tenant $TenantId
    az account set --subscription $SubscriptionGuid
}
else {
    Write-Host "Using Current Login Context"
}

### STORAGE ACCOUNT RESOURCE GROUP
Write-Host "Creating Storage Account Resource Group"
az group create --location $loadTestLocation --name $loadTestResourceGroup

### STORAGE ACCOUNT WITH SHARE CREATION
Write-Host "Creating Storage Account and Share for Jmeter test files"
az storage account create --name $storageAccountName --resource-group $loadTestResourceGroup --sku Standard_LRS
az storage share create --name $storageShareName --account-name $storageAccountName --quota 5
$storageAccountKey = $(az storage account keys list --resource-group $loadTestResourceGroup --account-name $storageAccountName --query "[0].value" --output tsv)
az storage directory create --account-name $storageAccountName --account-key $storageAccountKey --share-name $storageShareName --name $loadTestIdentifier

#### Trial starts
# Write-Host "Started uploading all the source files to storage account"
# az storage file upload-batch --account-name $storageAccountName --account-key $storageAccountKey --source $loadTestSourcePath --destination $storageShareName
# Write-Host "Completed uploading all the source files to storage account"
### Trail ends

az storage file upload --account-name $storageAccountName --account-key $storageAccountKey --share-name $storageShareName --source $loadTestScript --path "$loadTestIdentifier/$src_script"
Write-Host "Uploaded test files to storage account"

### AGENTS CONTAINER CREATION
$injectorsStart = Get-Date

Write-Host "Creating agents container(s)"
1..$K6AgentInstances | ForEach-Object -Parallel {   
    Write-Host "Creating Jmeter agent $_"
    az container create --resource-group $using:loadTestResourceGroup --name "$using:AciJmeterAgentNamePrefix-$_" --location $using:loadTestLocation `
        --image $using:JmeterAgentImage --restart-policy Never --cpu $using:JmeterAgentCPU --memory $using:JmeterAgentMemory `
        --environment-variables AGENT_NUM=$_ LOAD_TEST_ID=$using:loadTestIdentifier `
        --azure-file-volume-account-name $using:storageAccountName --azure-file-volume-account-key $using:storageAccountKey --azure-file-volume-share-name $using:storageShareName --azure-file-volume-mount-path "/$using:AciJmeterAgentLoadTestHome/" `
        --command-line "jmeter -n -t /$using:AciK6AgentLoadTestHome/src/$using:src_script -l /$using:AciK6AgentLoadTestHome/src/$using:src_script -DTHREADS=$using:src_users -DDURATION=$using:src_test_duration -DRAMP_UP=$using:src_rampup_duration" 
} -ThrottleLimit 10

$injectorsEnd = Get-Date

### WAIT FOR EXECUTION TO FINISH
do {
    $countRunning = 0;
    1..$K6AgentInstances | ForEach-Object {   
        if ($(az container show -g $loadTestResourceGroup -n "$AciJmeterAgentNamePrefix-$_" --query "containers[0].instanceView.currentState.state" -o tsv) -eq "Running") {
            $countRunning += 1
        }
    }
    if ($countRunning -gt 0) {
        Write-Host "Load test still running with $countRunning containers"
    }
    Start-Sleep -s 5
}while ($countRunning -gt 0)

Write-Host "Test completed"

############# HTML Report upload starts
Write-Host "Moving HTML report to storage account"
#az storage file upload --account-name $storageAccountName --account-key $storageAccountKey --share-name $storageShareName --source "/summary.html" --path "/$loadTestIdentifier/summary.html"
#azcopy login --tenant-id $TenantId
azcopy cp 'https://azurek6storageaccount.file.core.windows.net/azurek6storageaccount/summary.html?sv=2020-08-04&ss=bfqt&srt=sco&sp=rwdlacupitfx&se=2021-12-31T16:22:44Z&st=2021-12-02T08:22:44Z&spr=https&sig=%2Fr0Ei0xnRJOTEfXzpGoaEDDa9%2F6N6uxXRcMdeE8Gbik%3D' "https://azurek6storageaccount.file.core.windows.net/azurek6storageaccount/reports/'$loadTestIdentifier'_summary.html?sv=2020-08-04&ss=bfqt&srt=sco&sp=rwdlacupitfx&se=2021-12-31T16:22:44Z&st=2021-12-02T08:22:44Z&spr=https&sig=%2Fr0Ei0xnRJOTEfXzpGoaEDDa9%2F6N6uxXRcMdeE8Gbik%3D" 
azcopy rm 'https://azurek6storageaccount.file.core.windows.net/azurek6storageaccount/summary.html?sv=2020-08-04&ss=bfqt&srt=sco&sp=rwdlacupitfx&se=2021-12-31T16:22:44Z&st=2021-12-02T08:22:44Z&spr=https&sig=%2Fr0Ei0xnRJOTEfXzpGoaEDDa9%2F6N6uxXRcMdeE8Gbik%3D'  
Write-Host "Uploaded HTML report to storage account"
############# HTML Report upload ends

#### CLEAN UP THE LOAD TEST RESOURCES
1..$K6AgentInstances | ForEach-Object -Parallel {   
    Write-Host "Removing agent container: $_"
    az container delete --resource-group $using:loadTestResourceGroup --name "$using:AciJmeterAgentNamePrefix-$_" --yes
} -ThrottleLimit 10

Remove-Item $tempDownloadDirectory -Force -Recurse