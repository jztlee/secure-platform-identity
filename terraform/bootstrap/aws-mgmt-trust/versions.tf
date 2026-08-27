terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.60"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }

  cloud {
    organization = "velteca-org"

    workspaces {
      name = "bootstrap-mgmt-trust"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}