# ---------------------------------------------------------------------------
# Backend configuration -- TWO-PHASE. See README.md "Future State Migration
# Sequence" for the full procedure.
#
# Phase 1 (2026-07-25, completed): the `backend "s3" {}` block was commented
#   out. The first `terraform init` / `plan` / `apply` for this configuration
#   used Terraform's default LOCAL backend, because the S3 bucket this block
#   points at did not exist yet -- it was one of the resources THIS
#   configuration created (main.tf). That apply has since succeeded
#   (`Apply complete! Resources: 7 added, 0 changed, 0 destroyed.`,
#   2026-07-25) and the bucket's hardening has been verified against real
#   AWS output (README.md "Terraform Apply Results and AWS Verification").
#
# Phase 2 (this file's current state -- PREPARATION ONLY, migration itself
#   NOT run as part of this task): the partial `backend "s3" {}` block below
#   is now ACTIVE (uncommented). This alone does not migrate anything --
#   Terraform only reads this block and attempts a backend change the next
#   time `terraform init` is actually run, which has NOT happened as part
#   of this task. Migration additionally requires a real, gitignored
#   `backend.hcl` (created from `backend.hcl.example`, filled in with the
#   real bucket name only) and running, as a separate, later, explicit step:
#     terraform init -backend-config="backend.hcl" -migrate-state
#   Then verifying with `terraform state list` and a no-diff `terraform plan`
#   before removing the local state file. See README.md "Future State
#   Migration Sequence" for the full, still-undone procedure.
#
# No bucket name, account ID, role ARN, credentials, or local path is
# hardcoded in this file -- those are supplied only at `terraform init`
# time via -backend-config="backend.hcl". No `assume_role` configuration
# and no DynamoDB configuration are added here or anywhere in this
# configuration -- native S3 locking (`use_lockfile = true`, supplied via
# backend.hcl) is used instead, per Terraform_Bootstrap_Design.md Section 6.
# The backend remains human-administered, exactly like the provider
# (providers.tf) -- the deployment role is not used for this backend.
# ---------------------------------------------------------------------------

terraform {
  backend "s3" {
    # bucket, key, region, encrypt, and use_lockfile are all supplied via
    # `-backend-config="backend.hcl"` at init time -- see
    # backend.hcl.example. Native S3 state locking (use_lockfile = true) is
    # used; no DynamoDB lock table exists or is created by this
    # configuration.
  }
}
