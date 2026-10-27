namespace RiskEngineApi.Errors;

public sealed class PortfolioApiUnavailableException
    : Exception
{
    public PortfolioApiUnavailableException(
        string message,
        Exception innerException
    ) : base(message, innerException)
    {
    }
}
