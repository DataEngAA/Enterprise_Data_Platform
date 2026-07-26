# Terraform and provider version constraints.
#
# Exact patch/minor versions are intentionally NOT pinned to a specific
# value here. Per the approved design (02_Infrastructure/Terraform_Bootstrap_Design.md
# Sections 3-4) and the implementation plan
# (16_Implementation_Notes/Terraform_Bootstrap_Implementation_Plan.md Section 13),
# the exact Terraform and AWS provider versions actually in use are verified
# immediately before `terraform init` is run (not part of this task) and are
# then recorded concretely in the generated .terraform.lock.hcl file -- not
# invented here.

terraform {
  # Native S3 state locking (`use_lockfile`, see backend.tf) requires
  # Terraform 1.10 or later. No DynamoDB locking table is used.
  required_version = ">= 1.10.0, < 2.0.0"

  required_providers {
    aws = {
      source = "hashicorp/aws"

      # Pessimistic constraint against the AWS provider's current stable
      # major version series (6.x -- corrected 2026-07-25 static review;
      # 5.x is no longer current). This floor is a working assumption, not
      # a verified-today exact version -- confirm the AWS provider's latest
      # compatible version from the Terraform Registry
      # (https://registry.terraform.io/providers/hashicorp/aws/latest)
      # immediately before running `terraform init`, and adjust this
      # constraint if a newer major version is the current, compatible one.
      version = ">= 6.0.0, < 7.0.0"
    }
  }
}
