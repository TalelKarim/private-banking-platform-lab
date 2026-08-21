# Private Banking Platform Lab — Plan d’action complet de A à Z

> Ce document décrit la cible et l’ordre de construction du projet. Il reste volontairement indépendant de l’avancement courant : aucun statut d’avancement n’y est maintenu.

## 1. Structurer le repository

Construire un monorepo clair séparant les différentes responsabilités :

```text
private-banking-platform-lab/
├── infrastructure/
│   ├── terraform/
│   │   ├── aws/
│   │   └── openstack/
│   ├── openstack/
│   │   └── kolla/
│   └── ansible/
│       ├── inventories/
│       │   ├── dev/
│       │   ├── uat/
│       │   └── prod/
│       ├── roles/
│       └── playbooks/
├── platform/
│   ├── openshift/
│   └── helm/
├── applications/
│   ├── portfolio-java/
│   └── risk-engine-dotnet/
├── cicd/
│   └── jenkins/
│       └── shared-library/
├── observability/
├── scripts/
└── docs/
```

Principes :

- Terraform crée l’infrastructure.

- Ansible configure les systèmes et services.

- Kolla-Ansible déploie OpenStack.

- OpenStack fournit l’IaaS privé.

- OpenShift fournit la plateforme Kubernetes.

- Helm déploie les applications.

- Jenkins orchestre la CI/CD.

- Git reste la source de vérité.

- Les changements manuels doivent être évités autant que possible.

---

# 2. Construire la fondation AWS

Créer avec Terraform l’infrastructure servant à héberger le private cloud.

Architecture :

```text
AWS
│
├── lab-host
│   ├── Ubuntu
│   ├── KVM
│   ├── Docker
│   ├── OpenStack
│   ├── /data
│   └── Cinder storage
│
└── ops-runner
    ├── HCP Terraform Agent
    ├── Terraform
    ├── Ansible
    ├── OpenStack CLI
    └── AWS CLI
```

Créer :

- EC2 `lab-host`.

- EC2 `ops-runner`.

- Security Groups.

- IAM Roles.

- IAM Policies.

- SSM Parameters.

- EBS root du lab-host.

- EBS `/data`.

- EBS dédié à Cinder.

- EBS root ops-runner.

- routage AWS.

- règles réseau.

- accès administratifs.

Configurer le lab-host avec :

```text
source_dest_check = false
```

afin qu’il puisse agir comme routeur entre AWS et les réseaux OpenStack.

Utiliser une instance Spot pour le lab-host afin de réduire les coûts du lab.

---

# 3. Préparer automatiquement le lab-host

Chaîne de bootstrap :

```text
Terraform AWS
      ↓
minimal cloud-init
      ↓
Ansible
      ↓
host prêt pour OpenStack
```

Configurer automatiquement :

- Ubuntu.

- packages système.

- Python.

- virtualenv.

- Docker.

- Docker `data-root`.

- KVM.

- libvirt.

- nested virtualization.

- chrony.

- SSM Agent.

- AWS CLI.

- Terraform.

- outils réseau.

- sysctl.

- IP forwarding.

- bridge/netfilter settings.

- volumes EBS.

- `/data`.

- LVM pour Cinder.

- interfaces réseau nécessaires à OpenStack.

Objectif :

\> pouvoir reconstruire le lab-host sans refaire manuellement la préparation système.

---

# 4. Construire une Golden AMI du lab-host

Préparer une Golden AMI contenant les éléments lourds et relativement stables du lab.

Chaîne :

```text
Ubuntu
   ↓
bootstrap
   ↓
Ansible
   ↓
préparation Kolla/OpenStack
   ↓
Golden AMI
```

La Golden AMI sert à accélérer les futures reconstructions du lab-host.

Les configurations dépendantes de l’environnement restent gérées par Terraform et Ansible.

---

# 5. Déployer OpenStack avec Kolla-Ansible

Déployer OpenStack All-In-One sur le lab-host avec Kolla-Ansible.

Services principaux :

```text
OpenStack
├── Keystone
├── Nova
├── Neutron
├── Glance
├── Placement
├── Cinder
├── Heat
├── Horizon
└── Open vSwitch
```

Utiliser :

- Docker pour les services Kolla.

- KVM/QEMU pour Nova.

- Open vSwitch pour Neutron.

- LVM pour Cinder.

Valider :

- authentification Keystone.

- Glance.

- Nova.

- Neutron.

- Placement.

- Cinder.

- Horizon.

- création d’une VM.

- création d’un réseau.

- création d’un volume.

- attachement d’un volume.

---

# 6. Construire le control plane Terraform OpenStack

Installer un HCP Terraform Agent sur l’ops-runner.

Flux :

```text
Git
 ↓
HCP Terraform
 ↓
Agent Pool
 ↓
HCP Terraform Agent
 ↓
ops-runner
 ↓
OpenStack APIs
```

Séparer les deux niveaux Terraform :

```text
Terraform AWS
    ↓
crée l’infrastructure qui héberge OpenStack
Terraform OpenStack
    ↓
crée les ressources à l’intérieur d’OpenStack
```

Gérer proprement :

- Terraform State AWS.

- Terraform State OpenStack.

- credentials OpenStack.

- variables HCP.

- secrets.

- clés SSH.

- IAM.

---

# 7. Construire le réseau externe OpenStack

Créer le lien entre OpenStack et le lab-host Linux.

Architecture :

