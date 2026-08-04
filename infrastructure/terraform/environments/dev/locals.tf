# Small, root-module-local computed values. No shared/ directory exists yet
# (Section 3.2 "Is a separate shared/ directory still unnecessary? APPROVED
# -- Still unnecessary") -- this root module computes its own tagging
# locals rather than importing them from elsewhere, same pattern as
# bootstrap/locals.tf.

locals {
  # Required tags (Naming_Convention.md "Required tags"), applied to every
  # resource via the provider's default_tags (providers.tf) and merged
  # explicitly wherever a resource needs its own Name tag alongside these.
  #
  # Merge order matches bootstrap/locals.tf's corrected pattern:
  # var.additional_tags is merged FIRST and the required tags map SECOND,
  # so a key collision resolves to the required value, not a caller-
  # supplied override.
  common_tags = merge(
    var.additional_tags,
    {
      Project            = var.project_name
      Environment        = "dev"
      ManagedBy          = "terraform"
      Owner              = "DataEngAA"
      CostCenter         = "personal-learning"
      DataClassification = "internal"
    }
  )

  # AMI resolution (Section 22, Section 3.2 -- REVISED 2026-07-26: lives in
  # this root module, not modules/ec2-workstation). When var.ami_id_override
  # is null (the default), the current AL2023 AMI resolved by
  # data.aws_ami.al2023 (main.tf) is used; otherwise the explicit override
  # is used verbatim, letting a specific known-good AMI be pinned without
  # editing any module.
  #
  # Deliberately a native ternary (`!= null ? ... : ...`), NOT
  # coalesce(var.ami_id_override, data.aws_ami.al2023[0].id) -- coalesce()
  # is a strict function call and would force evaluation of
  # data.aws_ami.al2023[0] even when count = 0 (override set), producing an
  # "invalid index" error. The native conditional operator against a
  # count-based data source is the standard Terraform idiom for this exact
  # override-or-lookup pattern and correctly avoids evaluating the untaken
  # branch's index.
  resolved_ami_id = var.ami_id_override != null ? var.ami_id_override : data.aws_ami.al2023[0].id

  # Bootstrap script content, read once here and passed into
  # modules/ec2-workstation as a plain string -- NOT duplicated inline in
  # Terraform source, so a change to the script file itself is visible in a
  # normal `git diff`/`terraform plan` without touching this configuration
  # (Section 29.7, task "User data" requirements).
  bootstrap_script_path = "${path.root}/../../scripts/bootstrap_workstation.sh"
  bootstrap_script      = file(local.bootstrap_script_path)
}
