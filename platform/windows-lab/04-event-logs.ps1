param(
    [ValidateRange(1,168)][int]$Hours = 24,
    [ValidateRange(1,200)][int]$MaxEvents = 30
)

. "$PSScriptRoot\_common.ps1"
$start = (Get-Date).AddHours(-$Hours)

foreach ($logName in @("System", "Application")) {
    Invoke-SafeSection "$logName ERRORS/WARNINGS - LAST $Hours HOURS" {
        $events = Get-WinEvent -FilterHashtable @{
            LogName   = $logName
            Level     = 2,3
            StartTime = $start
        } -ErrorAction Stop | Select-Object -First $MaxEvents

        if (-not $events) {
            Write-Host "No matching events."
            return
        }

        $events |
            Select-Object TimeCreated, LevelDisplayName, ProviderName, Id, Message |
            Format-List |
            Out-Host
    }
}