```text
OpenStack
    ↓
br-ex
    ↓
os-ext
    ║
    ║ veth
    ║
os-host
192.168.250.1
    ↓
Linux lab-host
    ↓
enp39s0
    ↓
AWS
```

Configurer :

- `br-ex`.

- `os-ext`.

- `os-host`.

- veth pair.

- adresse `192.168.250.1/24`.

- IP forwarding.

- Linux routing.

- NAT lorsque nécessaire.

---

# 8. Construire la fondation réseau OpenStack avec Terraform

Créer :

```text
private-net
10.10.0.0/24
       │
       ▼
private-subnet
       │
       ▼
lab-router
       │
       ▼
public-net
192.168.250.0/24
       │
       ▼
public-subnet
```

Configurer :

- réseau tenant privé.

- subnet privé.

- DHCP.

- DNS.

- réseau provider externe.

- subnet externe.

- allocation pool Floating IP.

- router Neutron.

- gateway externe.

- SNAT.

- DNAT/Floating IP.

Architecture complète :

```text
VM
10.10.0.x
    ↓
private-net
    ↓
10.10.0.1
lab-router
    ↓
public-net
192.168.250.0/24
    ↓
br-ex
    ↓
os-ext ↔ os-host
    ↓
lab-host
    ↓
AWS
```

---

# 9. Construire le chemin d’administration depuis AWS vers OpenStack

Permettre à l’ops-runner d’administrer les workloads OpenStack.

Chemin :

```text
ops-runner
172.31.x.x
     ↓
AWS VPC routing
     ↓
lab-host
172.31.31.70
     ↓
Linux forwarding
     ↓
os-host
192.168.250.1
     ↓
br-ex
     ↓
Floating IP
192.168.250.x
     ↓
Neutron DNAT
     ↓
VM
10.10.0.x
```

Configurer :

- route AWS `192.168.250.0/24` vers le lab-host.

- `source_dest_check = false`.

- `net.ipv4.ip_forward = 1`.

- routage Linux.

- Netfilter/iptables.

- Security Groups AWS.

- Security Groups OpenStack.

- Floating IP.

- SSH.

---

# 10. Construire la stratégie de clés SSH

Séparer les accès AWS et OpenStack.

Utiliser :

```text
clé AWS
    ↓
lab-host / ops-runner
clé workloads OpenStack
    ↓
Jenkins / PostgreSQL / OpenShift VMs
```

La clé privée OpenStack ne doit jamais être stockée dans Git ni Terraform State.

Stocker la clé privée de manière sécurisée, par exemple dans :

```text
AWS SSM Parameter Store
```

L’ops-runner récupère cette clé au bootstrap et l’utilise pour Ansible.

---

# 11. Construire les Security Groups communs OpenStack

Créer un Security Group générique :

```text
lab-management
```

Responsabilité :

- SSH d’administration.

- ICMP lorsque nécessaire.

- flux communs aux workloads administrés.

Puis créer des Security Groups spécifiques par service :

```text
jenkins
postgresql
openshift
monitoring
etc.
```

Pattern :

```text
VM
│
├── lab-management
│
└── service-specific-security-group
```

Les Security Groups attachés à un même port sont additifs.

---

# 12. Construire un module Terraform générique pour les VMs OpenStack

Créer un module réutilisable :

```text
modules/compute-instance/
```

Le module doit pouvoir créer :

```text
Neutron Port
     \+
Nova VM
     \+
Security Groups
     \+
Floating IP optionnelle
     \+
Cinder Volume optionnel
```

Paramètres :

- hostname.

- image.

- flavor.

- fixed IP.

- network.

- subnet.

- keypair.

- Security Groups.

- volume data.

- Floating IP.

- metadata.

- tags.

Ce module devient le pattern standard pour les VMs du projet.

---

# 13. Construire l’image Ubuntu workload

Importer une image Ubuntu propre dans Glance.

Gérer avec Terraform :

- image URL/source.

- checksum.

- disk format.

- container format.

- visibilité.

- version.

L’image devient la base commune pour :

- Jenkins.

- PostgreSQL.

- OpenShift nodes.

- autres VMs de plateforme.

---

# 14. Créer la VM Jenkins

Créer avec Terraform :

```text
jenkins-controller
│
├── Neutron Port
├── fixed IP
├── Nova root disk
├── lab-management SG
├── jenkins SG
├── Floating IP
└── Cinder data volume
```

Architecture :

```text
Jenkins
10.10.0.20
│
├── root disk
│   └── Nova local storage
│
└── data disk
    └── Cinder
```

Le disque root contient le système.

Le volume Cinder contient les données persistantes Jenkins.

---

# 15. Construire l’inventory Ansible des workloads

Depuis l’ops-runner, créer une stratégie d’inventory permettant à Ansible d’atteindre les VMs OpenStack.

Structure :

```text
infrastructure/ansible/
├── inventories/
│   ├── dev/
│   ├── uat/
│   └── prod/
├── group_vars/
├── host_vars/
├── roles/
└── playbooks/
```

Définir :

- IPs d’administration.

- user SSH.

- clé SSH.

- groupes fonctionnels.

- variables communes.

- variables spécifiques.

Exemple :

```text
all
├── jenkins
├── postgresql
└── openshift
    ├── control_plane
    └── workers
```

---

# 16. Construire un rôle Ansible OS baseline

Créer un rôle générique appliqué aux workloads.

Configurer :

- hostname.

- timezone.

- packages.

- users.

- sudo.

- SSH.

