using Microsoft.Extensions.Diagnostics.HealthChecks;
using RiskEngineApi.Clients;

namespace RiskEngineApi.Health;

public sealed class PortfolioApiHealthCheck(
    IPortfolioClient portfolioClient
) : IHealthCheck
{
    public async Task<HealthCheckResult> CheckHealthAsync(
        HealthCheckContext context,
        CancellationToken cancellationToken = default
    )
    {
        var healthy = await portfolioClient.IsHealthyAsync(cancellationToken);

        return healthy
            ? HealthCheckResult.Healthy("portfolio-java is reachable")
            : HealthCheckResult.Unhealthy("portfolio-java is unreachable");
    }
}
