# syntax=docker/dockerfile:1.7

# ============================================================
# STAGE 1 - BUILD
# Full .NET SDK is used only to restore and publish the app.
# ============================================================

FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build

WORKDIR /src

# Copy the project file first so NuGet restore can be cached.
COPY RiskEngineApi.csproj ./

RUN --mount=type=cache,target=/root/.nuget/packages \
    dotnet restore RiskEngineApi.csproj

# Copy the application source only after dependencies are restored.
COPY . .

RUN --mount=type=cache,target=/root/.nuget/packages \
    dotnet publish RiskEngineApi.csproj \
      --configuration Release \
      --output /app/publish \
      --no-restore \
      /p:UseAppHost=false


# ============================================================
# STAGE 2 - RUNTIME
# Final image contains ASP.NET Core runtime + published DLL only.
# ============================================================

FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS runtime

WORKDIR /app

ENV ASPNETCORE_HTTP_PORTS=8080 \
    HOME=/tmp \
    DOTNET_EnableDiagnostics=0

COPY --from=build --chown=app:app /app/publish ./

USER app

EXPOSE 8080

ENTRYPOINT ["dotnet", "RiskEngineApi.dll"]
