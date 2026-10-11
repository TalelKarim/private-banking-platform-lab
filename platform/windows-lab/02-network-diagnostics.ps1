param(
    [string]$HostName = "localhost",
    [ValidateRange(1,65535)][int]$Port = 443
)

. "$PSScriptRoot\_common.ps1"

Invoke-SafeSection "IPv4 ADRESSES" {
   Get-NetIPAddress -AddressFamily IPv4  |
        Where-Object {
            $_.IPAddress -notlike "127.*" -and
            $_.IPAddress -notlike "169.254.*"
        } |
        Select-Object InterfaceAlias, IPAddress, PrefixLength |
        Format-Table -AutoSize |
        Out-Host
}

Invoke-SafeSection "DEFAULT ROUTE" {
    Get-NetRoute -DestinationPrefix "0.0.0.0/0" |
        Sort-Object RouteMetric |
        Select-Object InterfaceAlias, NextHop, RouteMetric |
        Format-Table -AutoSize |
        Out-Host
}

Invoke-SafeSection "DNS SERVERS" {
    Get-DnsClientServerAddress -AddressFamily IPv4 |
        Where-Object { $_.ServerAddresses.Count -gt 0 } |
        Select-Object InterfaceAlias, ServerAddresses |
        Format-Table -AutoSize |
        Out-Host
}

Invoke-SafeSection "DNS RESOLUTION: $HostName" {
    Resolve-DnsName $HostName -ErrorAction Stop |
        Select-Object Name, Type, IPAddress |
        Format-Table -AutoSize |
        Out-Host
}

Invoke-SafeSection "TCP TEST: ${HostName}:$Port" {
    Test-NetConnection -ComputerName $HostName -Port $Port |
        Select-Object ComputerName, RemoteAddress, RemotePort, InterfaceAlias, SourceAddress, TcpTestSucceeded |
        Format-List |
        Out-Host
}

Invoke-SafeSection "LISTENING PORTS (first 40)" {
    Get-NetTCPConnection -State Listen |
        Sort-Object LocalPort |
        Select-Object -First 40 LocalAddress, LocalPort, OwningProcess |
        Format-Table -AutoSize |
        Out-Host
}

Invoke-SafeSection "WINDOWS FIREWALL PROFILES" {
    Get-NetFirewallProfile |
        Select-Object Name, Enabled, DefaultInboundAction, DefaultOutboundAction |
        Format-Table -AutoSize |
        Out-Host
}
