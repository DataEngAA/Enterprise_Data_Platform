# Phase 0 KMS and Secrets Foundation.
#
# Implements the approved design in 02_Infrastructure/KMS_and_Secrets.md and
# 01_Architecture/ADRs/ADR-0004-kms-and-secrets-foundation.md: one shared
# customer-managed KMS key with an explicit, per-principal key policy; one
# dev-scoped demonstration Secrets Manager secret (metadata only, no
# version/value -- KMS_and_Secrets.md Section 6/13); one dev-scoped
# demonstration Parameter Store parameter (String, non-sensitive -- Section
# 5/13's "prefer the safer option" choice, explained below). Migrating any
# existing S3/CloudTrail/CloudWatch Logs/EBS/Terraform-state encryption to
# this key is explicitly OUT OF SCOPE for this task -- see this stack's
# README.md.
#
# NOT YET APPLIED. No `terraform apply` has been run against this
# configuration.

# -----------------------------------------------------------------------
# Customer-managed KMS key
# -----------------------------------------------------------------------

#checkov:skip=CKV_AWS_111:Root break-glass statement (EnableAccountRootBreakGlassAdministration) intentionally grants kms:* / Resource:"*" to the account root only -- AWS's own required pattern for a key policy to remain manageable; Resource:"*" here means "this key," not "every resource" (KMS-key-policy-specific semantics). Checkov triage 16_Implementation_Notes/Checkov_Triage_CI_CD_Slice_2A.md CKV_AWS_111/356/109 (C), citing bridgecrewio/checkov issues #5148/#5181 and this key's own real IAM-discipline compensating control (only root break-glass + deployment-role administration ever receive a kms: grant on this key).
#checkov:skip=CKV_AWS_356:Same root break-glass statement as CKV_AWS_111 above -- see that skip's reason and the triage doc's CKV_AWS_111/356/109 entry (C, false positive for KMS key policies specifically).
#checkov:skip=CKV_AWS_109:Same root break-glass statement as CKV_AWS_111 above -- see that skip's reason and the triage doc's CKV_AWS_111/356/109 entry (C, false positive for KMS key policies specifically).
resource "aws_kms_key" "this" {
  description = "Shared customer-managed key for the Enterprise Data Platform (KMS_and_Secrets.md). Symmetric ENCRYPT_DECRYPT. Not multi-region -- no cross-region replication requirement exists (KMS_and_Secrets.md Section 2/10)."

  key_usage                = "ENCRYPT_DECRYPT"
  customer_master_key_spec = "SYMMETRIC_DEFAULT"

  # Explicit, not left to the provider default -- matches
  # KMS_and_Secrets.md Section 10's explicit "no multi-region key unless
  # already explicitly required" instruction. No requirement exists.
  multi_region = false

  is_enabled = true

  # Approved: automatic annual rotation, the maximum 30-day deletion
  # window -- not the 7-day minimum -- since this key is expected to
  # eventually protect data across multiple services (KMS_and_Secrets.md
  # Section 2).
  enable_key_rotation     = true
  deletion_window_in_days = 30

  policy = data.aws_iam_policy_document.cmk.json

  # Protection against accidental deletion (KMS_and_Secrets.md Section 2) --
  # matches the pattern already used on the Terraform state bucket and
  # aws_iam_role.deployment in bootstrap/main.tf, and on the CloudTrail
  # audit bucket in logging/main.tf. Removing this key requires a
  # deliberate, conscious change to this lifecycle block first, not an
  # ordinary `terraform destroy` or resource removal. Does not protect
  # against a sufficiently privileged human calling
  # kms:ScheduleKeyDeletion directly against AWS -- see
  # KMS_and_Secrets.md Section 12 for the full set of limits and the
  # supplementary control (the deployment role is never granted
  # kms:ScheduleKeyDeletion -- see bootstrap/main.tf) this design relies on
  # alongside it.
  lifecycle {
    prevent_destroy = true
  }

  tags = merge(
    local.common_tags,
    {
      Name = local.cmk_name
    }
  )
}

resource "aws_kms_alias" "this" {
  name          = local.cmk_alias
  target_key_id = aws_kms_key.this.key_id
}

