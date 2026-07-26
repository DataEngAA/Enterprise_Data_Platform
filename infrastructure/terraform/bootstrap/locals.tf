# Small, root-module-local computed values. No shared/ directory exists yet
# (Terraform_Bootstrap_Implementation_Plan.md Section 7) -- this root module
# defines its own tagging locals rather than importing them from elsewhere.

locals {
  # Required tags (Naming_Convention.md "Required tags"), applied to every
  # resource in this configuration via the provider's default_tags
  # (providers.tf) and explicitly merged where a resource needs its own
  # Name tag alongside these.
  #
  # Merge order (corrected 2026-07-25 static review): var.additional_tags is
  # merged FIRST and the required tags map SECOND, so a key collision (e.g.
  # someone passing additional_tags = { Owner = "someone-else" }) resolves
  # to the required value, not the caller-supplied one. terraform's merge()
  # lets later arguments win -- additional custom tag keys that don't
  # collide with a required key are still accepted normally.
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

  # No deployment-role policy name local here (removed 2026-07-25 static
  # review): the deployment role currently has no attached permissions
  # policy at all -- see main.tf's "Deployment role permissions --
  # DELIBERATELY NONE ATTACHED" comment. When a future, separately
  # reviewed change adds one, it should follow Naming_Convention.md's IAM
  # policy pattern: <project>-<environment>-<role-purpose>-policy.
}
