# Small, root-module-local computed values. Same pattern as
# bootstrap/locals.tf, logging/locals.tf, and kms-secrets/locals.tf -- this
# root module computes its own tagging locals rather than importing them
# from elsewhere.

locals {
  # Required tags (Naming_Convention.md "Required tags"), same merge order
  # as every other root module in this project: var.additional_tags merged
  # FIRST, required tags map SECOND, so a key collision resolves to the
  # required value.
  common_tags = merge(
    var.additional_tags,
    {
      Project            = var.project_name
      Environment        = var.environment
      ManagedBy          = "terraform"
      Owner              = var.owner
      CostCenter         = var.cost_center
      DataClassification = var.data_classification
    }
  )
}
