<#
.SYNOPSIS
    Retrieves all apps (App Services and Function Apps) in the specified subscription, and removes a specified application setting from each app and its deployment slots.

.DESCRIPTION
    This script ensures the user is connected to an Azure account, prompting for login if necessary.
    It lists all available subscriptions and prompts the user to select one.
    After setting the selected subscription context, it retrieves all apps (App Services and Function Apps) and their deployment slots.
    For each app and slot, it backs up the current application settings to JSON files and removes the specified application setting.

.PARAMETER AppSettingKeyName
    The key of the application setting to search for and remove. Defaults to "YOUR_SETTING_KEY_NAME". 
    **Note:** Replace "YOUR_SETTING_KEY_NAME" with the actual key name you want to search for.

.NOTES
    Ensure the Azure PowerShell module is installed and you are connected to your Azure account before running this script.

.EXAMPLE
    .\Find-And-Remove-Specific-App-Setting.ps1 -AppSettingKeyName "YOUR_CUSTOM_SETTING_KEY"
#>

param (
    [string]$AppSettingKeyName = "YOUR_SETTING_KEY_NAME" # Replace with your actual setting key name
)

# Connect to your Azure account
if (-not (Get-AzContext)) {
    Connect-AzAccount | Out-Null
    Write-Output "Connected to Azure account."
} else {
    Write-Output "Already connected to Azure account."
}

# Get available subscriptions
$subscriptions = Get-AzSubscription | Sort-Object -Property Name

# Display available subscriptions with numbers and prompt user to select one
for ($i = 0; $i -lt $subscriptions.Count; $i++) {
    Write-Host "$($i + 1). $($subscriptions[$i].Name) [$($subscriptions[$i].Id)]"
}
$selectedSubscriptionIndex = Read-Host "Enter the number of the Azure Subscription"

# Validate the user input
if ($selectedSubscriptionIndex -lt 1 -or $selectedSubscriptionIndex -gt $subscriptions.Count) {
    Write-Host -ForegroundColor Red "Invalid selection. Exiting script."
    return
}

$selectedSubscriptionId = $subscriptions[$selectedSubscriptionIndex - 1].Id

# Set the selected subscription context
Set-AzContext -SubscriptionId $selectedSubscriptionId | Out-Null

# Suppress the warning message
$WarningPreference = "SilentlyContinue"

# Initialize the following with names of existing apps/slots within the specified subscription
$appList = Get-AzWebApp 2>$null | Select-Object Name, ResourceGroup | Sort-Object -Property Name
Write-Host -ForegroundColor Green ("Start the process to find and remove the [" + $AppSettingKeyName + "] setting from apps...")

$appServicesWithSetting = @()
$totalAppServices = $appList.Count
$currentCount = 0

