using RiskEngineApi.Clients;
using RiskEngineApi.Models;
using RiskEngineApi.Stores;

namespace RiskEngineApi.Services;

public sealed class RiskService(
    IPortfolioClient portfolioClient,
    IRiskStore riskStore,
    ILogger<RiskService> logger
) : IRiskService
{
    public async Task<RiskCalculationResponse?> CalculateAsync(
        RiskCalculationRequest request,
        CancellationToken cancellationToken
    )
    {
        var portfolio = await portfolioClient.GetByIdAsync(
            request.PortfolioId,
            cancellationToken
        );

        if (portfolio is null)
        {
            return null;
        }

        var score = Math.Round(
            (request.MarketVolatility * 50m)
            + (request.ConcentrationRatio * 30m)
            + (request.LeverageRatio * 20m),
            2,
            MidpointRounding.AwayFromZero
        );

        var calculation = new RiskCalculationResponse(
            Guid.NewGuid(),
            portfolio.Id,
            portfolio.ClientName,
            portfolio.PortfolioName,
            portfolio.TotalValue,
            portfolio.Currency,
            request.MarketVolatility,
            request.ConcentrationRatio,
            request.LeverageRatio,
            score,
            GetLevel(score),
            DateTimeOffset.UtcNow
        );

        riskStore.Save(calculation);

        logger.LogInformation(
            "Risk calculated for portfolioId={PortfolioId} score={Score} level={Level}",
            calculation.PortfolioId,
            calculation.Score,
            calculation.Level
        );

        return calculation;
    }

    public RiskCalculationResponse? GetLatest(long portfolioId)
    {
        return riskStore.GetLatest(portfolioId);
    }

    private static string GetLevel(decimal score)
    {
        return score switch
        {
            < 30m => "LOW",
            < 60m => "MEDIUM",
            < 80m => "HIGH",
            _ => "CRITICAL"
        };
    }
}
