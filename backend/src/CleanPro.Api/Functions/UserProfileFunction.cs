using System.Text.Json;
using Amazon.Lambda.APIGatewayEvents;
using Amazon.Lambda.Core;
using CleanPro.Application.Commands;
using CleanPro.Application.DTOs;
using CleanPro.Application.Handlers;
using CleanPro.Shared.Exceptions;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;

[assembly: LambdaSerializer(typeof(Amazon.Lambda.Serialization.SystemTextJson.DefaultLambdaJsonSerializer))]

namespace CleanPro.Api.Functions;

/// <summary>
/// Lambda function handling GET /users/me and POST /users/me.
/// Authenticated via Cognito authorizer — userId extracted from JWT sub claim.
/// </summary>
public sealed class UserProfileFunction : FunctionBase
{
    private readonly CreateUserProfileHandler _createHandler;
    private readonly GetEntitlementHandler _entitlementHandler;
    private readonly ILogger<UserProfileFunction> _logger;

    public UserProfileFunction() : base()
    {
        _createHandler = Services.GetRequiredService<CreateUserProfileHandler>();
        _entitlementHandler = Services.GetRequiredService<GetEntitlementHandler>();
        _logger = Services.GetRequiredService<ILogger<UserProfileFunction>>();
    }

    public async Task<APIGatewayProxyResponse> GetProfileAsync(
        APIGatewayProxyRequest request,
        ILambdaContext context)
    {
        try
        {
            var userId = ExtractUserId(request);
            var profileHandler = Services.GetRequiredService<CreateUserProfileHandler>();

            // GET returns existing or 404 — does not auto-create
            var profile = await GetExistingProfileAsync(userId);
            if (profile is null)
                return NotFound($"Profile not found for user {userId}");

            return Ok(profile);
        }
        catch (UnauthorizedException ex)
        {
            return Unauthorized(ex.Message);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Unhandled exception in GetProfile");
            return InternalServerError();
        }
    }

    public async Task<APIGatewayProxyResponse> CreateProfileAsync(
        APIGatewayProxyRequest request,
        ILambdaContext context)
    {
        try
        {
            var userId = ExtractUserId(request);
            var body = JsonSerializer.Deserialize<CreateProfileRequest>(request.Body ?? "{}",
                JsonOptions);

            if (string.IsNullOrWhiteSpace(body?.Email))
                return BadRequest("email", "Email is required");

            var command = new CreateUserProfileCommand(userId, body.Email);
            var (profile, isNew) = await _createHandler.HandleAsync(command);

            if (!isNew)
                return Conflict("A profile already exists for this user.");

            return Created($"/v1/users/me", profile);
        }
        catch (UnauthorizedException ex)
        {
            return Unauthorized(ex.Message);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Unhandled exception in CreateProfile");
            return InternalServerError();
        }
    }

    public async Task<APIGatewayProxyResponse> GetEntitlementAsync(
        APIGatewayProxyRequest request,
        ILambdaContext context)
    {
        try
        {
            var userId = ExtractUserId(request);
            var entitlement = await _entitlementHandler.HandleAsync(userId);
            return Ok(entitlement);
        }
        catch (UnauthorizedException ex)
        {
            return Unauthorized(ex.Message);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Unhandled exception in GetEntitlement");
            return InternalServerError();
        }
    }

    private Task<UserProfileDto?> GetExistingProfileAsync(string userId)
    {
        var repo = Services.GetRequiredService<CleanPro.Domain.Repositories.IUserProfileRepository>();
        var uid = CleanPro.Domain.ValueObjects.UserId.From(userId);
        return repo.GetByUserIdAsync(uid).ContinueWith(t => t.Result is null
            ? null
            : new UserProfileDto(
                t.Result.UserId.Value,
                t.Result.Email,
                t.Result.CreatedAt,
                t.Result.UpdatedAt,
                t.Result.TrialStartedAt,
                t.Result.TrialEndsAt,
                t.Result.TotalPhotosScanned,
                t.Result.TotalBytesReclaimed,
                t.Result.LastScanAt));
    }

    private sealed record CreateProfileRequest(string? Email);
}