# -----------------------------------------------------------------------
# KMS key policy -- explicit per-principal enumeration
# (KMS_and_Secrets.md Section 3; IAM_and_Access.md's already-approved "KMS
# access pattern": never the default "delegate entirely to IAM" root-trust
# key policy).
#
# Two statements only. A third, "AllowApprovedServiceUsage"/
# "AllowFutureRuntimeRoleUsage" statement (Decrypt/Encrypt/GenerateDataKey
# for actual key consumers) is DELIBERATELY NOT INCLUDED YET -- see this
# stack's README.md "Why No Usage Statement Exists Yet" for the full
# explanation: the demonstration secret created below has no version/value,
# and the demonstration parameter is a plain String, not a SecureString --
# neither actually invokes KMS. No real consumer of this key exists in this
# task's scope. Adding a usage statement is the well-defined next step for
# whenever a real SecureString value, a real secret version, or a migrated
# CloudWatch Logs/S3/EBS consumer is introduced (each a separate, later,
# explicitly reviewed change, per KMS_and_Secrets.md Section 3's own
# "AllowFutureRuntimeRoleUsage" pattern).
# -----------------------------------------------------------------------

data "aws_iam_policy_document" "cmk" {
  statement {
    sid    = "EnableAccountRootBreakGlassAdministration"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${var.aws_account_id}:root"]
    }

    actions   = ["kms:*"]
    resources = ["*"]

    # HONEST CAVEAT (KMS_and_Secrets.md Section 3, Statement 1): this
    # statement, on its own, is technically sufficient to let any IAM
    # identity in this account use this key if that identity separately
    # receives a matching IAM policy grant on this key's ARN. The real
    # protection this design relies on is IAM policy discipline -- only
    # the deployment role (Statement 2 below) and, later, explicitly
    # enumerated usage principals (KMS_and_Secrets.md Section 3, Statement
    # 3/4) ever receive a kms permission on this key anywhere in this
    # project's IAM. This statement exists for account-root break-glass
    # recoverability (AWS's own documented required baseline for a key to
    # remain manageable at all), not as the primary access-control
    # mechanism.
  }

  statement {
    sid    = "AllowDeploymentRoleKeyAdministration"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = [var.deployment_role_arn]
    }

    # Key ADMINISTRATION only -- deliberately excludes kms:Decrypt,
    # kms:Encrypt, kms:GenerateDataKey* (administrators do not
    # automatically receive usage rights, mirroring the deployment-role/
    # workstation-role separation-of-duties pattern already established
    # project-wide) and deliberately excludes kms:DisableKey,
    # kms:ScheduleKeyDeletion, kms:CancelKeyDeletion,
    # kms:DisableKeyRotation (KMS_and_Secrets.md Section 2/4 -- these
    # remain human/root-only, break-glass actions, never a standing
    # deployment-role grant).
    actions = [
      "kms:DescribeKey",
      "kms:GetKeyPolicy",
      "kms:PutKeyPolicy",
      "kms:CreateAlias",
      "kms:UpdateAlias",
      "kms:EnableKeyRotation",
      "kms:GetKeyRotationStatus",
      "kms:TagResource",
      "kms:UntagResource",
      "kms:ListResourceTags",
    ]

    resources = ["*"]
  }
}

