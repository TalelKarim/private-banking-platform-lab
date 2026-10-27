using RiskEngineApi.Models;

namespace RiskEngineApi.Services;

public interface IRiskService
{
    Task<RiskCalculationResponse?> CalculateAsync(
        RiskCalculationRequest request,
        CancellationToken cancellationToken
    );

    RiskCalculationResponse? GetLatest(long portfolioId);
}
