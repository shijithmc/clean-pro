using CleanPro.Application.Commands;
using CleanPro.Application.DTOs;
using CleanPro.Domain.Entities;
using CleanPro.Domain.Repositories;
using CleanPro.Domain.ValueObjects;
using CleanPro.Shared.Exceptions;
using Microsoft.Extensions.Logging;

namespace CleanPro.Application.Handlers;

public sealed class CreateUserProfileHandler
{
    private readonly IUserProfileRepository _profileRepository;
    private readonly ILogger<CreateUserProfileHandler> _logger;

    public CreateUserProfileHandler(
        IUserProfileRepository profileRepository,
        ILogger<CreateUserProfileHandler> logger)
    {
        _profileRepository = profileRepository;
        _logger = logger;
    }

    /// <summary>
    /// Creates a user profile. Returns existing profile if already created (idempotent).
    /// Returns (profile, isNew: true) when created; (profile, isNew: false) when already existed.
    /// </summary>
    public async Task<(UserProfileDto Profile, bool IsNew)> HandleAsync(
        CreateUserProfileCommand command,
        CancellationToken ct = default)
    {
        var userId = UserId.From(command.UserId);

        var existing = await _profileRepository.GetByUserIdAsync(userId, ct);
        if (existing is not null)
        {
            _logger.LogInformation("Profile already exists for user {UserId}", userId);
            return (MapToDto(existing), false);
        }

        var profile = UserProfile.Create(userId, command.Email);
        await _profileRepository.CreateAsync(profile, ct);

        _logger.LogInformation(
            "Created user profile {UserId} with trial ending {TrialEndsAt}",
            userId,
            profile.TrialEndsAt);

        profile.ClearDomainEvents();
        return (MapToDto(profile), true);
    }

    private static UserProfileDto MapToDto(UserProfile p) => new(
        UserId: p.UserId.Value,
        Email: p.Email,
        CreatedAt: p.CreatedAt,
        UpdatedAt: p.UpdatedAt,
        TrialStartedAt: p.TrialStartedAt,
        TrialEndsAt: p.TrialEndsAt,
        TotalPhotosScanned: p.TotalPhotosScanned,
        TotalBytesReclaimed: p.TotalBytesReclaimed,
        LastScanAt: p.LastScanAt);
}
