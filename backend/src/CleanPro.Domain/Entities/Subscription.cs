using CleanPro.Domain.Events;
using CleanPro.Domain.ValueObjects;

namespace CleanPro.Domain.Entities;

/// <summary>
/// Subscription aggregate — owns tier, status, and period lifecycle.
/// Updated by RevenueCat webhook events only.
/// </summary>
public sealed class Subscription
{
    private Subscription() { }

    public UserId UserId { get; private set; }
    public string RcSubscriberId { get; private set; } = null!;
    public SubscriptionTier Tier { get; private set; }
    public SubscriptionStatus Status { get; private set; }
    public DateTime? CurrentPeriodStart { get; private set; }
    public DateTime? CurrentPeriodEnd { get; private set; }
    public DateTime? CancelledAt { get; private set; }
    public DateTime? GracePeriodEndsAt { get; private set; }
    public string? ProductId { get; private set; }
    public bool AutoRenew { get; private set; }
    public DevicePlatform Platform { get; private set; }
    public DateTime CreatedAt { get; private set; }
    public DateTime UpdatedAt { get; private set; }

    private readonly List<IDomainEvent> _domainEvents = [];
    public IReadOnlyList<IDomainEvent> DomainEvents => _domainEvents.AsReadOnly();

    public static Subscription Activate(
        UserId userId,
        string rcSubscriberId,
        SubscriptionTier tier,
        DateTime periodStart,
        DateTime periodEnd,
        DevicePlatform platform,
        string? productId = null)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(rcSubscriberId);
        if (periodEnd <= periodStart) throw new ArgumentException("Period end must be after period start.");

        var now = DateTime.UtcNow;
        var sub = new Subscription
        {
            UserId = userId,
            RcSubscriberId = rcSubscriberId,
            Tier = tier,
            Status = SubscriptionStatus.Active,
            CurrentPeriodStart = periodStart,
            CurrentPeriodEnd = periodEnd,
            AutoRenew = true,
            Platform = platform,
            ProductId = productId,
            CreatedAt = now,
            UpdatedAt = now,
        };

        sub._domainEvents.Add(new SubscriptionActivatedEvent(userId, tier, periodEnd));
        return sub;
    }

    public void Renew(DateTime newPeriodStart, DateTime newPeriodEnd)
    {
        if (newPeriodEnd <= newPeriodStart) throw new ArgumentException("New period end must be after new period start.");

        CurrentPeriodStart = newPeriodStart;
        CurrentPeriodEnd = newPeriodEnd;
        Status = SubscriptionStatus.Active;
        AutoRenew = true;
        GracePeriodEndsAt = null;
        UpdatedAt = DateTime.UtcNow;
    }

    public void Cancel()
    {
        Status = SubscriptionStatus.Cancelled;
        AutoRenew = false;
        CancelledAt = DateTime.UtcNow;
        UpdatedAt = DateTime.UtcNow;
        _domainEvents.Add(new SubscriptionExpiredEvent(UserId, CurrentPeriodEnd ?? UpdatedAt));
    }

    public void MarkExpired()
    {
        Status = SubscriptionStatus.Expired;
        UpdatedAt = DateTime.UtcNow;
        _domainEvents.Add(new SubscriptionExpiredEvent(UserId, CurrentPeriodEnd ?? UpdatedAt));
    }

    public void SetGracePeriod(DateTime gracePeriodEnd)
    {
        Status = SubscriptionStatus.GracePeriod;
        GracePeriodEndsAt = gracePeriodEnd;
        UpdatedAt = DateTime.UtcNow;
    }

    public bool IsAccessGranted() =>
        Status is SubscriptionStatus.Active or SubscriptionStatus.Cancelled
        && CurrentPeriodEnd.HasValue && DateTime.UtcNow <= CurrentPeriodEnd.Value
        || Status == SubscriptionStatus.GracePeriod
        && GracePeriodEndsAt.HasValue && DateTime.UtcNow <= GracePeriodEndsAt.Value;

    public void ClearDomainEvents() => _domainEvents.Clear();

    /// <summary>Reconstitutes a Subscription from DynamoDB — no domain events raised.</summary>
    public static Subscription Reconstitute(
        UserId userId,
        string rcSubscriberId,
        SubscriptionTier tier,
        SubscriptionStatus status,
        DateTime createdAt,
        DateTime updatedAt,
        DateTime? currentPeriodStart,
        DateTime? currentPeriodEnd,
        DateTime? cancelledAt,
        DateTime? gracePeriodEndsAt,
        string? productId,
        DevicePlatform platform) => new()
        {
            UserId = userId,
            RcSubscriberId = rcSubscriberId,
            Tier = tier,
            Status = status,
            CreatedAt = createdAt,
            UpdatedAt = updatedAt,
            CurrentPeriodStart = currentPeriodStart,
            CurrentPeriodEnd = currentPeriodEnd,
            CancelledAt = cancelledAt,
            GracePeriodEndsAt = gracePeriodEndsAt,
            ProductId = productId,
            Platform = platform,
        };
}
