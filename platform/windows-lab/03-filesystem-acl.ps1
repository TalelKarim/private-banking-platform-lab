param(
    [string]$Path = "."
)

. "$PSScriptRoot\_common.ps1"

Invoke-SafeSection "PATH / ITEM" {
    $resolved = (Resolve-Path $Path -ErrorAction Stop).Path
    Get-Item $resolved |
        Select-Object FullName, Attributes, CreationTime, LastWriteTime |
        Format-List |
        Out-Host
}

Invoke-SafeSection "ACL" {
    $resolved = (Resolve-Path $Path -ErrorAction Stop).Path
    $acl = Get-Acl $resolved
    Write-Host "Owner: $($acl.Owner)"
    $acl.Access |
        Select-Object IdentityReference, FileSystemRights, AccessControlType,
            IsInherited, InheritanceFlags, PropagationFlags |
        Format-Table -Wrap -AutoSize |
        Out-Host
}