- repositories.

- updates.

- outils debug.

- filesystem tools.

- logging.

- chrony.

- limits système.

Ce rôle doit être réutilisable sur :

```text
Jenkins
PostgreSQL
OpenShift nodes
Monitoring nodes
```

---

# 17. Construire un rôle Ansible de gestion des volumes Cinder

Le rôle doit :

1. détecter le volume attaché ;

2. vérifier s’il possède déjà un filesystem ;

3. créer le filesystem si nécessaire ;

4. créer le mount point ;

5. monter le volume ;

6. gérer `/etc/fstab` ;

7. préserver les données existantes ;

8. rester idempotent.

Pattern :

```text
Terraform
   ↓
Cinder Volume
   ↓
Nova attachment
   ↓
/dev/vdb
   ↓
Ansible
   ↓
filesystem
   ↓
mount
   ↓
service data
```

---

# 18. Configurer Jenkins avec Ansible

Créer un rôle Jenkins.

Installer :

- Java.

- repository Jenkins.

- package Jenkins.

- service systemd.

- plugins nécessaires.

- configuration initiale.

- users/configuration.

- credentials.

- paramètres JVM.

- permissions.

Faire vivre les données Jenkins sur le volume Cinder.

Architecture :

```text
Ubuntu root disk
     ↓
Jenkins binaries
Cinder volume
     ↓
JENKINS_HOME
```

Valider l’idempotence :

```text
ansible-playbook #1
→ configure Jenkins
ansible-playbook #2
→ aucun changement inutile
```

---

# 19. Sécuriser Jenkins

Configurer :

- authentication.

- authorization.

- credentials.

- accès réseau.

- plugins minimaux.

- secrets.

- permissions filesystem.

- reverse proxy/TLS si retenu.

- sauvegarde de `JENKINS_HOME`.

Limiter l’accès au port Jenkins aux réseaux réellement nécessaires.

---

# 19A. Construire et valider le Jenkins Worker / Agent

Avant de poursuivre l’infrastructure de plateforme, créer un worker Jenkins dédié afin que le controller reste uniquement le cerveau d’orchestration.

Créer avec Terraform OpenStack :

```text
jenkins-agent-01
│
├── Neutron Port
├── fixed IP privée
├── Security Groups
├── Floating IP d’administration si nécessaire
└── Nova root disk
```

Configurer avec Ansible :

- Java 21 ;
- Git ;
- Maven ;
- utilisateur et répertoires de travail Jenkins ;
- prérequis Jenkins Remoting / connexion agent ;
- accès SSH strictement nécessaire ;
- labels Jenkins, par exemple `java-maven`.

Le flux controller/worker doit utiliser le réseau privé OpenStack :

```text
Jenkins Controller
10.10.0.20
      │
      │ Jenkins Remoting / SSH
      ▼
Jenkins Agent
10.10.0.x
```

Tester le worker avec un code Java volontairement minimaliste, uniquement pour valider l’infrastructure Jenkins avant de commencer les vraies applications :

```text
Git checkout
    ↓
Maven compile
    ↓
Maven test
    ↓
Maven package
    ↓
minimal-app.jar
```

Valider que :

- le job est exécuté sur le worker et non sur le controller ;
- Java et Maven fonctionnent ;
- le controller reçoit les logs du worker ;
- le JAR est archivé par Jenkins ;
- la configuration du worker est rejouable via Terraform + Ansible ;
- le worker est intégré à `make configure-lab` afin de ne pas ajouter une commande manuelle au rebuild quotidien.

---

# 20. Créer la VM PostgreSQL

Créer avec Terraform :

```text
postgresql
│
├── Nova VM
├── fixed IP
├── Security Groups
├── root disk
└── Cinder data volume
```

Utiliser :

```text
lab-management
\+
postgresql
```

comme Security Groups.

---

# 21. Configurer PostgreSQL avec Ansible

Créer un rôle PostgreSQL.

Configurer :

- package PostgreSQL.

- filesystem Cinder.

- data directory.

- service.

- users.

- roles.

- databases.

- permissions.

- `postgresql.conf`.

- `pg_hba.conf`.

- écoute réseau.

- authentication.

- logs.

Architecture :

```text
Application
    ↓
PostgreSQL
    ↓
Cinder
```

---

# 22. Ajouter sauvegarde et restauration PostgreSQL

Mettre en place :

- dumps.

- rétention.

- stockage des backups.

- restauration.

- procédure de recovery.

- tests de restauration.

Créer un runbook :

```text
backup
   ↓
failure
   ↓
restore
   ↓
validation
```

---

# 23. Définir l’architecture OpenShift / OKD

Déterminer les rôles nécessaires au cluster.

Exemple :

```text
OpenStack
│
├── control-plane nodes
│
├── worker nodes
└── infrastructure réseau/storage
```

Définir :

- nombre de nodes.

- CPU.

- RAM.

- disk.

- IPs.

- DNS.

- Security Groups.

- accès admin.

- storage.

- réseau.

---

# 24. Créer les VMs OpenShift avec Terraform

Créer l’ensemble du cluster comme une unité logique.

Utiliser le module compute générique.

Créer :

- ports Neutron.

- fixed IPs.

- Nova instances.

- Security Groups.

- volumes.

- Floating IPs uniquement lorsque nécessaires.

Architecture :

```text
OpenStack
      │
      ├── control-plane-01
      ├── control-plane-02
      ├── control-plane-03
      ├── worker-01
      └── worker-02
```

