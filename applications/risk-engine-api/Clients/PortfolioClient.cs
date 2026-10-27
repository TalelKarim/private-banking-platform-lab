using System.Net;
using System.Net.Http.Json;
using RiskEngineApi.Errors;
using RiskEngineApi.Models;

namespace RiskEngineApi.Clients;

public sealed class PortfolioClient(
    HttpClient httpClient,
    ILogger<PortfolioClient> logger
) : IPortfolioClient
{
    public async Task<PortfolioDto?> GetByIdAsync(
        long portfolioId,
        CancellationToken cancellationToken
    )
    {
        try
        {
            using var response = await httpClient.GetAsync(
                $"portfolios/{portfolioId}",
                cancellationToken
            );

            if (response.StatusCode == HttpStatusCode.NotFound)
            {
                logger.LogWarning(
                    "Portfolio {PortfolioId} was not found by portfolio-java",
                    portfolioId
                );

                return null;
            }

            response.EnsureSuccessStatusCode();

            return await response.Content.ReadFromJsonAsync<PortfolioDto>(
                cancellationToken: cancellationToken
            );
        }
        catch (OperationCanceledException ex)
            when (!cancellationToken.IsCancellationRequested)
        {
            throw new PortfolioApiUnavailableException(
                "portfolio-java timed out.",
                ex
            );
        }
        catch (HttpRequestException ex)
        {
            throw new PortfolioApiUnavailableException(
                "portfolio-java is unavailable.",
                ex
            );
        }
    }

    public async Task<bool> IsHealthyAsync(
        CancellationToken cancellationToken
    )
    {
        try
        {
            using var response = await httpClient.GetAsync(
                "actuator/health",
                cancellationToken
            );

            return response.IsSuccessStatusCode;
        }
        catch
        {
            return false;
        }
    }
}
