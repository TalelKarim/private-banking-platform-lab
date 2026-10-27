namespace RiskEngineApi.Models;

public sealed record RiskCalculationResponse(
    Guid CalculationId,
    long PortfolioId,
    string ClientName,
    string PortfolioName,
    decimal PortfolioValue,
    string Currency,
    decimal MarketVolatility,
    decimal ConcentrationRatio,
    decimal LeverageRatio,
    decimal Score,
    string Level,
    DateTimeOffset CalculatedAtUtc
);
