# Remote S3 backend, same state bucket bootstrap/ already created and
# hardened, but a SEPARATE state key -- "logging/terraform.tfstate" -- so
# this stack's state is fully independent of bootstrap's own
# "bootstrap/terraform.tfstate" and environments/dev's
# "dev/terraform.tfstate". No DynamoDB lock table; native S3 locking
# (`use_lockfile = true`, supplied via backend.hcl) is used, matching every
# other root module in this project.
#
# Partial configuration -- real values supplied only via
# `-backend-config="backend.hcl"` at `terraform init` time, never hardcoded
# here. See backend.hcl.example for the exact placeholder shape.
#
# Unlike environments/dev/backend.hcl.example, this backend's assume_role
# block is NOT required and is NOT included -- this stack authenticates
# human-direct (providers.tf), matching bootstrap/'s own backend pattern,
# not environments/dev's.
#
# NOT initialized as part of this task. `terraform init` has not been run.
# No real backend.hcl has been created. The logging state key
# (logging/terraform.tfstate) does not yet exist in the state bucket.

terraform {
  backend "s3" {
    # bucket, key, region, encrypt, and use_lockfile are all supplied via
    # `-backend-config="backend.hcl"` at init time -- see backend.hcl.example.
  }
}