La topologie exacte peut être adaptée aux ressources disponibles dans le lab.

---

# 25. Préparer les nodes OpenShift avec Ansible

Créer un rôle commun OpenShift nodes.

Configurer :

- hostname.

- DNS.

- kernel parameters.

- container runtime prérequis.

- packages.

- networking.

- storage.

- SSH.

- NTP.

- firewall.

- users.

- limits.

---

# 26. Installer OpenShift / OKD

Déployer le cluster.

Chaîne :

```text
Terraform
    ↓
OpenStack VMs
    ↓
Ansible / installer
    ↓
OpenShift / OKD
```

Configurer :

- control plane.

- workers.

- networking.

- DNS.

- API.

- ingress.

- authentication.

- operators.

- storage.

Valider :

```bash
oc get nodes
oc get pods -A
oc get clusteroperators
```

---

# 27. Construire la couche plateforme OpenShift

Créer les composants de plateforme :

- Projects / Namespaces.

- ServiceAccounts.

- RBAC.

- Secrets.

- ConfigMaps.

- ResourceQuotas.

- LimitRanges.

- NetworkPolicies.

- StorageClasses.

- PVC.

- Services.

- Routes.

- Ingress.

- PodDisruptionBudgets lorsque pertinent.

Organisation possible :

```text
OpenShift
│
├── private-banking-dev
├── private-banking-uat
├── private-banking-prod
└── observability
```

---

# 28. Construire l’application Java

Créer :

```text
applications/portfolio-java/
```

Inclure :

- application Spring Boot.

- API REST.

- logique métier simple.

- accès PostgreSQL.

- tests unitaires.

- tests d’intégration.

- configuration externalisée.

- health endpoints.

- metrics.

- logs structurés.

Architecture :

```text
Client
  ↓
Portfolio Java API
  ↓
PostgreSQL
```

---

# 29. Containeriser l’application Java

Créer un Dockerfile multi-stage.

Pipeline de build :

```text
source
  ↓
Maven/Gradle build
  ↓
tests
  ↓
JAR
  ↓
runtime container
```

Principes :

- image légère.

- user non-root.

- health check.

- configuration externe.

- secrets hors image.

- logs stdout/stderr.

---

# 30. Construire l’application .NET

Créer :

```text
applications/risk-engine-dotnet/
```

Inclure :

- API .NET.

- logique métier de calcul de risque.

- communication avec les autres composants.

- tests.

- health endpoints.

- metrics.

- logs.

Architecture possible :

```text
Portfolio Java
      ↓
Risk Engine .NET
```

---

# 31. Containeriser l’application .NET

Créer un Dockerfile multi-stage :

```text
source
   ↓
dotnet restore
   ↓
dotnet build
   ↓
dotnet test
   ↓
dotnet publish
   ↓
runtime image
```

Principes :

- image minimale.

- non-root.

- secrets externes.

- configuration externe.

- logs stdout/stderr.

---

# 32. Construire les Helm Charts

Créer :

```text
platform/helm/
├── portfolio-java/
└── risk-engine-dotnet/
```

Chaque chart doit gérer :

- Deployment.

- Service.

- Route/Ingress.

- ConfigMap.

- Secret references.

- ServiceAccount.

- requests.

- limits.

- livenessProbe.

- readinessProbe.

- replicas.

- autoscaling si nécessaire.

- NetworkPolicy.

- PVC si nécessaire.

Variables par environnement :

```text
values-dev.yaml
values-uat.yaml
values-prod.yaml
```

---

# 33. Construire la CI Jenkins

Créer les pipelines de build.

Flux Java :

```text
Git
 ↓
Jenkins
 ↓
checkout
 ↓
Maven/Gradle
 ↓
tests
 ↓
build
 ↓
container image
```

Flux .NET :

```text
Git
 ↓
Jenkins
 ↓
checkout
 ↓
dotnet restore
 ↓
dotnet test
 ↓
dotnet publish
 ↓
container image
```

---

# 34. Mettre en place un Container Registry

Définir le registry utilisé par Jenkins et OpenShift.

Flux :

```text
Jenkins
   ↓
build image
   ↓
push
   ↓
Container Registry
   ↓
OpenShift pull
```

Gérer :

- authentication.

- credentials.

- tags.

- versioning.

- nettoyage.

- permissions.

---

# 35. Construire la CD Jenkins vers OpenShift

Pipeline cible :

```text
Developer
    ↓
Git push
    ↓
Jenkins
    ↓
Tests
    ↓
Build
    ↓
Container image
    ↓
Registry
    ↓
Helm
    ↓
OpenShift
```

Gérer :

- environnement dev.

- UAT.

- prod simulée.

- promotion.

- approbations.

- rollback.

- versions.

- credentials OpenShift.

---

# 36. Construire une Jenkins Shared Library

Créer :

```text
cicd/jenkins/shared-library/
```

Factoriser les fonctions communes :

- checkout.

- Java build.

- .NET build.

- tests.

- image build.

- image push.

- Helm deploy.

- rollback.

- promotion.

- notifications.

- gestion des erreurs.

Objectif :

```text
Jenkinsfile application
        ↓
très simple
Shared Library
        ↓
logique commune
```

---

# 37. Ajouter Prometheus

Déployer Prometheus pour récupérer les métriques.

Sources :

- OpenShift.

- Kubernetes nodes.

- applications.

- Jenkins.

- PostgreSQL.

- Linux.

- éventuellement OpenStack.

