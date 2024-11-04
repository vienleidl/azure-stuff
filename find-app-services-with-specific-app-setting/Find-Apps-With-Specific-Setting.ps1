<#
.SYNOPSIS
    This script identifies Azure App Services and Function Apps which have a specific application setting.

.DESCRIPTION
    The script connects to an Azure account, retrieves all App Services and Function Apps in the specified subscription, and checks each one for a specified application setting. 
    It displays the names of those that have the specified setting in a grid view.

.PARAMETER AppSettingKeyName
    The key of the application setting to search for. Defaults to "YOUR_SETTING_KEY_NAME".

.NOTES
    Ensure the Azure PowerShell module is installed and you are connected to your Azure account before running this script.

.EXAMPLE
    .\Find-Apps-With-Specific-Setting.ps1 -AppSettingKeyName "YOUR_CUSTOM_SETTING_KEY"
#>

param (
    [string]$AppSettingKeyName = "YOUR_SETTING_KEY_NAME"
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

# Suppress the warning message
$WarningPreference = "SilentlyContinue"

# Initialize the following with names of existing apps/slots within the specified subscription
$appList = Get-AzWebApp 2>$null | Select-Object Name, ResourceGroup | Sort-Object -Property Name
Write-Host -ForegroundColor Green ("The names of apps which have the [" + $AppSettingKeyName + "] setting are being collected...")

$appServicesWithSetting = @()
$totalAppServices = $appList.Count
$currentCount = 0

# Use jobs to check each App Service in parallel
$jobs = @()
foreach ($app in $appList) {
    $jobs += Start-Job -ScriptBlock {
        param ($app, $AppSettingKeyName, $totalAppServices)

        $appSettings = (Get-AzWebApp -ResourceGroupName $app.ResourceGroup -Name $app.Name -WarningAction SilentlyContinue).SiteConfig.AppSettings
        if ($appSettings.Name -contains $AppSettingKeyName) {
            return [PSCustomObject]@{ Name = $app.Name; ResourceGroup = $app.ResourceGroup }
        }

        $appSlots = Get-AzWebAppSlot -ResourceGroupName $app.ResourceGroup -Name $app.Name -WarningAction SilentlyContinue
        if ($appSlots) {
            foreach ($appSlot in $appSlots) {
                $indexOf = $appSlot.Name.IndexOf('/')
                $slotName = $appSlot.Name.SubString($indexOf + 1)
                $fullSlotName = Get-AzWebAppSlot -ResourceGroupName $appSlot.ResourceGroup -Name $app.Name -Slot $slotName -WarningAction SilentlyContinue
                $slotSettings = ($fullSlotName).SiteConfig.AppSettings
                if ($slotSettings.Name -contains $AppSettingKeyName) {
                    return [PSCustomObject]@{ Name = $appSlot.Name; ResourceGroup = $appSlot.ResourceGroup }
                }
            }
        }
    } -ArgumentList $app, $AppSettingKeyName, $totalAppServices
}

# Display a message indicating the script is processing
Write-Host -ForegroundColor Yellow "Processing App Services. Please wait..."

# Wait for all jobs to complete and track progress
foreach ($job in $jobs) {
    Wait-Job -Job $job
    $result = Receive-Job -Job $job
    if ($result) {
        $appServicesWithSetting += $result
    }
    Remove-Job -Job $job
    $currentCount++
    Write-Progress -Activity "Checking App Services" -Status "Processing $currentCount of $totalAppServices" -PercentComplete (($currentCount / $totalAppServices) * 100)
}

# Output the App Services with the specific setting
if ($appServicesWithSetting.Count -gt 0) {
    $appServicesWithSetting | Sort-Object Name | Out-GridView -Title "App Services with the setting '$AppSettingKeyName'"
} else {
    Write-Output "No App Services found with the setting '$AppSettingKeyName'."
}
