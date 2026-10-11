param(
    [ValidateRange(1,3650)][int]$ExpiresWithinDays = 60
)

. "$PSScriptRoot\_common.ps1"
$limit = (Get-Date).AddDays($ExpiresWithinDays)

foreach ($store in @("Cert:\LocalMachine\My", "Cert:\CurrentUser\My")) {
    Invoke-SafeSection "$store - EXPIRING WITHIN $ExpiresWithinDays DAYS" {
        $certs = Get-ChildItem $store -ErrorAction Stop |
            Where-Object { $_.NotAfter -le $limit } |
            Sort-Object NotAfter

        if (-not $certs) {
            Write-Host "No certificate expiring in this window."
            return
        }

        $certs |
            Select-Object Subject, Issuer, Thumbprint, NotBefore, NotAfter |
            Format-Table -Wrap -AutoSize |
            Out-Host
    }
}
