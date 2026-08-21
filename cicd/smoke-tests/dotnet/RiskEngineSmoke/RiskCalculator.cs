namespace RiskEngineSmoke;

public static class RiskCalculator
{
    public static int CalculateLossRatio(decimal exposure, decimal potentialLoss)
    {
        if (exposure <= 0)
        {
            return 0;
        }

        return (int)Math.Round((potentialLoss / exposure) * 100m, MidpointRounding.AwayFromZero);
    }
}
