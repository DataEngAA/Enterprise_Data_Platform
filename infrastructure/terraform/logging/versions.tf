# Terraform and provider version constraints.
#
# Exact patch/minor versions are intentionally NOT pinned here, matching
# bootstrap/versions.tf and environments/dev/versions.tf -- the exact
# versions actually in use are verified immediately before `terraform init`
# and recorded in the generated .terraform.lock.hcl file, not invented here.

terraform {
  # Native S3 state locking (`use_lockfile`, see backend.tf) requires
  # Terraform 1.10 or later, matching every other root module in this
  # project. No DynamoDB locking table is used.
  required_version = ">= 1.10.0, < 2.0.0"

  required_providers {
    aws = {
      source = "hashicorp/aws"

      # Same pessimistic constraint as bootstrap/versions.tf and
      # environments/dev/versions.tf. Confirm the AWS provider's latest
      # compatible version from the Terraform Registry immediately before
      # running `terraform init`.
      version = ">= 6.0.0, < 7.0.0"
    }
  }
}
