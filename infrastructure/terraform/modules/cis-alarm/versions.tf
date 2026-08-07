# Terraform and AWS provider version constraints for this module.
# No provider block of its own -- matches every other module in this
# project (modules/vpc, modules/iam-workstation-role, modules/ec2-workstation).

terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0.0, < 7.0.0"
    }
  }
}
