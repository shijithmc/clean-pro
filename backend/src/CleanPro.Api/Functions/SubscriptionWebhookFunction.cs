using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Amazon.Lambda.APIGatewayEvents;
using Amazon.Lambda.Core;
using CleanPro.Application.DTOs;
using CleanPro.Application.Handlers;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;

namespace CleanPro.Api.Functions;

/// <summary>
/// Processes RevenueCat server-to-server webhook events.
/// Secured by HMAC-SHA256 signature verification.
/// Idempotent — duplicate events are silently ignored.
/// </summary>
public sealed class SubscriptionWebhookFunction : FunctionBase
{
    private readonly SubscriptionWebhookHandler _handler;
    private readonly ILogger<SubscriptionWebhookFunction> _logger;

    public SubscriptionWebhookFunction() : base()
    {
        _handler = Services.GetRequiredService<SubscriptionWebhookHandler>();
        _logger = Services.GetRequiredService<ILogger<SubscriptionWebhookFunction>>();
    }

    public async Task<APIGatewayProxyResponse> HandleAsync(
        APIGatewayProxyRequest request,
        ILambdaContext context)
    {
        try
        {
            // Verify HMAC-SHA256 signature from RevenueCat
            if (!VerifySignature(request))
            {
                _logger.LogWarning("RevenueCat webhook signature verification failed");
                return Unauthorized("Invalid webhook signature");
            }

            if (string.IsNullOrWhiteSpace(request.Body))
                return BadRequest("body", "Request body is required");

            var webhook = JsonSerializer.Deserialize<SubscriptionWebhookDto>(
                request.Body, JsonOptions);

            if (webhook?.Event is null)
                return BadRequest("event", "Webhook event payload is malformed");

            await _handler.HandleAsync(webhook);
            return Ok(new { processed = true });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Unhandled exception processing RevenueCat webhook");
            return InternalServerError();
        }
    }

    private bool VerifySignature(APIGatewayProxyRequest request)
    {
        var webhookSecret = System.Environment.GetEnvironmentVariable("REVENUECAT_WEBHOOK_SECRET");
        if (string.IsNullOrEmpty(webhookSecret))
        {
            _logger.LogError("REVENUECAT_WEBHOOK_SECRET environment variable not set");
            return false;
        }

        if (!request.Headers.TryGetValue("X-RevenueCat-Signature", out var signature)
            || string.IsNullOrWhiteSpace(signature))
        {
            return false;
        }

        var body = request.Body ?? string.Empty;
        var expectedSignature = ComputeHmacSha256(webhookSecret, body);

        // Constant-time comparison to prevent timing attacks
        return CryptographicOperations.FixedTimeEquals(
            Encoding.UTF8.GetBytes(signature),
            Encoding.UTF8.GetBytes(expectedSignature));
    }

    private static string ComputeHmacSha256(string secret, string payload)
    {
        using var hmac = new HMACSHA256(Encoding.UTF8.GetBytes(secret));
        var hash = hmac.ComputeHash(Encoding.UTF8.GetBytes(payload));
        return Convert.ToHexString(hash).ToLowerInvariant();
    }
}
