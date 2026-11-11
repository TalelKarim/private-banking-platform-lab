# risk-engine-api

ASP.NET Core / .NET 10 risk engine used by the private banking lab.

## Responsibilities

- fetch a portfolio from `portfolio-java`;
- calculate a deterministic lab risk score;
- keep the latest calculation per portfolio in memory;
- expose liveness/readiness endpoints for OpenShift.

The scoring model is deliberately simple and educational. It is not a real financial risk model.

## API

- `GET /`
- `GET /health/live`
- `GET /health/ready`
- `POST /risk/calculate`
- `GET /risk/{portfolioId}`

Risk score:

```text
score =
  marketVolatility   * 50
+ concentrationRatio * 30
+ leverageRatio      * 20
```

Each input ratio is between 0 and 1.

Levels:

- LOW: score < 30
- MEDIUM: score < 60
- HIGH: score < 80
- CRITICAL: score >= 80

## Local development

The Development configuration expects `portfolio-java` at:

```text
http://localhost:8080
```

Start the API:

```powershell
dotnet restore
dotnet build
dotnet run
```

The default launch profile listens on:

```text
http://localhost:5169
```

Quick standalone check:

```powershell
Invoke-RestMethod http://localhost:5169/health/live
```

For a full risk calculation, `portfolio-java` must also be running.
Use `RiskEngineApi.http` or PowerShell/curl to exercise the endpoints.

In OpenShift, override the Java service URL with:

```text
PortfolioApi__BaseUrl=http://portfolio-java:8080/
```


## Container and OpenShift deployment

Local container stack:

```powershell
docker compose -f .\applications\compose.local.yml up --build -d
```

OpenShift runtime contract:

```text
Route risk.apps.<cluster>.<base-domain>
  -> Service risk-engine-api:8080
  -> Pod risk-engine-api
  -> http://portfolio-java:8080/
  -> Service portfolio-java
  -> Java pods
  -> PostgreSQL VM 10.10.0.40:5432
```

The Helm chart intentionally starts with one risk-engine-api replica because
`InMemoryRiskStore` is process-local. Scale-out should be enabled only after
the calculation store becomes shared/persistent.

From the ops-runner, the deployment lifecycle is:

```bash
make configure-risk-engine-api
make helm-template-risk-engine-api
make deploy-risk-engine-api
make test-risk-engine-api
```

A full lab convergence also configures, deploys and validates the Risk Engine
after portfolio-java:

```bash
make configure-lab
```
