# Retrieve the minimum TLS version for all Event Grid topics across multiple subscriptions
# Login to Azure
Connect-AzAccount

# Get all subscriptions
$subscriptions = Get-AzSubscription

# Iterate through each subscription
foreach ($subscription in $subscriptions) {
    Set-AzContext -SubscriptionId $subscription.Id

    # Get all Event Grid topics in the current subscription
    $eventGridTopics = Get-AzEventGridTopic | Sort-Object -Property Name

    foreach ($topic in $eventGridTopics) {
        try {
            # Get the details for the Event Grid topic
            $topicDetails = Get-AzEventGridTopic -ResourceGroupName $topic.ResourceGroupName -Name $topic.Name

            # Get the minimum TLS version allowed
            $tlsVersion = $topicDetails.MinimumTlsVersionAllowed

            if (-not $tlsVersion) {
                $tlsVersion = "Not Set"
            }

            # Output the details
            Write-Output "Subscription: $($subscription.Name)"
            Write-Output "Event Grid Topic: $($topic.Name)"
            Write-Output "Minimum TLS Version Allowed: $tlsVersion"
            Write-Output "----------------------------------------"
        } catch {
            Write-Output "Error retrieving details for topic: $($topic.Name) in subscription: $($subscription.Name)"
            Write-Output "Exception: $_"
            Write-Output "----------------------------------------"
        }
    }
}

