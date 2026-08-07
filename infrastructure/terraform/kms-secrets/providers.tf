# Provider configuration for the kms-secrets root module.
#
# DESIGN DECISION (DEPARTS FROM logging/providers.tf's human-direct
# pattern -- deliberate, not an oversight): this configuration authenticates
# by ASSUMING THE SHARED DEPLOYMENT ROLE, the same pattern
# environments/dev/providers.tf already uses -- not bootstrap/'s or
# logging/'s human-direct pattern.
#
# Reason (KMS_and_Secrets.md Section 10; ADR-0004 Option 3): this workstream
# explicitly designs new, narrowly scoped deployment-role permissions for
# KMS key/alias lifecycle management, Secrets Manager secret metadata, and
# Parameter Store parameter lifecycle (bootstrap/main.tf's new
# deployment_shared_kms_secrets_permissions policy). Routing this stack
# human-direct, as logging/ did, would make that new IAM design pointless --
# the whole point of adding those permissions is for the deployment role to
# be the one that actually applies this stack. This is a deliberate
# departure from logging/'s own precedent, recorded here explicitly rather
# than left as an unexplained inconsistency between the two stacks.

provider "aws" {
  region = var.aws_region

  # Same wrong-account safety pattern as every other root module in this
  # project: the provider checks the active (post-assume-role) credentials'
  # account via AWS STS during provider configuration and refuses to operate
  # if it does not match, rather than silently running against an
  # unapproved account.
  allowed_account_ids = [var.aws_account_id]

  # Resource-management API calls (creating/reading/updating the KMS key,
  # alias, key policy, the demonstration Secrets Manager secret, and the
  # demonstration Parameter Store parameter) are made AS the shared
  # deployment role, not as whatever identity invoked Terraform. This is a
  # functionally SEPARATE AssumeRole call from the one backend.hcl's own
  # assume_role block makes for state storage access -- distinct
  # session_name so the two calls are individually visible in CloudTrail,
  # matching environments/dev/providers.tf's identical pattern.
  assume_role {
    role_arn     = var.deployment_role_arn
    session_name = "terraform-kms-secrets-provider"
  }

  default_tags {
    tags = local.common_tags
  }
}
