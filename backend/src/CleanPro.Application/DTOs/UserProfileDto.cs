namespace CleanPro.Application.DTOs;

public sealed record UserProfileDto(
    string UserId,
    string Email,
    DateTime CreatedAt,
    DateTime UpdatedAt,
    DateTime? TrialStartedAt,
    DateTime? TrialEndsAt,
    int TotalPhotosScanned,
    long TotalBytesReclaimed,
    DateTime? LastScanAt);

public sealed record EntitlementDto(
    string UserId,
    string Status,
    string Tier,
    DateTime? CurrentPeriodEnd,
    int? DaysRemaining);

public sealed record SubscriptionWebhookDto(
    WebhookEventDto Event);

public sealed record WebhookEventDto(
    string Id,
    string Type,
    string AppUserId,
    long? PurchasedAtMs,
    long? ExpirationAtMs,
    string? ProductId,
    string? Store,
    long? AutoResumeAtMs);
