# Terraform and AWS provider version constraints for this module.
#
# REVISED 2026-07-26 (TFLint finding, first local validation gate) -- see
# modules/vpc/versions.tf for the full explanation. This module still
# configures NO provider block of its own; only the version constraint is
# added, matching environments/dev/versions.tf's constraint exactly.

terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0.0, < 7.0.0"
    }
  }
}
