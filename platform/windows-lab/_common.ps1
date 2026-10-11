Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Section {
    param([Parameter(Mandatory=$true)][string]$Title)
    Write-Host ""
    Write-Host "=== $Title ==="
}

function Test-CommandAvailable {
    param([Parameter(Mandatory=$true)][string]$Name)
    return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Invoke-SafeSection {
    param(
        [Parameter(Mandatory=$true)][string]$Title,
        [Parameter(Mandatory=$true)][scriptblock]$Script
    )

    Write-Section $Title

    try {
        & $Script
    }
    catch {
        Write-Warning "$Title failed: $($_.Exception.Message)"
    }
}
