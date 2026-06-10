using Amazon.DynamoDBv2;
using Amazon.DynamoDBv2.Model;
using CleanPro.Domain.Entities;
using CleanPro.Domain.Repositories;
using CleanPro.Domain.ValueObjects;
using CleanPro.Shared.Exceptions;

namespace CleanPro.Infrastructure.DynamoDB.Repositories;

public sealed class SubscriptionRepository : ISubscriptionRepository
{
    private readonly DynamoDbContext _ctx;

    public SubscriptionRepository(DynamoDbContext ctx) => _ctx = ctx;

    public async Task<Subscription?> GetByUserIdAsync(UserId userId, CancellationToken ct = default)
    {
        var response = await _ctx.Client.GetItemAsync(new GetItemRequest
        {
            TableName = DynamoDbContext.TableName,
            Key = new Dictionary<string, AttributeValue>
            {
                ["PK"] = new() { S = $"USER#{userId.Value}" },
                ["SK"] = new() { S = "SUBSCRIPTION" },
            },
        }, ct);

        return response.Item.Count == 0 ? null : MapFromRecord(response.Item);
    }

    public async Task<Subscription?> GetByRcSubscriberIdAsync(string rcSubscriberId, CancellationToken ct = default)
    {
        var response = await _ctx.Client.QueryAsync(new QueryRequest
        {
            TableName = DynamoDbContext.TableName,
            IndexName = DynamoDbContext.Gsi1Name,
            KeyConditionExpression = "GSI1PK = :pk AND GSI1SK = :sk",
            ExpressionAttributeValues = new Dictionary<string, AttributeValue>
            {
                [":pk"] = new() { S = $"RC#{rcSubscriberId}" },
                [":sk"] = new() { S = "SUBSCRIPTION" },
            },
            Limit = 1,
        }, ct);

        return response.Items.Count == 0 ? null : MapFromRecord(response.Items[0]);
    }

    public async Task UpsertAsync(Subscription subscription, CancellationToken ct = default)
    {
        var item = new Dictionary<string, AttributeValue>
        {
            ["PK"] = new() { S = $"USER#{subscription.UserId.Value}" },
            ["SK"] = new() { S = "SUBSCRIPTION" },
            ["GSI1PK"] = new() { S = $"RC#{subscription.RcSubscriberId}" },
            ["GSI1SK"] = new() { S = "SUBSCRIPTION" },
            ["userId"] = new() { S = subscription.UserId.Value },
            ["rcSubscriberId"] = new() { S = subscription.RcSubscriberId },
            ["tier"] = new() { S = subscription.Tier.ToString() },
            ["status"] = new() { S = subscription.Status.ToString() },
            ["createdAt"] = new() { S = subscription.CreatedAt.ToString("O") },
            ["updatedAt"] = new() { S = subscription.UpdatedAt.ToString("O") },
        };

        if (subscription.CurrentPeriodStart.HasValue)
            item["currentPeriodStart"] = new() { S = subscription.CurrentPeriodStart.Value.ToString("O") };
        if (subscription.CurrentPeriodEnd.HasValue)
            item["currentPeriodEnd"] = new() { S = subscription.CurrentPeriodEnd.Value.ToString("O") };
        if (subscription.CancelledAt.HasValue)
            item["cancelledAt"] = new() { S = subscription.CancelledAt.Value.ToString("O") };
        if (subscription.GracePeriodEndsAt.HasValue)
            item["gracePeriodEndsAt"] = new() { S = subscription.GracePeriodEndsAt.Value.ToString("O") };
        if (subscription.ProductId is not null)
            item["productId"] = new() { S = subscription.ProductId };
        if (subscription.Platform != DevicePlatform.Unknown)
            item["platform"] = new() { S = subscription.Platform.ToString() };

        await _ctx.Client.PutItemAsync(new PutItemRequest
        {
            TableName = DynamoDbContext.TableName,
            Item = item,
        }, ct);
    }

    private static Subscription MapFromRecord(Dictionary<string, AttributeValue> item) =>
        Subscription.Reconstitute(
            userId: UserId.From(item["userId"].S),
            rcSubscriberId: item["rcSubscriberId"].S,
            tier: Enum.Parse<SubscriptionTier>(item["tier"].S),
            status: Enum.Parse<SubscriptionStatus>(item["status"].S),
            createdAt: DateTime.Parse(item["createdAt"].S),
            updatedAt: DateTime.Parse(item["updatedAt"].S),
            currentPeriodStart: item.TryGetValue("currentPeriodStart", out var cps)
                ? DateTime.Parse(cps.S) : null,
            currentPeriodEnd: item.TryGetValue("currentPeriodEnd", out var cpe)
                ? DateTime.Parse(cpe.S) : null,
            cancelledAt: item.TryGetValue("cancelledAt", out var ca)
                ? DateTime.Parse(ca.S) : null,
            gracePeriodEndsAt: item.TryGetValue("gracePeriodEndsAt", out var gpe)
                ? DateTime.Parse(gpe.S) : null,
            productId: item.TryGetValue("productId", out var pid) ? pid.S : null,
            platform: item.TryGetValue("platform", out var pl)
                ? Enum.Parse<DevicePlatform>(pl.S) : DevicePlatform.Unknown);
}
