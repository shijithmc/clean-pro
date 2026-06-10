using CleanPro.Domain.Entities;
using CleanPro.Domain.ValueObjects;

namespace CleanPro.Domain.Repositories;

public interface IUserProfileRepository
{
    /// <summary>Returns null if no profile exists for this user.</summary>
    Task<UserProfile?> GetByUserIdAsync(UserId userId, CancellationToken ct = default);

    /// <summary>Creates a new user profile. Throws ConflictException if one already exists.</summary>
    Task CreateAsync(UserProfile profile, CancellationToken ct = default);

    /// <summary>Updates an existing profile. Throws NotFoundException if not found.</summary>
    Task UpdateAsync(UserProfile profile, CancellationToken ct = default);
}
