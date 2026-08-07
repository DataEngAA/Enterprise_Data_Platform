# Remote S3 backend, same state bucket bootstrap/ already created and
# hardened, but a SEPARATE state key -- "cost-controls/terraform.tfstate" --
# so this stack's state is fully independent of bootstrap's own, logging's
# own, environments/dev's own, and kms-secrets' own state. No DynamoDB lock
# table; native S3 locking (`use_lockfile = true`, supplied via backend.hcl)
# is used, matching every other root module in this project.
#
# Partial configuration -- real values supplied only via
# `-backend-config="backend.hcl"` at `terraform init` time, never hardcoded
# here. See backend.hcl.example for the exact placeholder shape.
#
# This backend's assume_role block IS required and IS included in
# backend.hcl.example, matching kms-secrets/backend.hcl.example and
# environments/dev/backend.hcl.example -- this stack's state storage calls
# authenticate via the shared deployment role, not human-direct, per
# providers.tf's own departure from logging/'s pattern.
#
# NOT initialized as part of this task. `terraform init` has not been run.
# No real backend.hcl has been created. The cost-controls state key
# (cost-controls/terraform.tfstate) does not yet exist in the state bucket.

terraform {
  backend "s3" {
    # bucket, key, region, encrypt, use_lockfile, and assume_role are all
    # supplied via `-backend-config="backend.hcl"` at init time -- see
    # backend.hcl.example.
  }
}
