using Amazon.DynamoDBv2.Model;
using CleanPro.Domain.Entities;
using CleanPro.Domain.Repositories;
using CleanPro.Domain.ValueObjects;
using CleanPro.Shared.Exceptions;
using Microsoft.Extensions.Logging;

namespace CleanPro.Infrastructure.DynamoDB.Repositories;

public sealed class UserProfileRepository : IUserProfileRepository
{
    private readonly DynamoDbContext _context;
    private readonly ILogger<UserProfileRepository> _logger;

    private const string EntityType = "UserProfile";

    public UserProfileRepository(DynamoDbContext context, ILogger<UserProfileRepository> logger)
    {
        _context = context;
        _logger = logger;
    }

    public async Task<UserProfile?> GetByUserIdAsync(UserId userId, CancellationToken ct = default)
    {
        var response = await _context.Client.GetItemAsync(new GetItemRequest
        {
            TableName = DynamoDbContext.TableName,
            Key = new Dictionary<string, AttributeValue>
            {
                ["PK"] = new() { S = $"USER#{userId.Value}" },
                ["SK"] = new() { S = "PROFILE" },
            },
            ConsistentRead = true,
        }, ct);

        if (response.Item.Count == 0) return null;
        return MapFromRecord(response.Item);
    }

    public async Task CreateAsync(UserProfile profile, CancellationToken ct = default)
    {
        var item = MapToRecord(profile);

        try
        {
            await _context.Client.PutItemAsync(new PutItemRequest
            {
                TableName = DynamoDbContext.TableName,
                Item = item,
                ConditionExpression = "attribute_not_exists(PK)",
            }, ct);
        }
        catch (ConditionalCheckFailedException)
        {
            throw new ConflictException($"User profile already exists for {profile.UserId}");
        }
    }

    public async Task UpdateAsync(UserProfile profile, CancellationToken ct = default)
    {
        var item = MapToRecord(profile);

        try
        {
            await _context.Client.PutItemAsync(new PutItemRequest
            {
                TableName = DynamoDbContext.TableName,
                Item = item,
                ConditionExpression = "attribute_exists(PK)",
            }, ct);
        }
        catch (ConditionalCheckFailedException)
        {
            throw new NotFoundException($"User profile not found for {profile.UserId}");
        }
    }

    private static Dictionary<string, AttributeValue> MapToRecord(UserProfile p) =>
        new()
        {
            ["PK"] = new() { S = $"USER#{p.UserId.Value}" },
            ["SK"] = new() { S = "PROFILE" },
            ["entityType"] = new() { S = EntityType },
            ["userId"] = new() { S = p.UserId.Value },
            ["email"] = new() { S = p.Email },
            ["createdAt"] = new() { S = p.CreatedAt.ToString("O") },
            ["updatedAt"] = new() { S = p.UpdatedAt.ToString("O") },
            ["trialStartedAt"] = p.TrialStartedAt.HasValue
                ? new() { S = p.TrialStartedAt.Value.ToString("O") }
                : new() { NULL = true },
            ["trialEndsAt"] = p.TrialEndsAt.HasValue
                ? new() { S = p.TrialEndsAt.Value.ToString("O") }
                : new() { NULL = true },
            ["totalPhotosScanned"] = new() { N = p.TotalPhotosScanned.ToString() },
            ["totalBytesReclaimed"] = new() { N = p.TotalBytesReclaimed.ToString() },
            ["lastScanAt"] = p.LastScanAt.HasValue
                ? new() { S = p.LastScanAt.Value.ToString("O") }
                : new() { NULL = true },
        };

    private static UserProfile MapFromRecord(Dictionary<string, AttributeValue> item)
    {
        // Reconstruct via reflection-safe factory approach using internal constructor
        // In production, use a dedicated mapper or record reconstruction pattern
        var profile = UserProfile.Reconstitute(
            userId: UserId.From(item["userId"].S),
            email: item["email"].S,
            createdAt: DateTime.Parse(item["createdAt"].S),
            updatedAt: DateTime.Parse(item["updatedAt"].S),
            trialStartedAt: item.TryGetValue("trialStartedAt", out var tsa) && !tsa.NULL
                ? DateTime.Parse(tsa.S) : null,
            trialEndsAt: item.TryGetValue("trialEndsAt", out var tea) && !tea.NULL
                ? DateTime.Parse(tea.S) : null,
            totalPhotosScanned: int.Parse(item["totalPhotosScanned"].N),
            totalBytesReclaimed: long.Parse(item["totalBytesReclaimed"].N),
            lastScanAt: item.TryGetValue("lastScanAt", out var lsa) && !lsa.NULL
                ? DateTime.Parse(lsa.S) : null);

        return profile;
    }
}