# Process each App Service sequentially
foreach ($app in $appList) {
    $currentCount++
    Write-Host -ForegroundColor Cyan ("`nChecking '$($app.Name)' in resource group '$($app.ResourceGroup)' (processing $currentCount of $totalAppServices apps):")

    $appSettings = (Get-AzWebApp -ResourceGroupName $app.ResourceGroup -Name $app.Name -WarningAction SilentlyContinue).SiteConfig.AppSettings
    if ($appSettings -and $appSettings -ne "[]") {
        if ($appSettings.Name -contains $AppSettingKeyName) {
            # Backup current settings
            $backupFileName = "$($app.Name)_appsettings_backup.json"
            $appSettings | ConvertTo-Json | Out-File -FilePath $backupFileName
            Write-Output "Backup of $($app.Name) settings saved to $backupFileName"

            # Remove the specified setting
            $appSettings = $appSettings | Where-Object { $_.Name -ne $AppSettingKeyName }

            # Convert app settings to Hashtable
            $appSettingsHashtable = @{}
            foreach ($setting in $appSettings) {
                if ($setting.Name -and $setting.Value) {
                    $appSettingsHashtable[$setting.Name] = $setting.Value
                }
            }

            if ($appSettingsHashtable.Count -gt 0) {
                Set-AzWebApp -ResourceGroupName $app.ResourceGroup -Name $app.Name -AppSettings $appSettingsHashtable | Out-Null
                Write-Host -ForegroundColor Blue "App settings for $($app.Name) have been updated successfully."
            } else {
                Write-Host -ForegroundColor Yellow "No valid app settings found for $($app.Name). Skipping update."
            }

            $appServicesWithSetting += [PSCustomObject]@{ Name = $app.Name; ResourceGroup = $app.ResourceGroup }
        } else {
            Write-Host -ForegroundColor Yellow "The setting '$AppSettingKeyName' was not found in the app settings of '$($app.Name)'."
        }
    } else {
        Write-Host -ForegroundColor Yellow "No app settings found for $($app.Name)."
    }

    $appSlots = Get-AzWebAppSlot -ResourceGroupName $app.ResourceGroup -Name $app.Name -WarningAction SilentlyContinue
    if ($appSlots) {
        foreach ($appSlot in $appSlots) {
            $indexOf = $appSlot.Name.IndexOf('/')
            $slotName = $appSlot.Name.SubString($indexOf + 1)
            $fullSlotName = Get-AzWebAppSlot -ResourceGroupName $appSlot.ResourceGroup -Name $app.Name -Slot $slotName -WarningAction SilentlyContinue
            $slotSettings = ($fullSlotName).SiteConfig.AppSettings
            if ($slotSettings -and $slotSettings -ne "[]") {
                if ($slotSettings.Name -contains $AppSettingKeyName) {
                    # Backup current settings
                    $backupFileName = "$($appSlot.Name)_appsettings_backup.json"
                    $slotSettings | ConvertTo-Json | Out-File -FilePath $backupFileName
                    Write-Output "Backup of $($appSlot.Name) settings saved to $backupFileName"

                    # Remove the specified setting
                    $slotSettings = $slotSettings | Where-Object { $_.Name -ne $AppSettingKeyName }

                    # Convert slot settings to Hashtable
                    $slotSettingsHashtable = @{}
                    foreach ($setting in $slotSettings) {
                        if ($setting.Name -and $setting.Value) {
                            $slotSettingsHashtable[$setting.Name] = $setting.Value
                        }
                    }

                    if ($slotSettingsHashtable.Count -gt 0) {
                        Set-AzWebAppSlot -ResourceGroupName $appSlot.ResourceGroup -Name $app.Name -Slot $slotName -AppSettings $slotSettingsHashtable | Out-Null
                        Write-Host -ForegroundColor Blue "Slot settings for $($appSlot.Name) have been updated successfully."
                    } else {
                        Write-Host -ForegroundColor Yellow "No valid slot settings found for $($appSlot.Name). Skipping update."
                    }

                    $appServicesWithSetting += [PSCustomObject]@{ Name = $appSlot.Name; ResourceGroup = $appSlot.ResourceGroup }
                } else {
                    Write-Host -ForegroundColor Yellow "The setting '$AppSettingKeyName' was not found in the slot settings of '$($appSlot.Name)'."
                }
            } else {
                Write-Host -ForegroundColor Yellow "No slot settings found for $($appSlot.Name)."
            }
        }
    }

    Write-Progress -Activity "Checking App Services" -Status "Processing $currentCount of $totalAppServices" -PercentComplete (($currentCount / $totalAppServices) * 100)
}

# Output the App Services with the specific setting
Write-Host ""
if ($appServicesWithSetting.Count -gt 0) {
    Write-Host -ForegroundColor Green "The following apps had the specific setting '$AppSettingKeyName' and it has been removed:"
    $appServicesWithSetting | Sort-Object Name | ForEach-Object { Write-Host "$($_.Name) in resource group $($_.ResourceGroup)" }
} else {
    Write-Host -ForegroundColor Green "No App Services found with the setting '$AppSettingKeyName'."
}
