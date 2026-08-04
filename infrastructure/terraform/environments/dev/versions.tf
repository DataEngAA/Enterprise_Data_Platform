# Terraform and provider version constraints.
#
# Same floor as infrastructure/terraform/bootstrap/versions.tf -- native S3
# state locking (`use_lockfile`, see backend.tf) requires Terraform 1.10+
# here too, and there is no reason for the two root modules in this project
# to diverge on Terraform version support
# (Dev_Environment_Terraform_Implementation_Plan.md Section 39).
#
# The exact AWS provider version is re-verified against the Terraform
# Registry immediately before `terraform init` is actually run (not part of
# this file-creation task) and is then recorded concretely in this root
# module's own, independent .terraform.lock.hcl -- not shared with
# bootstrap's lock file (Terraform_Bootstrap_Design.md Section 20).

terraform {
  required_version = ">= 1.10.0, < 2.0.0"

  required_providers {
    aws = {
      source = "hashicorp/aws"

      # Same working-assumption floor as bootstrap/versions.tf. Confirm the
      # AWS provider's latest compatible version from the Terraform
      # Registry (https://registry.terraform.io/providers/hashicorp/aws/latest)
      # immediately before running `terraform init` for this root module,
      # and adjust this constraint if a newer major version is current.
      version = ">= 6.0.0, < 7.0.0"
    }
  }
}