Architecture :

```text
Targets
   ↓
Prometheus
   ↓
Metrics
```

---

# 38. Ajouter les exporters nécessaires

Ajouter selon les besoins :

```text
node-exporter
postgres-exporter
Jenkins metrics
application metrics
OpenShift metrics
```

Permettre à Prometheus de superviser :

- CPU.

- RAM.

- disk.

- network.

- application latency.

- HTTP errors.

- PostgreSQL.

- Jenkins pipelines.

---

# 39. Ajouter Grafana

Déployer Grafana.

Créer des dashboards :

- infrastructure.

- OpenStack workloads.

- Jenkins.

- PostgreSQL.

- OpenShift.

- Java application.

- .NET application.

- CPU/RAM/disk.

- HTTP latency.

- errors.

- availability.

Architecture :

```text
Prometheus
    ↓
Grafana
    ↓
Dashboards
```

---

# 40. Construire la centralisation des logs

Mettre en place une stack ELK/OpenSearch-like.

Collecter :

- logs Linux.

- logs Jenkins.

- logs PostgreSQL.

- logs OpenShift.

- logs Java.

- logs .NET.

- logs infrastructure.

Architecture :

```text
Applications
Infrastructure
OpenShift
Jenkins
PostgreSQL
     ↓
log collectors
     ↓
central log backend
     ↓
search / dashboards
```

---

# 41. Ajouter l’alerting

Créer des alertes pertinentes :

- VM down.

- OpenShift node unavailable.

- pod CrashLoopBackOff.

- application unavailable.

- CPU élevée.

- RAM élevée.

- disk presque plein.

- PostgreSQL down.

- Jenkins down.

- pipeline failure.

- HTTP error rate élevée.

- latence élevée.

Flux :

```text
Metric
  ↓
Alert rule
  ↓
Alert
  ↓
notification
```

---

# 42. Hardening AWS

Revoir :

- Security Groups.

- IAM.

- least privilege.

- SSM.

- SSH.

- EBS encryption.

- secrets.

- route tables.

- instance metadata.

- accès réseau.

---

# 43. Hardening du lab-host Linux

Revoir :

- Netfilter.

- iptables/nftables.

- INPUT.

- FORWARD.

- OUTPUT.

- SSH.

- users.

- sudo.

- services exposés.

- kernel parameters.

Évoluer progressivement vers :

```text
deny by default
\+
allow only required traffic
```

sans casser Neutron/Kolla.

---

# 44. Hardening OpenStack

Revoir :

- Keystone.

- credentials.

- Neutron Security Groups.

- admin access.

- project permissions.

- network isolation.

- Horizon.

- API exposure.

- Cinder.

- images.

- SSH keys.

---

# 45. Hardening PostgreSQL

Configurer :

- réseau limité.

- authentication.

- rôles.

- utilisateurs.

- permissions.

- backups.

- TLS si pertinent.

- secrets.

- logs.

- accès uniquement depuis les workloads autorisés.

---

# 46. Hardening Jenkins

Configurer :

- authentication.

- RBAC.

- credentials.

- agents.

- permissions.

- plugins minimaux.

- secrets.

- réseau.

- audit.

- sauvegarde.

---

# 47. Hardening OpenShift

Configurer :

- RBAC.

- ServiceAccounts.

- NetworkPolicies.

- namespaces.

- Secrets.

- SecurityContext.

- non-root.

- resource quotas.

- limits.

- permissions minimales.

---

# 48. Construire la stratégie de gestion des secrets

Répartir les secrets selon leur responsabilité.

Exemple :

```text
AWS SSM Parameter Store
├── bootstrap secrets
├── workload SSH private key
└── infrastructure secrets
HCP Terraform
├── OpenStack provider credentials
└── Terraform variables sensibles
Jenkins Credentials
├── registry
├── OpenShift
└── CI/CD secrets
OpenShift Secrets
└── runtime application secrets
```

Aucun secret ne doit être versionné dans Git.

---

# 49. Tester la persistance Jenkins

Tester :

```text
Jenkins fonctionne
       ↓
écrire données/configuration
       ↓
reboot VM
       ↓
validation
       ↓
recréation contrôlée
       ↓
validation Cinder
```

Vérifier que les données importantes restent persistantes.

---

# 50. Tester la persistance PostgreSQL

Créer des données de test.

Tester :

```text
insert data
   ↓
restart
   ↓
reboot
   ↓
backup
   ↓
restore
```

Valider la persistance Cinder.

---

# 51. Tester le redémarrage complet du lab-host

Tester :

```text
stop lab-host
     ↓
start lab-host
     ↓
Kolla services
     ↓
OpenStack
     ↓
VMs
     ↓
network
     ↓
storage
```

Valider :

- Docker.

- OVS.

- Kolla.

- Neutron.

- Cinder.

- Nova.

- workloads.

---

# 52. Tester la reconstruction d’une VM

Scénario :

```text
destroy VM
    ↓
Terraform apply
    ↓
nouvelle VM
    ↓
Ansible
    ↓
service opérationnel
```

Pour les données persistantes :

```text
Cinder
   ↓
réattachement/restauration
   ↓
service récupéré
```

---

# 53. Tester des incidents réseau

Créer volontairement :

- mauvaise route AWS.

- mauvaise route Linux.

- SG AWS incorrect.

- SG OpenStack incorrect.

- port SSH bloqué.

- Floating IP incorrecte.

- mauvaise DNAT.

