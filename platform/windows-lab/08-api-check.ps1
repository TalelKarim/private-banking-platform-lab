param(
    [Parameter(Mandatory=$true)]
    [ValidatePattern('^https?://')]
    [string]$Uri,
    [ValidateRange(1,120)]
    [int]$TimeoutSec = 15
)

. "$PSScriptRoot\_common.ps1"

Write-Section "HTTP CHECK"
Write-Host "URI: $Uri"

$sw = [System.Diagnostics.Stopwatch]::StartNew()

try {
    $response = Invoke-WebRequest -Uri $Uri -Method Get -TimeoutSec $TimeoutSec -ErrorAction Stop
    $sw.Stop()

    [PSCustomObject]@{
        Success     = $true
        StatusCode  = [int]$response.StatusCode
        DurationMs  = $sw.ElapsedMilliseconds
        ContentType = $response.Headers["Content-Type"]
    } | Format-List | Out-Host

    Write-Section "BODY (first 500 chars)"
    $body = [string]$response.Content
    if ($body.Length -gt 500) { $body.Substring(0, 500) } else { $body }
}
catch {
    $sw.Stop()

    [PSCustomObject]@{
        Success    = $false
        DurationMs = $sw.ElapsedMilliseconds
        Error      = $_.Exception.Message
    } | Format-List | Out-Host

    exit 1
}
