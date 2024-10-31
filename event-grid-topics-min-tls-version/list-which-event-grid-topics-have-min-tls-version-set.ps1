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

            # Check if the MinimumTlsVersionAllowed property is set and not empty
            if ($topicDetails.PSObject.Properties["MinimumTlsVersionAllowed"] -and $topicDetails.MinimumTlsVersionAllowed) {
                $tlsVersion = $topicDetails.MinimumTlsVersionAllowed

                # Output the details
                Write-Output "Subscription: $($subscription.Name)"
                Write-Output "Event Grid Topic: $($topic.Name)"
                Write-Output "Minimum TLS Version Allowed: $tlsVersion"
                Write-Output "----------------------------------------"
            }
        } catch {
            Write-Output "Error retrieving details for topic: $($topic.Name) in subscription: $($subscription.Name)"
            Write-Output "Exception: $_"
            Write-Output "----------------------------------------"
        }
    }
}