- interface down.

- problème DNS.

Utiliser :

```text
ping
ip route
ip neigh
ss
nc
tcpdump
iptables
nft
openstack CLI
ovs-vsctl
ovs-ofctl
```

Documenter le diagnostic.

---

# 54. Tester des incidents OpenStack

Créer des scénarios :

- Nova instance ERROR.

- Neutron port incorrect.

- volume Cinder absent.

- Glance image incorrecte.

- router mal configuré.

- Security Group manquant.

- Floating IP non associée.

Documenter :

```text
symptôme
   ↓
diagnostic
   ↓
cause
   ↓
fix
   ↓
prévention
```

---

# 55. Tester des incidents OpenShift

Créer :

- CrashLoopBackOff.

- ImagePullBackOff.

- mauvaise readinessProbe.

- mauvaise livenessProbe.

- mauvais Secret.

- NetworkPolicy bloquante.

- PVC Pending.

- node unavailable.

- manque CPU/RAM.

Utiliser :

```bash
oc get
oc describe
oc logs
oc events
```

---

# 56. Tester des incidents applicatifs

Créer :

- PostgreSQL indisponible.

- API Java indisponible.

- Risk Engine indisponible.

- timeout réseau.

- credentials incorrects.

- mauvaise configuration.

- erreurs HTTP.

Vérifier que :

- logs permettent le diagnostic.

- métriques montrent l’anomalie.

- alerting détecte le problème.

---

# 57. Construire les runbooks

Créer des runbooks pour :

- démarrage du lab.

- arrêt du lab.

- reconstruction lab-host.

- reconstruction OpenStack.

- accès ops-runner.

- accès lab-host.

- accès Jenkins.

- accès PostgreSQL.

- accès OpenShift.

- troubleshooting réseau.

- troubleshooting Neutron.

- troubleshooting Nova.

- troubleshooting Cinder.

- troubleshooting Jenkins.

- troubleshooting PostgreSQL.

- troubleshooting OpenShift.

- backup.

- restore.

---

# 58. Construire les scripts d’exploitation

Créer des scripts dans :

```text
scripts/
```

Pour :

- start lab.

- stop lab.

- status lab.

- bootstrap.

- health checks.

- backup.

- cleanup.

- validation réseau.

- validation OpenStack.

- validation workloads.

---

# 59. Ajouter des health checks globaux

Construire un script qui vérifie :

```text
AWS
 ↓
lab-host reachable
 ↓
OpenStack APIs
 ↓
Nova
 ↓
Neutron
 ↓
Cinder
 ↓
Jenkins
 ↓
PostgreSQL
 ↓
OpenShift
 ↓
applications
```

Produire un résumé simple :

```text
AWS          OK
OpenStack    OK
Jenkins      OK
PostgreSQL   OK
OpenShift    OK
Java API     OK
.NET API     OK
Monitoring   OK
```

---

# 60. Optimiser les coûts AWS

Surveiller :

- lab-host.

- ops-runner.

- EBS.

- snapshots.

- trafic.

- ressources inutilisées.

Utiliser :

- Spot lorsque pertinent.

- stop/start.

- nettoyage.

- volumes dimensionnés correctement.

Objectif :

\> garder le lab financièrement soutenable tout en conservant assez de ressources pour OpenStack et OpenShift.

---

# 61. Automatiser l’arrêt du lab

Éviter de laisser les EC2 tourner inutilement.

Prévoir :

```text
stop lab-host
stop ops-runner
```

tout en conservant :

```text
EBS
Terraform State
configuration Git
```

---

# 62. Automatiser le redémarrage du lab

Construire un processus :

```text
start AWS instances
      ↓
validation lab-host
      ↓
validation Kolla
      ↓
validation OpenStack APIs
      ↓
validation VMs
      ↓
validation Jenkins
      ↓
validation OpenShift
```

---

# 63. Documenter l’architecture AWS

Créer un diagramme :

```text
Internet
   ↓
AWS VPC
   │
   ├── ops-runner
   │
   └── lab-host
          │
          ├── EBS root
          ├── EBS /data
          └── EBS Cinder
```

Documenter :

- EC2.

- SG.

- routing.

- IAM.

- EBS.

- SSM.

- Spot.

- bootstrap.

---

# 64. Documenter l’architecture OpenStack

Créer un diagramme :

```text
Kolla-Ansible
      ↓
OpenStack
├── Keystone
├── Nova
├── Neutron
├── Glance
├── Cinder
├── Placement
├── Heat
└── Horizon
```

Documenter le rôle de chaque service.

---

# 65. Documenter l’architecture réseau

Créer un diagramme détaillé :

```text
AWS ops-runner
172.31.x.x
      ↓
AWS Route Table
      ↓
lab-host enp39s0
172.31.31.70
      ↓
Linux routing
      ↓
os-host
192.168.250.1
      ║
      ║ veth
      ║
os-ext
      ↓
br-ex
      ↓
public-net
192.168.250.0/24
      ↓
Neutron router
      ↓
private-net
10.10.0.0/24
      ↓
workloads
```

Documenter :

- L2.

- L3.

- NAT.

- Floating IP.

- SNAT.

- DNAT.

- Security Groups.

- Netfilter.

- OVS.

- Neutron.

---

# 66. Documenter l’architecture stockage

Créer :

```text
AWS EBS
│
├── root lab-host
│
├── /data
│   └── Docker / Nova local disks
│
└── Cinder EBS
    └── cinder-volumes VG
        ├── Jenkins data volume
        ├── PostgreSQL data volume
        └── autres persistent volumes
```

