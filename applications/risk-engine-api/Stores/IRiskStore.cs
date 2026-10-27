using RiskEngineApi.Models;

namespace RiskEngineApi.Stores;

public interface IRiskStore
{
    void Save(RiskCalculationResponse calculation);

    RiskCalculationResponse? GetLatest(long portfolioId);
}
