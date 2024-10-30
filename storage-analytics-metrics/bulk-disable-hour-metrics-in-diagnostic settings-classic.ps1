$ResourceGroupName = "YourResourceGroupName"
Write-Host "Starting the process to turn off Diagnostic settings (classic) of related Storage Accounts..." -ForegroundColor Green
$StorageAccounts = (Get-AzStorageAccount -ResourceGroupName $ResourceGroupName)

ForEach ($StorageAccount in $StorageAccounts) {  
    $StorageContext = $StorageAccount.Context
    Write-Host "Turning off the Diagnostic settings (classic) of the Storage Account: $($StorageAccount.StorageAccountName)" -ForegroundColor Blue
    Set-AzStorageServiceMetricsProperty -MetricsType Hour -MetricsLevel None -Context $StorageContext -ServiceType Blob
    Set-AzStorageServiceMetricsProperty -MetricsType Hour -MetricsLevel None -Context $StorageContext -ServiceType File
    Set-AzStorageServiceMetricsProperty -MetricsType Hour -MetricsLevel None -Context $StorageContext -ServiceType Table
    Set-AzStorageServiceMetricsProperty -MetricsType Hour -MetricsLevel None -Context $StorageContext -ServiceType Queue
}
