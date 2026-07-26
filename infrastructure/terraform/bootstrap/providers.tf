# Provider configuration for the bootstrap root module.
#
# This configuration runs directly as the human bootstrap identity's own
# AWS credentials (e.g. `aws configure`, an SSO profile, or environment
# variables set outside Terraform) -- there is deliberately no
# `assume_role` block here.
#
# Rationale (Terraform_Bootstrap_Design.md Section 2, Section 19): the
# Terraform deployment role does not exist until THIS configuration creates
# it, so it cannot be assumed by this same configuration's own provider.
# Bootstrap is the one place in this project where Terraform runs as the
# human identity directly rather than via an assumed role.

provider "aws" {
  region = var.aws_region

  # Safety check (added 2026-07-25 static review, wording corrected in a
  # later pass): during provider configuration, the AWS provider calls AWS
  # STS (GetCallerIdentity) to determine which account the active
  # credentials belong to, and compares it against this list. It does NOT
  # stop that one STS call itself -- it prevents every subsequent
  # resource-management operation (plan/apply against any resource in this
  # configuration) if the account does not match, rather than silently
  # operating against the wrong account. var.aws_account_id has no default
  # and is never invented (variables.tf).
  allowed_account_ids = [var.aws_account_id]

  default_tags {
    tags = local.common_tags
  }
}
