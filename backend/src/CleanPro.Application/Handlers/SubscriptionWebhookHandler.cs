using CleanPro.Application.DTOs;
using CleanPro.Domain.Entities;
using CleanPro.Domain.Repositories;
using CleanPro.Domain.ValueObjects;
using CleanPro.Shared.Exceptions;
using Microsoft.Extensions.Logging;

namespace CleanPro.Application.Handlers;

public sealed class SubscriptionWebhookHandler
{
    private readonly ISubscriptionRepository _subscriptionRepository;
    private readonly IWebhookIdempotencyRepository _idempotencyRepository;
    private readonly ILogger<SubscriptionWebhookHandler> _logger;

    public SubscriptionWebhookHandler(
        ISubscriptionRepository subscriptionRepository,
        IWebhookIdempotencyRepository idempotencyRepository,
        ILogger<SubscriptionWebhookHandler> logger)
    {
        _subscriptionRepository = subscriptionRepository;
        _idempotencyRepository = idempotencyRepository;
        _logger = logger;
    }

    public async Task HandleAsync(SubscriptionWebhookDto webhook, CancellationToken ct = default)
    {
        var evt = webhook.Event;

        // Idempotency check — RevenueCat may deliver the same event more than once
        if (await _idempotencyRepository.HasBeenProcessedAsync(evt.Id, ct))
        {
            _logger.LogInformation("Skipping duplicate webhook event {EventId}", evt.Id);
            return;
        }

        var userId = UserId.From(evt.AppUserId);

        switch (evt.Type.ToUpperInvariant())
        {
            case "INITIAL_PURCHASE":
            case "RENEWAL":
            case "PRODUCT_CHANGE":
                await HandleActivationAsync(userId, evt, ct);
                break;

            case "CANCELLATION":
                await HandleCancellationAsync(userId, ct);
                break;

            case "EXPIRATION":
                await HandleExpirationAsync(userId, ct);
                break;

            case "BILLING_ISSUE":
                await HandleBillingIssueAsync(userId, ct);
                break;

            default:
                _logger.LogWarning("Unhandled RevenueCat event type {EventType}", evt.Type);
                break;
        }

        // Record event to prevent duplicate processing (TTL 48h handled by DynamoDB)
        await _idempotencyRepository.MarkProcessedAsync(evt.Id, ct);
    }

    private async Task HandleActivationAsync(UserId userId, WebhookEventDto evt, CancellationToken ct)
    {
        var tier = evt.ProductId?.Contains("annual", StringComparison.OrdinalIgnoreCase) == true
            ? SubscriptionTier.Annual
            : SubscriptionTier.Monthly;

        var periodStart = evt.PurchasedAtMs.HasValue
            ? DateTimeOffset.FromUnixTimeMilliseconds(evt.PurchasedAtMs.Value).UtcDateTime
            : DateTime.UtcNow;

        var periodEnd = evt.ExpirationAtMs.HasValue
            ? DateTimeOffset.FromUnixTimeMilliseconds(evt.ExpirationAtMs.Value).UtcDateTime
            : periodStart.AddMonths(tier == SubscriptionTier.Annual ? 12 : 1);

        var platform = evt.Store?.ToUpperInvariant() switch
        {
            "APP_STORE" => DevicePlatform.iOS,
            "PLAY_STORE" => DevicePlatform.Android,
            _ => DevicePlatform.Unknown,
        };

        var existing = await _subscriptionRepository.GetByUserIdAsync(userId, ct);
        if (existing is not null)
        {
            existing.Renew(periodStart, periodEnd);
            await _subscriptionRepository.UpsertAsync(existing, ct);
        }
        else
        {
            var subscription = Subscription.Activate(
                userId, evt.AppUserId, tier, periodStart, periodEnd, platform);
            await _subscriptionRepository.UpsertAsync(subscription, ct);
        }

        _logger.LogInformation(
            "Subscription activated for {UserId}: {Tier} until {PeriodEnd}",
            userId, tier, periodEnd);
    }

    private async Task HandleCancellationAsync(UserId userId, CancellationToken ct)
    {
        var subscription = await _subscriptionRepository.GetByUserIdAsync(userId, ct);
        if (subscription is null)
        {
            _logger.LogWarning("Cancellation received for unknown user {UserId}", userId);
            return;
        }
        subscription.Cancel();
        await _subscriptionRepository.UpsertAsync(subscription, ct);
    }

    private async Task HandleExpirationAsync(UserId userId, CancellationToken ct)
    {
        var subscription = await _subscriptionRepository.GetByUserIdAsync(userId, ct);
        if (subscription is null) return;
        subscription.MarkExpired();
        await _subscriptionRepository.UpsertAsync(subscription, ct);
    }

    private async Task HandleBillingIssueAsync(UserId userId, CancellationToken ct)
    {
        var subscription = await _subscriptionRepository.GetByUserIdAsync(userId, ct);
        if (subscription is null) return;
        // 14-day grace period from current period end (or now if no period)
        var gracePeriodEnd = subscription.CurrentPeriodEnd.HasValue
            ? subscription.CurrentPeriodEnd.Value.AddDays(14)
            : DateTime.UtcNow.AddDays(14);
        subscription.SetGracePeriod(gracePeriodEnd);
        await _subscriptionRepository.UpsertAsync(subscription, ct);
    }
}

public interface IWebhookIdempotencyRepository
{
    Task<bool> HasBeenProcessedAsync(string eventId, CancellationToken ct = default);
    Task MarkProcessedAsync(string eventId, CancellationToken ct = default);
}
