using System.Collections.Concurrent;
using RiskEngineApi.Models;

namespace RiskEngineApi.Stores;

public sealed class InMemoryRiskStore : IRiskStore
{
    private readonly ConcurrentDictionary<long, RiskCalculationResponse>
        _latestByPortfolio = new();

    public void Save(RiskCalculationResponse calculation)
    {
        _latestByPortfolio[calculation.PortfolioId] = calculation;
    }

    public RiskCalculationResponse? GetLatest(long portfolioId)
    {
        return _latestByPortfolio.TryGetValue(
            portfolioId,
            out var calculation
        )
            ? calculation
            : null;
    }
}
