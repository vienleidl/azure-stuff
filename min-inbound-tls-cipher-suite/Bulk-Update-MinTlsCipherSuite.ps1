# Define the expected value of Minimum Inbound TLS Cipher Suite
$MinTlsCipherSuite = "TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256"

# Check if the CSV file exists
$csvFilePath = "./AzureserverFarms.csv"
if (-Not (Test-Path -Path $csvFilePath)) {
    Write-Output "The file 'AzureserverFarms.csv' does not exist. Please ensure the file is present in the script directory."
    exit
}

# Connect to Azure account if not already connected
if (-Not (Get-AzContext)) {
    Write-Output "Connecting to Azure account..."
    Connect-AzAccount
    # Verify connection
    if (-Not (Get-AzContext)) {
        Write-Output "Failed to connect to Azure account. Please check your credentials and try again."
        exit
    }
}

# Get the list of Azure subscriptions
$subscriptions = Get-AzSubscription
if (-Not $subscriptions) {
    Write-Output "No subscriptions found. Please check your Azure account."
    exit
}

# Display the list of subscriptions with numbers for easier selection
Write-Output "Available subscriptions:"
$i = 1
$subscriptions | ForEach-Object { 
    Write-Output "$i. $($_.Name)"
    $i++
}
$subscriptionChoice = Read-Host "Please enter the number corresponding to the subscription to apply changes to"

# Validate the entered subscription choice
if ($subscriptionChoice -gt 0 -and $subscriptionChoice -le $subscriptions.Count) {
    $subscription = $subscriptions[$subscriptionChoice - 1]
} else {
    Write-Output "Invalid choice. Please run the script again and enter a valid number."
    exit
}

Set-AzContext -SubscriptionId $subscription.Id

# Get the access token once
$token = (Get-AzAccessToken).Token

# Import the CSV file
$appServicePlans = Import-Csv -Path $csvFilePath

# Prompt the user for their choice of environments/landscapes
$environmentChoice = Read-Host "Please choose the environment to apply changes to: (1) DEV and STAGING App Services OR (2) PRODUCTION ones (excluding DEV and STAGING). Enter 1 or 2"

# Check for invalid choice and exit if necessary
if ($environmentChoice -ne "1" -and $environmentChoice -ne "2") {
    Write-Output "Invalid choice. Please run the script again and enter 1 or 2."
    exit
}

# Initialize arrays to store App Services based on the user's choice
$selectedAppServices = @()

# Loop through each App Service plan from the CSV and check its App Services
foreach ($appServicePlan in $appServicePlans) {
    $resourceGroupName = $appServicePlan.'RESOURCE GROUP'
    $appServicePlanName = $appServicePlan.NAME
    Write-Output "`nChecking App Service Plan: ${appServicePlanName} in Resource Group: ${resourceGroupName}"
    
    # Get the App Service plan ID
    $appServicePlanId = (Get-AzAppServicePlan -ResourceGroupName $resourceGroupName -Name $appServicePlanName).Id
    Write-Output "App Service Plan ID: ${appServicePlanId}"
    if (-not $appServicePlanId) {
        Write-Output "App Service Plan ID not found for ${appServicePlanName} in ${resourceGroupName}"
        continue
    }
    
    # Get all App Services in the current App Service plan
    $currentAppServices = Get-AzWebApp -ResourceGroupName $resourceGroupName | Where-Object { $_.ServerFarmId -eq $appServicePlanId }
    if (-not $currentAppServices) {
        Write-Output "No App Services found for ${appServicePlanName} in ${resourceGroupName}"
        continue
    }
    
    # List all App Services found in the corresponding Resource Group
    Write-Output "`nApp Services found for ${appServicePlanName} in ${resourceGroupName}:"
    $currentAppServices | ForEach-Object { Write-Output $_.Name }
    
    # Filter App Services based on the user's choice
    if ($environmentChoice -eq "1") {
        # Include only dev and staging app services
        $selectedAppServices += $currentAppServices | Where-Object { $_.Name -like "*dev*" -or $_.Name -like "*staging*" }
    } elseif ($environmentChoice -eq "2") {
        # Exclude dev and staging app services
        $selectedAppServices += $currentAppServices | Where-Object { $_.Name -notlike "*dev*" -and $_.Name -notlike "*staging*" }
    }
}

if (-not $selectedAppServices) {
    Write-Output "No app services found based on the selected criteria."
    exit
}

# Loop through each selected App Service to update the Minimum Inbound TLS Cipher Suite
foreach ($appService in $selectedAppServices) {
    $resourceGroupName = $appService.ResourceGroup
    $appServiceName = $appService.Name
    Write-Output "`nChecking MinTlsCipherSuite for App Service: ${appServiceName} in Resource Group: ${resourceGroupName}"
    
    # Get the App Service configuration using the ARM API
    $url = "https://management.azure.com/subscriptions/$($subscription.Id)/resourceGroups/$resourceGroupName/providers/Microsoft.Web/sites/$appServiceName/config/web?api-version=2021-02-01"
    $response = Invoke-RestMethod -Uri $url -Method Get -Headers @{Authorization = "Bearer $token"}
    # Check if the Minimum Inbound TLS Cipher Suite has been already configured
    if ($response.properties.minTlsCipherSuite -eq $MinTlsCipherSuite) {
        Write-Output "MinTlsCipherSuite is already configured for App Service ${appServiceName}. Skipping update."
    } else {
        # Update the Minimum Inbound TLS Cipher Suite
        $response.properties.minTlsCipherSuite = $MinTlsCipherSuite
        $response | Set-AzResource -Force
        Write-Output "Updated MinTlsCipherSuite to ${MinTlsCipherSuite} for App Service: ${appServiceName}"
    }
}

# Sort the selected App Services by name
$selectedAppServices = $selectedAppServices | Sort-Object Name

# Count the total number of selected App Services
$totalSelectedAppServices = $selectedAppServices.Count

# Print the total number of selected App Services
Write-Output "`nTotal number of selected App Services: ${totalSelectedAppServices}"

# Print the sorted list of selected App Services
Write-Output "List of selected App Services:"
$selectedAppServices | ForEach-Object { Write-Output $_.Name }