Documenter la différence entre :

- Nova local storage.

- Cinder block storage.

- EBS physique.

- Kubernetes/OpenShift persistent storage.

---

# 67. Documenter l’architecture CI/CD

Créer :

```text
Developer
   ↓
Git
   ↓
Jenkins
   ↓
Tests
   ↓
Build
   ↓
Container Registry
   ↓
Helm
   ↓
OpenShift
```

Documenter :

- Jenkinsfile.

- Shared Library.

- credentials.

- promotion.

- rollback.

- environnements.

---

# 68. Documenter l’observabilité

Créer :

```text
Infrastructure
Applications
OpenShift
PostgreSQL
Jenkins
      ↓
Metrics + Logs
      ↓
Prometheus / Logging backend
      ↓
Grafana / Search
      ↓
Alerts
```

---

# 69. Créer les ADR

Créer des Architecture Decision Records pour les décisions importantes :

- AWS comme infrastructure physique du lab.

- nested virtualization.

- OpenStack avec Kolla-Ansible.

- OpenStack All-In-One.

- Terraform pour provisioning.

- Ansible pour configuration.

- HCP Terraform Agent.

- ops-runner séparé.

- Neutron provider network.

- Cinder pour stockage persistant.

- Jenkins pour CI/CD.

- OpenShift/OKD pour plateforme.

- Helm pour déploiement.

- stratégie secrets.

- stratégie observabilité.

- stratégie réseau.

- stratégie de persistence.

---

# 70. Construire la documentation de reconstruction complète

Créer un guide permettant de repartir de zéro.

Chaîne :

```text
Git clone
   ↓
Terraform AWS
   ↓
lab-host + ops-runner
   ↓
Ansible bootstrap
   ↓
Kolla-Ansible
   ↓
OpenStack
   ↓
Terraform OpenStack
   ↓
VMs
   ↓
Ansible workloads
   ↓
Jenkins / PostgreSQL
   ↓
OpenShift
   ↓
applications
   ↓
observability
```

---

# 71. Construire un scénario de démonstration CI/CD final

Scénario :

```text
1. Modifier portfolio-java
        ↓
2. git commit
        ↓
3. git push
        ↓
4. Jenkins démarre
        ↓
5. tests Java
        ↓
6. build
        ↓
7. création image
        ↓
8. push registry
        ↓
9. Helm upgrade
        ↓
10. OpenShift effectue le rollout
        ↓
11. readinessProbe valide
        ↓
12. application disponible
```

---

# 72. Construire un scénario de communication inter-applications

Architecture :

```text
Client
   ↓
Portfolio Java
   ↓
Risk Engine .NET
   ↓
PostgreSQL
```

Vérifier :

- DNS.

- Service discovery.

- NetworkPolicies.

- authentication si mise en place.

- timeouts.

- retries.

- logs.

- métriques.

---

# 73. Construire un scénario de rollback

Créer volontairement une mauvaise release.

Flux :

```text
v1 fonctionne
   ↓
deploy v2
   ↓
health check KO
   ↓
rollback
   ↓
v1 restaurée
```

Documenter le processus Jenkins + Helm.

---

# 74. Construire un scénario de montée en charge

Générer du trafic sur les applications.

Observer :

```text
requests
   ↓
pods
   ↓
CPU/RAM
   ↓
Prometheus
   ↓
Grafana
```

Tester si pertinent :

- replicas.

- HPA.

- requests/limits.

- saturation PostgreSQL.

- latence.

---

# 75. Construire un scénario d’incident complet

Exemple :

```text
Security Group modifié
        ↓
Portfolio ne joint plus PostgreSQL
        ↓
HTTP errors
        ↓
Prometheus détecte
        ↓
Grafana montre l’erreur
        ↓
logs montrent timeout DB
        ↓
tcpdump / nc
        ↓
SG identifié
        ↓
Terraform corrige
        ↓
service restauré
```

Objectif :

\> démontrer une vraie démarche DevOps/SRE de diagnostic.

---

# 76. Vérifier l’idempotence de l’ensemble

Tester plusieurs fois :

```text
terraform plan
ansible-playbook
helm upgrade
```

Résultat attendu lorsqu’aucune modification n’est nécessaire :

```text
Terraform
→ 0 add
→ 0 change
→ 0 destroy
Ansible
→ changed=0 ou changements strictement attendus
Helm
→ aucun drift involontaire
```

---

# 77. Vérifier le principe Infrastructure as Code

S’assurer que les éléments importants sont définis dans Git :

```text
AWS infrastructure
OpenStack infrastructure
networking
Security Groups
VMs
storage
Ansible configuration
OpenShift configuration
Helm charts
Jenkins pipelines
observability
documentation
```

Les actions manuelles restantes doivent être :

- exceptionnelles ;

- documentées ;

- idéalement automatisées ensuite.

---

# 78. Nettoyer et standardiser le repository

Avant clôture :

- supprimer fichiers temporaires.

- supprimer scripts obsolètes.

- supprimer secrets.

- harmoniser naming.

- harmoniser variables.

- commenter les éléments non évidents.

- vérifier `.gitignore`.

- vérifier README.

- vérifier Terraform formatting.

- vérifier Ansible linting.

- vérifier YAML.

- vérifier Dockerfiles.

- vérifier Helm templates.

---

# 79. Construire le README principal

