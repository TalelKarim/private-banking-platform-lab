. "$PSScriptRoot\_common.ps1"

Invoke-SafeSection "POWERSHELL" {
    $PSVersionTable |
        Select-Object PSEdition, PSVersion, OS, Platform |
        Format-List |
        Out-Host
}

Invoke-SafeSection "WINDOWS" {
    Get-CimInstance Win32_OperatingSystem |
        Select-Object Caption, Version, OSArchitecture,
            @{Name="LastBoot";Expression={$_.LastBootUpTime}},
            @{Name="UptimeHours";Expression={[math]::Round(((Get-Date) - $_.LastBootUpTime).TotalHours, 1)}} |
        Format-List |
        Out-Host
}

Invoke-SafeSection "MACHINE" {
    Get-CimInstance Win32_ComputerSystem |
        Select-Object Manufacturer, Model,
            @{Name="RAM_GB";Expression={[math]::Round($_.TotalPhysicalMemory / 1GB, 2)}} |
        Format-List |
        Out-Host
}

Invoke-SafeSection "CPU" {
    Get-CimInstance Win32_Processor |
        Select-Object Name, NumberOfCores, NumberOfLogicalProcessors |
        Format-List |
        Out-Host
}

Invoke-SafeSection "DISKS" {
    Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" |
        Select-Object DeviceID,
            @{Name="Size_GB";Expression={[math]::Round($_.Size / 1GB, 2)}},
            @{Name="Free_GB";Expression={[math]::Round($_.FreeSpace / 1GB, 2)}},
            @{Name="FreePct";Expression={
                if ($_.Size -gt 0) { [math]::Round(100 * $_.FreeSpace / $_.Size, 1) } else { 0 }
            }} |
        Format-Table -AutoSize |
        Out-Host
}

Invoke-SafeSection "DOTNET" {
    if (Test-CommandAvailable "dotnet") {
        Write-Host "dotnet path: $((Get-Command dotnet).Source)"
        dotnet --version
        dotnet --list-runtimes
    }
    else {
        Write-Warning "dotnet CLI not found in PATH."
        Write-Host "Install the .NET SDK, then reopen VS Code / the terminal."
    }
}

Invoke-SafeSection "JAVA / MAVEN" {
    if (Test-CommandAvailable "java") {
        Write-Host "java path: $((Get-Command java).Source)"
        java -version 2>&1 | Out-Host
    } else {
        Write-Warning "java not found in PATH."
    }

    if (Test-CommandAvailable "mvn") {
        Write-Host "mvn path: $((Get-Command mvn).Source)"
        mvn -version | Out-Host
    } else {
        Write-Warning "mvn not found in PATH."
    }
}
