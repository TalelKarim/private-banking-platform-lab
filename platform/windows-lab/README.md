# Windows / PowerShell Lab

Mini-lab Windows orienté DevOps / production support.

## Exécution
Depuis la racine du repo :

```powershell
cd C:\Users\talel\projects\private-banking-platform-lab
.\platform\windows-lab\00-quick-inventory.ps1
```

Ou :

```powershell
cd .\platform\windows-lab
.\00-quick-inventory.ps1
```

Si l'exécution des scripts locaux est bloquée sur TON PC personnel :

```powershell
Get-ExecutionPolicy -List
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

Sur un poste d'entreprise, ne contourne pas une stratégie imposée par GPO.

## Scripts
- 00-quick-inventory.ps1 : OS, uptime, CPU, RAM, disques, PowerShell, .NET.
- 01-processes-services.ps1 : processus, services, top CPU/RAM.
- 02-network-diagnostics.ps1 : IP, DNS, route, ports, test TCP.
- 03-filesystem-acl.ps1 : NTFS, propriétaire et ACL.
- 04-event-logs.ps1 : erreurs/warnings System + Application.
- 05-env-registry.ps1 : variables d'environnement et Registry.
- 06-certificates.ps1 : certificats et dates d'expiration.
- 07-dotnet-runtime.ps1 : SDK/runtimes .NET et variables ASP.NET.
- 08-api-check.ps1 : test HTTP/HTTPS.
- 09-incident-snapshot.ps1 : collecte rapide pour incident.
