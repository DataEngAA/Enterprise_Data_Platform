# Terraform and AWS provider version constraints for this module.
#
# REVISED 2026-07-26 (TFLint finding, first local validation gate): TFLint
# flagged this module for declaring no required_version/provider version
# constraint of its own. The prior comment's reasoning -- that only the
# calling root module (environments/dev/versions.tf) needs to pin exact
# version ranges -- is a reasonable convention for provider *configuration*,
# but TFLint's own default ruleset (terraform_required_version,
# terraform_required_providers) expects every module, including child
# modules, to declare its own compatible version range so the module remains
# self-describing and safely reusable outside this specific root. This
# module still configures NO provider block of its own (that remains the
# root module's responsibility, per Terraform convention) -- only the
# version CONSTRAINT is added here, matching environments/dev/versions.tf's
# constraint exactly so the two can never silently drift apart.

terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0.0, < 7.0.0"
    }
  }
}
