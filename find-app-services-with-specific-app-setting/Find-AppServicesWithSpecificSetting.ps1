<#
.SYNOPSIS
    This script identifies Azure App Services with a specific application setting.

.DESCRIPTION
    The script connects to an Azure account, retrieves all App Services in the subscription, and checks each one for a specified application setting. 
    It outputs the names and resource groups of App Services that contain the specified setting.

.PARAMETER AppSettingKeyName
    The key of the application setting to search for. Defaults to "WEBSITE_APPINSIGHTS_ENCRYPTEDAPIKEY".

.NOTES
    Ensure the Azure PowerShell module is installed and you are connected to your Azure account before running this script.

.EXAMPLE
    .\Find-AppServicesWithSpecificSetting.ps1 -AppSettingKeyName "YOUR_CUSTOM_SETTING_KEY"
#>

param (
    [string]$AppSettingKeyName = "WEBSITE_APPINSIGHTS_ENCRYPTEDAPIKEY"
)

# Ensure you have the Azure PowerShell module installed
# Install-Module -Name Az -AllowClobber -Force

# Connect to your Azure account
if (-not (Get-AzContext)) {
    Connect-AzAccount
    Write-Output "Connected to Azure account."
} else {
    Write-Output "Already connected to Azure account."
}

# Get available subscriptions
$subscriptions = Get-AzSubscription | Sort-Object -Property Name

# Prompt user to select a subscription
$subscriptionNames = $subscriptions.Name
$selectedSubscription = $subscriptionNames | Out-GridView -Title "Select an Azure Subscription" -OutputMode Single

# Set the selected subscription context
Set-AzContext -SubscriptionName $selectedSubscription

# Get all App Services in the selected subscription and sort by name
$appServices = Get-AzWebApp | Sort-Object -Property Name

# Initialize an array to store App Services with the specific setting
$appServicesWithSetting = @()

# Total number of app services
$totalAppServices = $appServices.Count
$currentCount = 0

# Loop through each App Service to check for the specific setting
foreach ($appService in $appServices) {
    $currentCount++
    Write-Progress -Activity "Checking App Services" -Status "Processing $currentCount of $totalAppServices" -PercentComplete (($currentCount / $totalAppServices) * 100)

    $appSettings = (Get-AzWebApp -ResourceGroupName $appService.ResourceGroup -Name $appService.Name -WarningAction SilentlyContinue).SiteConfig.AppSettings

    if ($appSettings.Name -contains $AppSettingKeyName) {
        $appServicesWithSetting += $appService
    }
}

# Output the App Services with the specific setting
if ($appServicesWithSetting.Count -gt 0) {
    Write-Output "App Services with the setting '$AppSettingKeyName':"
    $appServicesWithSetting | Sort-Object -Property Name | ForEach-Object {
        Write-Output "Name: $($_.Name), Resource Group: $($_.ResourceGroup)"
    }
} else {
    Write-Output "No App Services found with the setting '$AppSettingKeyName'."
}

# .\Find-AppServicesWithSpecificSetting.ps1 -AppSettingKeyName "YOUR_CUSTOM_SETTING_KEY"