Le README doit permettre de comprendre rapidement :

1. ce qu’est le projet ;

2. pourquoi il existe ;

3. son architecture ;

4. les technologies ;

5. comment démarrer ;

6. comment arrêter ;

7. comment reconstruire ;

8. comment déployer ;

9. comment diagnostiquer ;

10. où trouver les runbooks.

---

# 80. Construire la documentation portfolio / entretien

Préparer une version présentable du projet.

Présenter :

```text
Problème
   ↓
Architecture
   ↓
Choix techniques
   ↓
Automatisation
   ↓
Sécurité
   ↓
CI/CD
   ↓
Observabilité
   ↓
Incidents rencontrés
   ↓
Troubleshooting
   ↓
Résultats
```

Être capable d’expliquer :

- Terraform vs Ansible.

- AWS vs OpenStack.

- Nova vs Cinder.

- Neutron networking.

- Floating IP.

- Security Groups.

- Kolla-Ansible.

- Jenkins.

- OpenShift.

- Helm.

- Prometheus/Grafana.

- CI/CD.

- IaC.

- persistence.

- troubleshooting réseau.

---

# 81. Architecture finale cible

```text
                                   GIT
                                    │
                 ┌──────────────────┴───────────────────┐
                 │                                      │
                 ▼                                      ▼
          HCP Terraform                              Jenkins
                 │                                      │
                 ▼                                      │
            ops-runner                                  │
                 │                                      │
        ┌────────┴────────┐                             │
        │                 │                             │
        ▼                 ▼                             │
    Terraform          Ansible                          │
        │                 │                             │
        └────────┬────────┘                             │
                 │                                      │
                 ▼                                      │
              OpenStack                                 │
                 │                                      │
     ┌───────────┼─────────────────┐                    │
     │           │                 │                    │
     ▼           ▼                 ▼                    │
 Jenkins     PostgreSQL       OpenShift / OKD ◄─────────┘
     │           │                 │
     │           │       ┌─────────┴─────────┐
     │           │       │                   │
     ▼           ▼       ▼                   ▼
  Cinder      Cinder  Portfolio Java    Risk Engine .NET
                            │                   │
                            └─────────┬─────────┘
                                      │
                                      ▼
                                 PostgreSQL
                 OpenShift workloads
                        │
             ┌──────────┴───────────┐
             │                      │
             ▼                      ▼
         Prometheus               Logs
             │                      │
             ▼                      ▼
          Grafana            ELK/OpenSearch
```

Sous OpenStack :

```text
OpenStack
│
├── Keystone
├── Nova
├── Neutron
├── Glance
├── Placement
├── Cinder
├── Heat
├── Horizon
└── Open vSwitch
```

Sous OpenStack se trouve finalement l’infrastructure AWS :

```text
OpenStack
    ↓
Kolla containers
    ↓
Docker
    ↓
Ubuntu lab-host
    ↓
KVM / nested virtualization
    ↓
AWS EC2
    ↓
AWS VPC + EBS
```

---

# 82. Chaîne technologique finale

```text
AWS
 ↓
EC2
 ↓
Linux
 ↓
KVM + Docker
 ↓
Kolla-Ansible
 ↓
OpenStack
 ↓
Nova + Neutron + Cinder
 ↓
OpenStack VMs
 ↓
Ansible
 ↓
Jenkins + PostgreSQL + OpenShift
 ↓
Kubernetes/OpenShift
 ↓
Helm
 ↓
Java + .NET
 ↓
Prometheus + Grafana + Logs
```

CI/CD :

```text
Git
 ↓
Jenkins
 ↓
Build
 ↓
Tests
 ↓
Container image
 ↓
Registry
 ↓
Helm
 ↓
OpenShift
 ↓
Application
```

Infrastructure :

```text
Git
 ↓
HCP Terraform
 ↓
ops-runner
 ↓
Terraform OpenStack
 ↓
OpenStack APIs
 ↓
Infrastructure
```

Configuration :

```text
Git
 ↓
ops-runner
 ↓
Ansible
 ↓
VMs OpenStack
 ↓
Services configurés
```

---

# 83. Principe directeur du projet

```text
Terraform
= crée les ressources
Ansible
= configure les systèmes
Kolla-Ansible
= déploie OpenStack
OpenStack
= fournit l’IaaS privé
Cinder
= fournit le stockage bloc persistant
Neutron
= fournit le réseau virtuel
Nova
= fournit le compute
OpenShift
= fournit la plateforme applicative
Helm
= décrit et déploie les workloads
Jenkins
= automatise CI/CD
Prometheus
= collecte les métriques
Grafana
= visualise les métriques
Logging stack
= centralise les logs
Git
= source de vérité
```

---

# 84. Objectif final

Construire une plateforme DevOps/private-cloud complète permettant de démontrer toute la chaîne :

```text
Infrastructure AWS
        ↓
Private Cloud OpenStack
        ↓
Compute + Network + Storage
        ↓
Configuration Ansible
        ↓
Jenkins + PostgreSQL
        ↓
OpenShift / Kubernetes
        ↓
Applications Java + .NET
        ↓
CI/CD
        ↓
Observabilité
        ↓
Sécurité
        ↓
Résilience
        ↓
Troubleshooting
```

Le projet final doit être :

- reproductible ;

- automatisé ;

- versionné ;

- idempotent ;

- sécurisé ;

- observable ;

- documenté ;

- exploitable ;

- démontrable ;

- reconstruisible à partir du code.
