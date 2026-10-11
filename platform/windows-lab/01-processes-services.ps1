param(
    [string]$ServiceName = ""
)

. "$PSScriptRoot\_common.ps1"

Invoke-SafeSection "TOP 10 PROCESSES BY RAM" {
    Get-Process |
        Sort-Object WorkingSet64 -Descending |
        Select-Object -First 10 Name, Id,
            @{Name="RAM_MB";Expression={[math]::Round($_.WorkingSet64 / 1MB, 1)}},
            CPU |
        Format-Table -AutoSize |
        Out-Host
}

Invoke-SafeSection "TOP 10 PROCESSES BY CPU TIME" {
    Get-Process |
        Where-Object { $null -ne $_.CPU } |
        Sort-Object CPU -Descending |
        Select-Object -First 10 Name, Id,
            @{Name="CPU_Seconds";Expression={[math]::Round($_.CPU, 1)}} |
        Format-Table -AutoSize |
        Out-Host
}

Invoke-SafeSection "RUNNING SERVICES" {
    Get-Service |
        Where-Object Status -eq "Running" |
        Select-Object -First 30 Name, DisplayName, Status |
        Format-Table -AutoSize |
        Out-Host
}

if ($ServiceName) {
    Invoke-SafeSection "SERVICE MATCH: $ServiceName" {
        Get-Service |
            Where-Object {
                $_.Name -like "*$ServiceName*" -or
                $_.DisplayName -like "*$ServiceName*"
            } |
            Select-Object Name, DisplayName, Status, StartType |
            Format-Table -AutoSize |
            Out-Host
    }
}
