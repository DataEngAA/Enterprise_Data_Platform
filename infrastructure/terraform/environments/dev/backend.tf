# Active S3 backend, from this root module's very first apply -- unlike
# bootstrap's two-phase (local-then-migrate) backend.tf, environments/dev is
# remote-state-from-day-one, because the S3 state bucket this configuration
# depends on already exists and is already hardened/verified (the Terraform
# Bootstrap phase is formally complete -- see
# 16_Implementation_Notes/PROJECT_EXECUTION_JOURNAL.md Section 27g).
#
# Partial configuration, same mechanism as bootstrap: real values are
# supplied only via `-backend-config=backend.hcl` at `terraform init` time,
# never hardcoded here. See backend.hcl.example for the exact placeholder
# shape, including the nested assume_role block this backend requires
# (Dev_Environment_Terraform_Implementation_Plan.md Section 9).
#
# NOT initialized as part of this task. `terraform init` has not been run.
# No real backend.hcl has been created. The dev state key
# (dev/terraform.tfstate) does not yet exist in the state bucket.

terraform {
  backend "s3" {}
}
