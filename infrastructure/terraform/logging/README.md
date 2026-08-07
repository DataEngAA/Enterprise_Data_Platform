# infrastructure/terraform/logging

Status: **Deployed and validated on real AWS (2026-08-04). `Apply complete! Resources: 27 added, 0 changed, 0 destroyed.` A follow-up `terraform plan` reported `No changes. Your infrastructure matches the configuration.`** Implements the approved Phase 0 Logging and Audit Foundation design: `02_Infrastructure/Logging_and_Audit.md` and `01_Architecture/ADRs/ADR-0002-logging-and-audit-foundation.md`. Read both before making any change here — they are the authoritative source for every decision this configuration implements. This root module is the third Terraform root module in this project, alongside `bootstrap/` and `environments/dev/`. Full deployment/validation record: `16_Implementation_Notes/PROJECT_EXECUTION_JOURNAL.md` Section 27an.

## Architecture

A single root module owning the account-level, shared logging/audit foundation, plus one reusable module for the repeated security-alarm pattern:

- **This root module (`logging/`)** — the CloudTrail trail, the dedicated hardened S3 audit-log bucket and its policy, the CloudTrail-to-CloudWatch-Logs IAM role, the CloudWatch Logs log group, and the SNS topic + email subscription. All single-instance, account-level resources — not modularized, matching `bootstrap/`'s own precedent of keeping single-instance resources flat.
- **`modules/cis-alarm`** — a small, generic module wrapping exactly one CloudWatch Logs metric filter + CloudWatch alarm pair, instantiated 7 times via `for_each` over `local.cis_alarms` (`locals.tf`). Owns nothing else — no CloudTrail, S3, IAM role, or SNS resource lives inside it (`02_Infrastructure/Logging_and_Audit.md` Section 8; ADR-0002 Option 5).

**Not created by this stack**: any `aws_flow_log` resource or VPC-scoped log group — VPC Flow Logs are explicitly out of scope, owned by the networking workstream (`Logging_and_Audit.md` Section 6). No customer-managed KMS key (deferred to Phase 0 Step 7). No CloudTrail Insights, no data event selector, no organization trail.

## Why this stack authenticates human-direct, not via the shared deployment role

Unlike `environments/dev/`, this configuration's `providers.tf` and `backend.tf` have **no `assume_role` block** — they authenticate exactly like `bootstrap/` does, directly as the human bootstrap identity's own AWS credentials. This was a deliberate design choice made during implementation, not an oversight: the shared deployment role's current IAM permissions (`infrastructure/terraform/bootstrap/main.tf`) grant nothing for `cloudtrail:*`, `logs:*`, `sns:*`, or creating a new, non-runtime, non-workstation IAM service role (the CloudTrail-to-CloudWatch role this stack creates doesn't match the deployment role's existing workstation-IAM or runtime-IAM scoped permission patterns). Routing this stack through the deployment role would have required expanding the deployment role's own permissions in `bootstrap/main.tf` — out of the approved scope for this implementation task unless unavoidable. Running this stack human-direct, exactly like `bootstrap/`, avoids that dependency entirely. **No `bootstrap/` or `environments/dev` resource, permission, or state file is touched by this stack.**

## Backend setup process (no real values)

1. Copy `backend.hcl.example` to `backend.hcl` (gitignored, never committed).
2. Replace `<STATE_BUCKET_NAME>` with the real state bucket name (same bucket `infrastructure/terraform/bootstrap` created — see its `state_bucket_name` output). No new state bucket is created by this stack.
3. `key = "logging/terraform.tfstate"` — a state key dedicated to this stack, independent of `bootstrap/terraform.tfstate` and `dev/terraform.tfstate`. Do not change it without a deliberate, reviewed reason.
4. No `assume_role` block — see "Why this stack authenticates human-direct," above.

None of this has been executed as part of this task.

## Variable setup process (no real values)

