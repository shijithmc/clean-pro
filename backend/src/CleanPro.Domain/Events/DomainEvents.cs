using CleanPro.Domain.ValueObjects;

namespace CleanPro.Domain.Events;

public interface IDomainEvent
{
    DateTime OccurredAt { get; }
}

public sealed record UserProfileCreatedEvent(
    UserId UserId,
    DateTime OccurredAt,
    DateTime TrialEndsAt) : IDomainEvent;

public sealed record SubscriptionActivatedEvent(
    UserId UserId,
    SubscriptionTier Tier,
    DateTime PeriodEnd,
    DateTime OccurredAt = default) : IDomainEvent
{
    public DateTime OccurredAt { get; } = OccurredAt == default ? DateTime.UtcNow : OccurredAt;
}

public sealed record SubscriptionExpiredEvent(
    UserId UserId,
    DateTime PeriodEnd,
    DateTime OccurredAt = default) : IDomainEvent
{
    public DateTime OccurredAt { get; } = OccurredAt == default ? DateTime.UtcNow : OccurredAt;
}
