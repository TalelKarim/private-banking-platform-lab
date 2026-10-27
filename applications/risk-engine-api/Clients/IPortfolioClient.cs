using RiskEngineApi.Models;

namespace RiskEngineApi.Clients;

public interface IPortfolioClient
{
    Task<PortfolioDto?> GetByIdAsync(
        long portfolioId,
        CancellationToken cancellationToken
    );

    Task<bool> IsHealthyAsync(CancellationToken cancellationToken);
}
