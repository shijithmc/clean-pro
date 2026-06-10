namespace CleanPro.Domain.ValueObjects;

/// <summary>Strongly-typed user identifier (Cognito sub claim).</summary>
public readonly record struct UserId
{
    public string Value { get; }

    public UserId(string value)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(value);
        if (!Guid.TryParse(value, out _))
            throw new ArgumentException("UserId must be a valid UUID (Cognito sub).", nameof(value));
        Value = value.ToLowerInvariant();
    }

    public static UserId From(string value) => new(value);

    public override string ToString() => Value;
}

public enum SubscriptionTier
{
    None = 0,
    FreeTrial = 1,
    Monthly = 2,
    Annual = 3,
}

public enum SubscriptionStatus
{
    None = 0,
    Active = 1,
    Expired = 2,
    Cancelled = 3,
    GracePeriod = 4,
}

public enum DevicePlatform
{
    Unknown = 0,
    iOS = 1,
    Android = 2,
}
