terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "enhanceit-tfstate-dr"
    key            = "disaster-recovery/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-state-lock"
    encrypt        = true
  }
}

# Primary region — us-east-1
provider "aws" {
  alias  = "primary"
  region = var.primary_region

  default_tags {
    tags = {
      Project     = "disaster-recovery"
      Environment = var.environment
      ManagedBy   = "terraform"
      Owner       = "TechConsulting"
    }
  }
}

# DR region — us-west-2
provider "aws" {
  alias  = "dr"
  region = var.dr_region

  default_tags {
    tags = {
      Project     = "disaster-recovery"
      Environment = "${var.environment}-dr"
      ManagedBy   = "terraform"
      Owner       = "TechConsulting"
    }
  }
}
