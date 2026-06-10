using CleanPro.Domain.Entities;
using CleanPro.Domain.ValueObjects;

namespace CleanPro.Domain.Repositories;

public interface ISubscriptionRepository
{
    Task<Subscription?> GetByUserIdAsync(UserId userId, CancellationToken ct = default);

    Task<Subscription?> GetByRcSubscriberIdAsync(string rcSubscriberId, CancellationToken ct = default);

    /// <summary>Creates or fully replaces the subscription for this user.</summary>
    Task UpsertAsync(Subscription subscription, CancellationToken ct = default);
}
