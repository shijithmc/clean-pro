using Amazon.DynamoDBv2.Model;
using CleanPro.Application.Handlers;
using CleanPro.Infrastructure.DynamoDB;

namespace CleanPro.Infrastructure.DynamoDB.Repositories;

/// <summary>
/// DynamoDB implementation of webhook idempotency tracking.
/// Uses TTL (48 h) so processed event IDs expire automatically.
/// </summary>
public sealed class WebhookIdempotencyRepository : IWebhookIdempotencyRepository
{
    private const string IdempotencyPrefix = "WEBHOOK#";
    private const string IdempotencySK = "IDEMPOTENCY";
    private static readonly TimeSpan Ttl = TimeSpan.FromHours(48);

    private readonly DynamoDbContext _ctx;

    public WebhookIdempotencyRepository(DynamoDbContext ctx) => _ctx = ctx;

    public async Task<bool> HasBeenProcessedAsync(string eventId, CancellationToken ct = default)
    {
        var response = await _ctx.Client.GetItemAsync(new GetItemRequest
        {
            TableName = DynamoDbContext.TableName,
            Key = new Dictionary<string, AttributeValue>
            {
                ["PK"] = new() { S = $"{IdempotencyPrefix}{eventId}" },
                ["SK"] = new() { S = IdempotencySK },
            },
            ProjectionExpression = "PK",
        }, ct);

        return response.Item.Count > 0;
    }

    public async Task MarkProcessedAsync(string eventId, CancellationToken ct = default)
    {
        var ttlUnix = DateTimeOffset.UtcNow.Add(Ttl).ToUnixTimeSeconds();

        await _ctx.Client.PutItemAsync(new PutItemRequest
        {
            TableName = DynamoDbContext.TableName,
            Item = new Dictionary<string, AttributeValue>
            {
                ["PK"] = new() { S = $"{IdempotencyPrefix}{eventId}" },
                ["SK"] = new() { S = IdempotencySK },
                ["eventId"] = new() { S = eventId },
                ["processedAt"] = new() { S = DateTime.UtcNow.ToString("O") },
                ["TTL"] = new() { N = ttlUnix.ToString() },
            },
            ConditionExpression = "attribute_not_exists(PK)",
        }, ct);
    }
}