1. Copy `terraform.tfvars.example` to `terraform.tfvars` (gitignored, never committed).
2. Fill in `aws_account_id` (`aws sts get-caller-identity --query Account --output text`).
3. Fill in `cloudtrail_bucket_name` — must be globally unique; the recommended pattern is `enterprise-data-platform-shared-cloudtrail-logs`, with an account-ID suffix appended only if that collides.
4. Fill in `alert_email` with a real, monitored email address. This is not committed anywhere and creates only a *pending* SNS subscription — see "SNS email subscription confirmation" below.
5. The S3 lifecycle (`cloudtrail_s3_ia_transition_days`/`cloudtrail_s3_glacier_transition_days`/`cloudtrail_s3_expiration_days`) and CloudWatch Logs retention (`cloudwatch_log_retention_days`) variables already default to the approved Phase 0 values (30/90/365 days S3; 90 days CloudWatch Logs) — override only with a deliberate, documented reason.

None of this has been executed as part of this task.

## SNS email subscription confirmation (human-only step)

`aws_sns_topic_subscription.security_alerts_email` creates a subscription in AWS's `PendingConfirmation` state. **No Terraform resource and no AWS API call can complete this confirmation** — AWS requires a human to open the confirmation email delivered to `var.alert_email` and click the link inside it. This is the same category of human-only step this project has already flagged elsewhere (MFA device enrollment, `gh auth login`) — until that click happens, alarms will fire but no notification will actually be delivered.

## Resources this configuration proposes (design-time list — confirm against a real `terraform plan`)

- `aws_s3_bucket.cloudtrail` + `aws_s3_bucket_versioning` + `aws_s3_bucket_ownership_controls` + `aws_s3_bucket_public_access_block` + `aws_s3_bucket_server_side_encryption_configuration` + `aws_s3_bucket_lifecycle_configuration` + `aws_s3_bucket_policy` (7)
- `aws_cloudwatch_log_group.cloudtrail` (1)
- `aws_iam_role.cloudtrail_cloudwatch` + `aws_iam_role_policy.cloudtrail_cloudwatch` (2)
- `aws_cloudtrail.this` (1)
- `aws_sns_topic.security_alerts` + `aws_sns_topic_subscription.security_alerts_email` (2)
- `module.cis_alarms` × 7 (`aws_cloudwatch_log_metric_filter.this` + `aws_cloudwatch_metric_alarm.this` each) (14)

**Total: 27 resources**, matching the design-time estimate in `Logging_and_Audit.md` Section 8. `data.aws_iam_policy_document.*` sources (bucket policy, CloudTrail trust, CloudTrail-to-CloudWatch permissions) are data sources, not managed resources, and do not appear in a `plan`'s add/change/destroy counts.

## Expected `terraform plan` shape

`Plan: 27 to add, 0 to change, 0 to destroy.` — no existing `bootstrap/` or `environments/dev` resource is read, referenced, or modified by this configuration; this stack has its own, independent state.

## Real AWS validation evidence (2026-08-04)

- `terraform apply`: `Apply complete! Resources: 27 added, 0 changed, 0 destroyed.` — matching this file's own "Expected `terraform plan` shape," above, exactly.
- A follow-up `terraform plan`: `No changes. Your infrastructure matches the configuration.` — the stack is confirmed stable with no drift.
- `aws cloudtrail get-trail-status` returned `"IsLogging": true`.
- CloudTrail log streams are present in the CloudWatch Logs log group `/enterprise-data-platform/shared/cloudtrail`.
- CloudTrail delivery prefixes are present in the dedicated S3 audit bucket.
- The SNS email subscription confirmation link was clicked by the user — the human-only step described above is complete; alarm notifications now have a live delivery path.
- All 7 CIS-benchmark-pattern metric filters and alarms (`modules/cis-alarm` × 7) are confirmed deployed.
- Log file validation is confirmed enabled on the live trail.

Full record: `16_Implementation_Notes/PROJECT_EXECUTION_JOURNAL.md` Section 27an.

## What has NOT been done

- No live-fire test of any alarm (e.g. a deliberate console sign-in failure, to exercise the `console-signin-failures` filter/alarm end-to-end) has been performed — this remains an optional, not-yet-scheduled operational exercise per `Logging_and_Audit.md` Section 9, not a blocking condition for this workstream's closure.
- A customer-managed KMS key for the audit bucket (Phase 0 Step 7), CloudTrail Insights, data events, and an organization trail remain deliberately out of scope, unchanged from the original design.
- The `aws_flow_log` resource itself is not created by this stack — it is owned by the next Phase 0 workstream, Networking Hardening.