# -----------------------------------------------------------------------
# Demonstration Secrets Manager secret -- METADATA ONLY.
#
# aws_secretsmanager_secret_version is deliberately never created anywhere
# in this project's Terraform (KMS_and_Secrets.md Section 6, standing
# policy, not a Phase-0-only restriction). The initial value, an explicitly
# non-sensitive placeholder, is set manually, once, via
# `aws secretsmanager put-secret-value`, outside Terraform, by a human --
# see this stack's README.md "Setting the Demonstration Secret's Value."
#
# REVISED 2026-08-07 (real, first apply -- CreateSecret denied): no
# kms_key_id is set here. A real apply against the original design (CMK
# specified, no version) was denied -- AWS Secrets Manager validates KMS
# usability at CreateSecret time even when no version/value is supplied,
# requiring the caller to hold kms:GenerateDataKey/kms:Decrypt against the
# specified key. The original design's assumption that no KMS usage occurs
# without a version was technically incomplete -- corrected in
# KMS_and_Secrets.md Section 6/13. Rather than grant the deployment role
# any KMS data-use right for a secret that holds no real value yet, this
# demonstration secret uses the AWS-managed Secrets Manager default key
# (omitting kms_key_id), which requires no caller KMS permission at all.
# THIS SECRET IS NOT PROTECTED BY THE SHARED PROJECT CMK. Migrating it (or
# a real future secret) to the CMK is a separate, later, explicitly
# reviewed change, using the dual-gate model already designed in
# KMS_and_Secrets.md Section 3: a matching key-policy usage statement, a
# matching narrowly scoped IAM identity grant, a
# kms:ViaService=secretsmanager.<region>.amazonaws.com condition, and the
# exact CMK ARN -- never a standing, speculative grant.
# -----------------------------------------------------------------------

#checkov:skip=CKV_AWS_149:Demo secret deliberately uses the AWS-managed default key, not the shared CMK -- a real CreateSecret apply against the CMK-backed design was denied (AccessDeniedException). No real secret value/version exists (Versions: [] always). ADR-0004; Checkov triage CKV_AWS_149 (B).
#checkov:skip=CKV2_AWS_57:Rotation requires a real secret value and a rotation Lambda; this demo secret is metadata-only (no version), so rotation is meaningless. Checkov triage CKV2_AWS_57 (B).
resource "aws_secretsmanager_secret" "demo" {
  name        = local.demo_secret_name
  description = "Phase 0 KMS/Secrets Foundation demonstration secret (metadata only -- no version/value managed by Terraform; uses the AWS-managed default key, not the shared project CMK -- see the comment above). Proves the create/tag path only. See KMS_and_Secrets.md Section 13."

  # Not set to prevent_destroy=true -- this is a disposable demonstration
  # resource, not precious infrastructure, consistent with this project's
  # existing disposable-vs-precious distinction (e.g. the EC2 workstation's
  # own explicit no-prevent_destroy rationale).
  recovery_window_in_days = 30

  tags = local.demo_tags
}

# -----------------------------------------------------------------------
# Demonstration Parameter Store parameter.
#
# TYPE CHOICE: String, not SecureString (KMS_and_Secrets.md Section 5/13's
# "if the approved design allows avoiding a Terraform-managed SecureString
# value entirely, prefer the safer option" instruction). A SecureString
# value set via a Terraform resource argument would, exactly like a
# Secrets Manager secret version, be written into Terraform state in
# decrypted form -- the same core risk Section 6 closes for Secrets
# Manager by never creating a version. Using String here for the
# demonstration parameter sidesteps that risk entirely rather than
# accepting it for a value that has no real sensitivity to protect in the
# first place: the value below is a literal, obviously non-secret
# placeholder string, so there is nothing gained by encrypting it, and
# real cost (a plaintext-in-state precedent for this stack) in doing so
# anyway. A real SecureString parameter, backed by this same CMK, remains
# fully designed and available (KMS_and_Secrets.md Section 7) for whenever
# a genuinely sensitive, non-Secrets-Manager-warranting value is needed --
# it is simply not what this demonstration resource needs to be.
# -----------------------------------------------------------------------

#checkov:skip=CKV2_AWS_34:type = "String" is deliberate, not SecureString -- a SecureString value set via a Terraform argument would be written into state in decrypted form, the same risk avoided for Secrets Manager by never creating a version. This value is a non-sensitive literal placeholder. KMS_and_Secrets.md Section 5/13; Checkov triage CKV2_AWS_34 (B).
resource "aws_ssm_parameter" "demo" {
  name        = local.demo_parameter_name
  description = "Phase 0 KMS/Secrets Foundation demonstration parameter -- non-sensitive placeholder, proves the Parameter Store create/tag path. See KMS_and_Secrets.md Section 13."
  type        = "String"
  tier        = "Standard"
  value       = "phase0-kms-secrets-demo-non-secret-placeholder"

  tags = local.demo_tags
}
