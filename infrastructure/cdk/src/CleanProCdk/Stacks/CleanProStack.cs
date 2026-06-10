using Amazon.CDK;
using Amazon.CDK.AWS.APIGateway;
using Amazon.CDK.AWS.CertificateManager;
using Amazon.CDK.AWS.Cognito;
using Amazon.CDK.AWS.DynamoDB;
using Amazon.CDK.AWS.IAM;
using Amazon.CDK.AWS.Lambda;
using Amazon.CDK.AWS.Logs;
using Amazon.CDK.AWS.SNS;
using Amazon.CDK.AWS.SNS.Subscriptions;
using Amazon.CDK.AWS.CloudWatch;
using Amazon.CDK.AWS.CloudWatch.Actions;
using Amazon.CDK.AWS.SecretsManager;
using Constructs;

namespace CleanProCdk.Stacks;

public sealed class CleanProStack : Stack
{
    public CleanProStack(Construct scope, string id, IStackProps? props = null)
        : base(scope, id, props)
    {
        var env = (string)this.Node.TryGetContext("env") ?? "dev";
        var isProd = env == "prod";

        // ── DynamoDB single table ───────────────────────────────────────────
        var table = new Table(this, "CleanProTable", new TableProps
        {
            TableName = $"CleanPro-{env}",
            PartitionKey = new Attribute { Name = "PK", Type = AttributeType.STRING },
            SortKey = new Attribute { Name = "SK", Type = AttributeType.STRING },
            BillingMode = BillingMode.PAY_PER_REQUEST,
            Encryption = TableEncryption.AWS_MANAGED,
            RemovalPolicy = isProd ? RemovalPolicy.RETAIN : RemovalPolicy.DESTROY,
            PointInTimeRecovery = isProd,
            TimeToLiveAttribute = "TTL",
        });

        // GSI1: RevenueCat subscriber ID lookup
        table.AddGlobalSecondaryIndex(new GlobalSecondaryIndexProps
        {
            IndexName = "GSI1",
            PartitionKey = new Attribute { Name = "gsi1Pk", Type = AttributeType.STRING },
            SortKey = new Attribute { Name = "gsi1Sk", Type = AttributeType.STRING },
            ProjectionType = ProjectionType.ALL,
        });

        // GSI2: Status-based subscription queries
        table.AddGlobalSecondaryIndex(new GlobalSecondaryIndexProps
        {
            IndexName = "GSI2",
            PartitionKey = new Attribute { Name = "gsi2Pk", Type = AttributeType.STRING },
            SortKey = new Attribute { Name = "gsi2Sk", Type = AttributeType.STRING },
            ProjectionType = ProjectionType.ALL,
        });

        // ── Cognito User Pool ───────────────────────────────────────────────
        var userPool = new UserPool(this, "CleanProUserPool", new UserPoolProps
        {
            UserPoolName = $"clean-pro-{env}",
            SelfSignUpEnabled = true,
            AutoVerify = new AutoVerifiedAttrs { Email = true },
            StandardAttributes = new StandardAttributes
            {
                Email = new StandardAttribute { Required = true, Mutable = true },
            },
            PasswordPolicy = new PasswordPolicy
            {
                MinLength = 8,
                RequireDigits = true,
                RequireLowercase = true,
                RequireUppercase = false,
                RequireSymbols = false,
            },
            AccountRecovery = AccountRecovery.EMAIL_ONLY,
            RemovalPolicy = isProd ? RemovalPolicy.RETAIN : RemovalPolicy.DESTROY,
            DeletionProtection = isProd,
        });

        var userPoolClient = userPool.AddClient("MobileClient", new UserPoolClientOptions
        {
            UserPoolClientName = "mobile",
            AuthFlows = new AuthFlow
            {
                UserSrp = true,
                UserPassword = false,
            },
            GenerateSecret = false,
            AccessTokenValidity = Duration.Hours(1),
            RefreshTokenValidity = Duration.Days(30),
            EnableTokenRevocation = true,
        });

        // ── Secrets Manager ─────────────────────────────────────────────────
        var rcWebhookSecret = new Secret(this, "RevenueCatWebhookSecret", new SecretProps
        {
            SecretName = $"/clean-pro/{env}/revenuecat-webhook-secret",
            Description = "RevenueCat webhook HMAC secret for signature verification",
        });

        // ── Lambda execution role ────────────────────────────────────────────
        var lambdaRole = new Role(this, "LambdaExecutionRole", new RoleProps
        {
            AssumedBy = new ServicePrincipal("lambda.amazonaws.com"),
            ManagedPolicies = [ManagedPolicy.FromAwsManagedPolicyName("service-role/AWSLambdaBasicExecutionRole")],
        });

        // Least-privilege: DynamoDB access scoped to this table only
        lambdaRole.AddToPolicy(new PolicyStatement(new PolicyStatementProps
        {
            Effect = Effect.ALLOW,
            Actions = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:UpdateItem", "dynamodb:Query"],
            Resources = [table.TableArn, $"{table.TableArn}/index/*"],
        }));

        // Secrets Manager read access for webhook secret
        lambdaRole.AddToPolicy(new PolicyStatement(new PolicyStatementProps
        {
            Effect = Effect.ALLOW,
            Actions = ["secretsmanager:GetSecretValue"],
            Resources = [rcWebhookSecret.SecretArn],
        }));

        // ── Lambda functions ─────────────────────────────────────────────────
        var commonEnv = new Dictionary<string, string>
        {
            ["DYNAMODB_TABLE"] = table.TableName,
            ["COGNITO_USER_POOL_ID"] = userPool.UserPoolId,
            ["ASPNETCORE_ENVIRONMENT"] = env == "prod" ? "Production" : "Development",
        };

        var lambdaCode = Code.FromAsset("../backend/publish");

        var userProfileFn = new Function(this, "UserProfileFunction", new FunctionProps
        {
            FunctionName = $"clean-pro-{env}-user-profile",
            Runtime = Runtime.DOTNET_8,
            Handler = "CleanPro.Api::CleanPro.Api.Functions.UserProfileFunction::HandleAsync",
            Code = lambdaCode,
            Role = lambdaRole,
            MemorySize = 512,
            Timeout = Duration.Seconds(30),
            Environment = commonEnv,
            LogRetention = isProd ? RetentionDays.ONE_YEAR : RetentionDays.ONE_WEEK,
            Tracing = Tracing.ACTIVE,
        });

        var webhookFn = new Function(this, "WebhookFunction", new FunctionProps
        {
            FunctionName = $"clean-pro-{env}-webhook",
            Runtime = Runtime.DOTNET_8,
            Handler = "CleanPro.Api::CleanPro.Api.Functions.SubscriptionWebhookFunction::HandleAsync",
            Code = lambdaCode,
            Role = lambdaRole,
            MemorySize = 256,
            Timeout = Duration.Seconds(30),
            Environment = new Dictionary<string, string>(commonEnv)
            {
                ["REVENUECAT_WEBHOOK_SECRET_ARN"] = rcWebhookSecret.SecretArn,
            },
            LogRetention = isProd ? RetentionDays.ONE_YEAR : RetentionDays.ONE_WEEK,
            Tracing = Tracing.ACTIVE,
        });

        // ── API Gateway ──────────────────────────────────────────────────────
        var api = new RestApi(this, "CleanProApi", new RestApiProps
        {
            RestApiName = $"clean-pro-{env}",
            Description = "Clean Pro backend API",
            DefaultCorsPreflightOptions = new CorsOptions
            {
                AllowOrigins = Cors.ALL_ORIGINS,
                AllowMethods = Cors.ALL_METHODS,
                AllowHeaders = ["Authorization", "Content-Type"],
            },
            DeployOptions = new StageOptions
            {
                StageName = env,
                TracingEnabled = true,
                ThrottlingRateLimit = 1000,
                ThrottlingBurstLimit = 500,
            },
        });

        var cognitoAuthorizer = new CognitoUserPoolsAuthorizer(this, "CognitoAuthorizer",
            new CognitoUserPoolsAuthorizerProps
            {
                CognitoUserPools = [userPool],
                AuthorizerName = "CognitoAuthorizer",
                IdentitySource = IdentitySource.Header("Authorization"),
            });

        var v1 = api.Root.AddResource("v1");
        var usersMe = v1.AddResource("users").AddResource("me");

        var userProfileIntegration = new LambdaIntegration(userProfileFn);

        usersMe.AddMethod("GET", userProfileIntegration, new MethodOptions
        {
            Authorizer = cognitoAuthorizer,
            AuthorizationType = AuthorizationType.COGNITO,
        });

        usersMe.AddMethod("POST", userProfileIntegration, new MethodOptions
        {
            Authorizer = cognitoAuthorizer,
            AuthorizationType = AuthorizationType.COGNITO,
        });

        var entitlement = usersMe.AddResource("entitlement");
        entitlement.AddMethod("GET", userProfileIntegration, new MethodOptions
        {
            Authorizer = cognitoAuthorizer,
            AuthorizationType = AuthorizationType.COGNITO,
        });

        var webhooks = v1.AddResource("webhooks");
        var rcWebhooks = webhooks.AddResource("revenuecat");
        rcWebhooks.AddMethod("POST", new LambdaIntegration(webhookFn));

        // ── CloudWatch Alarms ────────────────────────────────────────────────
        var alarmTopic = new Topic(this, "AlarmTopic", new TopicProps
        {
            TopicName = $"clean-pro-{env}-alarms",
        });

        new Alarm(this, "ApiErrorRateAlarm", new AlarmProps
        {
            AlarmName = $"clean-pro-{env}-api-error-rate",
            Metric = new Metric(new MetricProps
            {
                Namespace = "AWS/ApiGateway",
                MetricName = "5XXError",
                DimensionsMap = new Dictionary<string, string>
                {
                    ["ApiName"] = api.RestApiName,
                },
                Statistic = "Average",
                Period = Duration.Minutes(5),
            }),
            Threshold = 0.01,
            EvaluationPeriods = 2,
            ComparisonOperator = ComparisonOperator.GREATER_THAN_THRESHOLD,
            AlarmDescription = "API 5XX error rate > 1% over 10 minutes",
            ActionsEnabled = isProd,
        }).AddAlarmAction(new SnsAction(alarmTopic));

        // ── Stack Outputs ────────────────────────────────────────────────────
        _ = new CfnOutput(this, "ApiUrl", new CfnOutputProps
        {
            Value = api.Url,
            Description = "Clean Pro API base URL",
            ExportName = $"CleanProApiUrl-{env}",
        });

        _ = new CfnOutput(this, "UserPoolId", new CfnOutputProps
        {
            Value = userPool.UserPoolId,
            Description = "Cognito User Pool ID",
            ExportName = $"CleanProUserPoolId-{env}",
        });

        _ = new CfnOutput(this, "UserPoolClientId", new CfnOutputProps
        {
            Value = userPoolClient.UserPoolClientId,
            Description = "Cognito User Pool Client ID (mobile)",
            ExportName = $"CleanProUserPoolClientId-{env}",
        });

        _ = new CfnOutput(this, "DynamoDbTableName", new CfnOutputProps
        {
            Value = table.TableName,
            Description = "DynamoDB table name",
            ExportName = $"CleanProTableName-{env}",
        });
    }
}
