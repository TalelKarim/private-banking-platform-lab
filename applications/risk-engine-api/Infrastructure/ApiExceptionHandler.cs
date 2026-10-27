using Microsoft.AspNetCore.Diagnostics;
using Microsoft.AspNetCore.Mvc;
using RiskEngineApi.Errors;

namespace RiskEngineApi.Infrastructure;

public sealed class ApiExceptionHandler(
    ILogger<ApiExceptionHandler> logger
) : IExceptionHandler
{
    public async ValueTask<bool> TryHandleAsync(
        HttpContext httpContext,
        Exception exception,
        CancellationToken cancellationToken
    )
    {
        var statusCode = exception switch
        {
            PortfolioApiUnavailableException =>
                StatusCodes.Status503ServiceUnavailable,

            _ =>
                StatusCodes.Status500InternalServerError
        };

        if (statusCode == StatusCodes.Status500InternalServerError)
        {
            logger.LogError(exception, "Unhandled application error");
        }
        else
        {
            logger.LogWarning(exception, "Downstream dependency unavailable");
        }

        var problem = new ProblemDetails
        {
            Status = statusCode,
            Title = statusCode == StatusCodes.Status503ServiceUnavailable
                ? "Portfolio API unavailable"
                : "Internal server error",
            Detail = statusCode == StatusCodes.Status503ServiceUnavailable
                ? exception.Message
                : "An unexpected error occurred.",
            Instance = httpContext.Request.Path
        };

        httpContext.Response.StatusCode = statusCode;

        await httpContext.Response.WriteAsJsonAsync(
            problem,
            cancellationToken
        );

        return true;
    }
}
