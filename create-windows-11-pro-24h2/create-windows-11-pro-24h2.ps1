param (
    [string]$ResourceGroup = "YourResourceGroupName",
    [string]$VmName = "YourVmName",
    [string]$DnsName = "yourdnsname",
    [string]$VnetName = "YourVnetName",
    [string]$SubnetName = "YourSubnetName",
    [string]$Location = "southeastasia",
    [string]$AdminUsername = "YourAdminUsername",
    [string]$AdminPassword = "YourPassword123!",
    [string]$AddressPrefix = "10.11.0.0/16",
    [string]$SubnetPrefix = "10.11.0.0/24",
    [string]$PublisherName = "MicrosoftWindowsDesktop",
    [string]$Offer = "windows-11",
    [string]$Skus = "win11-24h2-pro",
    [string]$Version = "latest",
    [string]$VmSize = "Standard_B2s"
)

# Validate the DNS name
if ($DnsName -notmatch '^[a-z][a-z0-9-]{1,61}[a-z0-9]$') {
    throw "The DNS name label '$DnsName' is invalid. It must start with a letter, can contain letters, numbers, and hyphens, and must end with a letter or number."
}

# Create a virtual network
New-AzVirtualNetwork -ResourceGroupName $ResourceGroup -Location $Location -Name $VnetName -AddressPrefix $AddressPrefix -Subnet @{"Name" = $SubnetName; "AddressPrefix" = $SubnetPrefix}

# Create a public IP address with Static allocation
$PublicIp = New-AzPublicIpAddress -ResourceGroupName $ResourceGroup -Location $Location -Name "${VmName}PublicIP" -AllocationMethod Static -Sku Standard
$PublicIp.DnsSettings = New-Object Microsoft.Azure.Commands.Network.Models.PSPublicIpAddressDnsSettings
$PublicIp.DnsSettings.DomainNameLabel = $DnsName
$PublicIp | Set-AzPublicIpAddress

# Create a network security group
$Nsg = New-AzNetworkSecurityGroup -ResourceGroupName $ResourceGroup -Location $Location -Name "${VmName}NSG"

# Create a network security group rule to allow RDP
$NsgRule = New-AzNetworkSecurityRuleConfig -Name "AllowRDP" -Protocol "Tcp" -Direction "Inbound" -Priority 1000 -SourceAddressPrefix "*" -SourcePortRange "*" -DestinationAddressPrefix "*" -DestinationPortRange 3389 -Access "Allow"
$Nsg.SecurityRules.Add($NsgRule)
$Nsg | Set-AzNetworkSecurityGroup

# Create a virtual network interface and associate with public IP address and NSG
$Nic = New-AzNetworkInterface -ResourceGroupName $ResourceGroup -Location $Location -Name "${VmName}NIC" -SubnetId (Get-AzVirtualNetwork -ResourceGroupName $ResourceGroup -Name $VnetName).Subnets[0].Id -PublicIpAddressId $PublicIp.Id -NetworkSecurityGroupId $Nsg.Id

# Create a virtual machine without boot diagnostics
$VmConfig = New-AzVMConfig -VMName $VmName -VMSize $VmSize | `
    Set-AzVMOperatingSystem -Windows -ComputerName $VmName -Credential (New-Object PSCredential -ArgumentList $AdminUsername, (ConvertTo-SecureString -String $AdminPassword -AsPlainText -Force)) | `
    Set-AzVMSourceImage -PublisherName $PublisherName -Offer $Offer -Skus $Skus -Version $Version | `
    Add-AzVMNetworkInterface -Id $Nic.Id | `
    Set-AzVMOSDisk -CreateOption FromImage -StorageAccountType "Standard_LRS"

# Disable boot diagnostics in the VM configuration
$VmConfig.DiagnosticsProfile = New-Object Microsoft.Azure.Management.Compute.Models.DiagnosticsProfile
$VmConfig.DiagnosticsProfile.BootDiagnostics = New-Object Microsoft.Azure.Management.Compute.Models.BootDiagnostics
$VmConfig.DiagnosticsProfile.BootDiagnostics.Enabled = $false

New-AzVM -ResourceGroupName $ResourceGroup -Location $Location -VM $VmConfig

# Open port 3389 to allow RDP traffic (if not already added)
if (-not ($Nsg.SecurityRules | Where-Object { $_.Name -eq "AllowRDP" })) {
    Get-AzNetworkSecurityGroup -ResourceGroupName $ResourceGroup -Name "${VmName}NSG" | Add-AzNetworkSecurityRuleConfig -Name "AllowRDP" -Protocol "Tcp" -Direction "Inbound" -Priority 1000 -SourceAddressPrefix "*" -SourcePortRange "*" -DestinationAddressPrefix "*" -DestinationPortRange 3389 -Access "Allow" | Set-AzNetworkSecurityGroup
}
