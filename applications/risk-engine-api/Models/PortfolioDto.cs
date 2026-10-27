namespace RiskEngineApi.Models;

public sealed record PortfolioDto(
    long Id,
    string ClientName,
    string PortfolioName,
    decimal TotalValue,
    string Currency
);
