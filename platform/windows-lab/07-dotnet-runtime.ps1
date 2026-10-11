. "$PSScriptRoot\_common.ps1"

Invoke-SafeSection "DOTNET CLI" {
    if (-not (Test-CommandAvailable "dotnet")) {
        Write-Warning "dotnet CLI not found in PATH."
        return
    }

    Write-Host "dotnet path: $((Get-Command dotnet).Source)"
    dotnet --info | Out-Host
}

Invoke-SafeSection "SDKs" {
    if (Test-CommandAvailable "dotnet") {
        dotnet --list-sdks | Out-Host
    } else {
        Write-Host "Skipped: dotnet unavailable."
    }
}

Invoke-SafeSection "RUNTIMES" {
    if (Test-CommandAvailable "dotnet") {
        dotnet --list-runtimes | Out-Host
    } else {
        Write-Host "Skipped: dotnet unavailable."
    }
}

Invoke-SafeSection "DOTNET PROCESSES" {
    $processes = Get-Process dotnet -ErrorAction SilentlyContinue
    if ($processes) {
        $processes |
            Select-Object Name, Id, CPU,
                @{Name="RAM_MB";Expression={[math]::Round($_.WorkingSet64 / 1MB, 1)}} |
            Format-Table -AutoSize |
            Out-Host
    } else {
        Write-Host "No dotnet process currently running."
    }
}

Invoke-SafeSection "ASP.NET ENVIRONMENT" {
    [PSCustomObject]@{
        ASPNETCORE_ENVIRONMENT = $env:ASPNETCORE_ENVIRONMENT
        ASPNETCORE_URLS        = $env:ASPNETCORE_URLS
        DOTNET_ROOT            = $env:DOTNET_ROOT
    } | Format-List | Out-Host
}
