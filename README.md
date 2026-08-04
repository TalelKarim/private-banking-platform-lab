# Private Banking Platform Lab

## Overview

This project is a personal DevOps and platform engineering lab designed to reproduce a realistic private banking infrastructure and application environment.

The objective is to build and operate a complete platform combining private cloud infrastructure, container orchestration, infrastructure as code, configuration management, CI/CD, observability, and enterprise application workloads.

The lab is intentionally designed around technologies commonly found in large financial institutions and hybrid cloud environments.

## Main Objectives

The project focuses on:

* Deploying and operating a private cloud with OpenStack
* Running OpenShift / Kubernetes on top of OpenStack infrastructure
* Provisioning infrastructure using Terraform
* Automating system and application configuration using Ansible and Jinja2
* Building CI/CD pipelines with Jenkins and Shared Libraries
* Deploying Java / Spring Boot and C# / ASP.NET Core applications
* Managing application artifacts and code quality with Artifactory and SonarQube
* Implementing monitoring and logging with Prometheus, Grafana, and ELK
* Practicing production operations, troubleshooting, upgrades, rollback procedures, and incident management

## Architecture

The lab follows a layered architecture:

```text
AWS
└── EC2 Spot Instance
    └── Linux + KVM
        └── OpenStack
            ├── Networking — Neutron
            ├── Compute — Nova
            ├── Storage — Cinder
            ├── Images — Glance
            ├── Identity — Keystone
            │
            ├── PostgreSQL VM
            ├── DevOps Tools VM
            └── OpenShift VM
                └── OpenShift / Kubernetes
                    ├── Portfolio Management Core
                    │   └── Java / Spring Boot
                    │
                    └── Risk & Reporting Engine
                        └── C# / ASP.NET Core
```

AWS is only used as the underlying infrastructure hosting the lab. OpenStack acts as the private cloud platform used to provision and manage the virtual infrastructure.

## Infrastructure and Automation

The project uses several complementary automation layers:

* **Terraform AWS Provider** — provisions the AWS infrastructure hosting the lab
* **Kolla-Ansible** — deploys the OpenStack platform
* **Terraform OpenStack Provider** — provisions networks, virtual machines, and volumes inside OpenStack
* **Ansible** — configures operating systems, databases, middleware, and DevOps tools
* **Jinja2** — manages environment-specific configuration templates
* **OpenShift / Kubernetes manifests and Helm** — manage containerized workloads
* **Jenkins** — automates build, test, quality checks, artifact publication, and deployment

## Applications

### Portfolio Management Core

Java / Spring Boot application responsible for portfolio management, transactions, positions, valuation, batch processing, and audit operations.

### Risk & Reporting Engine

C# / ASP.NET Core application responsible for risk calculations, exposure analysis, stress scenarios, and reporting.

The applications are intentionally designed to generate realistic operational scenarios involving CPU, memory, JVM/.NET runtime behavior, database performance, networking, and application configuration.

## Observability

The platform includes:

* Prometheus for metrics collection
* Grafana for dashboards and operational monitoring
* ELK for centralized logging and troubleshooting

The lab will also include simulated production incidents to practice Run, MCO, troubleshooting, rollback, and performance analysis.

## Repository Structure

```text
private-banking-platform-lab/
├── infrastructure/
│   ├── terraform/
│   ├── openstack/
│   └── ansible/
├── platform/
│   ├── openshift/
│   └── helm/
├── applications/
│   ├── portfolio-java/
│   └── risk-engine-dotnet/
├── cicd/
│   └── jenkins/
├── observability/
├── scripts/
└── docs/
```

## Status

The project is currently under active development.

The first phase focuses on building the underlying AWS and OpenStack infrastructure before progressively adding OpenShift, application workloads, CI/CD, automation, and observability.
