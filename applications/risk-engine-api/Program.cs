using Microsoft.AspNetCore.Diagnostics.HealthChecks;
using Microsoft.Extensions.Diagnostics.HealthChecks;
using RiskEngineApi.Clients;
using RiskEngineApi.Health;
using RiskEngineApi.Infrastructure;
using RiskEngineApi.Services;
using RiskEngineApi.Stores;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddControllers();
builder.Services.AddOpenApi();
builder.Services.AddProblemDetails();
builder.Services.AddExceptionHandler<ApiExceptionHandler>();

builder.Services.AddSingleton<IRiskStore, InMemoryRiskStore>();
builder.Services.AddScoped<IRiskService, RiskService>();

builder.Services.AddHttpClient<IPortfolioClient, PortfolioClient>((services, client) =>
{
    var configuration = services.GetRequiredService<IConfiguration>();

    var baseUrl = configuration["PortfolioApi:BaseUrl"];
    if (string.IsNullOrWhiteSpace(baseUrl))
    {
        throw new InvalidOperationException("PortfolioApi:BaseUrl is not configured.");
    }

    client.BaseAddress = new Uri(baseUrl);
    client.Timeout = TimeSpan.FromSeconds(
        configuration.GetValue<int?>("PortfolioApi:TimeoutSeconds") ?? 3
    );
});

builder.Services.AddHealthChecks()
    .AddCheck(
        "self",
        () => HealthCheckResult.Healthy("risk-engine-api is running"),
        tags: ["live"]
    )
    .AddCheck<PortfolioApiHealthCheck>(
        "portfolio-api",
        tags: ["ready"]
    );

var app = builder.Build();

if (app.Environment.IsDevelopment())
{
    app.MapOpenApi();
}

app.UseExceptionHandler();

app.MapGet("/", () => Results.Ok(new
{
    service = "risk-engine-api",
    status = "UP",
    environment = app.Environment.EnvironmentName
}));

app.MapHealthChecks("/health");

app.MapHealthChecks(
    "/health/live",
    new HealthCheckOptions
    {
        Predicate = registration => registration.Tags.Contains("live")
    }
);

app.MapHealthChecks(
    "/health/ready",
    new HealthCheckOptions
    {
        Predicate = registration => registration.Tags.Contains("ready")
    }
);

app.MapControllers();

app.Run();

public partial class Program;
