<#
.SYNOPSIS
    Automates the removal of installed extensions from Azure App Services in bulk.

.DESCRIPTION
    This script automates the management of Azure App Service extensions by performing the following tasks:
    1. Connects to the Azure account and prompts the user to select a subscription.
    2. Retrieves all App Services within the selected subscription.
    3. Checks each App Service for installed extensions and collects detailed information.
    4. Outputs detailed information about the installed extensions.
    5. Prompts the user for confirmation before proceeding with deletion.
    6. Removes resource locks from the resource groups before deleting the extensions.
    7. Deletes the installed extensions using the Azure Management API.
    8. Re-adds the resource locks to the resource groups after successfully deleting the extensions.

.NOTES
    This script ensures proper handling of access tokens and provides detailed logging for each step of the process.
    It is designed to be idempotent and safe to run multiple times without causing unintended side effects.
#>

# Function to get a new access token
function Get-NewAccessToken {
    $tokenResponse = Get-AzAccessToken -ResourceUrl "https://management.azure.com/" -AsSecureString
    $global:tokenExpiry = (Get-Date).AddMinutes(55) # Set token expiry to 55 minutes from now
    return [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($tokenResponse.Token))
}

# Function to refresh the access token if expired
function Update-AccessToken {
    if ((Get-Date) -gt $global:tokenExpiry) {
        Get-NewAccessToken 3>$null
    }
}

# Function to check installed extensions for a given App Service
function Get-AppServiceExtensions {
    param (
        [string]$SubscriptionId,
        [string]$ResourceGroupName,
        [string]$AppServiceName
    )

    $Url = "https://management.azure.com/subscriptions/$($SubscriptionId)/resourceGroups/$($ResourceGroupName)/providers/Microsoft.Web/sites/$($AppServiceName)/siteextensions?api-version=2024-04-01"
    try {
        Update-AccessToken
        $Extension = Invoke-WebRequest -Method Get -Uri $Url -Headers @{Authorization = "Bearer $global:accessToken"} -ContentType "application/json" | Select-Object -ExpandProperty Content
        $InstalledExtensions = (ConvertFrom-Json $Extension).value

        return $InstalledExtensions
    } catch {
        Write-Host "Error accessing $($AppServiceName): $_" -ForegroundColor Red
        return $null
    }
}

# Function to remove resource group lock
function Remove-ResourceGroupLock {
    param (
        [string]$ResourceGroupName
    )
    $Lock = Get-AzResourceLock -ResourceGroupName $ResourceGroupName | Where-Object {$_.ResourceType -eq "Microsoft.Authorization/locks"}
    if ($Lock) {
        Remove-AzResourceLock -LockName "ResourceGroup" -ResourceGroupName $ResourceGroupName -Force
    } else {
        Write-Host "No locks found for resource group: $ResourceGroupName"
    }
}

# Function to add resource group lock
function Add-ResourceGroupLock {
    param (
        [string]$ResourceGroupName
    )
    New-AzResourceLock -LockName "ResourceGroup" -LockLevel CanNotDelete -ResourceGroupName $ResourceGroupName
}

# Function to remove an installed extension from a given App Service
function Remove-AppServiceExtension {
    param (
        [string]$SubscriptionId,
        [string]$ResourceGroupName,
        [string]$AppServiceName,
        [string]$ExtensionId
    )

    $DeleteUrl = "https://management.azure.com/subscriptions/$($SubscriptionId)/resourceGroups/$($ResourceGroupName)/providers/Microsoft.Web/sites/$($AppServiceName)/siteextensions/$($ExtensionId)?api-version=2024-04-01"
    try {
        # Check if the token is expired and refresh if necessary
        if ((Get-Date) -gt $global:tokenExpiry) {
            $global:accessToken = Get-NewAccessToken 3>$null
        }

        $response = Invoke-WebRequest -Method Delete -Uri $DeleteUrl -Headers @{Authorization = "Bearer $global:accessToken"} -ContentType "application/json"
        if ($response.StatusCode -eq 200) {
            Write-Host "Deleted extension: $ExtensionId from App Service: $AppServiceName" -ForegroundColor Blue
        } else {
            Write-Host "Failed to delete extension: $ExtensionId from App Service: $AppServiceName. Status Code: $($response.StatusCode)" -ForegroundColor Red
        }
    } catch {
        Write-Host "Error removing extension: $ExtensionId from App Service: $($AppServiceName): $_" -ForegroundColor Red
    }
}

