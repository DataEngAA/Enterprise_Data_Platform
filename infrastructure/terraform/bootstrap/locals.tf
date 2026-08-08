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

  # Bootstrap Update 2 (added): the exact ARN of the environments/dev
  # workstation IAM role, Terraform-derived from the same two variables
  # (var.aws_account_id, var.dev_workstation_role_name) already used
  # throughout main.tf's dev-permissions statements to scope access to
  # exactly this one role -- never duplicated as a raw string. Used only by
  # deployment_role_trust's second statement (main.tf) to trust this role
  # as an additional principal. This does not create the role itself
  # (still environments/dev's own responsibility) and does not change the
  # existing human-bootstrap-principal/MFA trust statement.
  dev_workstation_role_arn = "arn:aws:iam::${var.aws_account_id}:role/${var.dev_workstation_role_name}"

  # Added 2026-08-07 -- Phase 0 CI/CD Foundation implementation slice 1
  # dependency-propagation correction (02_Infrastructure/CI_CD.md,
  # ADR-0006-cicd-foundation.md; PROJECT_EXECUTION_JOURNAL.md). A real
  # bootstrap plan reported an unwanted second change,
  # aws_iam_policy.deployment_dev_runtime_iam_permissions, even though that
  # policy's own statements were never intentionally edited. Root cause:
  # IAM role ARNs are fully deterministic (arn:aws:iam::<account-id>:role/
  # <role-name>, no random or apply-time-generated component), but using
  # the RESOURCE reference aws_iam_role.deployment.arn anywhere Terraform
  # only needed the already-knowable ARN string created a real dependency
  # edge on that resource's apply. Once data.aws_iam_policy_document.
  # deployment_role_trust (main.tf) was extended to also reference
  # aws_iam_role.github_actions.arn (a genuinely new resource, not yet
  # created), aws_iam_role.deployment itself became dependent on
  # aws_iam_role.github_actions -- and every OTHER document that referenced
  # aws_iam_role.deployment.arn (including this pre-existing runtime-IAM
  # guardrail statement, unrelated to this task) was then forced to treat
  # that ARN as known-after-apply too, producing an artificial in-place
  # plan diff on a policy nothing here actually changed.
  #
  # Fix: two new locals, computed the exact same way
  # dev_workstation_role_arn already is above -- from variables only, with
  # no dependency on any resource's apply-time output -- used everywhere a
  # reference existed ONLY to obtain an already-knowable ARN (never where a
  # genuine creation-order dependency is required, e.g. an
  # aws_iam_role_policy_attachment's own role/policy arguments, which are
  # left as real resource references). Renders byte-identical policy JSON
  # to what the resource-attribute references produced -- no ARN value,
  # principal, resource, action, or condition changes as a result.
  deployment_role_arn     = "arn:aws:iam::${var.aws_account_id}:role/${var.deployment_role_name}"
  github_actions_role_arn = "arn:aws:iam::${var.aws_account_id}:role/${var.github_actions_role_name}"

  # Added 2026-08-08 -- Phase 0 CI/CD Slice 2B, GitHub OIDC immutable-subject
  # correction. A real GitHub Actions run failed at
  # aws-actions/configure-aws-credentials@v4 with "Not authorized to perform
  # sts:AssumeRoleWithWebIdentity": GitHub's OIDC token issuer now emits
  # "sub" claims in an immutable-ID format
  # (repo:<org>@<owner_id>/<repo>@<repo_id>:...), which no longer matches
  # the legacy, login-name-only subject strings
  # (repo:<org>/<repo>:...) data.aws_iam_policy_document.github_actions_trust
  # (main.tf) was built from. github_repository_immutable is the
  # Terraform-derived equivalent of var.github_repository in this new
  # format -- split(...) extracts the org and repo name from the existing
  # "<org>/<repo>" variable so the org/repo login names are still sourced
  # from var.github_repository (never hand-copied a second time), then the
  # two GitHub-issued immutable numeric IDs (var.github_owner_id,
  # var.github_repo_id) are appended in the exact "@<id>" positions
  # GitHub's own documented format requires. Used ONLY to build the two
  # "sub" StringEquals values below -- no other statement, role, or policy
  # references this local.
  github_repository_immutable = "${split("/", var.github_repository)[0]}@${var.github_owner_id}/${split("/", var.github_repository)[1]}@${var.github_repo_id}"

  # NOTE (2026-08-07): a dev_workstation_instance_arn local previously lived
  # here, for Phase 0 Cost Controls's deployment_shared_cost_controls_
  # permissions policy (main.tf). Removed, along with the corresponding
  # dev_workstation_instance_id variable (variables.tf), when that policy's
  # own ec2:StopInstances statement was removed -- the deployment role does
  # not call ec2:StopInstances at all; only the dedicated EventBridge
  # Scheduler execution role does (environments/dev/main.tf), scoped there
  # to module.ec2_workstation.instance_id directly. See main.tf's comment
  # above deployment_shared_cost_controls_permissions for the full,
  # corrected rationale.
}
