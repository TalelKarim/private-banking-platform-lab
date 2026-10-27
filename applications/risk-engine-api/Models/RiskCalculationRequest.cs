using System.ComponentModel.DataAnnotations;

namespace RiskEngineApi.Models;

public sealed class RiskCalculationRequest
{
    [Range(1, int.MaxValue)]
    public long PortfolioId { get; init; }

    [Range(typeof(decimal), "0", "1")]
    public decimal MarketVolatility { get; init; }

    [Range(typeof(decimal), "0", "1")]
    public decimal ConcentrationRatio { get; init; }

    [Range(typeof(decimal), "0", "1")]
    public decimal LeverageRatio { get; init; }
}