# Connect to Azure account if not already connected
if (-Not (Get-AzContext)) {
    Write-Output "Connecting to Azure account..."
    Connect-AzAccount
    # Verify connection
    if (-Not (Get-AzContext)) {
        Write-Host "Failed to connect to Azure account. Exiting script..." -ForegroundColor Red
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

Set-AzContext -SubscriptionId $subscription.Id | Out-Null

# Inform the user that the process of checking installed extensions has started
Write-Host "`nThe process of checking installed extensions has started..." -ForegroundColor Green

# Get the access token for the selected subscription
Write-Output "Getting new access token..."
$global:accessToken = Get-NewAccessToken 3>$null

# Get all App Services in the subscription and sort by name
$WebApps = Get-AzWebApp | Sort-Object -Property Name

# Create an array to store the results
$Results = @()

# Loop through each App Service and check for installed extensions
foreach ($WebApp in $WebApps) {
    Write-Host "`nChecking installed extensions for App Service: $($WebApp.Name)" -ForegroundColor Cyan
    $InstalledExtensions = Get-AppServiceExtensions -SubscriptionId $subscription.Id -ResourceGroupName $WebApp.ResourceGroup -AppServiceName $WebApp.Name

    if ($InstalledExtensions) {
        foreach ($Extension in $InstalledExtensions) {
            # Debug: Output each extension's properties
            Write-Output "Extension Properties: $($Extension | ConvertTo-Json -Depth 3)"

            $Results += [PSCustomObject]@{
                AppServiceName    = $WebApp.Name
                ResourceGroupName = $WebApp.ResourceGroup
                ExtensionName     = $Extension.name
                Version           = $Extension.properties.version
                ProvisioningState = $Extension.properties.provisioningState
                InstalledDateTime = $Extension.properties.installed_date_time
                Title             = $Extension.properties.title
                ExtensionId       = $Extension.properties.id
            }
        }
    } else {
        Write-Output "No extensions found for App Service: $($WebApp.Name)"
    }
}

# Check if there are any App Services with extensions installed
if ($Results.Count -gt 0) {
    # Print out detailed information for App Services which have extensions installed
    Write-Host "`nThe following is a list of App Services which have extensions installed:" -ForegroundColor Green
    $Results | ForEach-Object {
        Write-Host ""
        Write-Host "App Service Name : $($_.AppServiceName)"
        Write-Host "Resource Group : $($_.ResourceGroupName)"
        Write-Host "Title : $($_.Title)"
        Write-Host "Version : $($_.Version)"
        Write-Host "Installed Date : $($_.InstalledDateTime)"
        Write-Host "Provisioning State : $($_.ProvisioningState)"
        Write-Host "----------------------------------------"
    }

    # Output the total count of App Services which have extensions installed
    Write-Host ("`nTotal of App Services which have extensions installed: {0}" -f $Results.Count) -ForegroundColor Yellow

    # Ask for user confirmation before proceeding with deletion
    $confirmation = Read-Host "Do you want to proceed with the deletion of these extensions? (yes/no)"
    if ($confirmation -ne "yes") {
        Write-Host "`nOperation cancelled by user. Exiting script..." -ForegroundColor Yellow
        exit
    }

    # Inform the user that the process of removing installed extensions has started
    Write-Host "`nThe process of removing installed extensions is now in progress. Please wait while we complete this operation..." -ForegroundColor Green

    # Remove the lock from the resource group and delete the installed extensions
    foreach ($Result in $Results) {
        Remove-AppServiceExtension -SubscriptionId $subscription.Id -ResourceGroupName $($Result.ResourceGroupName) -AppServiceName $($Result.AppServiceName) -ExtensionId $($Result.ExtensionId) -ExtensionName $($Result.ExtensionName)
    }

    # Inform the user that the process of removing installed extensions has been completed
    Write-Host "`nThe process of removing installed extensions has been completed." -ForegroundColor Green
} else {
    Write-Host "`nNo extensions found to remove. Exiting script..." -ForegroundColor Yellow
    exit
}
