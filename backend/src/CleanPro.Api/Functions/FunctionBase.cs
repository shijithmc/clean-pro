using System.Text.Json;
using System.Text.Json.Serialization;
using Amazon.DynamoDBv2;
using Amazon.Lambda.APIGatewayEvents;
using Amazon.Lambda.Core;
using CleanPro.Application.Handlers;
using CleanPro.Domain.Repositories;
using CleanPro.Infrastructure.DynamoDB;
using CleanPro.Infrastructure.DynamoDB.Repositories;
using CleanPro.Shared.Exceptions;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;

namespace CleanPro.Api.Functions;

/// <summary>
/// Base class for all Lambda function handlers.
/// Builds the DI container once per Lambda cold start.
/// </summary>
public abstract class FunctionBase
{
    protected IServiceProvider Services { get; }

    protected static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
    };

    protected FunctionBase()
    {
        var services = new ServiceCollection();
        ConfigureServices(services);
        Services = services.BuildServiceProvider();
    }

    protected virtual void ConfigureServices(IServiceCollection services)
    {
        services.AddLogging(b => b.AddLambdaLogger());

        // AWS DynamoDB
        services.AddSingleton<IAmazonDynamoDB>(_ =>
        {
            var serviceUrl = System.Environment.GetEnvironmentVariable("DYNAMODB_SERVICE_URL");
            if (!string.IsNullOrEmpty(serviceUrl))
            {
                // Local development
                var config = new AmazonDynamoDBConfig { ServiceURL = serviceUrl };
                return new AmazonDynamoDBClient(config);
            }
            return new AmazonDynamoDBClient();
        });

        services.AddSingleton<DynamoDbContext>();

        // Repositories
        services.AddScoped<IUserProfileRepository, UserProfileRepository>();
        services.AddScoped<ISubscriptionRepository, SubscriptionRepository>();
        services.AddScoped<IWebhookIdempotencyRepository, WebhookIdempotencyRepository>();

        // Application handlers
        services.AddScoped<CreateUserProfileHandler>();
        services.AddScoped<GetEntitlementHandler>();
        services.AddScoped<SubscriptionWebhookHandler>();
        services.AddScoped<RecordScanStatsHandler>();
    }

    protected string ExtractUserId(APIGatewayProxyRequest request)
    {
        // Cognito authorizer injects claims into requestContext
        if (request.RequestContext?.Authorizer?.Claims?.TryGetValue("sub", out var sub) == true
            && !string.IsNullOrWhiteSpace(sub))
        {
            return sub;
        }

        throw new UnauthorizedException("Missing or invalid Cognito JWT — sub claim not found.");
    }

    protected APIGatewayProxyResponse Ok<T>(T body) => new()
    {
        StatusCode = 200,
        Headers = new Dictionary<string, string> { ["Content-Type"] = "application/json" },
        Body = JsonSerializer.Serialize(body, JsonOptions),
    };

    protected APIGatewayProxyResponse Created<T>(string location, T body) => new()
    {
        StatusCode = 201,
        Headers = new Dictionary<string, string>
        {
            ["Content-Type"] = "application/json",
            ["Location"] = location,
        },
        Body = JsonSerializer.Serialize(body, JsonOptions),
    };

    protected APIGatewayProxyResponse NoContent() => new() { StatusCode = 204 };

    protected APIGatewayProxyResponse BadRequest(string field, string message) => Problem(400,
        "https://api.cleanpro.app/errors/validation",
        "Validation Error",
        message,
        new Dictionary<string, string[]> { [field] = [message] });

    protected APIGatewayProxyResponse NotFound(string detail) => Problem(404,
        "https://api.cleanpro.app/errors/not-found", "Not Found", detail);

    protected APIGatewayProxyResponse Conflict(string detail) => Problem(409,
        "https://api.cleanpro.app/errors/conflict", "Conflict", detail);

    protected APIGatewayProxyResponse Unauthorized(string detail = "Unauthorized") => Problem(401,
        "https://api.cleanpro.app/errors/unauthorized", "Unauthorized", detail);

    protected APIGatewayProxyResponse InternalServerError() => Problem(500,
        "https://api.cleanpro.app/errors/internal", "Internal Server Error",
        "An unexpected error occurred.");

    private APIGatewayProxyResponse Problem(
        int status,
        string type,
        string title,
        string detail,
        Dictionary<string, string[]>? errors = null)
    {
        var body = new ProblemDetailsResponse(type, title, status, detail, errors);
        return new APIGatewayProxyResponse
        {
            StatusCode = status,
            Headers = new Dictionary<string, string> { ["Content-Type"] = "application/problem+json" },
            Body = JsonSerializer.Serialize(body, JsonOptions),
        };
    }

    private sealed record ProblemDetailsResponse(
        string Type,
        string Title,
        int Status,
        string Detail,
        Dictionary<string, string[]>? Errors = null);
}
