# Provider configuration for the logging root module.
#
# DESIGN DECISION (not modifying bootstrap/ or environments/dev/ IAM):
# this configuration runs directly as the human bootstrap identity's own AWS
# credentials, with NO `assume_role` block -- deliberately mirroring
# bootstrap/providers.tf's pattern, not environments/dev/providers.tf's
# pattern.
#
# Reason: CloudTrail, the dedicated audit-log S3 bucket, the CloudTrail-to-
# CloudWatch-Logs service role, the SNS topic, and the security-event alarms
# are account-level, shared resources analogous to bootstrap's own state
# bucket and deployment role (02_Infrastructure/Logging_and_Audit.md Section
# 8; ADR-0002 Option 3) -- not environment-owned infrastructure the shared
# deployment role exists to manage. The shared deployment role's current IAM
# permissions (infrastructure/terraform/bootstrap/main.tf) grant nothing for
# cloudtrail:*, logs:*, sns:*, or creating a new, non-runtime, non-workstation
# IAM service role -- routing this stack through the deployment role would
# have required expanding the deployment role's own permissions in
# bootstrap/main.tf, which the approved scope for this task explicitly
# excludes unless unavoidable. Running this stack human-direct, exactly like
# bootstrap/, avoids that dependency entirely -- no bootstrap or
# environments/dev resource is touched by this stack.

provider "aws" {
  region = var.aws_region

  # Same wrong-account safety pattern as bootstrap/providers.tf: the
  # provider checks the active credentials' account via AWS STS during
  # provider configuration and refuses to operate against any resource in
  # this configuration if it does not match.
  allowed_account_ids = [var.aws_account_id]

  default_tags {
    tags = local.common_tags
  }
}
