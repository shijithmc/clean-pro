using CleanPro.Application.Commands;
using CleanPro.Domain.Repositories;
using CleanPro.Domain.ValueObjects;
using CleanPro.Shared.Exceptions;

namespace CleanPro.Application.Handlers;

public sealed class RecordScanStatsHandler
{
    private readonly IUserProfileRepository _userProfileRepo;

    public RecordScanStatsHandler(IUserProfileRepository userProfileRepo)
        => _userProfileRepo = userProfileRepo;

    public async Task HandleAsync(RecordScanStatsCommand command, CancellationToken ct = default)
    {
        var userId = UserId.From(command.UserId);
        var profile = await _userProfileRepo.GetByUserIdAsync(userId, ct)
            ?? throw new NotFoundException($"User profile not found: {command.UserId}");

        profile.RecordScan(command.PhotosScanned, command.BytesReclaimed, DateTime.UtcNow);
        await _userProfileRepo.UpdateAsync(profile, ct);
    }
}
