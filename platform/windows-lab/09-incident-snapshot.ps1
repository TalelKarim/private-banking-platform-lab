param(
    [string]$TargetHost = "localhost",
    [ValidateRange(1,65535)][int]$TargetPort = 443
)

. "$PSScriptRoot\_common.ps1"

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$outDir = Join-Path $PSScriptRoot "output"
New-Item -ItemType Directory -Path $outDir -Force | Out-Null
$outFile = Join-Path $outDir "incident-$timestamp.txt"

function Add-ReportSection {
    param(
        [string]$Title,
        [scriptblock]$Script
    )

    "`n=== $Title ===" | Out-File $outFile -Append -Encoding utf8
    try {
        & $Script | Out-String -Width 240 | Out-File $outFile -Append -Encoding utf8
    }
    catch {
        "ERROR: $($_.Exception.Message)" | Out-File $outFile -Append -Encoding utf8
    }
}

"=== INCIDENT SNAPSHOT ===" | Out-File $outFile -Encoding utf8
"Date: $(Get-Date -Format o)" | Out-File $outFile -Append -Encoding utf8
"Computer: $env:COMPUTERNAME" | Out-File $outFile -Append -Encoding utf8
"User: $env:USERNAME" | Out-File $outFile -Append -Encoding utf8

Add-ReportSection "OS" {
    Get-CimInstance Win32_OperatingSystem |
        Select-Object Caption, Version, OSArchitecture, LastBootUpTime |
        Format-List
}

Add-ReportSection "TOP RAM PROCESSES" {
    Get-Process |
        Sort-Object WorkingSet64 -Descending |
        Select-Object -First 10 Name, Id, CPU,
            @{Name="RAM_MB";Expression={[math]::Round($_.WorkingSet64 / 1MB,1)}} |
        Format-Table -AutoSize
}

Add-ReportSection "DISKS" {
    Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" |
        Select-Object DeviceID,
            @{Name="Size_GB";Expression={[math]::Round($_.Size/1GB,1)}},
            @{Name="Free_GB";Expression={[math]::Round($_.FreeSpace/1GB,1)}} |
        Format-Table -AutoSize
}

Add-ReportSection "NETWORK TEST ${TargetHost}:$TargetPort" {
    Test-NetConnection -ComputerName $TargetHost -Port $TargetPort |
        Format-List
}

Add-ReportSection "LISTENING PORTS" {
    Get-NetTCPConnection -State Listen |
        Sort-Object LocalPort |
        Select-Object LocalAddress, LocalPort, OwningProcess |
        Format-Table -AutoSize
}

foreach ($log in @("System", "Application")) {
    Add-ReportSection "RECENT $log ERRORS" {
        Get-WinEvent -FilterHashtable @{
            LogName   = $log
            Level     = 2
            StartTime = (Get-Date).AddHours(-4)
        } -ErrorAction Stop |
            Select-Object -First 15 TimeCreated, ProviderName, Id, Message |
            Format-List
    }
}

Write-Host "Snapshot written to:"
Write-Host $outFile
