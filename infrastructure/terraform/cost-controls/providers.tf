# Provider configuration for the cost-controls root module.
#
# DESIGN DECISION (matches kms-secrets/providers.tf and
# environments/dev/providers.tf -- DEPARTS from logging/providers.tf's
# human-direct pattern, deliberate, not an oversight): this configuration
# authenticates by ASSUMING THE SHARED DEPLOYMENT ROLE.
#
# Reason (10_Cost_and_FinOps/Cost_Controls.md Section 10; ADR-0005): this
# workstream explicitly designs new, narrowly scoped deployment-role
# permissions for AWS Budgets, EventBridge Scheduler, and a scoped
# ec2:StopInstances grant (bootstrap/main.tf's new
# deployment_shared_cost_controls_permissions policy). Routing this stack
# human-direct, as logging/ did, would make that new IAM design pointless --
# the whole point of adding those permissions is for the deployment role to
# be the one that actually applies this stack.

provider "aws" {
  region = var.aws_region

  # Same wrong-account safety pattern as every other root module in this
  # project: the provider checks the active (post-assume-role) credentials'
  # account via AWS STS during provider configuration and refuses to operate
  # if it does not match, rather than silently running against an
  # unapproved account.
  allowed_account_ids = [var.aws_account_id]

  # Resource-management API calls (creating/reading/updating the AWS Budget
  # and its notifications) are made AS the shared deployment role, not as
  # whatever identity invoked Terraform. This is a functionally SEPARATE
  # AssumeRole call from the one backend.hcl's own assume_role block makes
  # for state storage access -- distinct session_name so the two calls are
  # individually visible in CloudTrail, matching every other assume_role-
  # routed stack in this project.
  assume_role {
    role_arn     = var.deployment_role_arn
    session_name = "terraform-cost-controls-provider"
  }

  default_tags {
    tags = local.common_tags
  }
}
