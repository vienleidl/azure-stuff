<#
.SYNOPSIS
    Identifies Azure App Services and Function Apps that either have or lack specific application settings.

.DESCRIPTION
    This script connects to an Azure account, retrieves all App Services and Function Apps within a specified subscription, and checks each one for the presence of specified application settings. 
    It displays the names of those that match the search criteria in a grid view. The script supports parallel processing to enhance performance.

.PARAMETER AppSettingKeyName1
    The first application setting key to search for. Defaults to "YOUR_SETTING_KEY_NAME1".

.PARAMETER AppSettingKeyName2
    The second application setting key to search for. If left blank, the script will only check for AppSettingKeyName1.

.PARAMETER SearchType
    Specifies whether to search for App Services with or without the specified setting keys. Valid values are "With" and "Without".

.PARAMETER FilterByTag
    Specifies whether to filter App Services by specific tags. If set to $true, only App Services with the specified tags and values will be included.

.PARAMETER TagName1
    The first tag name to filter by. Required if FilterByTag is $true.

.PARAMETER TagValue1
    The first tag value to filter by. Required if FilterByTag is $true.

.PARAMETER TagName2
    Optional second tag name to filter by, for example: "ms-resource-usage".

.PARAMETER TagValue2
    Optional second tag value to filter by, for example: "azure-app-service".

.NOTES
    Ensure the Azure PowerShell module is installed and you are connected to your Azure account before running this script.

.EXAMPLE
    .\Find-Apps-WithOrWithout-Specific-Setting.ps1 -AppSettingKeyName1 "YOUR_CUSTOM_SETTING_KEY1" -AppSettingKeyName2 "YOUR_CUSTOM_SETTING_KEY2" -SearchType "With" -FilterByTag $true -TagName1 "landscape" -TagValue1 "production"
#>

param (
    [string]$AppSettingKeyName1 = "YOUR_SETTING_KEY_NAME1",
    [string]$AppSettingKeyName2 = "YOUR_SETTING_KEY_NAME2", # Optional second application setting key to search for
    [ValidateSet("With", "Without")]
    [string]$SearchType        = "With",
    [bool]$FilterByTag         = $false,
    [string]$TagName1          = "", # The first tag name to filter by. Required if FilterByTag is $true.
    [string]$TagValue1         = "", # The first tag value to filter by. Required if FilterByTag is $true.
    [string]$TagName2          = "", # Optional second tag name, e.g., "ms-resource-usage"
    [string]$TagValue2         = ""  # Optional second tag value, e.g., "azure-app-service"
)

