<#
.SYNOPSIS
    Lists installed extensions for Azure App Services.

.DESCRIPTION
    This script automates the process of listing Azure App Service extensions by performing the following tasks:
    1. Connects to the Azure account and prompts the user to select a subscription.
    2. Retrieves all App Services within the selected subscription.
    3. Checks each App Service for installed extensions and collects detailed information.
    4. Outputs detailed information about the installed extensions, including the name, resource group, title, version, installation date, and provisioning state.
    5. Provides a summary of the total count of App Services with extensions installed.

.NOTES
    This script ensures proper handling of access tokens and provides detailed logging for each step of the process.
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
            # # Debug: Output each extension's properties
            # Write-Output "Extension Properties: $($Extension | ConvertTo-Json -Depth 3)"
            
            $Results += [PSCustomObject]@{
                AppServiceName    = $WebApp.Name
                ResourceGroupName = $WebApp.ResourceGroup
                ExtensionName     = $Extension.name
                Version           = $Extension.properties.version
                ProvisioningState = $Extension.properties.provisioningState
                InstalledDateTime = $Extension.properties.installed_date_time
                Title             = $Extension.properties.title
                Description       = $Extension.properties.description
            }
        }
    } else {
        Write-Output "No extensions found for App Service: $($WebApp.Name)"
    }
}

# Check if there are any App Services with extensions installed
if ($Results.Count -gt 0) {
    # Output the total count of App Services which have extensions installed
    Write-Host ("`nTotal of App Services with installed extensions: {0}" -f $Results.Count) -ForegroundColor Yellow

    # Inform the user that the results are being displayed in Out-GridView
    Write-Host "`nDisplaying the results in Out-GridView..." -ForegroundColor Green

    # Display the results in Out-GridView with renamed columns
    $Results | Select-Object `
        @{Name='Name'; Expression={$_.AppServiceName}}, `
        @{Name='Resource Group'; Expression={$_.ResourceGroupName}}, `
        @{Name='Extension Title'; Expression={$_.Title}}, `
        @{Name='Version'; Expression={$_.Version}}, `
        @{Name='Provisioning State'; Expression={$_.ProvisioningState}}, `
        @{Name='Installed Date'; Expression={$_.InstalledDateTime}}, `
        @{Name='Description'; Expression={if ($_.Description.Length -gt 100) { $_.Description.Substring(0, 100) + '...' } else { $_.Description }}} `
        | Out-GridView -Title "App Services with Installed Extensions"

} else {
    Write-Host "`nNo extensions found within an Azure subscription. Exiting script..." -ForegroundColor Yellow
    exit
}
