# Connect to Azure from Automation Account with its system-assigned managed identity
# Connect-AzAccount -Identity # Uncomment this line for running on the Automation Account

# Checking IP address ranges of Azure Event Grid service
$Url = "https://www.microsoft.com/en-us/download/details.aspx?id=56519"
try {
    $DownloadUrl = (Invoke-WebRequest $Url -ErrorAction Stop)
    $JsonFileLink = $DownloadUrl.Links `
        | Where-Object href -Like '*json' `
        | Select-Object href -first 1 `
        | Select-Object -ExpandProperty href
    $JsonFileResponse = Invoke-RestMethod $JsonFileLink

    $AzureService = @('AzureEventGrid.WestEurope')
    $ChangeNumber = $JsonFileResponse.values `
                  | Where-Object {$AzureService.contains($_.name)} `
                  | Select-Object -ExpandProperty properties `
                  | Select-Object -ExpandProperty changeNumber
    
    $OriChangeNumber = 2
    If ($ChangeNumber -gt $OriChangeNumber) {
        Write-Warning "WARNING! The IP address ranges of $AzureService service have been changed."
        $AddressPrefixes = $JsonFileResponse.values `
                         | Where-Object {$AzureService.contains($_.name)} `
                         | Select-Object -ExpandProperty properties `
                         | Select-Object -ExpandProperty addressPrefixes `
                         | ConvertTo-Json
        Write-Output "The new IP ranges of $AzureService service are: $AddressPrefixes"
    } Else {
        Write-Output ("No action required. The IP address ranges of $AzureService are not changed.")
    }
} catch {
    Write-Error "An error occurred: $($_.Exception.Message)"
}
