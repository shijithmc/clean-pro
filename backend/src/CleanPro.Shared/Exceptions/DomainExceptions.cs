namespace CleanPro.Shared.Exceptions;

public class DomainException : Exception
{
    public DomainException(string message) : base(message) { }
}

public class NotFoundException : DomainException
{
    public NotFoundException(string message) : base(message) { }
}

public class ConflictException : DomainException
{
    public ConflictException(string message) : base(message) { }
}

public class UnauthorizedException : DomainException
{
    public UnauthorizedException(string message = "Unauthorized") : base(message) { }
}

public class ValidationException : DomainException
{
    public ValidationException(string field, string message)
        : base($"Validation failed for '{field}': {message}") { }

    public IReadOnlyDictionary<string, string[]> Errors { get; init; }
        = new Dictionary<string, string[]>();
}
