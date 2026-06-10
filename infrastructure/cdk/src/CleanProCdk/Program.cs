using Amazon.CDK;
using CleanProCdk.Stacks;

var app = new App();

var env = new Amazon.CDK.Environment
{
    Account = System.Environment.GetEnvironmentVariable("CDK_DEFAULT_ACCOUNT"),
    Region = System.Environment.GetEnvironmentVariable("CDK_DEFAULT_REGION") ?? "ap-southeast-1",
};

_ = new CleanProStack(app, "CleanProStack", new StackProps
{
    Env = env,
    Description = "Clean Pro — AI Photo Cleaner backend (DynamoDB, Cognito, Lambda, API Gateway)",
    Tags = new Dictionary<string, string>
    {
        ["Project"] = "CleanPro",
        ["ManagedBy"] = "CDK",
    },
});

app.Synth();
