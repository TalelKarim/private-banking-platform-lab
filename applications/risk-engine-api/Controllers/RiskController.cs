using Microsoft.AspNetCore.Mvc;
using RiskEngineApi.Models;
using RiskEngineApi.Services;

namespace RiskEngineApi.Controllers;

[ApiController]
[Route("risk")]
public sealed class RiskController(
    IRiskService riskService,
    ILogger<RiskController> logger
) : ControllerBase
{
    [HttpPost("calculate")]
    [ProducesResponseType<RiskCalculationResponse>(
        StatusCodes.Status200OK
    )]
    [ProducesResponseType<ProblemDetails>(
        StatusCodes.Status404NotFound
    )]
    [ProducesResponseType<ValidationProblemDetails>(
        StatusCodes.Status400BadRequest
    )]
    public async Task<ActionResult<RiskCalculationResponse>> Calculate(
        [FromBody] RiskCalculationRequest request,
        CancellationToken cancellationToken
    )
    {
        logger.LogInformation(
            "HTTP POST /risk/calculate portfolioId={PortfolioId}",
            request.PortfolioId
        );

        var result = await riskService.CalculateAsync(
            request,
            cancellationToken
        );

        if (result is null)
        {
            return NotFound(new ProblemDetails
            {
                Status = StatusCodes.Status404NotFound,
                Title = "Portfolio not found",
                Detail =
                    $"Portfolio {request.PortfolioId} does not exist."
            });
        }

        return Ok(result);
    }

    [HttpGet("{portfolioId:long}")]
    [ProducesResponseType<RiskCalculationResponse>(
        StatusCodes.Status200OK
    )]
    [ProducesResponseType<ProblemDetails>(
        StatusCodes.Status404NotFound
    )]
    public ActionResult<RiskCalculationResponse> GetLatest(
        long portfolioId
    )
    {
        logger.LogInformation(
            "HTTP GET /risk/{PortfolioId}",
            portfolioId
        );

        var result = riskService.GetLatest(portfolioId);

        if (result is null)
        {
            return NotFound(new ProblemDetails
            {
                Status = StatusCodes.Status404NotFound,
                Title = "Risk calculation not found",
                Detail =
                    $"No risk calculation exists for portfolio {portfolioId}."
            });
        }

        return Ok(result);
    }
}
