<powershell>
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# AWS Windows AMIs already ship with SSM Agent. Keep it enabled so Fleet
# Manager can open the desktop without exposing TCP/3389 to the Internet.
Set-Service -Name AmazonSSMAgent -StartupType Automatic
Start-Service -Name AmazonSSMAgent

# Ensure the local RDP service is available for the Fleet Manager tunnel while
# the EC2 security group remains inbound-closed.
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections" -Value 0
Enable-NetFirewallRule -DisplayGroup "Remote Desktop"

# Install a normal browser for Jenkins, Horizon and the OpenShift console.
$installer = "C:\Windows\Temp\chrome_installer.exe"
Invoke-WebRequest -Uri "https://dl.google.com/chrome/install/latest/chrome_installer.exe" -OutFile $installer
Start-Process -FilePath $installer -ArgumentList "/silent /install" -Wait
Remove-Item -Path $installer -Force -ErrorAction SilentlyContinue
</powershell>
