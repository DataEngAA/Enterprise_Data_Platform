# AWS provider configuration for environments/dev.
#
# No credential, access key, or profile name appears anywhere in this file
# -- the provider authenticates by assuming the shared deployment role
# (assume_role block below); the identity/credentials used to reach THAT
# role in the first place come from whatever is invoking Terraform (a
# human's MFA-authenticated session during the human-administered interim
# period, or later the EC2 workstation's own instance-profile credentials
# once Bootstrap Update 2 has landed -- see README.md "Provider Role
# Assumption").
#
# NOT initialized as part of this task. No `terraform init`/`plan`/`apply`
# has been run against this file.

provider "aws" {
  region = var.region

  # Same wrong-account safety pattern as bootstrap/providers.tf: the
  # provider checks the active (post-assume-role) credentials' account via
  # AWS STS during provider configuration and refuses to operate if it does
  # not match, rather than silently running against an unapproved account.
  allowed_account_ids = [var.aws_account_id]

  # Resource-management API calls (creating/reading/updating the VPC,
  # workstation IAM role, security group, EC2 instance) are made AS the
  # shared deployment role, not as whatever identity invoked Terraform.
  # This is a functionally SEPARATE AssumeRole call from the one
  # backend.hcl's own assume_role block makes for state storage access
  # (Section 9) -- distinct session_name so the two calls are individually
  # visible in CloudTrail.
  assume_role {
    role_arn     = var.deployment_role_arn
    session_name = "terraform-dev-provider"
  }

  default_tags {
    tags = local.common_tags
  }
}
