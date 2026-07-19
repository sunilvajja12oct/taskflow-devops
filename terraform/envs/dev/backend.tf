terraform {
  required_version = ">= 1.7.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  backend "s3" {
    key            = "dev/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "taskflow-tf-locks"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region

  # Applied to every resource automatically - satisfies the repo's
  # tagging convention without repeating a tags block everywhere.
  default_tags {
    tags = {
      Project     = "taskflow"
      Environment = var.environment
      Owner       = var.owner
      CostCenter  = "learning"
      TTL         = "manual-cleanup"
    }
  }
}
