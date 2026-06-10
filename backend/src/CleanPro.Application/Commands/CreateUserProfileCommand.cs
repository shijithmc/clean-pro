namespace CleanPro.Application.Commands;

/// <summary>Command to create a new user profile on first login. Idempotent — returns existing profile if already created.</summary>
public sealed record CreateUserProfileCommand(
    string UserId,
    string Email);

/// <summary>Command to record aggregate scan statistics. No photo data — counts only.</summary>
public sealed record RecordScanStatsCommand(
    string UserId,
    int PhotosScanned,
    int DuplicateGroupsFound,
    int PhotosDeleted,
    long BytesReclaimed,
    int ScanDurationSeconds,
    string Platform,
    string AppVersion);