function Find-AppServices {
    param (
        [string]$AppSettingKeyName1,
        [string]$AppSettingKeyName2,
        [string]$SearchType,
        [bool]$FilterByTag,
        [string]$TagName1,
        [string]$TagValue1,
        [string]$TagName2,
        [string]$TagValue2
    )

    # Validate that TagName1 and TagValue1 are provided if FilterByTag is $true
    if ($FilterByTag -and ($TagName1 -eq "" -or $TagValue1 -eq "")) {
        throw "When FilterByTag is set to `$true`, both TagName1 and TagValue1 must be provided."
    }

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
    Set-AzContext -SubscriptionName $selectedSubscription | Out-Null

    # Suppress the warning message
    $WarningPreference = "SilentlyContinue"

    # Initialize the following with names of existing apps/slots within the specified subscription
    if ($FilterByTag) {
        $appList = Get-AzWebApp 2>$null | Where-Object {
            $_.Tags -and $_.Tags[$TagName1] -eq $TagValue1 -and
            ($TagName2 -eq "" -or $_.Tags[$TagName2] -eq $TagValue2)
        } | Select-Object Name, ResourceGroup | Sort-Object -Property Name
    } else {
        $appList = Get-AzWebApp 2>$null | Select-Object Name, ResourceGroup | Sort-Object -Property Name
    }

    Write-Host -ForegroundColor Green ("The names of apps which " + ($SearchType -eq "With" ? "have" : "do not have") + " the [" + $AppSettingKeyName1 + "]" + ($AppSettingKeyName2 -ne "" ? " and [" + $AppSettingKeyName2 + "]" : "") + " setting(s) are being collected...")

    $appServicesResult = @()
    $jobs = @()

    foreach ($app in $appList) {
        $jobs += Start-Job -ScriptBlock {
            param ($app, $AppSettingKeyName1, $AppSettingKeyName2, $SearchType)

            $appSettings = (Get-AzWebApp -ResourceGroupName $app.ResourceGroup -Name $app.Name -WarningAction SilentlyContinue).SiteConfig.AppSettings

            $hasSetting1 = $false
            $hasSetting2 = $false
            foreach ($setting in $appSettings) {
                if ($setting.Name -eq $AppSettingKeyName1) {
                    $hasSetting1 = $true
                }
                if ($AppSettingKeyName2 -ne "" -and $setting.Name -eq $AppSettingKeyName2) {
                    $hasSetting2 = $true
                }
            }

            if ($AppSettingKeyName2 -eq "") {
                if (($SearchType -eq "With" -and $hasSetting1) -or ($SearchType -eq "Without" -and -not $hasSetting1)) {
                    return [PSCustomObject]@{ Name = $app.Name; ResourceGroup = $app.ResourceGroup }
                }
            } else {
                if (($SearchType -eq "With" -and $hasSetting1 -and $hasSetting2) -or ($SearchType -eq "Without" -and -not $hasSetting1 -and -not $hasSetting2)) {
                    return [PSCustomObject]@{ Name = $app.Name; ResourceGroup = $app.ResourceGroup }
                }
            }

            $appSlots = Get-AzWebAppSlot -ResourceGroupName $app.ResourceGroup -Name $app.Name -WarningAction SilentlyContinue
            if ($appSlots) {
                foreach ($appSlot in $appSlots) {
                    $indexOf = $appSlot.Name.IndexOf('/')
                    $slotName = $appSlot.Name.SubString($indexOf + 1)
                    $fullSlotName = Get-AzWebAppSlot -ResourceGroupName $appSlot.ResourceGroup -Name $app.Name -Slot $slotName -WarningAction SilentlyContinue
                    $slotSettings = ($fullSlotName).SiteConfig.AppSettings

                    $slotHasSetting1 = $false
                    $slotHasSetting2 = $false
                    foreach ($setting in $slotSettings) {
                        if ($setting.Name -eq $AppSettingKeyName1) {
                            $slotHasSetting1 = $true
                        }
                        if ($AppSettingKeyName2 -ne "" -and $setting.Name -eq $AppSettingKeyName2) {
                            $slotHasSetting2 = $true
                        }
                    }

                    if ($AppSettingKeyName2 -eq "") {
                        if (($SearchType -eq "With" -and $slotHasSetting1) -or ($SearchType -eq "Without" -and -not $slotHasSetting1)) {
                            return [PSCustomObject]@{ Name = $appSlot.Name; ResourceGroup = $appSlot.ResourceGroup }
                        }
                    } else {
                        if (($SearchType -eq "With" -and $slotHasSetting1 -and $slotHasSetting2) -or ($SearchType -eq "Without" -and -not $slotHasSetting1 -and -not $slotHasSetting2)) {
                            return [PSCustomObject]@{ Name = $appSlot.Name; ResourceGroup = $appSlot.ResourceGroup }
                        }
                    }
                }
            }
        } -ArgumentList $app, $AppSettingKeyName1, $AppSettingKeyName2, $SearchType
    }

    # Display a message indicating the script is processing
    Write-Host -ForegroundColor Yellow "Processing App Services. Please wait..."

    # Wait for all jobs to complete and collect results
    foreach ($job in $jobs) {
        try {
            Wait-Job -Job $job -Timeout 300 | Out-Null
            $result = Receive-Job -Job $job
            if ($result) {
                $appServicesResult += $result
            }
        } catch {
            Write-Host -ForegroundColor Red "Error processing job for app: $($job.Name)"
        } finally {
            Remove-Job -Job $job | Out-Null
        }
    }

    # Output the App Services based on the search type
    if ($appServicesResult.Count -gt 0) {
        $appServicesResult | Sort-Object Name | Out-GridView -Title ("App Services " + ($SearchType -eq "With" ? "with" : "without") + " the setting(s) '$AppSettingKeyName1'" + ($AppSettingKeyName2 -ne "" ? " and '$AppSettingKeyName2'" : ""))
    } else {
        Write-Output ("No App Services found " + ($SearchType -eq "With" ? "with" : "without") + " the setting(s) '$AppSettingKeyName1'" + ($AppSettingKeyName2 -ne "" ? " and '$AppSettingKeyName2'" : ""))
    }
}

# Call the function
Find-AppServices -AppSettingKeyName1 $AppSettingKeyName1 -AppSettingKeyName2 $AppSettingKeyName2 -SearchType $SearchType -FilterByTag $FilterByTag -TagName1 $TagName1 -TagValue1 $TagValue1 -TagName2 $TagName2 -TagValue2 $TagValue2
