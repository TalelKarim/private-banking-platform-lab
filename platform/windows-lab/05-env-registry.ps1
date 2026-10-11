. "$PSScriptRoot\_common.ps1"

Invoke-SafeSection "IMPORTANT ENVIRONMENT VARIABLES" {
    $names = @(
        "PATH",
        "TEMP",
        "TMP",
        "USERPROFILE",
        "JAVA_HOME",
        "MAVEN_HOME",
        "DOTNET_ROOT",
        "ASPNETCORE_ENVIRONMENT",
        "ASPNETCORE_URLS"
    )

    foreach ($name in $names) {
        [PSCustomObject]@{
            Name  = $name
            Value = [Environment]::GetEnvironmentVariable($name)
        }
    }  Format-Table -Wrap -AutoSize | Out-Host
}




Invoke-SafeSection "WINDOWS CURRENT VERSION REGISTRY (READ ONLY)" {
    $path = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion"
    Get-ItemProperty $path |
        Select-Object ProductName, DisplayVersion, CurrentBuild, UBR |
        Format-List |
        Out-Host
}
