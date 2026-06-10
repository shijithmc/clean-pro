using Amazon.DynamoDBv2;
using Amazon.DynamoDBv2.DocumentModel;
using Amazon.DynamoDBv2.Model;
using Microsoft.Extensions.Options;

namespace CleanPro.Infrastructure.DynamoDB;

public sealed class DynamoDbContext
{
    public const string TableName = "CleanPro";
    public const string Gsi1Name = "GSI1";
    public const string Gsi2Name = "GSI2";

    public IAmazonDynamoDB Client { get; }

    public DynamoDbContext(IAmazonDynamoDB client)
    {
        Client = client;
    }
}

public sealed class DynamoDbOptions
{
    public string TableName { get; set; } = DynamoDbContext.TableName;
    public string? ServiceUrl { get; set; } // Override for local DynamoDB
}
