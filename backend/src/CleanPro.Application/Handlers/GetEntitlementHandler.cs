using CleanPro.Application.DTOs;
using CleanPro.Domain.Repositories;
using CleanPro.Domain.ValueObjects;
using Microsoft.Extensions.Logging;

namespace CleanPro.Application.Handlers;

public sealed class GetEntitlementHandler
{
    private readonly IUserProfileRepository _profileRepository;
    private readonly ISubscriptionRepository _subscriptionRepository;
    private readonly ILogger<GetEntitlementHandler> _logger;

    public GetEntitlementHandler(
        IUserProfileRepository profileRepository,
        ISubscriptionRepository subscriptionRepository,
        ILogger<GetEntitlementHandler> logger)
    {
        _profileRepository = profileRepository;
        _subscriptionRepository = subscriptionRepository;
        _logger = logger;
    }

    public async Task<EntitlementDto> HandleAsync(string userId, CancellationToken ct = default)
    {
        var uid = UserId.From(userId);
        var profile = await _profileRepository.GetByUserIdAsync(uid, ct);

        if (profile is null)
        {
            return new EntitlementDto(userId, "NONE", "NONE", null, null);
        }

        // Check active paid subscription first
        var subscription = await _subscriptionRepository.GetByUserIdAsync(uid, ct);
        if (subscription is not null && subscription.IsAccessGranted())
        {
            var daysLeft = subscription.CurrentPeriodEnd.HasValue
                ? (int)(subscription.CurrentPeriodEnd.Value - DateTime.UtcNow).TotalDays
                : 0;
            return new EntitlementDto(
                UserId: userId,
                Status: subscription.Status.ToString().ToUpperInvariant(),
                Tier: subscription.Tier.ToString().ToUpperInvariant(),
                CurrentPeriodEnd: subscription.CurrentPeriodEnd,
                DaysRemaining: Math.Max(0, daysLeft));
        }

        // Fall back to trial
        if (profile.IsTrialActive())
        {
            var trialDaysLeft = (int)(profile.TrialEndsAt!.Value - DateTime.UtcNow).TotalDays;
            return new EntitlementDto(
                UserId: userId,
                Status: "TRIAL",
                Tier: "FREE_TRIAL",
                CurrentPeriodEnd: profile.TrialEndsAt,
                DaysRemaining: Math.Max(0, trialDaysLeft));
        }

        // Trial expired, no active subscription
        return new EntitlementDto(
            UserId: userId,
            Status: "EXPIRED",
            Tier: "NONE",
            CurrentPeriodEnd: profile.TrialEndsAt,
            DaysRemaining: 0);
    }
}
