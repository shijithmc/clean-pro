using CleanPro.Domain.Entities;
using CleanPro.Domain.Events;
using CleanPro.Domain.ValueObjects;
using Xunit;

namespace CleanPro.Domain.Tests.Entities;

[Trait("Category", "Unit")]
public sealed class UserProfileTests
{
    private static UserId TestUserId => UserId.From("a1b2c3d4-e5f6-7890-abcd-ef1234567890");

    [Fact]
    public void Create_WithValidInputs_CreatesProfileWithTrialStarted()
    {
        var before = DateTime.UtcNow;
        var profile = UserProfile.Create(TestUserId, "user@example.com");
        var after = DateTime.UtcNow;

        Assert.Equal(TestUserId.Value, profile.UserId.Value);
        Assert.Equal("user@example.com", profile.Email);
        Assert.NotNull(profile.TrialStartedAt);
        Assert.NotNull(profile.TrialEndsAt);
        Assert.InRange(profile.TrialStartedAt!.Value, before, after);
        Assert.Equal(7, (int)(profile.TrialEndsAt!.Value - profile.TrialStartedAt.Value).TotalDays);
    }

    [Fact]
    public void Create_WithValidInputs_EmitsUserProfileCreatedEvent()
    {
        var profile = UserProfile.Create(TestUserId, "user@example.com");

        var evt = Assert.Single(profile.DomainEvents);
        var createdEvt = Assert.IsType<UserProfileCreatedEvent>(evt);
        Assert.Equal(TestUserId.Value, createdEvt.UserId.Value);
    }

    [Theory]
    [InlineData("")]
    [InlineData("  ")]
    public void Create_WithBlankEmail_ThrowsArgumentException(string email)
    {
        Assert.Throws<ArgumentException>(() =>
            UserProfile.Create(TestUserId, email));
    }

    [Fact]
    public void Create_WithNullEmail_ThrowsArgumentNullException()
    {
        Assert.Throws<ArgumentNullException>(() =>
            UserProfile.Create(TestUserId, null!));
    }

    [Fact]
    public void Create_WithInvalidEmailFormat_ThrowsArgumentException()
    {
        Assert.Throws<ArgumentException>(() =>
            UserProfile.Create(TestUserId, "notanemail"));
    }

    [Fact]
    public void RecordScan_UpdatesTotalsAndLastScanAt()
    {
        var profile = UserProfile.Create(TestUserId, "user@example.com");
        var before = DateTime.UtcNow;

        profile.RecordScan(photosScanned: 500, bytesReclaimed: 1_000_000L, scannedAt: DateTime.UtcNow);

        Assert.Equal(500, profile.TotalPhotosScanned);
        Assert.Equal(1_000_000L, profile.TotalBytesReclaimed);
        Assert.NotNull(profile.LastScanAt);
    }

    [Fact]
    public void RecordScan_MultipleTimes_AccumulatesTotals()
    {
        var profile = UserProfile.Create(TestUserId, "user@example.com");

        profile.RecordScan(200, 500_000L, DateTime.UtcNow);
        profile.RecordScan(300, 700_000L, DateTime.UtcNow);

        Assert.Equal(500, profile.TotalPhotosScanned);
        Assert.Equal(1_200_000L, profile.TotalBytesReclaimed);
    }

    [Fact]
    public void RecordScan_WithNegativePhotosScanned_ThrowsArgumentOutOfRangeException()
    {
        var profile = UserProfile.Create(TestUserId, "user@example.com");
        Assert.Throws<ArgumentOutOfRangeException>(() =>
            profile.RecordScan(-1, 0L, DateTime.UtcNow));
    }

    [Fact]
    public void IsTrialActive_WithinTrialPeriod_ReturnsTrue()
    {
        var profile = UserProfile.Create(TestUserId, "user@example.com");
        Assert.True(profile.IsTrialActive());
    }
}
