using CleanPro.Domain.Events;
using CleanPro.Domain.ValueObjects;

namespace CleanPro.Domain.Entities;

/// <summary>
/// User profile aggregate root. Owns trial lifecycle and lifetime scan statistics.
/// </summary>
public sealed class UserProfile
{
    private UserProfile() { }

    public UserId UserId { get; private set; }
    public string Email { get; private set; } = null!;
    public DateTime CreatedAt { get; private set; }
    public DateTime UpdatedAt { get; private set; }
    public DateTime? TrialStartedAt { get; private set; }
    public DateTime? TrialEndsAt { get; private set; }
    public int TotalPhotosScanned { get; private set; }
    public long TotalBytesReclaimed { get; private set; }
    public DateTime? LastScanAt { get; private set; }

    private readonly List<IDomainEvent> _domainEvents = [];
    public IReadOnlyList<IDomainEvent> DomainEvents => _domainEvents.AsReadOnly();

    /// <summary>Creates a new user profile and starts a 7-day free trial.</summary>
    public static UserProfile Create(UserId userId, string email, int trialDays = 7)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(email);
        if (!email.Contains('@')) throw new ArgumentException("Invalid email format.", nameof(email));

        var now = DateTime.UtcNow;
        var profile = new UserProfile
        {
            UserId = userId,
            Email = email.ToLowerInvariant().Trim(),
            CreatedAt = now,
            UpdatedAt = now,
            TrialStartedAt = now,
            TrialEndsAt = now.AddDays(trialDays),
            TotalPhotosScanned = 0,
            TotalBytesReclaimed = 0L,
        };

        profile._domainEvents.Add(new UserProfileCreatedEvent(userId, now, profile.TrialEndsAt.Value));
        return profile;
    }

    /// <summary>Records the outcome of a completed scan session.</summary>
    public void RecordScan(int photosScanned, long bytesReclaimed, DateTime scannedAt)
    {
        if (photosScanned < 0) throw new ArgumentOutOfRangeException(nameof(photosScanned));
        if (bytesReclaimed < 0) throw new ArgumentOutOfRangeException(nameof(bytesReclaimed));

        TotalPhotosScanned += photosScanned;
        TotalBytesReclaimed += bytesReclaimed;
        LastScanAt = scannedAt;
        UpdatedAt = DateTime.UtcNow;
    }

    public bool IsTrialActive() =>
        TrialEndsAt.HasValue && DateTime.UtcNow < TrialEndsAt.Value;

    public void ClearDomainEvents() => _domainEvents.Clear();

    /// <summary>
    /// Reconstitutes a UserProfile from persistent storage without raising domain events.
    /// For repository use only — not for application-layer construction.
    /// </summary>
    public static UserProfile Reconstitute(
        UserId userId,
        string email,
        DateTime createdAt,
        DateTime updatedAt,
        DateTime? trialStartedAt,
        DateTime? trialEndsAt,
        int totalPhotosScanned,
        long totalBytesReclaimed,
        DateTime? lastScanAt) => new()
        {
            UserId = userId,
            Email = email,
            CreatedAt = createdAt,
            UpdatedAt = updatedAt,
            TrialStartedAt = trialStartedAt,
            TrialEndsAt = trialEndsAt,
            TotalPhotosScanned = totalPhotosScanned,
            TotalBytesReclaimed = totalBytesReclaimed,
            LastScanAt = lastScanAt,
        };
}
