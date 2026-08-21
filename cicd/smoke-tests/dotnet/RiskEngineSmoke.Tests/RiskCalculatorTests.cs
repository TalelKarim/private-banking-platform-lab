using Xunit;
using RiskEngineSmoke;

namespace RiskEngineSmoke.Tests;

public class RiskCalculatorTests
{
    [Fact]
    public void CalculateLossRatioReturnsExpectedPercentage()
    {
        Assert.Equal(25, RiskCalculator.CalculateLossRatio(100_000m, 25_000m));
    }
}
