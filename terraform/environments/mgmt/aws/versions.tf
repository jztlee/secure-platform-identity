terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.60"
    }
  }

  cloud {
    organization = "velteca-org"

    workspaces {
      name = "aws-mgmt-scp"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}