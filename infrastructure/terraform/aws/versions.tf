terraform {
  required_version = ">= 1.10.0"

  backend "s3" {
    bucket       = "realtime-media-analytics-tfstate-156358246560-us-east-1"
    key          = "private-banking-platform-lab/aws/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.33"
    }

    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }

    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }

    http = {
      source  = "hashicorp/http"
      version = "~> 3.0"
    }
  }
}