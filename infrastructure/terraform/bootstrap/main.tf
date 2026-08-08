# Terraform Bootstrap -- resources defined directly in this root module.
#
# Per the approved implementation plan
# (16_Implementation_Notes/Terraform_Bootstrap_Implementation_Plan.md
# Sections 1-2), NO modules are used for this scope: modules/state-backend
# and modules/iam-deployment-role were considered and explicitly rejected
# for this small, single-use configuration. Modules may be introduced later
# only if genuine reuse appears.
#
# This file has not been applied. Nothing below has been created in AWS.

# =============================================================================
# Remote-state S3 bucket and hardening
# (Terraform_Bootstrap_Design.md Sections 5-11, 28.1-28.2)
# =============================================================================

resource "aws_s3_bucket" "terraform_state" {
  #checkov:skip=CKV_AWS_18:No access-logging destination bucket exists yet -- reviewed and accepted as Trivy AWS-0089 (LOW) during the original Terraform Bootstrap validation gate (Bootstrap_Checklist.md); a correct implementation needs its own hardened bucket, IAM, and retention policy. Checkov triage CKV_AWS_18 (B).
  #checkov:skip=CKV2_AWS_62:Event notifications never part of the Bootstrap design's threat model; only the deployment role and the human bootstrap identity can write to this bucket (least-privilege IAM), bounding the realistic threat surface. Genuinely new design work, not yet scoped. Checkov triage CKV2_AWS_62 (D -- deferred hardening, not an accepted trade-off).
  #checkov:skip=CKV_AWS_144:Cross-region replication explicitly, textually "deliberately NOT created" per this file's own "Items Deliberately Out of Scope" comment -- single-region, personal-portfolio project with no DR requirement in PROJECT_BLUEPRINT.md Phase 0. Checkov triage CKV_AWS_144 (B).
  #checkov:skip=CKV2_AWS_61:Lifecycle expiration for old state-object versions is explicitly, textually "deliberately NOT created" per this file's own comment -- unlike replication, a real low-cost fix exists (a lifecycle rule on noncurrent versions) and is a genuine future improvement candidate, not a settled trade-off. Checkov triage CKV2_AWS_61 (D -- deferred hardening).
  #checkov:skip=CKV_AWS_145:SSE-S3 (AES256) is an explicit Terraform_Bootstrap_Design.md Section 9 decision, reviewed and accepted as Trivy AWS-0132 (HIGH) during the original validation gate. Checkov triage CKV_AWS_145 (B).
  bucket = var.state_bucket_name

  # Blocks Terraform-initiated destruction of the state bucket (`terraform
  # destroy` or a plan that would replace/remove it). This does NOT protect
  # against deletion outside Terraform by a sufficiently privileged
  # identity, nor against `terraform state rm` -- see README.md
  # "Destruction Protection Warning" for the full set of limits and the
  # supplementary controls (least-privilege IAM, versioning) this design
  # relies on alongside it.
  lifecycle {
    prevent_destroy = true
  }

  tags = merge(
    local.common_tags,
    {
      Name = var.state_bucket_name
    }
  )
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      # SSE-S3, not SSE-KMS -- approved decision, Terraform_Bootstrap_Design.md
      # Section 9. No customer-managed KMS key is created or referenced.
      sse_algorithm = "AES256"
    }
    # No bucket_key_enabled here (corrected 2026-07-25 static review): S3
    # Bucket Keys reduce KMS request cost/traffic for SSE-KMS-encrypted
    # objects. This bucket uses SSE-S3, so bucket_key_enabled has no effect
    # and is omitted rather than left on as a no-op.
  }
}

resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# Deny any request to the state bucket that does not use TLS.
data "aws_iam_policy_document" "terraform_state_tls_only" {
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    actions = ["s3:*"]

    resources = [
      aws_s3_bucket.terraform_state.arn,
      "${aws_s3_bucket.terraform_state.arn}/*",
    ]

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  policy = data.aws_iam_policy_document.terraform_state_tls_only.json

  # Ensure Block Public Access is in place before any bucket policy is
  # attached, so the policy is never briefly evaluated without it.
  depends_on = [aws_s3_bucket_public_access_block.terraform_state]
}

# Explicitly NOT created in this configuration (see README.md "Items
# Deliberately Out of Scope"): a DynamoDB lock table (native S3 locking via
# `use_lockfile` is used instead, see backend.tf/backend.hcl.example), a
# customer-managed KMS key, a separate access-logging bucket, cross-region
# or cross-account replication, and lifecycle-expiration rules for old
# state object versions.

# =============================================================================
# Terraform deployment IAM role
# (Terraform_Bootstrap_Design.md Sections 21-23)
# =============================================================================

# Trust policy: two separate, independent statements -- kept as two
# statements deliberately, not merged into one multi-principal statement,
# because they require different conditions and it must remain obvious on
# inspection (of source or of the deployed policy JSON) which principal
# needs MFA and which does not.
#
#   1. AllowHumanBootstrapPrincipalAssumeRoleWithMFA -- the human bootstrap
#      IAM user (var.human_bootstrap_principal_arn), gated on an active MFA
#      session. UNCHANGED by Bootstrap Update 2 below.
#   2. AllowDevWorkstationRoleAssumeRoleNoMfa -- BOOTSTRAP UPDATE 2 (added).
#      The environments/dev EC2 workstation IAM role
#      (local.dev_workstation_role_arn, Terraform-derived from
#      var.aws_account_id + var.dev_workstation_role_name -- the exact role
#      ARN, never a wildcard or account-root principal), with NO MFA
#      condition. An IAM role assumed by an EC2 instance profile has no
#      mechanism to present an MFA token when it in turn calls
#      sts:AssumeRole -- aws:MultiFactorAuthPresent would always evaluate
#      false for this principal, so requiring it here would make this path
#      permanently unusable, not merely inconvenient. This asymmetry is
#      deliberate and does not weaken the human path above: the two
#      statements are independent Allow grants to two different, exact
#      principals, and removing or loosening one has no effect on the
#      other's own condition.
#
# (Terraform_Bootstrap_Design.md Section 2 step 5, Section 22;
# Terraform_Bootstrap_Implementation_Plan.md Section 16;
# Dev_Environment_Terraform_Implementation_Plan.md "IAM Sequencing" Stage C.)
data "aws_iam_policy_document" "deployment_role_trust" {
  statement {
    sid    = "AllowHumanBootstrapPrincipalAssumeRoleWithMFA"
    effect = "Allow"

    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = [var.human_bootstrap_principal_arn]
    }

    condition {
      test     = "Bool"
      variable = "aws:MultiFactorAuthPresent"
      values   = ["true"]
    }
  }

  statement {
    sid    = "AllowDevWorkstationRoleAssumeRoleNoMfa"
    effect = "Allow"

    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = [local.dev_workstation_role_arn]
    }

    # Deliberately no MFA (or any other) condition here -- see the comment
    # block above this data source for why an EC2-instance-profile-assumed
    # role cannot supply one. This statement is scoped to the exact
    # workstation role ARN only; it does not grant account-root or
    # wildcard trust, and it does not alter the human-principal statement's
    # own MFA requirement above.
  }

  # Added 2026-08-07 -- Phase 0 CI/CD Foundation implementation slice 1
  # (GitHub OIDC trust only; 02_Infrastructure/CI_CD.md, ADR-0006-cicd-
  # foundation.md). ADDITIVE ONLY: the two statements above are completely
  # unchanged -- the human-MFA requirement and the workstation no-MFA
  # statement's own exact-ARN scoping are neither weakened nor touched by
  # this addition.
  #
  # Third, independent trusted principal: the new, near-empty external
  # GitHub Actions workload-identity role defined later in this file. This
  # is a direct AWS-principal AssumeRole trust, NOT the GitHub OIDC trust
  # itself -- GitHub's own token never reaches this role. GitHub Actions
  # authenticates to aws_iam_role.github_actions via
  # aws_iam_openid_connect_provider.github_actions/data.aws_iam_policy_
  # document.github_actions_trust (below), then that already-authenticated
  # role makes this SECOND, separate sts:AssumeRole call to reach this role
  # -- the two-hop chain 02_Infrastructure/CI_CD.md Section 2/4 designed
  # specifically so this deployment role's own trust policy never has to
  # reason about GitHub's OIDC claims directly.
  #
  # CORRECTED 2026-08-07 (real terraform plan review, dependency-
  # propagation fix): identifiers below uses local.github_actions_role_arn
  # (a deterministic string computed from var.aws_account_id and
  # var.github_actions_role_name, locals.tf), not the resource reference
  # aws_iam_role.github_actions.arn. Byte-identical value once applied --
  # this is the same exact ARN aws_iam_role.github_actions will have --
  # but using the resource reference here made aws_iam_role.deployment
  # depend on aws_iam_role.github_actions's creation, which in turn made
  # every OTHER document referencing aws_iam_role.deployment.arn
  # elsewhere in this file (including the pre-existing, otherwise-
  # untouched deployment_dev_runtime_iam_permissions guardrail) report a
  # real, unwanted known-after-apply plan diff. See locals.tf's comment
  # above deployment_role_arn/github_actions_role_arn for the full root-
  # cause record.
  statement {
    sid    = "AllowGitHubActionsRoleAssumeRoleNoMfa"
    effect = "Allow"

    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = [local.github_actions_role_arn]
    }

    # Deliberately no MFA (or any other) condition here, for the same
    # reason as the workstation-role statement above: a role reached via
    # sts:AssumeRoleWithWebIdentity (GitHub OIDC) cannot supply
    # aws:MultiFactorAuthPresent, so requiring it would make this path
    # permanently unusable. This statement is scoped to the exact GitHub
    # Actions role ARN only -- not a wildcard, not account-root, not any
    # other AWS-principal type. The GitHub-repository/branch/environment
    # restriction itself lives one hop earlier, on
    # aws_iam_role.github_actions's own trust policy (this deployment
    # role's trust policy does not, and does not need to, re-check GitHub's
    # OIDC claims -- it only ever sees "the already-authenticated GitHub
    # Actions role is asking to assume this role," exactly as it already
    # only ever sees "the already-authenticated workstation role is asking
    # to assume this role" for the statement above).
  }
}

# Deployment role description -- kept short deliberately (IAM hard-limits a
# role's description to 1,000 characters; a prior, longer narrative value
# here caused a real terraform plan/apply failure -- see
# PROJECT_EXECUTION_JOURNAL.md for that incident). The detailed explanation
# previously carried in the description itself is preserved here as a
# comment instead:
#
# Three dev-scoped managed permissions policies are attached (see
# aws_iam_policy.deployment_dev_permissions,
# aws_iam_policy.deployment_dev_networking_permissions, and
# aws_iam_policy.deployment_dev_workstation_iam_permissions, and the
# comment block below this resource) -- split across three policies as of
# the 2026-07-26 IAM managed-policy size-quota corrections (Bootstrap
# Update 1: first a two-policy split after a real iam:CreatePolicyVersion
# LimitExceeded failure, then a second split of the non-networking policy
# after its own lifecycle.precondition reported 6212 characters against a
# 6144 quota). Trust now covers two independent principals (Bootstrap
# Update 2): the bootstrap-scoped human identity, MFA required, unchanged;
# and the environments/dev EC2 workstation role
# (local.dev_workstation_role_arn), no MFA condition (not obtainable from
# an instance-profile-assumed role) -- see
# data.aws_iam_policy_document.deployment_role_trust above for both
# statements.
resource "aws_iam_role" "deployment" {
  name                 = var.deployment_role_name
  description          = "Terraform deployment role for ${var.project_name}."
  assume_role_policy   = data.aws_iam_policy_document.deployment_role_trust.json
  max_session_duration = var.deployment_role_max_session_duration

  lifecycle {
    # See README.md "Destruction Protection Warning" for the same caveats
    # that apply to the state bucket's prevent_destroy above.
    prevent_destroy = true

    # Added 2026-07-25 static review: fail plan/apply rather than silently
    # creating a role that trusts a principal from a different AWS account
    # than the one this configuration is scoped to run against
    # (providers.tf's allowed_account_ids). The account segment of an IAM
    # ARN (arn:aws:iam::<account-id>:user/<name>) is index 4 when split on
    # ":". No account value is invented here -- both sides of this
    # comparison come from user-supplied variables (variables.tf).
    precondition {
      condition     = split(":", var.human_bootstrap_principal_arn)[4] == var.aws_account_id
      error_message = "human_bootstrap_principal_arn's account ID does not match aws_account_id -- they must refer to the same AWS account. Check terraform.tfvars."
    }
  }

  tags = local.common_tags
}

# ---------------------------------------------------------------------------
# Deployment role permissions -- BOOTSTRAP UPDATE 1 (code added 2026-07-26,
# NOT YET APPLIED -- see README.md "Bootstrap Update 1" for status).
#
# Bootstrap management model (decided 2026-07-25, unchanged by this update):
#
#   - This bootstrap root module remains a human-administered exception.
#     Its own provider and backend continue to run as the authorized human
#     IAM identity directly (providers.tf) -- never via this role.
#   - The deployment role's trust policy is UNCHANGED by this update -- it
#     still trusts ONLY the human bootstrap principal, with the MFA
#     condition above. The future EC2 workstation role is NOT trusted yet;
#     it cannot be, since it does not exist until environments/dev's own
#     apply creates it (Bootstrap Update 2, a separate, later, reviewed
#     change -- not implemented by this update).
#   - The deployment role does NOT receive access to bootstrap/terraform.tfstate
#     (or its lock object), and never will -- granting that would let a role
#     whose purpose is managing dev infrastructure also read/write the very
#     state object that defines the deployment role itself and the state
#     bucket's hardening, a self-referential, unnecessary blast-radius
#     expansion this design avoids by simply not granting it. See the
#     DevStateListBucket statement below: its s3:prefix condition matches
#     only "dev/terraform.tfstate*" keys, never "bootstrap/*".
#   - environments/dev can never modify this role's own trust or permissions
#     -- the IAM statements below grant create/manage permissions scoped to
#     exactly the workstation role/instance-profile name
#     (var.dev_workstation_role_name), never to aws_iam_role.deployment
#     itself.
#
# Full action/resource/condition matrix, JSON equivalent, wildcard
# justification, human-only-permissions list, and residual risks:
# Dev_Environment_Terraform_Implementation_Plan.md Section 11 (11.1-11.6).
# The statements below were originally the literal Terraform translation of
# that document's Section 11.2 proposed policy JSON -- 18 statements, same
# Sids, using HCL data "aws_iam_policy_document" statement blocks (this
# project's established style, matching the trust-policy document above)
# rather than a raw JSON heredoc. **CORRECTED 2026-07-26**: two of those 17
# original statements (DevNetworkingCreateManage,
# DevNetworkingCreateManageTaggedOnCreate) had an IAM tag-enforcement bypass
# and were replaced, 2-for-2, with DevNetworkingCreateTaggedOnly and
# DevNetworkingManageTaggedResourceOnly. **CORRECTED AGAIN 2026-07-26**: the
# original single DevRunInstances statement applied an ec2:Owner = "amazon"
# condition to a Resource list that mixed the AMI resource type together
# with instance/volume/network-interface/subnet/security-group resource
# types -- ec2:Owner is only a meaningful, populated context key for the AMI
# (image) resource being launched from, not for the instance/volume/network-
# interface/subnet/security-group resources RunInstances also references in
# the same call. Scoping that condition across all six resource types in one
# statement was broader than the condition key is actually meant to apply
# to. Split 1-for-2 into DevRunInstancesAmi (Resource = the AMI ARN only,
# carrying ec2:Owner plus the region/instance-type conditions) and
# DevRunInstancesSupportingResources (Resource = the five non-AMI resource
# types, carrying only the region/instance-type conditions, no ec2:Owner) --
# statement count became 18, not 17, after that correction.
# **CORRECTED A THIRD TIME 2026-07-26** (second real partial
# `environments/dev` apply failure): the single combined
# DevNetworkingCreateTaggedOnly statement was itself a real, deployed
# defect -- CreateSubnet/CreateRouteTable/CreateSecurityGroup each authorize
# against TWO resources in one call (the new resource being created, and
# the existing parent VPC it's created inside), but the single statement
# only ever supplied an aws:RequestTag condition, which has no value for
# the existing-parent-VPC side of the authorization check -- causing a real
# AccessDenied on all three actions against the parent VPC ARN. Replaced
# with 8 statements (DevCreateVpcTaggedOnly, DevCreateInternetGatewayTaggedOnly,
# and a new-resource/existing-parent-VPC pair each for CreateSubnet,
# CreateRouteTable, and CreateSecurityGroup). The old, broad,
# untagged-condition DevTagging statement was also replaced with two
# narrower statements (DevTaggingOnApprovedCreateActions,
# DevTaggingManageTaggedResourceOnly) in the same pass. Statement count
# became 26, not 18.
#
# **CORRECTED A FOURTH TIME 2026-07-26** (real IAM managed-policy size-quota
# failure): applying the 26-statement version above against real AWS failed
# -- `iam:CreatePolicyVersion` returned `LimitExceeded: Cannot exceed quota
# for PolicySize: 6144`. **The attempted policy update was NOT applied; the
# real, deployed policy in AWS remains whatever its existing default version
# already was (the pre-26-statement version) -- no AWS change occurred from
# that failed attempt.** A single customer-managed IAM policy has a default
# size quota of 6,144 characters (not counting whitespace) per version.
# Fixed, per explicit instruction, by SPLITTING the single
# `deployment_dev_permissions` policy document into two separate customer-
# managed policies, both attached to the same `aws_iam_role.deployment`:
#
#   - `data.aws_iam_policy_document.deployment_dev_permissions` /
#     `aws_iam_policy.deployment_dev_permissions` (name UNCHANGED:
#     "${var.project_name}-dev-deployment-scope-policy") -- every
#     NON-networking statement: dev Terraform state + lock-object access,
#     EC2 read-only Describe permissions, RunInstances + instance/volume
#     lifecycle permissions, and IAM workstation role/instance-profile
#     creation-management + PassRole. 14 statements.
#   - `data.aws_iam_policy_document.deployment_dev_networking_permissions` /
#     `aws_iam_policy.deployment_dev_networking_permissions` (NEW, name
#     "${var.project_name}-dev-networking-scope-policy") -- every
#     networking statement: the 8-statement CreateVpc/CreateSubnet/
#     CreateInternetGateway/CreateRouteTable/CreateSecurityGroup split
#     (new-resource + existing-parent-VPC pairs), network management
#     actions (Modify/Delete/Attach/Detach/route + route-table-association
#     actions), security-group egress rules, and networking CreateTags/
#     DeleteTags. 12 statements.
#
# 14 + 12 = 26 -- the exact same 26 statements as before this split, moved
# whole (Sid, actions, resources, every condition) into one policy or the
# other, NONE merged, none combined "to save space," and none removed or
# weakened. Every existing control is preserved: no bootstrap-state access
# in either policy, no ability for either policy to modify
# aws_iam_role.deployment itself, no trust-policy change, no
# AdministratorAccess, no wildcard Action, the exact iam:PassRole
# restriction, and the existing DevRunInstancesAmi/
# DevRunInstancesSupportingResources split all unchanged. Each new
# `aws_iam_policy` resource below carries a `lifecycle.precondition` that
# computes the REAL, Terraform-rendered JSON length of its own policy
# document (`length(data.aws_iam_policy_document.<x>.json)`) and fails the
# plan/apply loudly, with a clear message, if it is not comfortably under
# AWS's 6,144-character quota -- a real, Terraform-computed measurement,
# not an estimate, though not guaranteed byte-identical to AWS's own
# internal counting algorithm (Terraform's `.json` output is already
# compact/minified, so this is expected to be a very close proxy). See
# `locals.deployment_dev_permissions_json_length` and
# `locals.deployment_dev_networking_permissions_json_length` below, and the
# matching outputs in outputs.tf.
#
# **CORRECTED A FIFTH TIME 2026-07-26** (SECOND real IAM managed-policy
# size-quota failure): after the fourth correction above was made, the
# resulting `deployment_dev_permissions` document (still 14 statements --
# every NON-networking statement) was itself checked against the new
# `lifecycle.precondition` and found to still exceed the quota:
# `local.deployment_dev_permissions_json_length = 6212`,
# `local.iam_managed_policy_size_quota = 6144` -- 68 characters over. This
# was caught by the precondition at plan time, NOT by a real
# `iam:CreatePolicyVersion` API rejection -- **no AWS command was run and no
# AWS change occurred as part of discovering or fixing this.** The
# networking policy split (above) already resolved its own size question;
# only the non-networking policy remained oversized. Fixed by SPLITTING
# `deployment_dev_permissions` a second time, moving the 4
# workstation-IAM-specific statements (DevWorkstationRoleManage,
# DevWorkstationRolePolicyAttachApprovedOnly,
# DevWorkstationInstanceProfileManage, DevPassWorkstationRoleToEC2Only) out
# into a THIRD customer-managed policy:
#
#   - `data.aws_iam_policy_document.deployment_dev_permissions` (same
#     address, now 10 statements) / `aws_iam_policy.deployment_dev_permissions`
#     (name still UNCHANGED: "${var.project_name}-dev-deployment-scope-policy")
#     -- dev Terraform state + lock-object access, EC2 read-only Describe
#     permissions, RunInstances + instance/volume lifecycle permissions,
#     instance metadata options permissions, and RunInstances tag-on-create
#     permissions.
#   - `data.aws_iam_policy_document.deployment_dev_workstation_iam_permissions`
#     (NEW, 4 statements) / `aws_iam_policy.deployment_dev_workstation_iam_permissions`
#     (NEW, name "${var.project_name}-dev-workstation-iam-scope-policy") --
#     the dev workstation IAM role/instance-profile creation-management +
#     PassRole statements, moved whole (same Sid, actions, resources, every
#     condition) from where they previously lived inside
#     `deployment_dev_permissions`. NONE merged, none combined "to save
#     space," and none removed or weakened.
#
# 10 + 4 = 14 -- the exact same 14 non-networking statements as before this
# second split, now spread across two policies instead of one. Combined
# with the networking policy's 12 statements, all 26 original statements
# from the fourth correction remain present, unchanged in substance, across
# three managed policies now. Every existing control is preserved: no
# bootstrap-state access in any of the three policies, no ability for any
# of the three to modify aws_iam_role.deployment itself, no trust-policy
# change, no AdministratorAccess, no wildcard Action, the exact
# iam:PassRole restriction (now in the workstation-IAM policy), and the
# networking policy is entirely untouched by this correction. The new
# `aws_iam_policy.deployment_dev_workstation_iam_permissions` resource
# carries the same `lifecycle.precondition` pattern as the other two,
# computing `length(data.aws_iam_policy_document.deployment_dev_workstation_iam_permissions.json)`
# against the same 6,144-character quota. See
# `locals.deployment_dev_workstation_iam_permissions_json_length` below and
# the matching new output in outputs.tf.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "deployment_dev_permissions" {
  # --- Dev Terraform state access (Section 11.1 rows 1-4) -----------------

  statement {
    sid       = "DevStateListBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.terraform_state.arn]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values = [
        "dev/terraform.tfstate",
        "dev/terraform.tfstate.tflock",
      ]
    }
  }

  statement {
    sid    = "DevStateBucketMetadataRead"
    effect = "Allow"
    actions = [
      "s3:GetBucketLocation",
      "s3:GetBucketVersioning",
    ]
    resources = [aws_s3_bucket.terraform_state.arn]
  }

  statement {
    sid    = "DevStateObjectReadWrite"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
    ]
    # No s3:DeleteObject on the state object itself -- intentional,
    # mirrors bootstrap's own now-removed self-scoped pattern.
    resources = ["${aws_s3_bucket.terraform_state.arn}/dev/terraform.tfstate"]
  }

  statement {
    sid    = "DevStateLockObjectManage"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject", # delete IS needed here -- releasing a native S3 lock removes the lock object.
    ]
    resources = ["${aws_s3_bucket.terraform_state.arn}/dev/terraform.tfstate.tflock"]
  }

  # --- kms-secrets Terraform state access (ADDED 2026-08-07) ---------------
  # Real regression: the new infrastructure/terraform/kms-secrets/ stack's
  # backend initialized successfully (backend CONFIGURATION has no
  # permissions check of its own), but the first real state read failed --
  # `S3 HeadObject 403 Forbidden` on
  # s3://enterprise-data-platform-tfstate-732264765658/kms-secrets/terraform.tfstate.
  # Root cause: this policy's existing state-access statements
  # (DevStateListBucket/DevStateObjectReadWrite/DevStateLockObjectManage,
  # immediately above) are scoped, by explicit design, ONLY to the
  # "dev/terraform.tfstate*" prefix -- kms-secrets/main.tf's own provider
  # now assumes the deployment role (kms-secrets/providers.tf's departure
  # from logging/'s human-direct pattern, per ADR-0004 Option 3), but no
  # statement anywhere in this role's permissions ever granted it access to
  # the "kms-secrets/terraform.tfstate*" prefix -- an omission, not a
  # deliberate exclusion (unlike bootstrap/terraform.tfstate itself, which
  # is deliberately, permanently excluded -- see the comment block above
  # data.aws_iam_policy_document.deployment_dev_permissions). Fixed by
  # extending the exact same three-statement pattern used for the dev state
  # prefix to this one, scoped only to the two exact kms-secrets state
  # object keys -- no other state prefix (dev/*, bootstrap/*, logging/*) is
  # touched or broadened by this addition.
  statement {
    sid       = "KmsSecretsStateListBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.terraform_state.arn]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values = [
        "kms-secrets/terraform.tfstate",
        "kms-secrets/terraform.tfstate.tflock",
      ]
    }
  }

  statement {
    sid    = "KmsSecretsStateObjectReadWrite"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
    ]
    # No s3:DeleteObject on the state object itself -- same intentional
    # omission as DevStateObjectReadWrite above.
    resources = ["${aws_s3_bucket.terraform_state.arn}/kms-secrets/terraform.tfstate"]
  }

  statement {
    sid    = "KmsSecretsStateLockObjectManage"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject", # delete IS needed here -- releasing a native S3 lock removes the lock object, same as DevStateLockObjectManage above.
    ]
    resources = ["${aws_s3_bucket.terraform_state.arn}/kms-secrets/terraform.tfstate.tflock"]
  }

  # --- cost-controls Terraform state access -- MOVED OUT 2026-08-07 --------
  # A real cost-controls state-access gap (S3 HeadObject 403 on
  # cost-controls/terraform.tfstate) was first fixed by adding
  # CostControlsStateListBucket/CostControlsStateObjectReadWrite/
  # CostControlsStateLockObjectManage directly here, the same shape as the
  # dev/* and kms-secrets/* statements above. That addition pushed this
  # policy document's own rendered JSON to 6715 characters against the
  # 6144-character quota -- caught entirely at plan time by this policy's
  # own lifecycle.precondition below, NOT by a real iam:CreatePolicyVersion
  # AWS API call; no AWS command was run and no AWS change occurred.
  # SPLIT OUT: all three statements moved, unchanged (same Sid, actions,
  # resources, conditions), into a new, dedicated
  # data.aws_iam_policy_document.deployment_shared_cost_controls_state_permissions
  # / aws_iam_policy.deployment_shared_cost_controls_state_permissions
  # further down this file -- following the exact same "split into an
  # additional managed policy" precedent this project has already used
  # three times (the original 26-statement split, the workstation-IAM
  # split, and now this one). Nothing was merged, dropped, or weakened to
  # save space. DevStateBucketMetadataRead (s3:GetBucketLocation/
  # s3:GetBucketVersioning, above) remains bucket-wide, unconditioned, and
  # still attached to the same shared deployment role -- it continues to
  # cover the cost-controls backend's need for these two actions with no
  # duplicate statement needed in the new policy, since IAM evaluates the
  # union of every policy attached to a role, not each policy in
  # isolation.

  # --- Read-only / describe (Section 11.1 row 8) ---------------------------
  # Resource = "*" is unconditional here -- Describe* actions never support
  # resource-level restriction in AWS IAM (Section 11.3 item 2) -- this part
  # is unchanged. aws:RequestedRegion ADDED 2026-07-26: unlike
  # aws:ResourceTag/aws:RequestTag (which require the specific action to
  # evaluate resource/request tags, genuinely unsupported by some actions),
  # aws:RequestedRegion is one of AWS's standard, universally-available
  # GLOBAL condition context keys -- documented as applicable to any AWS API
  # call regardless of service or action, since it reflects the region the
  # request itself was made to, not a resource attribute. It is added here
  # for the same reason it is already used on every other statement in this
  # policy: confining this role's blast radius to ap-south-1, even though
  # Describe* actions cannot be resource-scoped. No other condition key is
  # added to this statement -- Describe* actions do not support
  # aws:ResourceTag/ec2:ResourceTag or any other resource-tag-based
  # condition, since they are inventory/read operations, not actions against
  # one specific resource whose tags could be evaluated; adding one here
  # would be exactly the "unsupported condition added merely for appearance"
  # this review was told not to do.
  #
  # ec2:DescribeVpcAttribute ADDED 2026-07-26 (real partial-apply failure,
  # first environments/dev apply attempt): the AWS provider calls this
  # action internally while waiting for an aws_vpc resource's
  # enable_dns_hostnames/enable_dns_support attributes (modules/vpc/main.tf)
  # to finish propagating after creation -- a read-only Describe action,
  # same category as every other action already in this statement, not a
  # new write permission. Its absence caused a real AccessDenied error
  # partway through the first real environments/dev apply; see
  # PROJECT_EXECUTION_JOURNAL.md and Memory.md for the full incident record
  # and required recovery sequence. No other action, resource, or condition
  # in this statement changed. **Kept in this (non-networking) policy by the
  # 2026-07-26 size-quota split** -- these are EC2 read-only Describe
  # permissions used across both networking and instance/AMI inventory
  # lookups, categorized as a non-networking permission per this split's
  # explicit instruction.
  statement {
    sid    = "DevReadOnlyDescribe"
    effect = "Allow"
    actions = [
      "ec2:DescribeVpcs",
      "ec2:DescribeVpcAttribute",
      "ec2:DescribeSubnets",
      "ec2:DescribeInternetGateways",
      "ec2:DescribeRouteTables",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSecurityGroupRules",
      "ec2:DescribeInstances",
      "ec2:DescribeInstanceAttribute",
      "ec2:DescribeInstanceTypes",
      "ec2:DescribeInstanceCreditSpecifications",
      "ec2:DescribeImages",
      "ec2:DescribeAvailabilityZones",
      "ec2:DescribeTags",
      "ec2:DescribeVolumes",
      "ec2:DescribeAccountAttributes",
      # ec2:DescribeVpcEndpoints, ec2:DescribeFlowLogs, logs:DescribeLogGroups
      # ADDED 2026-08-07 (Phase 0 Networking Hardening remaining-resource
      # authorization gap) -- same category as every other action already in
      # this statement: unconditional, read-only Describe/inventory actions
      # that AWS IAM does not support restricting to a specific resource ARN
      # for. logs:DescribeLogGroups is a CloudWatch Logs action, not EC2, but
      # is added to this same statement rather than a new one -- it is the
      # established home in this policy for exactly this category
      # (unconditional Describe, region-scoped only), and adding a
      # single-action statement elsewhere for it alone would not change its
      # behavior or its resource-scoping, only where it's declared.
      "ec2:DescribeVpcEndpoints",
      "ec2:DescribeFlowLogs",
      "logs:DescribeLogGroups",
      # ec2:DescribePrefixLists ADDED 2026-08-07 (second real Networking
      # Hardening apply, partial success -- refresh failure). The AWS
      # provider calls this internally while flattening/reading the S3
      # Gateway VPC endpoint's prefix-list-based service name
      # (com.amazonaws.<region>.s3) during a normal `terraform plan`
      # refresh -- a read-only Describe action, same category as every
      # other action already in this statement, not a new write
      # permission. Real evidence: this exact action name, on this exact
      # endpoint, was reported as the refresh-time AccessDenied by a real
      # `terraform plan` against the already-created
      # vpce-0baab9fe0d5815ad8.
      "ec2:DescribePrefixLists",
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.aws_region]
    }
  }

  # --- RunInstances and instance lifecycle (Section 11.1 rows 9-11) -------
  # CORRECTED 2026-07-26 (deployed-v1-policy review, RunInstances condition-
  # scoping issue): RunInstances is a multi-resource-type action -- a single
  # launch call references the AMI it boots from AND the instance/volume/
  # network-interface/subnet/security-group resources it creates/attaches,
  # all in the same API call. The two statements below split the ORIGINAL
  # single "DevRunInstances" statement's Resource list along that exact
  # boundary, because ec2:Owner is an AMI-specific condition key -- it
  # reflects who owns the IMAGE being launched from, and is not a meaningful
  # or populated context key for the instance/volume/network-interface/
  # subnet/security-group resources RunInstances also touches. Applying
  # ec2:Owner = "amazon" across a Resource list that mixed the AMI resource
  # type together with those five non-AMI types scoped the condition more
  # broadly than the key is actually meant to apply to.

  statement {
    sid    = "DevRunInstancesAmi"
    effect = "Allow"
    actions = [
      "ec2:RunInstances",
    ]
    # AWS-owned AMI only -- no account segment in this ARN, same as the
    # original combined statement's image/* entry.
    resources = ["arn:aws:ec2:${var.aws_region}::image/*"]

    # DIAGNOSTIC CONDITIONS RESTORED (2026-07-26), THEN ec2:InstanceType
    # REMOVED AGAIN AS A CONFIRMED DEFECT (2026-08-04) -- see below.
    #
    # A three-round diagnostic sequence (removing ec2:Owner, then
    # ec2:InstanceType, then aws:RequestedRegion, one at a time, on real
    # applies) had been run earlier against a real, unexplained
    # ec2:RunInstances UnauthorizedOperation on this exact AMI resource. At
    # that time an MFA/STS credential-flow issue (Terraform not actually
    # operating under the deployment role's assumed-role session) was
    # identified and fixed, and all three conditions were restored here on
    # the belief that the credential issue fully explained the failure. **That
    # belief was incomplete.** It is NOT accurate to say this investigation
    # was fully closed at that point, and it is NOT accurate to say
    # ec2:InstanceType on this AMI-only statement was harmless -- both claims
    # were removed from this comment on 2026-08-04 (see below).
    #
    # REAL EVIDENCE, 2026-08-04: after this statement (with ec2:InstanceType
    # restored, t3.small included) was deployed to real AWS, a real
    # `ec2:RunInstances --dry-run` request was executed under the confirmed,
    # genuine deployment-role session. AWS denied it: `UnauthorizedOperation`
    # on `arn:aws:ec2:ap-south-1::image/<AMI_ID>`. `--dry-run` creates no
    # resource, so this test had no side effect. Root cause, confirmed
    # directly from this statement's own condition, not from a credential
    # issue this time: `ec2:InstanceType` is an INSTANCE-resource condition
    # key (it describes the instance type of the instance being launched,
    # not any property of the AMI it boots from) -- it is not a supported,
    # populated condition key on the AMI/`image` resource type at all.
    # During AMI-side authorization, AWS IAM Policy Evaluation treats an
    # absent condition key under `StringEquals` as a non-match (unlike
    # `StringEqualsIfExists`, which was deliberately NOT used here -- see the
    # design note below), so this entire `Allow` statement failed to match
    # and `RunInstances` was denied on the AMI resource specifically.
    #
    # FIX (2026-08-04): the `ec2:InstanceType` condition block is removed
    # from this AMI-only statement. `ec2:Owner` and `aws:RequestedRegion`
    # (both genuinely applicable to the AMI resource) are unchanged. The
    # instance-type restriction remains fully enforced -- it lives on
    # `DevRunInstancesSupportingResources` below, whose `Resource` is the
    # `instance/*` type that `ec2:InstanceType` actually applies to. This is
    # the cleaner least-privilege design: placing a condition key only on the
    # resource type it is actually defined for, rather than attaching it
    # everywhere and relying on AWS silently ignoring it where it doesn't
    # apply -- which is exactly what happened here and caused a real,
    # deployed authorization failure, not a merely theoretical one.
    #
    # Full incident record, including the real `--dry-run` command/output and
    # this correction: PROJECT_EXECUTION_JOURNAL.md.
    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.aws_region]
    }
    condition {
      test     = "StringEquals"
      variable = "ec2:Owner"
      values   = ["amazon"]
    }
  }

  statement {
    sid    = "DevRunInstancesSupportingResources"
    effect = "Allow"
    actions = [
      "ec2:RunInstances",
    ]
    # The five non-AMI resource types RunInstances also references in the
    # same call -- all account/region-scoped, unchanged in substance from
    # the original combined statement's entries for these five types.
    resources = [
      "arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:instance/*",
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.aws_region]
    }
    # TEMPORARY, ACCOUNT-SPECIFIC WORKAROUND (2026-07-26) -- NOT a design
    # change. This account rejects t3.medium/t3.large/t3.xlarge with a real
    # RunInstances-time `InvalidParameterCombination: instance type is not
    # eligible for Free Tier` error (confirmed via manual launch testing;
    # t3.small, t3.micro, and m7i-flex.large all launch successfully in
    # this account). t3.small is added here ONLY so this specific, Free-
    # Tier-restricted account can proceed with implementation and testing
    # work -- it mirrors the identical, identically-reasoned widening of
    # the environments/dev and modules/ec2-workstation variable validations
    # (see those files' comments for the full incident record). The
    # project's approved default and design target remain t3.medium; this
    # is not evidence toward EC2_Development_Workstation.md Section 6/28's
    # separate, still-open "whether t3.small is adopted later" question,
    # since the cause here is account eligibility, not workload capacity.
    # Revert to ["t3.medium", "t3.large", "t3.xlarge"] once this account's
    # restriction is resolved or development moves to an unrestricted
    # account -- see PROJECT_EXECUTION_JOURNAL.md for the incident record.
    condition {
      test     = "StringEquals"
      variable = "ec2:InstanceType"
      values = [
        "t3.medium",
        "t3.large",
        "t3.xlarge",
        "t3.small",
      ]
    }
    # Deliberately NO ec2:Owner condition here -- these five resource types
    # are not AMIs, and this condition key does not apply to them (see the
    # comment block above this statement).
  }

  statement {
    sid    = "DevRunInstancesSupportingResourcesNonInstance"
    effect = "Allow"
    actions = [
      "ec2:RunInstances",
    ]
    # The five non-AMI resource types RunInstances also references in the
    # same call -- all account/region-scoped, unchanged in substance from
    # the original combined statement's entries for these five types.
    resources = [
      "arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:volume/*",
      "arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:network-interface/*",
      "arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:subnet/*",
      "arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:security-group/*",
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.aws_region]
    }
    # Deliberately NO ec2:Owner condition here -- these five resource types
    # are not AMIs, and this condition key does not apply to them (see the
    # comment block above this statement).
  }

  statement {
    sid     = "DevRunInstancesTagOnCreate"
    effect  = "Allow"
    actions = ["ec2:CreateTags"]
    resources = [
      "arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:instance/*",
      "arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:volume/*",
    ]

    condition {
      test     = "StringEquals"
      variable = "ec2:CreateAction"
      values   = ["RunInstances"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Project"
      values   = [var.project_name]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Environment"
      values   = ["dev"]
    }
  }

  statement {
    sid    = "DevInstanceLifecycleTaggedOnly"
    effect = "Allow"
    actions = [
      "ec2:StartInstances",
      "ec2:StopInstances",
      "ec2:RebootInstances",
      "ec2:TerminateInstances",
    ]
    resources = ["arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:instance/*"]

    # Standardized 2026-07-26 from ec2:ResourceTag to the global
    # aws:ResourceTag form, for consistency with
    # DevNetworkingManageTaggedResourceOnly and DevSecurityGroupEgressRulesOnly
    # (both now in the networking policy) -- both keys are confirmed
    # supported together by AWS's EC2 Service Authorization Reference for
    # every taggable resource type checked during this review; this is a
    # non-functional consistency change, not a capability fix.
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Project"
      values   = [var.project_name]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Environment"
      values   = ["dev"]
    }
  }

  statement {
    sid       = "DevInstanceMetadataOptionsTaggedOnly"
    effect    = "Allow"
    actions   = ["ec2:ModifyInstanceMetadataOptions"]
    resources = ["arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:instance/*"]

    # Standardized 2026-07-26 -- see DevInstanceLifecycleTaggedOnly above.
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Project"
      values   = [var.project_name]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Environment"
      values   = ["dev"]
    }
  }
}

# ---------------------------------------------------------------------------
# Workstation IAM permissions -- SPLIT OUT 2026-07-26 into this third,
# separate policy document, purely to stay under AWS's per-policy size
# quota (see the comment block above
# `data.aws_iam_policy_document.deployment_dev_permissions` for the full
# incident: after the fourth correction split networking out into its own
# policy, the remaining non-networking `deployment_dev_permissions` document
# was itself checked by its own `lifecycle.precondition` and found to still
# be 68 characters over the 6,144-character quota -- caught at plan time by
# that precondition, NOT by a real `iam:CreatePolicyVersion` AWS API call;
# no AWS command was run and no AWS change occurred). Every statement below
# is moved here UNCHANGED (same Sid, actions, resources, conditions) from
# where it previously lived inside `deployment_dev_permissions` -- exact
# resource-level ARN restriction, IAM DOES support this (unlike most of the
# EC2 actions in the other two policies). environments/dev can never widen
# these beyond the exact var.dev_workstation_role_name resource, and can
# never touch aws_iam_role.deployment (this role) itself. Nothing was
# merged, combined, removed, or weakened to save space.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "deployment_dev_workstation_iam_permissions" {
  statement {
    sid    = "DevWorkstationRoleManage"
    effect = "Allow"
    actions = [
      "iam:CreateRole",
      "iam:GetRole",
      "iam:UpdateRole",
      "iam:UpdateAssumeRolePolicy",
      "iam:DeleteRole",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:PutRolePolicy",
      "iam:GetRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies",
    ]
    resources = ["arn:aws:iam::${var.aws_account_id}:role/${var.dev_workstation_role_name}"]
  }

  statement {
    sid    = "DevWorkstationRolePolicyAttachApprovedOnly"
    effect = "Allow"
    actions = [
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
    ]
    resources = ["arn:aws:iam::${var.aws_account_id}:role/${var.dev_workstation_role_name}"]

    condition {
      test     = "StringEquals"
      variable = "iam:PolicyARN"
      values   = ["arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"]
    }
  }

  statement {
    sid    = "DevWorkstationInstanceProfileManage"
    effect = "Allow"
    actions = [
      "iam:CreateInstanceProfile",
      "iam:GetInstanceProfile",
      "iam:DeleteInstanceProfile",
      "iam:AddRoleToInstanceProfile",
      "iam:RemoveRoleFromInstanceProfile",
      "iam:TagInstanceProfile",
      "iam:UntagInstanceProfile",
    ]
    resources = ["arn:aws:iam::${var.aws_account_id}:instance-profile/${var.dev_workstation_role_name}"]
  }

  statement {
    sid       = "DevPassWorkstationRoleToEC2Only"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = ["arn:aws:iam::${var.aws_account_id}:role/${var.dev_workstation_role_name}"]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ec2.amazonaws.com"]
    }
  }
}

# ---------------------------------------------------------------------------
# Networking permissions -- SPLIT OUT 2026-07-26 into this second, separate
# policy document, purely to stay under AWS's per-policy size quota (see the
# comment block above `data.aws_iam_policy_document.deployment_dev_permissions`
# for the full incident: a real `iam:CreatePolicyVersion` call failed with
# `LimitExceeded: Cannot exceed quota for PolicySize: 6144` when this
# project tried to apply all 26 statements as one policy; that failed
# attempt made NO change to the real, deployed policy in AWS). Every
# statement below is moved here UNCHANGED (same Sid, actions, resources,
# conditions) from where it previously lived inside
# `deployment_dev_permissions` -- nothing was merged, combined, removed, or
# weakened to save space.
#
# CORRECTED 2026-07-26 (IAM policy bypass fix, first-real-validation-gate
# follow-up task): the ORIGINAL two-statement design below (a single
# untagged "DevNetworkingCreateManage" covering ALL 20 create+manage
# actions, plus a second "DevNetworkingCreateManageTaggedOnCreate"
# re-granting 5 of those same actions with a tag condition) had a real
# bypass -- IAM Allow statements are additive/OR'd, so ANY statement that
# allows an action is sufficient, regardless of how many OTHER statements
# also mention that same action with a stricter condition. Because
# CreateVpc/CreateSubnet/CreateInternetGateway/CreateRouteTable/
# CreateSecurityGroup appeared in BOTH statements, the untagged statement's
# unconditional Allow made the tagged statement's tag condition
# meaningless for those 5 actions -- a caller could omit the Project/
# Environment tags entirely and still succeed via the untagged statement.
# Fixed by making each action appear in EXACTLY ONE statement: the 5 pure
# "create a brand-new resource" actions lived ONLY in a single combined
# DevNetworkingCreateTaggedOnly statement (tag-on-create enforced via
# aws:RequestTag, no untagged alternative anywhere in this policy); the
# remaining "modify an already-existing resource" actions live in
# DevNetworkingManageTaggedResourceOnly below, conditioned on the TARGET
# resource already carrying the Project/Environment tags
# (aws:ResourceTag), not on request-time tags (which don't apply to an
# action that isn't creating anything).
#
# CORRECTED AGAIN 2026-07-26 (second real partial `environments/dev` apply
# failure): that single combined DevNetworkingCreateTaggedOnly statement
# was itself a real, deployed defect. A real apply against it created a
# replacement VPC and an Internet Gateway successfully, then failed with
# AccessDenied on ec2:CreateSubnet / ec2:CreateRouteTable /
# ec2:CreateSecurityGroup, each against the PARENT VPC's ARN. Root cause:
# CreateSubnet, CreateRouteTable, and CreateSecurityGroup are each
# multi-resource-type actions that authorize against TWO different
# resources in the same call -- the new resource being created (subnet /
# route-table / security-group) AND the existing parent VPC it is created
# inside. aws:RequestTag only has a value for a resource actually being
# tagged as part of the current call -- the existing parent VPC is not
# being tagged (it already has tags), so when AWS evaluated authorization
# against the parent-VPC side of the call, the single statement's
# aws:RequestTag condition had nothing to match against that resource,
# producing an implicit deny for that resource even though the new-resource
# side would have passed. CreateVpc and CreateInternetGateway do not have
# this problem: confirmed via a real 2026-07-26 fetch of AWS's own EC2
# Service Authorization Reference, CreateVpc's only resource type is "vpc"
# (no parent) and CreateInternetGateway's only resource type is
# "internet-gateway" (not attached to a VPC until a separate
# AttachInternetGateway call, already authorized in
# DevNetworkingManageTaggedResourceOnly below) -- both already succeeded in
# this second partial apply. CreateSubnet, CreateRouteTable, and
# CreateSecurityGroup were each confirmed (same fetch) to require BOTH
# their own new resource type (subnet* / route-table* / security-group*,
# supporting aws:RequestTag/${TagKey}) AND the existing "vpc" resource type
# (supporting aws:ResourceTag/${TagKey}, not aws:RequestTag). Fixed by
# replacing the single DevNetworkingCreateTaggedOnly statement with the
# eight statements below: one each for CreateVpc and CreateInternetGateway
# (single resource type, aws:RequestTag only), and a NEW-resource /
# EXISTING-parent-VPC pair for each of CreateSubnet, CreateRouteTable, and
# CreateSecurityGroup -- the new-resource half conditioned on
# aws:RequestTag (the resource being created), the existing-VPC half
# conditioned on aws:ResourceTag (the resource already tagged by a prior
# DevCreateVpcTaggedOnly call). Tag enforcement is preserved throughout --
# no untagged path exists for any of these 5 actions anywhere in this
# policy.
#
# Condition-key support was checked against AWS's own "Actions, resources,
# and condition keys for Amazon EC2" Service Authorization Reference
# (fetched 2026-07-26) rather than assumed. Every action below that
# creates a NEW taggable resource (vpc, subnet, internet-gateway,
# route-table, security-group) was confirmed to support
# aws:RequestTag/${TagKey} at creation time. Every action below that acts
# on an EXISTING taggable resource of one of those same five types is
# CONFIRMED to support aws:ResourceTag/${TagKey} (and the equivalent
# ec2:ResourceTag/${TagKey} where applicable):
# CreateRoute, DeleteSubnet, DeleteInternetGateway, DeleteRoute,
# DeleteRouteTable, AssociateRouteTable, AttachInternetGateway,
# DisassociateRouteTable -- these 8 were directly confirmed against this
# project's own fetch of the official AWS reference. The remaining 7 --
# DeleteVpc, ModifyVpcAttribute, ModifySubnetAttribute,
# DetachInternetGateway, ReplaceRoute, ReplaceRouteTableAssociation,
# DeleteSecurityGroup -- were originally included on pattern-inference
# alone (this project's own fetch tool truncates the reference page before
# reaching them alphabetically), then CONFIRMED 2026-07-26 (second review
# pass) by the user's own direct review of the current official AWS EC2
# Service Authorization Reference. Attribution note, per this project's
# evidence discipline: this specific confirmation is recorded as
# user-reported reference evidence -- this sandbox's own fetch tool still
# could not independently re-retrieve these 7 entries when re-attempted
# during the same review, so it is not claimed as a Claude-repeated fetch.
# All 15 actions in this statement are therefore treated as confirmed; none
# remain on inference alone. Resource-level ARN scoping (narrowing
# `resources` below from "*" to per-type ARN patterns) is a separate,
# distinct question -- see that comment immediately below.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "deployment_dev_networking_permissions" {
  statement {
    sid    = "DevCreateVpcTaggedOnly"
    effect = "Allow"
    actions = [
      "ec2:CreateVpc",
    ]
    # CONFIRMED 2026-07-26 (real AWS reference fetch): CreateVpc's only
    # resource type is "vpc" -- no parent resource is authorized in the same
    # call, so a single-statement, aws:RequestTag-only grant is correct and
    # sufficient. This action was NOT part of the second partial-apply
    # failure -- the replacement VPC was created successfully against this
    # same permission.
    resources = ["arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:vpc/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.aws_region]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Project"
      values   = [var.project_name]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Environment"
      values   = ["dev"]
    }
  }

  statement {
    sid    = "DevCreateInternetGatewayTaggedOnly"
    effect = "Allow"
    actions = [
      "ec2:CreateInternetGateway",
    ]
    # CONFIRMED 2026-07-26 (real AWS reference fetch): CreateInternetGateway's
    # only resource type is "internet-gateway" -- it is not attached to any
    # VPC at creation time (AttachInternetGateway is a separate call,
    # already authorized in DevNetworkingManageTaggedResourceOnly below), so
    # no parent-resource statement is needed here. This action was NOT part
    # of the second partial-apply failure -- the Internet Gateway was
    # created successfully against this same permission.
    resources = ["arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:internet-gateway/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.aws_region]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Project"
      values   = [var.project_name]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Environment"
      values   = ["dev"]
    }
  }

  statement {
    sid    = "DevCreateSubnetNewResourceTaggedOnly"
    effect = "Allow"
    actions = [
      "ec2:CreateSubnet",
    ]
    # CONFIRMED 2026-07-26 (real AWS reference fetch): CreateSubnet requires
    # BOTH the new "subnet" resource type (this statement, aws:RequestTag)
    # AND the existing "vpc" resource type it is created inside (the paired
    # statement immediately below, aws:ResourceTag) -- see the correction
    # note above DevCreateVpcTaggedOnly for the real AccessDenied this fixes.
    resources = ["arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:subnet/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.aws_region]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Project"
      values   = [var.project_name]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Environment"
      values   = ["dev"]
    }
  }

  statement {
    sid    = "DevCreateSubnetExistingVpcTaggedOnly"
    effect = "Allow"
    actions = [
      "ec2:CreateSubnet",
    ]
    # The PARENT VPC side of CreateSubnet's authorization -- conditioned on
    # aws:ResourceTag, not aws:RequestTag, since the VPC already exists and
    # is not itself being tagged by this call. Only a VPC created via
    # DevCreateVpcTaggedOnly above (and therefore already carrying the
    # Project/Environment tags) satisfies this.
    resources = ["arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:vpc/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.aws_region]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Project"
      values   = [var.project_name]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Environment"
      values   = ["dev"]
    }
  }

  statement {
    sid    = "DevCreateRouteTableNewResourceTaggedOnly"
    effect = "Allow"
    actions = [
      "ec2:CreateRouteTable",
    ]
    # CONFIRMED 2026-07-26 (real AWS reference fetch): CreateRouteTable
    # requires BOTH the new "route-table" resource type (this statement,
    # aws:RequestTag) AND the existing "vpc" resource type (the paired
    # statement immediately below, aws:ResourceTag).
    resources = ["arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:route-table/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.aws_region]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Project"
      values   = [var.project_name]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Environment"
      values   = ["dev"]
    }
  }

  statement {
    sid    = "DevCreateRouteTableExistingVpcTaggedOnly"
    effect = "Allow"
    actions = [
      "ec2:CreateRouteTable",
    ]
    # The PARENT VPC side of CreateRouteTable's authorization -- see
    # DevCreateSubnetExistingVpcTaggedOnly above for the identical rationale.
    resources = ["arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:vpc/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.aws_region]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Project"
      values   = [var.project_name]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Environment"
      values   = ["dev"]
    }
  }

  statement {
    sid    = "DevCreateSecurityGroupNewResourceTaggedOnly"
    effect = "Allow"
    actions = [
      "ec2:CreateSecurityGroup",
    ]
    # CONFIRMED 2026-07-26 (real AWS reference fetch): CreateSecurityGroup
    # requires BOTH the new "security-group" resource type (this statement,
    # aws:RequestTag) AND the existing "vpc" resource type (the paired
    # statement immediately below, aws:ResourceTag).
    resources = ["arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:security-group/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.aws_region]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Project"
      values   = [var.project_name]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Environment"
      values   = ["dev"]
    }
  }

  statement {
    sid    = "DevCreateSecurityGroupExistingVpcTaggedOnly"
    effect = "Allow"
    actions = [
      "ec2:CreateSecurityGroup",
    ]
    # The PARENT VPC side of CreateSecurityGroup's authorization -- see
    # DevCreateSubnetExistingVpcTaggedOnly above for the identical rationale.
    resources = ["arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:vpc/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.aws_region]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Project"
      values   = [var.project_name]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Environment"
      values   = ["dev"]
    }
  }

  statement {
    sid    = "DevNetworkingManageTaggedResourceOnly"
    effect = "Allow"
    actions = [
      "ec2:ModifyVpcAttribute",
      "ec2:DeleteVpc",
      "ec2:ModifySubnetAttribute",
      "ec2:DeleteSubnet",
      "ec2:AttachInternetGateway",
      "ec2:DetachInternetGateway",
      "ec2:DeleteInternetGateway",
      "ec2:CreateRoute",
      "ec2:ReplaceRoute",
      "ec2:DeleteRoute",
      "ec2:AssociateRouteTable",
      "ec2:DisassociateRouteTable",
      "ec2:ReplaceRouteTableAssociation",
      "ec2:DeleteRouteTable",
      "ec2:DeleteSecurityGroup",
    ]
    # These actions all operate on an ALREADY-EXISTING vpc/subnet/internet-
    # gateway/route-table/security-group resource -- unlike the 8 pure
    # create statements above, resource-level ARN restriction genuinely is
    # possible in principle for several of these per the AWS reference, but
    # this policy keeps Resource = "*" here (not attempting a specific ARN
    # pattern this task did not ask for and this review did not verify the
    # exact syntax of) and instead relies entirely on the aws:ResourceTag
    # condition below to require the TARGET resource already carry this
    # project's Project/Environment tags -- a resource that was created via
    # the create statements above (and therefore already tagged) satisfies
    # this; an untagged or foreign resource does not.
    #
    # REVIEWED 2026-07-26 (resource-ARN-type coverage pass): the 15 actions
    # above collectively require these AWS resource types (per the official
    # EC2 reference): vpc*, subnet*, internet-gateway*, route-table*, and
    # security-group*. Several actions are multi-resource-type (e.g.
    # AttachInternetGateway/DetachInternetGateway act on BOTH
    # internet-gateway AND vpc; AssociateRouteTable/DisassociateRouteTable/
    # ReplaceRouteTableAssociation act on route-table AND subnet/gateway). A
    # bare "*" wildcard trivially includes every one of these types with no
    # gap -- there is no itemized ARN list here for a required type to be
    # missing from, so no resource ARN type is missing or incorrectly scoped
    # and no change was made to this element. Replacing "*" with an itemized,
    # per-type ARN list remains a distinct, NOT-yet-adopted future tightening
    # option (unchanged from the note above), separate from the
    # missing-type question this review checked.
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.aws_region]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Project"
      values   = [var.project_name]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Environment"
      values   = ["dev"]
    }
  }

  statement {
    sid    = "DevSecurityGroupEgressRulesOnly"
    effect = "Allow"
    actions = [
      "ec2:AuthorizeSecurityGroupEgress",
      "ec2:RevokeSecurityGroupEgress",
    ]
    # Resource already scoped to the security-group resource type (not "*")
    # -- unchanged from the prior design. aws:ResourceTag conditions added
    # (2026-07-26) for the same reason as DevNetworkingManageTaggedResourceOnly
    # above: a security group's egress rules can only be modified once the
    # group itself already exists and is tagged. Not independently confirmed
    # against the AWS reference this pass (same documented caveat as above)
    # -- inferred from the security-group resource type's consistent pattern.
    resources = ["arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:security-group/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.aws_region]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Project"
      values   = [var.project_name]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Environment"
      values   = ["dev"]
    }
  }

  # CORRECTED 2026-07-26 (second real partial `environments/dev` apply
  # failure, deployment-role policy restructuring): the prior DevTagging
  # statement granted ec2:CreateTags/ec2:DeleteTags against Resource = "*"
  # with NO tag condition at all -- broader than necessary, since AWS
  # performs its own implicit ec2:CreateTags authorization check whenever a
  # resource is tagged as part of its own creation call (the
  # TagSpecifications parameter), and Terraform's separate tag-reconciliation
  # machinery needs CreateTags/DeleteTags only against resources that already
  # exist. Split into the two narrower statements below: create-time tagging
  # (conditioned on ec2:CreateAction, restricted to exactly the five approved
  # non-RunInstances create actions, with aws:RequestTag enforced -- matching
  # the tag actually being requested) and post-creation tag management
  # (conditioned on aws:ResourceTag, restricted to resources that already
  # carry this project's tags). Do not broaden either statement merely to
  # make a future apply work -- narrow further, or add a separately reviewed
  # statement, if a genuine new need is found.
  #
  # ec2:CreateAction as a condition key on ec2:CreateTags is AWS's own
  # officially documented tag-on-create enforcement pattern -- this exact
  # policy already relies on it, unmodified and previously reviewed, in the
  # DevRunInstancesTagOnCreate statement (deployment_dev_permissions,
  # non-networking policy: ec2:CreateAction = "RunInstances", Resource =
  # instance/*). This statement applies the same pattern to the five
  # non-RunInstances create actions -- RunInstances itself is deliberately
  # NOT included below; its create-time tagging remains exclusively
  # authorized by the pre-existing, unchanged DevRunInstancesTagOnCreate
  # statement in the other policy, preserving all existing RunInstances
  # split logic per this correction's constraints. **Evidence note**: a real
  # 2026-07-26 fetch of AWS's EC2 Service Authorization Reference confirmed
  # CreateVpc/CreateSubnet/CreateInternetGateway/CreateRouteTable/
  # CreateSecurityGroup's own resource-type support (used for the eight
  # create statements above), but the same fetch's copy of ec2:CreateTags'
  # own resource-type table did not show ec2:CreateAction listed against the
  # vpc/subnet/internet-gateway/route-table/security-group resource-type
  # rows specifically -- it appeared once in the reachable portion of that
  # table, against the unrelated vpn-gateway resource type. This project's
  # fetch tool has a known, previously documented truncation issue against
  # this same reference page (PROJECT_EXECUTION_JOURNAL.md), so this is
  # recorded as an inconclusive fetch, not a confirmed absence. This
  # statement is therefore pattern-inferred from AWS's well-established,
  # officially documented tag-on-create pattern and this policy's own
  # already-working RunInstances precedent -- not independently
  # reference-confirmed for these five specific actions -- flagged here for
  # a future confirmation pass, the same evidence-attribution treatment
  # already used elsewhere in this policy for pattern-inferred condition
  # keys (see DevNetworkingManageTaggedResourceOnly's history above).
  statement {
    sid    = "DevTaggingOnApprovedCreateActions"
    effect = "Allow"
    actions = [
      "ec2:CreateTags",
    ]
    # Resource = "*" here (not narrowed to per-type ARNs in this pass) --
    # this single call-time authorization spans whichever of the five
    # resource types below was just created.
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "ec2:CreateAction"
      values = [
        "CreateVpc",
        "CreateSubnet",
        "CreateInternetGateway",
        "CreateRouteTable",
        "CreateSecurityGroup",
        # CreateVpcEndpoint, CreateFlowLogs ADDED 2026-08-07 (Phase 0
        # Networking Hardening remaining-resource authorization gap) -- same
        # tag-on-create pattern as the five original actions above, no
        # untagged alternative anywhere in this policy.
        "CreateVpcEndpoint",
        "CreateFlowLogs",
      ]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.aws_region]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Project"
      values   = [var.project_name]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Environment"
      values   = ["dev"]
    }
  }

  statement {
    sid    = "DevTaggingManageTaggedResourceOnly"
    effect = "Allow"
    actions = [
      "ec2:CreateTags",
      "ec2:DeleteTags",
    ]
    # Post-creation tag management for the networking resource types this
    # policy manages -- Terraform's own tag-reconciliation machinery
    # (default_tags, or a subsequent apply that changes a resource's tags)
    # against a resource that ALREADY exists and already carries this
    # project's Project/Environment tags. Restricting via aws:ResourceTag
    # (rather than leaving this broad and untagged, as the prior DevTagging
    # statement did) does not block legitimate reconciliation, since
    # Project/Environment are fixed, unchanging tag values on every resource
    # this policy can create -- only a genuinely untagged or foreign
    # resource is excluded, which is the intended restriction, not an
    # accidental one.
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.aws_region]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Project"
      values   = [var.project_name]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Environment"
      values   = ["dev"]
    }
  }

  # -------------------------------------------------------------------------
  # NOTE (2026-08-07, moved same day): the default-security-group adoption
  # statement (CKV2_AWS_12 remediation, Sid DevDefaultSecurityGroupAdoptionOnly)
  # briefly lived here. A real bootstrap `terraform plan` failed this
  # document's own size-quota precondition (below) once that statement was
  # added: rendered JSON length 6282 characters against the 6144 AWS
  # managed-policy quota. Per this project's standing precedent for size-
  # quota failures (never merge statements or drop conditions to save
  # space -- split into an additional managed policy instead), that
  # statement now lives in its own dedicated document/policy/attachment:
  # data.aws_iam_policy_document.deployment_dev_default_sg_adoption_permissions
  # / aws_iam_policy.deployment_dev_default_sg_adoption_permissions /
  # aws_iam_role_policy_attachment.deployment_dev_default_sg_adoption_permissions
  # (defined later in this file, alongside the other split-out dev
  # policies). Its content -- Sid, actions, exact SG ARN, single
  # aws:RequestedRegion condition, deliberate absence of any
  # aws:ResourceTag condition -- is unchanged from what briefly lived here;
  # only its containing managed policy changed. Every other statement in
  # this document (including DevSecurityGroupEgressRulesOnly,
  # DevTaggingManageTaggedResourceOnly, and everything above) is untouched
  # by this move.
  # -------------------------------------------------------------------------
}

# ---------------------------------------------------------------------------
# Real, Terraform-computed policy-document sizes -- added 2026-07-26 as part
# of the size-quota-failure correction above (and extended the same day for
# the second size-quota correction that split out the workstation-IAM
# policy). `length()` on each data source's own `.json` attribute is a REAL
# measurement of the exact JSON string Terraform will submit to AWS, not a
# separate estimate -- and that `.json` output is already compact/minified
# (no pretty-printing), so this is expected to closely track AWS's own
# "non-whitespace character count" quota check, though it is not guaranteed
# byte-identical to AWS's internal algorithm (e.g. any Unicode-escaping
# difference would not be caught here). Used in each aws_iam_policy
# resource's own lifecycle.precondition below, and exposed via outputs.tf
# for visibility after any real plan/apply. It was exactly this mechanism
# that caught the second size-quota failure
# (deployment_dev_permissions_json_length = 6212, over the 6144 quota) at
# plan time, before any AWS API call was made.
# ---------------------------------------------------------------------------

locals {
  iam_managed_policy_size_quota = 6144

  deployment_dev_permissions_json_length                 = length(data.aws_iam_policy_document.deployment_dev_permissions.json)
  deployment_dev_networking_permissions_json_length      = length(data.aws_iam_policy_document.deployment_dev_networking_permissions.json)
  deployment_dev_workstation_iam_permissions_json_length = length(data.aws_iam_policy_document.deployment_dev_workstation_iam_permissions.json)

  # Added for the Phase 0 IAM Foundation permission-boundary task
  # (2026-08-04) -- same real, Terraform-computed length check, used by the
  # two new policies' own lifecycle.precondition blocks below.
  runtime_role_permission_boundary_json_length       = length(data.aws_iam_policy_document.runtime_role_permission_boundary.json)
  deployment_dev_runtime_iam_permissions_json_length = length(data.aws_iam_policy_document.deployment_dev_runtime_iam_permissions.json)

  # Added for the Phase 0 Networking Hardening remaining-resource
  # authorization gap task (2026-08-07) -- same real, Terraform-computed
  # length check, used by the new policy's own lifecycle.precondition below.
  deployment_dev_networking_observability_permissions_json_length = length(data.aws_iam_policy_document.deployment_dev_networking_observability_permissions.json)

  # Added for the Phase 0 KMS and Secrets Foundation task (2026-08-07) --
  # same real, Terraform-computed length check, used by the new policy's
  # own lifecycle.precondition below.
  deployment_shared_kms_secrets_permissions_json_length = length(data.aws_iam_policy_document.deployment_shared_kms_secrets_permissions.json)

  # Added for the Phase 0 Cost Controls task (2026-08-07) -- same real,
  # Terraform-computed length check, used by the new policy's own
  # lifecycle.precondition below.
  deployment_shared_cost_controls_permissions_json_length = length(data.aws_iam_policy_document.deployment_shared_cost_controls_permissions.json)

  # Added 2026-08-07, in direct response to the real deployment_dev_permissions
  # size-quota failure (6715 > 6144) caused by the cost-controls state-access
  # statements -- same real, Terraform-computed length check, used by the
  # new dedicated state-access policy's own lifecycle.precondition below.
  deployment_shared_cost_controls_state_permissions_json_length = length(data.aws_iam_policy_document.deployment_shared_cost_controls_state_permissions.json)

  # Added for the Phase 0 CI/CD Foundation implementation slice 1 task
  # (2026-08-07) -- same real, Terraform-computed length check, used by
  # aws_iam_policy.github_actions_permissions's own lifecycle.precondition
  # below. Expected to be far under the 6144 quota (this policy holds
  # exactly one statement, one action, one resource) -- the precondition is
  # added anyway, matching every other managed policy in this file, rather
  # than assumed safe by inspection.
  github_actions_permissions_json_length = length(data.aws_iam_policy_document.github_actions_permissions.json)

  # Added 2026-08-07, in direct response to the real
  # deployment_dev_networking_permissions size-quota failure (6282 > 6144)
  # caused by the CKV2_AWS_12 default-security-group adoption statement --
  # same real, Terraform-computed length check, used by the new dedicated
  # policy's own lifecycle.precondition below.
  deployment_dev_default_sg_adoption_permissions_json_length = length(data.aws_iam_policy_document.deployment_dev_default_sg_adoption_permissions.json)
}

resource "aws_iam_policy" "deployment_dev_permissions" {
  # ---------------------------------------------------------------------------
  # CORRECTED A SIXTH TIME 2026-07-26 (real terraform plan review, pre-apply --
  # NOT an AWS error, NOT a precondition failure, a manual review finding
  # before any apply was attempted): the reviewed `terraform plan` for the
  # THIRD-policy split above showed `6 to add, 1 to change, 2 to destroy`,
  # with the two unexpected destroys being THIS resource (replaced, not
  # changed in place) and its attachment (replaced as a consequence, since
  # the policy's ARN changes on replacement). Root cause: `description` is a
  # `Forces new resource` argument on `aws_iam_policy` -- AWS's IAM API has
  # no operation to update a customer-managed policy's description after
  # creation (only its policy DOCUMENT can be updated, via
  # CreatePolicyVersion), so Terraform can only apply a description change
  # by destroying and recreating the policy. Every prior correction to this
  # resource (the first two-policy split, then the workstation-IAM split)
  # rewrote this argument's text to narrate what had just changed --
  # harmless as long as the resource had never been applied for real, but
  # this resource WAS applied for real (Bootstrap Update 1's original real
  # apply, before any of the size-quota corrections existed in source), so
  # every one of those rewrites was silently queuing up a forced replacement
  # of an already-live, real, in-use customer-managed policy the very next
  # time anyone ran `plan`/`apply` -- exactly what this review caught before
  # `apply` ran. **Fixed two ways, together:** (1) this argument is reset to
  # a short, stable, split-narrative-free description that will not need
  # further editing merely because a future statement gets moved to another
  # policy; (2) `lifecycle.ignore_changes = ["description"]` added below, so
  # Terraform stops comparing this argument to configuration at all and
  # simply keeps whatever description is already live in AWS, regardless of
  # what this file says -- a deliberate, permanent guard against this exact
  # mistake recurring, chosen specifically because this project cannot
  # independently confirm the exact literal string already deployed in real
  # AWS (no AWS CLI access from this sandbox), so relying on getting a
  # byte-perfect match in `description` itself would be fragile; ignoring
  # the field entirely is not. Do NOT remove `ignore_changes` from this
  # resource, and do NOT edit `description` expecting it to take effect --
  # if this policy's description genuinely needs to change, that requires a
  # separate, deliberately reviewed decision (removing the ignore_changes
  # entry, accepting the resulting forced replacement, and planning around
  # it explicitly), not a byproduct of an unrelated statement-content edit.
  # `name` and `path` were NOT touched by any correction and remain exactly
  # as originally applied (`path` was never set, so it remains the "/"
  # default both before and after every correction).
  # ---------------------------------------------------------------------------
  name        = "${var.project_name}-dev-deployment-scope-policy"
  description = "Core deployment permissions for the Enterprise Data Platform."
  policy      = data.aws_iam_policy_document.deployment_dev_permissions.json

  lifecycle {
    # Added 2026-07-26 (sixth correction) -- description is immutable
    # (Forces new resource) in the AWS provider because AWS IAM has no API
    # to update a customer-managed policy's description after creation.
    # This resource was already applied for real before any of the
    # size-quota corrections existed in source, so any further edit to
    # `description` above would force a real, already-deployed,
    # already-in-use policy to be destroyed and recreated (and its
    # attachment along with it, since the ARN changes) -- ignoring this
    # field is the deliberate fix; see the comment block above this
    # resource for the full incident.
    ignore_changes = [description]

    # Added 2026-07-26, in direct response to the real CreatePolicyVersion
    # size-quota failure this split corrects -- fail the plan/apply loudly,
    # with a clear message, if this policy's own real, Terraform-computed
    # JSON length is not comfortably under AWS's quota, rather than
    # discovering it again only via a raw AWS API error during apply. This
    # exact precondition is what caught the SECOND size-quota failure
    # (6212 > 6144) that led to the workstation-IAM policy split below.
    precondition {
      condition     = local.deployment_dev_permissions_json_length <= local.iam_managed_policy_size_quota
      error_message = "aws_iam_policy.deployment_dev_permissions's rendered JSON (${local.deployment_dev_permissions_json_length} characters) exceeds AWS's managed-policy size quota (${local.iam_managed_policy_size_quota} characters). Do not respond by merging statements or dropping tag/condition enforcement to save space -- split further into an additional managed policy, reviewed separately, the same way this policy itself was split out of the original combined deployment_dev_permissions document on 2026-07-26, and the way the workstation-IAM statements were split out of it a second time the same day."
    }
  }

  tags = local.common_tags
}

resource "aws_iam_policy" "deployment_dev_workstation_iam_permissions" {
  name        = "${var.project_name}-dev-workstation-iam-scope-policy"
  description = "Workstation IAM permissions for the Enterprise Data Platform."
  policy      = data.aws_iam_policy_document.deployment_dev_workstation_iam_permissions.json

  lifecycle {
    # Same rationale as aws_iam_policy.deployment_dev_permissions's identical
    # ignore_changes entry: description is immutable (Forces new resource)
    # in the AWS provider, since AWS IAM has no API to update a
    # customer-managed policy's description after creation. Ignoring it here
    # too, so any future edit to this argument can never force a real
    # destroy+recreate of this policy (and its attachment) the way it did
    # for deployment_dev_permissions.
    ignore_changes = [description]

    # See aws_iam_policy.deployment_dev_permissions's identical precondition
    # above for the full rationale.
    precondition {
      condition     = local.deployment_dev_workstation_iam_permissions_json_length <= local.iam_managed_policy_size_quota
      error_message = "aws_iam_policy.deployment_dev_workstation_iam_permissions's rendered JSON (${local.deployment_dev_workstation_iam_permissions_json_length} characters) exceeds AWS's managed-policy size quota (${local.iam_managed_policy_size_quota} characters). Do not respond by merging statements or dropping tag/condition enforcement to save space -- split further into an additional managed policy, reviewed separately."
    }
  }

  tags = local.common_tags
}

resource "aws_iam_policy" "deployment_dev_networking_permissions" {
  name        = "${var.project_name}-dev-networking-scope-policy"
  description = "Networking permissions for the Enterprise Data Platform."
  policy      = data.aws_iam_policy_document.deployment_dev_networking_permissions.json

  lifecycle {
    # Same rationale as aws_iam_policy.deployment_dev_permissions's identical
    # ignore_changes entry: description is immutable (Forces new resource)
    # in the AWS provider, since AWS IAM has no API to update a
    # customer-managed policy's description after creation. Ignoring it here
    # too, so any future edit to this argument can never force a real
    # destroy+recreate of this policy (and its attachment) the way it did
    # for deployment_dev_permissions.
    ignore_changes = [description]

    # See aws_iam_policy.deployment_dev_permissions's identical precondition
    # above for the full rationale.
    precondition {
      condition     = local.deployment_dev_networking_permissions_json_length <= local.iam_managed_policy_size_quota
      error_message = "aws_iam_policy.deployment_dev_networking_permissions's rendered JSON (${local.deployment_dev_networking_permissions_json_length} characters) exceeds AWS's managed-policy size quota (${local.iam_managed_policy_size_quota} characters). Do not respond by merging statements or dropping tag/condition enforcement to save space -- split further into an additional managed policy, reviewed separately."
    }
  }

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "deployment_dev_permissions" {
  role       = aws_iam_role.deployment.name
  policy_arn = aws_iam_policy.deployment_dev_permissions.arn
}

resource "aws_iam_role_policy_attachment" "deployment_dev_networking_permissions" {
  role       = aws_iam_role.deployment.name
  policy_arn = aws_iam_policy.deployment_dev_networking_permissions.arn
}

resource "aws_iam_role_policy_attachment" "deployment_dev_workstation_iam_permissions" {
  role       = aws_iam_role.deployment.name
  policy_arn = aws_iam_policy.deployment_dev_workstation_iam_permissions.arn
}

# ---------------------------------------------------------------------------
# Default security group adoption (CKV2_AWS_12 remediation) -- SPLIT OUT
# 2026-08-07 into this fourth, separate, dedicated managed policy, purely to
# stay under AWS's per-policy size quota. A real bootstrap terraform plan
# reported deployment_dev_networking_permissions's own rendered JSON at 6282
# characters against the 6144-character quota, 138 characters over -- caught
# entirely by that policy's own lifecycle.precondition at plan time, NOT by
# a real iam:CreatePolicyVersion AWS API call; no AWS command was run and no
# AWS change occurred. The single statement below is moved here UNCHANGED
# (same Sid, actions, resource, condition) from where it previously lived
# inside deployment_dev_networking_permissions -- nothing was merged,
# combined, dropped, or weakened to save space, and no aws:ResourceTag
# condition was added (see the statement's own comment for why one is
# deliberately absent). Scoped ONLY to the one, real, already-existing
# default security group for the dev VPC (vpc-0b9e094c41712d68a) -- not
# security-group/*, not Resource = "*", and not an ec2:Vpc condition.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "deployment_dev_default_sg_adoption_permissions" {
  statement {
    sid    = "DevDefaultSecurityGroupAdoptionOnly"
    effect = "Allow"
    actions = [
      "ec2:RevokeSecurityGroupIngress",
      "ec2:RevokeSecurityGroupEgress",
      "ec2:CreateTags",
      "ec2:DeleteTags",
    ]

    # The one, real, already-existing default security group for the dev
    # VPC (vpc-0b9e094c41712d68a) -- not a wildcard, not a pattern, the
    # exact resource ARN and nothing else.
    resources = ["arn:aws:ec2:ap-south-1:732264765658:security-group/sg-043396862de555680"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.aws_region]
    }

    # Deliberately NO aws:ResourceTag/Project or aws:ResourceTag/Environment
    # condition here: the default security group carries NO tags at all
    # before this first adoption, so a tag-conditioned statement could never
    # authorize the very apply that is supposed to be the one setting those
    # tags. The exact-resource-ARN scoping above is this statement's only
    # narrowing mechanism, not a tag condition. Every other security-group
    # statement in deployment_dev_networking_permissions keeps its own
    # tag-conditioned or create-time-tagged protection exactly as before --
    # this statement adds no reach into any other security group, default
    # or otherwise, anywhere in this account.
  }
}

resource "aws_iam_policy" "deployment_dev_default_sg_adoption_permissions" {
  name        = "${var.project_name}-dev-default-sg-adoption-policy"
  description = "Default security group adoption (CKV2_AWS_12) for the Enterprise Data Platform dev VPC."
  policy      = data.aws_iam_policy_document.deployment_dev_default_sg_adoption_permissions.json

  lifecycle {
    # Same rationale as every other managed policy in this file: description
    # is immutable (Forces new resource) in the AWS provider. Ignored
    # pre-emptively here, as a new resource.
    ignore_changes = [description]

    precondition {
      condition     = local.deployment_dev_default_sg_adoption_permissions_json_length <= local.iam_managed_policy_size_quota
      error_message = "aws_iam_policy.deployment_dev_default_sg_adoption_permissions's rendered JSON (${local.deployment_dev_default_sg_adoption_permissions_json_length} characters) exceeds AWS's managed-policy size quota (${local.iam_managed_policy_size_quota} characters). Do not respond by merging statements or dropping tag/condition enforcement to save space -- split further into an additional managed policy, reviewed separately."
    }
  }

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "deployment_dev_default_sg_adoption_permissions" {
  role       = aws_iam_role.deployment.name
  policy_arn = aws_iam_policy.deployment_dev_default_sg_adoption_permissions.arn
}

# ---------------------------------------------------------------------------
# Phase 0 IAM Foundation -- Permission Boundary + Runtime-Role Lifecycle
# (2026-08-04). First approved Terraform implementation task from
# 02_Infrastructure/IAM_and_Access.md ("Permission Boundary -- Version 1
# Specification" and "Runtime-Role Lifecycle -- Version 1") and
# 01_Architecture/ADRs/ADR-0001-iam-foundation-permission-boundaries-and-
# runtime-role-pattern.md. Design only prior to this task -- nothing below
# implements Lambda, Step Functions, SQS, EventBridge, S3 zones, DynamoDB
# tables, Glue, ECS, KMS, Secrets Manager, modules/iam-runtime-role, or any
# runtime/read-only/OIDC role. This adds exactly two new managed policies
# (the boundary itself, and the deployment role's narrowly scoped ability to
# create/manage boundary-protected runtime roles) plus one new attachment --
# nothing else. No existing resource, policy document, or attachment above
# this block is modified.
#
# Runtime-role name/ARN pattern (approved, IAM_and_Access.md "4. Approved
# runtime-role ARN and name pattern"): a required "runtime-" segment,
# structurally distinct from the workstation role's own name
# (var.dev_workstation_role_name, "...-workstation-role") and the deployment
# role's own name (var.deployment_role_name, "...-shared-deployment-role"),
# so no wildcard below can ever match either protected role.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "runtime_role_permission_boundary" {
  # --- Baseline platform permissions (the ceiling; each runtime role's own
  #     identity policy still narrows this further to only what it uses).
  #     Scope: Lambda, Step Functions, SQS, EventBridge, the three standard
  #     S3 ingestion zones, and DynamoDB pipeline metadata only -- the exact
  #     v1 runtime scope approved in IAM_and_Access.md "2. Initial runtime
  #     scope", derived from PROJECT_BLUEPRINT.md's Phase 1 Source 1/2
  #     patterns and shared build steps. Glue, ECS/Fargate, Kinesis, and DMS
  #     are deliberately NOT included -- a later, separate boundary revision
  #     when each is actually adopted, not now. ---

  statement {
    sid    = "AllowBaselineCloudWatchLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["arn:aws:logs:${var.aws_region}:${var.aws_account_id}:log-group:/${var.project_name}/dev/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.aws_region]
    }
  }

  statement {
    sid    = "AllowBaselineSqsDlqAccess"
    effect = "Allow"
    actions = [
      "sqs:SendMessage",
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
    ]
    resources = ["arn:aws:sqs:${var.aws_region}:${var.aws_account_id}:${var.project_name}-dev-*"]
  }

  statement {
    sid       = "AllowBaselineEventBridgePutEvents"
    effect    = "Allow"
    actions   = ["events:PutEvents"]
    resources = ["arn:aws:events:${var.aws_region}:${var.aws_account_id}:event-bus/${var.project_name}-dev-*"]
  }

  statement {
    sid    = "AllowBaselineStepFunctionsExecution"
    effect = "Allow"
    actions = [
      "states:StartExecution",
      "states:DescribeExecution",
    ]
    resources = [
      "arn:aws:states:${var.aws_region}:${var.aws_account_id}:stateMachine:${var.project_name}-dev-*",
      "arn:aws:states:${var.aws_region}:${var.aws_account_id}:execution:${var.project_name}-dev-*:*",
    ]
  }

  statement {
    sid    = "AllowBaselineS3IngestionZones"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
    ]
    resources = [
      "arn:aws:s3:::${var.project_name}-dev-landing/*",
      "arn:aws:s3:::${var.project_name}-dev-quarantine/*",
      "arn:aws:s3:::${var.project_name}-dev-audit/*",
    ]
  }

  statement {
    sid     = "AllowBaselineS3IngestionZonesListBucket"
    effect  = "Allow"
    actions = ["s3:ListBucket"]
    resources = [
      "arn:aws:s3:::${var.project_name}-dev-landing",
      "arn:aws:s3:::${var.project_name}-dev-quarantine",
      "arn:aws:s3:::${var.project_name}-dev-audit",
    ]
  }

  statement {
    sid    = "AllowBaselineDynamoDbPipelineMetadata"
    effect = "Allow"
    actions = [
      "dynamodb:PutItem",
      "dynamodb:GetItem",
      "dynamodb:UpdateItem",
      "dynamodb:Query",
    ]
    resources = ["arn:aws:dynamodb:${var.aws_region}:${var.aws_account_id}:table/${var.project_name}-dev-pipeline-*"]
  }

  # --- Always-prohibited actions (explicit Deny, defense-in-depth against a
  #     future mistake in the allow-list above -- IAM_and_Access.md "1.
  #     Boundary model"). Resource = "*" throughout: these must never be
  #     reachable regardless of resource. ---

  statement {
    sid    = "DenyIamMutatingActions"
    effect = "Deny"
    actions = [
      "iam:CreateUser",
      "iam:CreateGroup",
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:CreatePolicy",
      "iam:DeletePolicy",
      "iam:CreatePolicyVersion",
      "iam:SetDefaultPolicyVersion",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:AttachUserPolicy",
      "iam:PutUserPolicy",
      "iam:UpdateAssumeRolePolicy",
      "iam:PutRolePermissionsBoundary",
      "iam:DeleteRolePermissionsBoundary",
      "iam:CreateAccessKey",
      "iam:UpdateAccessKey",
      "iam:CreateLoginProfile",
      "iam:UpdateLoginProfile",
      "iam:CreateServiceSpecificCredential",
      "iam:UploadSSHPublicKey",
      "iam:CreateVirtualMFADevice",
      "iam:DeactivateMFADevice",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "DenyPassRoleByDefault"
    effect    = "Deny"
    actions   = ["iam:PassRole"]
    resources = ["*"]
  }

  statement {
    sid    = "DenyAuditLoggingTampering"
    effect = "Deny"
    actions = [
      "cloudtrail:StopLogging",
      "cloudtrail:DeleteTrail",
      "cloudtrail:UpdateTrail",
      "cloudtrail:PutEventSelectors",
      "cloudtrail:PutInsightSelectors",
      "logs:DeleteLogGroup",
      "logs:DeleteLogStream",
      "logs:PutRetentionPolicy",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "DenySecurityControlTampering"
    effect = "Deny"
    actions = [
      "guardduty:DeleteDetector",
      "guardduty:UpdateDetector",
      "guardduty:DisassociateFromMasterAccount",
      "securityhub:DisableSecurityHub",
      "securityhub:UpdateStandardsControl",
      "config:DeleteConfigRule",
      "config:StopConfigurationRecorder",
      "config:DeleteConfigurationRecorder",
      "config:DeleteDeliveryChannel",
      "access-analyzer:DeleteAnalyzer",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "DenyKmsAdministration"
    effect = "Deny"
    actions = [
      "kms:CreateKey",
      "kms:ScheduleKeyDeletion",
      "kms:DisableKey",
      "kms:EnableKey",
      "kms:PutKeyPolicy",
      "kms:CreateGrant",
      "kms:RevokeGrant",
      "kms:CreateAlias",
      "kms:DeleteAlias",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "DenyOrganizationsAndAccountSettings"
    effect = "Deny"
    actions = [
      "organizations:*",
      "account:*",
      "aws-portal:*",
      "iam:UpdateAccountPasswordPolicy",
      "iam:CreateAccountAlias",
      "iam:DeleteAccountAlias",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "DenyKnownEscalationVectors"
    effect = "Deny"
    actions = [
      "glue:CreateDevEndpoint",
      "glue:UpdateDevEndpoint",
      "cloudformation:CreateStack",
      "cloudformation:UpdateStack",
      "ec2:RunInstances",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "runtime_role_permission_boundary" {
  name        = "${var.project_name}-shared-runtime-role-boundary-policy"
  description = "Permission boundary for Enterprise Data Platform runtime roles."
  policy      = data.aws_iam_policy_document.runtime_role_permission_boundary.json

  lifecycle {
    # Same rationale as every other managed policy in this file:
    # description is immutable (Forces new resource) in the AWS provider.
    # Ignored pre-emptively here even though this is a new resource, so a
    # future narrative edit to this field can never force an unplanned
    # replacement once this policy is live and attached to real roles.
    ignore_changes = [description]

    precondition {
      condition     = local.runtime_role_permission_boundary_json_length <= local.iam_managed_policy_size_quota
      error_message = "aws_iam_policy.runtime_role_permission_boundary's rendered JSON (${local.runtime_role_permission_boundary_json_length} characters) exceeds AWS's managed-policy size quota (${local.iam_managed_policy_size_quota} characters). Do not respond by merging statements or dropping a Deny category to save space -- split into an additional boundary-adjacent policy, reviewed separately."
    }
  }

  tags = local.common_tags
}

# ---------------------------------------------------------------------------
# Deployment role's new, narrowly scoped runtime-role lifecycle permissions.
# IAM_and_Access.md "5-6. Lifecycle actions, conditions, and the Version 1
# statement set" -- five statements, each mapped to exactly one lifecycle
# operation (create, read/manage/delete, policy attachment, PassRole, and an
# explicit guardrail deny). iam:PutRolePolicy/DeleteRolePolicy (inline
# policies) and iam:UpdateAssumeRolePolicy (trust-policy mutation) are
# DELIBERATELY never granted here -- IAM has no condition key capable of
# inspecting either an inline policy's content or a new trust document's
# content, so neither can be safely constrained; a genuine need for either
# means deleting and recreating the runtime role through the boundary-
# enforced CreateRole statement below, not an in-place mutation.
# iam:PutRolePermissionsBoundary/DeleteRolePermissionsBoundary and
# iam:CreatePolicy/CreatePolicyVersion/SetDefaultPolicyVersion (against the
# boundary policy's own ARN or any other) are also never granted -- boundary
# upgrades are a new default version of the SAME policy ARN, applied only by
# the human bootstrap principal through this file's own reviewed workflow,
# never a deployment-role-initiated action.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "deployment_dev_runtime_iam_permissions" {
  statement {
    sid       = "DevRuntimeRoleCreateTaggedWithBoundary"
    effect    = "Allow"
    actions   = ["iam:CreateRole"]
    resources = ["arn:aws:iam::${var.aws_account_id}:role/${var.project_name}-dev-runtime-*"]

    condition {
      test     = "StringEquals"
      variable = "iam:PermissionsBoundary"
      values   = [aws_iam_policy.runtime_role_permission_boundary.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Project"
      values   = [var.project_name]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Environment"
      values   = ["dev"]
    }
  }

  statement {
    sid    = "DevRuntimeRoleReadManageTaggedOnly"
    effect = "Allow"
    actions = [
      "iam:GetRole",
      "iam:DeleteRole",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies",
    ]
    resources = ["arn:aws:iam::${var.aws_account_id}:role/${var.project_name}-dev-runtime-*"]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Project"
      values   = [var.project_name]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Environment"
      values   = ["dev"]
    }
  }

  statement {
    sid    = "DevRuntimeRolePolicyAttachApprovedOnly"
    effect = "Allow"
    actions = [
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
    ]
    resources = ["arn:aws:iam::${var.aws_account_id}:role/${var.project_name}-dev-runtime-*"]

    condition {
      test     = "StringLike"
      variable = "iam:PolicyARN"
      values   = ["arn:aws:iam::${var.aws_account_id}:policy/${var.project_name}-*"]
    }
  }

  statement {
    sid       = "DevPassRuntimeRoleToApprovedServicesOnly"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = ["arn:aws:iam::${var.aws_account_id}:role/${var.project_name}-dev-runtime-*"]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values = [
        "lambda.amazonaws.com",
        "states.amazonaws.com",
      ]
    }
  }

  # Explicit Deny, defense-in-depth: even if the "-dev-runtime-*" resource
  # pattern above were ever mistakenly widened in a future edit, this
  # statement independently guarantees none of these actions can ever
  # target the deployment role or the workstation role -- an IAM Deny
  # always wins regardless of what any Allow statement (existing or
  # future) grants. Named by exact ARN, not by pattern.
  #
  # CORRECTED 2026-08-04 (real regression found via a real environments/dev
  # `terraform plan`): this statement originally also denied iam:GetRole,
  # iam:ListRolePolicies, and iam:ListAttachedRolePolicies -- copied
  # wholesale from DevRuntimeRoleReadManageTaggedOnly's action list above
  # without distinguishing read-only discovery actions from actions that
  # actually carry mutation/escalation risk. Because a Deny always wins
  # across every policy attached to the deployment role, this silently
  # overrode DevWorkstationRoleManage's legitimate iam:GetRole/
  # iam:ListRolePolicies/iam:ListAttachedRolePolicies grant on the
  # workstation role (deployment_dev_workstation_iam_permissions, above),
  # breaking ordinary Terraform state refresh with a real
  # "explicit deny in enterprise-data-platform-dev-runtime-iam-scope-policy"
  # error on iam:GetRole. Fixed by removing exactly those three read-only
  # actions -- none of them can create, delete, modify a trust policy,
  # put/delete an inline policy, attach/detach a managed policy, tag/untag,
  # change a permissions boundary, or pass the role anywhere. Every action
  # capable of mutation or escalation remains denied below, unchanged.
  statement {
    sid    = "DevRuntimeIamGuardrailDenyProtectedRoles"
    effect = "Deny"
    actions = [
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:UpdateAssumeRolePolicy",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:PassRole",
      "iam:PutRolePermissionsBoundary",
      "iam:DeleteRolePermissionsBoundary",
    ]
    # CORRECTED 2026-08-07 (real terraform plan review, dependency-
    # propagation fix -- 02_Infrastructure/CI_CD.md, ADR-0006-cicd-
    # foundation.md; this policy's own statement content and protected-role
    # set are UNCHANGED, still exactly the deployment role and the dev
    # workstation role, nothing added or removed): local.deployment_role_arn
    # replaces the resource reference aws_iam_role.deployment.arn --
    # byte-identical value, but the resource reference had made this
    # entirely unrelated, pre-existing policy report an artificial
    # known-after-apply diff once aws_iam_role.deployment itself gained a
    # new dependency (the GitHub Actions role trust statement above). See
    # locals.tf's comment above deployment_role_arn for the full root-cause
    # record.
    resources = [
      local.deployment_role_arn,
      local.dev_workstation_role_arn,
    ]
  }
}

resource "aws_iam_policy" "deployment_dev_runtime_iam_permissions" {
  name        = "${var.project_name}-dev-runtime-iam-scope-policy"
  description = "Runtime-role lifecycle permissions for the Enterprise Data Platform."
  policy      = data.aws_iam_policy_document.deployment_dev_runtime_iam_permissions.json

  lifecycle {
    # Same rationale as every other managed policy in this file: description
    # is immutable (Forces new resource) in the AWS provider. Ignored
    # pre-emptively here, as a new resource, for the same reason as the
    # boundary policy above.
    ignore_changes = [description]

    precondition {
      condition     = local.deployment_dev_runtime_iam_permissions_json_length <= local.iam_managed_policy_size_quota
      error_message = "aws_iam_policy.deployment_dev_runtime_iam_permissions's rendered JSON (${local.deployment_dev_runtime_iam_permissions_json_length} characters) exceeds AWS's managed-policy size quota (${local.iam_managed_policy_size_quota} characters). Do not respond by merging statements or dropping tag/condition/guardrail enforcement to save space -- split further into an additional managed policy, reviewed separately."
    }
  }

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "deployment_dev_runtime_iam_permissions" {
  role       = aws_iam_role.deployment.name
  policy_arn = aws_iam_policy.deployment_dev_runtime_iam_permissions.arn
}

# ---------------------------------------------------------------------------
# Phase 0 Networking Hardening -- Remaining Resource Authorization Gap
# (2026-08-07). A real networking apply landed 12 of the original 17 planned
# resources; the remaining 5 --
# module.vpc.aws_vpc_endpoint.s3[0], module.vpc.aws_cloudwatch_log_group.
# vpc_flow_logs[0], module.vpc.aws_iam_role.vpc_flow_logs[0],
# module.vpc.aws_iam_role_policy.vpc_flow_logs[0], and
# module.vpc.aws_flow_log.this[0] -- failed with confirmed AccessDenied on
# ec2:CreateVpcEndpoint, logs:CreateLogGroup, and iam:CreateRole. This adds
# exactly one new, narrowly scoped managed policy covering the S3 Gateway
# VPC endpoint, VPC Flow Logs, the Flow Logs CloudWatch Logs log group, and
# the Flow Logs delivery IAM role, plus the two small amendments above
# (DevReadOnlyDescribe, DevTaggingOnApprovedCreateActions) for the three new
# Describe* actions and two new tag-on-create actions. No existing statement
# is removed, weakened, or merged. No networking Terraform (modules/vpc,
# environments/dev) is touched by this change; no AWS resource is created or
# modified.
#
# Design choice: a FOURTH policy, not a further split of the three existing
# ones -- this is a genuinely new permission domain (a new IAM role's own
# lifecycle, a new CloudWatch Logs log group, VPC-endpoint/Flow-Log
# lifecycle actions), not an extension of any existing domain, and keeping
# it separate avoids risking a further size-quota failure on any of the
# three already-live, already-applied policies (see the "CORRECTED A
# [FOURTH/FIFTH/SIXTH] TIME" comment blocks above for how costly that
# failure mode has been in this project's real history).
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "deployment_dev_networking_observability_permissions" {
  # --- S3 Gateway VPC Endpoint (Networking.md Section 4) -------------------
  # ec2:CreateVpcEndpoint is a multi-resource-type action -- the AWS EC2
  # Service Authorization Reference lists "vpc-endpoint" (the new resource),
  # "vpc" (the parent it's created in), and "route-table" (each route table
  # supplied via route_table_ids) as resource types it authorizes against in
  # the same call -- the same multi-resource pattern already established and
  # confirmed for CreateSubnet/CreateRouteTable/CreateSecurityGroup above.
  # Split the same way: new-resource (aws:RequestTag) plus one
  # existing-parent (aws:ResourceTag) statement per additional resource type
  # touched.
  statement {
    sid       = "DevCreateVpcEndpointNewResourceTaggedOnly"
    effect    = "Allow"
    actions   = ["ec2:CreateVpcEndpoint"]
    resources = ["arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:vpc-endpoint/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.aws_region]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Project"
      values   = [var.project_name]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Environment"
      values   = ["dev"]
    }
  }

  statement {
    sid       = "DevCreateVpcEndpointExistingVpcTaggedOnly"
    effect    = "Allow"
    actions   = ["ec2:CreateVpcEndpoint"]
    resources = ["arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:vpc/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.aws_region]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Project"
      values   = [var.project_name]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Environment"
      values   = ["dev"]
    }
  }

  statement {
    sid       = "DevCreateVpcEndpointExistingRouteTableTaggedOnly"
    effect    = "Allow"
    actions   = ["ec2:CreateVpcEndpoint"]
    resources = ["arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:route-table/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.aws_region]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Project"
      values   = [var.project_name]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Environment"
      values   = ["dev"]
    }
  }

  statement {
    sid    = "DevVpcEndpointManageDeleteTaggedOnly"
    effect = "Allow"
    actions = [
      "ec2:ModifyVpcEndpoint",
      "ec2:DeleteVpcEndpoints",
    ]
    resources = ["arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:vpc-endpoint/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.aws_region]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Project"
      values   = [var.project_name]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Environment"
      values   = ["dev"]
    }
  }

  # --- VPC Flow Logs (Networking.md Section 5) ------------------------------
  # ec2:CreateFlowLogs's own resource type, per the AWS EC2 Service
  # Authorization Reference, is "vpc-flow-log" -- CONFIRMED 2026-08-07 to
  # also require authorization against the EXISTING SOURCE VPC it monitors,
  # the same multi-resource pattern already established for CreateSubnet/
  # CreateRouteTable/CreateSecurityGroup/CreateVpcEndpoint above. This
  # supersedes the pattern-inferred, not-yet-confirmed note previously here:
  # a real, final Networking Hardening apply denied ec2:CreateFlowLogs with
  # AccessDenied evaluated specifically against
  # arn:aws:ec2:ap-south-1:732264765658:vpc/vpc-0b9e094c41712d68a -- the
  # deployment role had an Allow for the new vpc-flow-log resource (below)
  # but none for the existing parent VPC side of the same call. Fixed the
  # same way every other multi-resource create action in this policy was
  # fixed: an additional existing-parent-VPC statement, immediately below,
  # conditioned on aws:ResourceTag (the VPC already carries this project's
  # tags, having been created via DevCreateVpcTaggedOnly), not a literal VPC
  # ID -- this bootstrap root module has no Terraform-known reference to
  # environments/dev's real VPC (separate state, separate root module), and
  # tag-based scoping is this policy's own established design for every
  # other existing-parent-VPC statement (DevCreateSubnetExistingVpcTaggedOnly,
  # DevCreateRouteTableExistingVpcTaggedOnly,
  # DevCreateSecurityGroupExistingVpcTaggedOnly,
  # DevCreateVpcEndpointExistingVpcTaggedOnly) -- kept consistent here rather
  # than introducing a one-off literal-ARN exception.
  statement {
    sid       = "DevCreateFlowLogsTaggedOnly"
    effect    = "Allow"
    actions   = ["ec2:CreateFlowLogs"]
    resources = ["arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:vpc-flow-log/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.aws_region]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Project"
      values   = [var.project_name]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Environment"
      values   = ["dev"]
    }
  }

  # The PARENT VPC side of CreateFlowLogs's authorization -- see the comment
  # block above DevCreateFlowLogsTaggedOnly for the real AccessDenied this
  # fixes. Only ec2:CreateFlowLogs is granted here -- no other Flow Logs or
  # VPC action -- and only against a VPC already carrying this project's
  # Project/Environment tags (aws:ResourceTag), never any VPC unconditionally.
  statement {
    sid       = "DevCreateFlowLogsExistingVpcTaggedOnly"
    effect    = "Allow"
    actions   = ["ec2:CreateFlowLogs"]
    resources = ["arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:vpc/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.aws_region]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Project"
      values   = [var.project_name]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Environment"
      values   = ["dev"]
    }
  }

  statement {
    sid       = "DevDeleteFlowLogsTaggedOnly"
    effect    = "Allow"
    actions   = ["ec2:DeleteFlowLogs"]
    resources = ["arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:vpc-flow-log/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.aws_region]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Project"
      values   = [var.project_name]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Environment"
      values   = ["dev"]
    }
  }

  # --- Flow Logs CloudWatch Logs log group (Logging_and_Audit.md Section 6;
  #     Networking.md Section 5) -- scoped to the exact log group this
  #     module creates, /enterprise-data-platform/dev/vpc-flow-logs, not a
  #     wildcard prefix. logs:DescribeLogGroups is deliberately NOT included
  #     here -- like EC2's Describe* actions, it does not support
  #     resource-level restriction in AWS IAM, and is granted (Resource
  #     "*") alongside the other unconditional Describe actions in
  #     DevReadOnlyDescribe (deployment_dev_permissions) instead, per the
  #     amendment above.
  statement {
    sid    = "DevVpcFlowLogsLogGroupManage"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:PutRetentionPolicy",
      "logs:DeleteLogGroup",
    ]
    resources = ["arn:aws:logs:${var.aws_region}:${var.aws_account_id}:log-group:/${var.project_name}/dev/vpc-flow-logs:*"]
  }

  # REVISED 2026-08-07, split out of DevVpcFlowLogsLogGroupManage above
  # (second real Networking Hardening apply, partial success -- refresh
  # failure). Root cause of the real logs:ListTagsForResource AccessDenied:
  # CreateLogGroup/PutRetentionPolicy/DeleteLogGroup use CloudWatch Logs'
  # own, log-group-specific API operations, whose IAM resource-type ARN
  # format (per AWS's "Actions, resources, and condition keys for Amazon
  # CloudWatch Logs" reference) genuinely includes a trailing ":*" --
  # DevVpcFlowLogsLogGroupManage's resource above is correct for those three
  # actions. TagResource, UntagResource, and ListTagsForResource are
  # different: they are CloudWatch Logs' generic, ARN-based resource-tagging
  # API (introduced after the older, log-group-specific
  # TagLogGroup/UntagLogGroup/ListTagsLogGroup actions), and the resourceArn
  # value AWS evaluates the IAM policy against for these three actions is
  # the BARE log group ARN, with NO trailing ":*" or log-stream suffix of
  # any kind -- unlike DescribeLogGroups's own "arn" attribute (which does
  # carry the trailing ":*") and unlike the other three actions above. The
  # prior single statement's resource ("...:vpc-flow-logs:*") is an IAM
  # resource pattern requiring a literal trailing colon before the wildcard
  # -- it does not match a real request-context resourceArn of
  # "...:vpc-flow-logs" (no trailing colon at all), producing a real,
  # confirmed AccessDenied on logs:ListTagsForResource even though the
  # action was already present in this policy's source and this policy was
  # confirmed attached to the deployment role. The action was never
  # "missing" from the attached policy -- its resource ARN shape was wrong
  # for these three specific actions. Fixed by moving TagResource/
  # UntagResource/ListTagsForResource into their own statement, scoped to
  # the bare log group ARN (no trailing ":*"). Not broadened to logs:*, and
  # CreateLogGroup/PutRetentionPolicy/DeleteLogGroup above are unchanged.
  statement {
    sid    = "DevVpcFlowLogsLogGroupTagging"
    effect = "Allow"
    actions = [
      "logs:TagResource",
      "logs:UntagResource",
      "logs:ListTagsForResource",
    ]
    resources = ["arn:aws:logs:${var.aws_region}:${var.aws_account_id}:log-group:/${var.project_name}/dev/vpc-flow-logs"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.aws_region]
    }
  }

  # --- Flow Logs delivery IAM role (Networking.md Section 5) --------------
  # Treated as a separately governed infrastructure service role -- NOT
  # folded into deployment_dev_runtime_iam_permissions (scoped to
  # "-dev-runtime-*" Lambda/Step Functions execution roles) or
  # deployment_dev_workstation_iam_permissions (scoped only to the
  # workstation role). Scoped to the SINGLE, EXACT role ARN this module
  # creates -- no wildcard, no pattern -- the tightest possible restriction,
  # matching DevWorkstationRoleManage's own precedent above. Exactly the 10
  # lifecycle actions approved, in the same shape as DevWorkstationRoleManage
  # (no iam:UpdateAssumeRolePolicy, iam:AttachRolePolicy/DetachRolePolicy,
  # or iam:PutRolePermissionsBoundary/DeleteRolePermissionsBoundary granted
  # -- this role's trust policy is fixed at creation, it uses only an inline
  # policy (aws_iam_role_policy, not a managed-policy attachment) per
  # modules/vpc/main.tf, and it carries no permission boundary).
  statement {
    sid    = "DevVpcFlowLogsRoleManage"
    effect = "Allow"
    actions = [
      "iam:CreateRole",
      "iam:GetRole",
      "iam:DeleteRole",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:PutRolePolicy",
      "iam:GetRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies",
    ]
    resources = ["arn:aws:iam::${var.aws_account_id}:role/${var.project_name}-dev-vpc-flow-logs-role"]
  }

  # iam:PassRole -- REQUIRED: aws_flow_log's iam_role_arn (the CloudWatch
  # Logs delivery role) is passed by the caller to the VPC Flow Logs service
  # as part of the same ec2:CreateFlowLogs call; AWS requires iam:PassRole
  # on that exact role ARN to do so. Restricted to iam:PassedToService =
  # "vpc-flow-logs.amazonaws.com" -- the exact principal already trusted by
  # this role's own trust policy (modules/vpc/main.tf,
  # data.aws_iam_policy_document.vpc_flow_logs_trust) -- so this role can
  # never be passed to Lambda, EC2, or any other service via this
  # statement. This statement does not touch or broaden the existing,
  # separate DevPassWorkstationRoleToEC2Only (ec2.amazonaws.com) or
  # DevPassRuntimeRoleToApprovedServicesOnly (lambda.amazonaws.com,
  # states.amazonaws.com) PassRole grants above.
  statement {
    sid       = "DevPassVpcFlowLogsRoleToFlowLogsServiceOnly"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = ["arn:aws:iam::${var.aws_account_id}:role/${var.project_name}-dev-vpc-flow-logs-role"]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["vpc-flow-logs.amazonaws.com"]
    }
  }
}

resource "aws_iam_policy" "deployment_dev_networking_observability_permissions" {
  name        = "${var.project_name}-dev-networking-observability-scope-policy"
  description = "VPC endpoint and Flow Logs observability permissions for the Enterprise Data Platform."
  policy      = data.aws_iam_policy_document.deployment_dev_networking_observability_permissions.json

  lifecycle {
    # Same rationale as every other managed policy in this file: description
    # is immutable (Forces new resource) in the AWS provider. Ignored
    # pre-emptively here, as a new resource, for the same reason as the
    # three original split policies and the runtime-role policies above.
    ignore_changes = [description]

    precondition {
      condition     = local.deployment_dev_networking_observability_permissions_json_length <= local.iam_managed_policy_size_quota
      error_message = "aws_iam_policy.deployment_dev_networking_observability_permissions's rendered JSON (${local.deployment_dev_networking_observability_permissions_json_length} characters) exceeds AWS's managed-policy size quota (${local.iam_managed_policy_size_quota} characters). Do not respond by merging statements or dropping tag/condition enforcement to save space -- split further into an additional managed policy, reviewed separately."
    }
  }

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "deployment_dev_networking_observability_permissions" {
  role       = aws_iam_role.deployment.name
  policy_arn = aws_iam_policy.deployment_dev_networking_observability_permissions.arn
}

# ---------------------------------------------------------------------------
# Phase 0 KMS and Secrets Foundation (2026-08-07). Implements the approved
# design (02_Infrastructure/KMS_and_Secrets.md; ADR-0004) -- new, narrowly
# scoped deployment-role permissions for the new infrastructure/terraform/
# kms-secrets/ stack (routed through the deployment role, unlike logging/'s
# human-direct pattern -- see kms-secrets/providers.tf for why). Covers
# three domains in ONE dedicated managed policy, kept together because each
# domain's action count is small and they are all part of the same single
# workstream/stack, unlike the earlier networking-vs-workstation-vs-runtime
# splits (which existed to solve real, separately-discovered size-quota
# failures, not as a default pattern to replicate here):
#
#   - KMS: key creation (tag-conditioned, Resource "*" -- the key does not
#     yet exist at authorization time, same category as ec2:CreateVpc
#     above), key administration (Resource "key/*", tag-conditioned -- KMS
#     supports this resource-type wildcard, tighter than EC2's bare "*"),
#     and alias lifecycle (exact, literal alias ARN, known in advance,
#     unlike the key's own ID). kms:CreateAlias/UpdateAlias are ALSO
#     granted on the key/* administration statement (in addition to the
#     alias statement) -- kms:CreateAlias/UpdateAlias are multi-resource
#     actions requiring authorization against BOTH the alias AND its
#     target key, the same multi-resource-type pattern this project
#     already discovered the hard way for ec2:CreateSubnet/
#     CreateRouteTable/CreateSecurityGroup/CreateVpcEndpoint/CreateFlowLogs
#     (bootstrap/main.tf's own "CORRECTED" comment history above) --
#     applied here PROACTIVELY based on that prior, repeated lesson, not
#     from a fresh, independently re-confirmed AWS KMS reference fetch in
#     this task (this sandbox's fetch tool returned the KMS Service
#     Authorization Reference page in a form too large/line-truncated to
#     reliably extract in this task, the same known limitation already
#     documented elsewhere in this project's history). kms:DeleteAlias is
#     granted only on the exact alias ARN (no key-side authorization
#     documented as required for deletion). NEVER granted:
#     kms:DisableKey, kms:EnableKey, kms:ScheduleKeyDeletion,
#     kms:CancelKeyDeletion, kms:DisableKeyRotation, or any kms:*
#     wildcard -- deliberately absent per KMS_and_Secrets.md Section 2/4;
#     these remain human/root-only, break-glass actions.
#   - Secrets Manager: metadata management only (create/describe/update/
#     delete/tag/untag) for the exact demonstration secret this stack
#     creates, scoped by its exact name plus Secrets Manager's own
#     documented ARN convention (a trailing "-*" wildcard for the random
#     6-character suffix AWS appends to every secret's real ARN -- the
#     name itself is deterministic, the full ARN is not). NEVER granted:
#     secretsmanager:GetSecretValue, secretsmanager:PutSecretValue, or any
#     secretsmanager:* wildcard -- preserves IAM_and_Access.md's
#     already-approved "deployment role manages the resource, never reads
#     or writes values" pattern.
#   - Parameter Store: metadata and value lifecycle for the exact
#     demonstration parameter this stack creates -- SSM parameter ARNs are
#     fully deterministic from the parameter name (no random suffix, unlike
#     Secrets Manager above), so this is scoped to one exact, literal ARN,
#     no wildcard needed. The demonstration parameter is a plain String,
#     not SecureString (kms-secrets/main.tf's own documented rationale), so
#     no KMS-related condition or action is needed here for it.
#
# No existing statement in any of the four prior managed policies attached
# to this role is modified by this addition. No runtime-role permission
# boundary, protected-role guardrail, PassRole restriction, or logging/
# networking IAM policy is touched.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "deployment_shared_kms_secrets_permissions" {
  # --- KMS key creation (Phase 0 KMS and Secrets Foundation) ---------------

  statement {
    sid       = "DevKmsCreateKeyTaggedOnly"
    effect    = "Allow"
    actions   = ["kms:CreateKey"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.aws_region]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Project"
      values   = [var.project_name]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Environment"
      values   = ["shared"]
    }
  }

  # --- KMS key administration -----------------------------------------------

  statement {
    sid    = "DevKmsKeyManageTaggedOnly"
    effect = "Allow"
    actions = [
      "kms:DescribeKey",
      "kms:GetKeyPolicy",
      "kms:PutKeyPolicy",
      "kms:EnableKeyRotation",
      "kms:GetKeyRotationStatus",
      "kms:TagResource",
      "kms:UntagResource",
      "kms:ListResourceTags",
      # kms:CreateAlias/UpdateAlias ALSO granted here (see block comment
      # above this policy) -- these are multi-resource actions requiring
      # authorization against the TARGET KEY side of the call, in addition
      # to the alias-side statement below.
      "kms:CreateAlias",
      "kms:UpdateAlias",
    ]
    resources = ["arn:aws:kms:${var.aws_region}:${var.aws_account_id}:key/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.aws_region]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Project"
      values   = [var.project_name]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Environment"
      values   = ["shared"]
    }
  }

  # --- KMS alias lifecycle -- exact, literal alias ARN, known in advance ---

  statement {
    sid    = "DevKmsAliasManageOnly"
    effect = "Allow"
    actions = [
      "kms:CreateAlias",
      "kms:UpdateAlias",
      "kms:DeleteAlias",
    ]
    resources = ["arn:aws:kms:${var.aws_region}:${var.aws_account_id}:alias/${var.project_name}-shared-primary"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.aws_region]
    }
  }

  # ADDED 2026-08-07 (real, first kms-secrets apply -- partial success):
  # kms:ListAliases has no resource-level scoping support in AWS IAM -- KMS
  # exposes no "describe one alias by name" API, so the aws_kms_alias
  # resource's own Terraform read/refresh has no other mechanism to confirm
  # the alias exists, same category as ec2:DescribePrefixLists and
  # logs:DescribeLogGroups elsewhere in this file. Real evidence: a real
  # `terraform plan`/`apply` denied this exact action while refreshing
  # alias/enterprise-data-platform-shared-primary. No other KMS read/use
  # action added alongside this one.
  statement {
    sid       = "DevKmsListAliasesUnconditioned"
    effect    = "Allow"
    actions   = ["kms:ListAliases"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.aws_region]
    }
  }

  # --- Secrets Manager -- exact demonstration secret, metadata only --------

  statement {
    sid       = "DevSecretsManagerDemoCreateTaggedOnly"
    effect    = "Allow"
    actions   = ["secretsmanager:CreateSecret"]
    resources = ["arn:aws:secretsmanager:${var.aws_region}:${var.aws_account_id}:secret:${var.project_name}/dev/demo/ingestion-api-*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.aws_region]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Project"
      values   = [var.project_name]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Environment"
      values   = ["dev"]
    }
  }

  statement {
    sid    = "DevSecretsManagerDemoManage"
    effect = "Allow"
    actions = [
      "secretsmanager:DescribeSecret",
      "secretsmanager:UpdateSecret",
      "secretsmanager:DeleteSecret",
      "secretsmanager:TagResource",
      "secretsmanager:UntagResource",
      # ADDED 2026-08-07 (real, first apply -- CreateSecret succeeded, the
      # resource entered Creating, then Terraform's own post-create read
      # was denied). secretsmanager:GetResourcePolicy has no bearing on the
      # secret's VALUE -- it reads the secret's resource-based access
      # policy (whether one is attached at all; none is here), which
      # Terraform's own aws_secretsmanager_secret read/refresh logic checks
      # as part of a normal read, independent of GetSecretValue. Real
      # evidence: a real apply denied exactly this action against
      # arn:aws:secretsmanager:ap-south-1:732264765658:secret:enterprise-
      # data-platform/dev/demo/ingestion-api-elfizH.
      "secretsmanager:GetResourcePolicy",
    ]
    # Same exact-name-plus-random-suffix-wildcard ARN pattern as the create
    # statement above -- deliberately NOT secretsmanager:GetSecretValue or
    # secretsmanager:PutSecretValue (see block comment above this policy).
    resources = ["arn:aws:secretsmanager:${var.aws_region}:${var.aws_account_id}:secret:${var.project_name}/dev/demo/ingestion-api-*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.aws_region]
    }
  }

  # --- Parameter Store -- exact demonstration parameter, no random suffix --

  statement {
    sid    = "DevSsmDemoParameterManage"
    effect = "Allow"
    actions = [
      "ssm:PutParameter",
      "ssm:GetParameter",
      "ssm:DeleteParameter",
      "ssm:AddTagsToResource",
      "ssm:RemoveTagsFromResource",
      "ssm:ListTagsForResource",
    ]
    resources = ["arn:aws:ssm:${var.aws_region}:${var.aws_account_id}:parameter/${var.project_name}/dev/demo/ingestion-config"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.aws_region]
    }
  }

  # ADDED 2026-08-07 (real, first kms-secrets apply -- partial success):
  # ssm:DescribeParameters has no resource-level scoping support in AWS
  # IAM -- it is an account/region-wide search action, distinct from
  # ssm:GetParameter above (which reads one specific, already-scoped
  # parameter's value). Real evidence: a real `terraform plan`/`apply`
  # denied this exact action while refreshing
  # /enterprise-data-platform/dev/demo/ingestion-config. Not broadened to
  # ssm:*.
  statement {
    sid       = "DevSsmDescribeParametersUnconditioned"
    effect    = "Allow"
    actions   = ["ssm:DescribeParameters"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.aws_region]
    }
  }
}

resource "aws_iam_policy" "deployment_shared_kms_secrets_permissions" {
  name        = "${var.project_name}-shared-kms-secrets-scope-policy"
  description = "KMS, Secrets Manager, and Parameter Store foundation permissions for the Enterprise Data Platform."
  policy      = data.aws_iam_policy_document.deployment_shared_kms_secrets_permissions.json

  lifecycle {
    # Same rationale as every other managed policy in this file: description
    # is immutable (Forces new resource) in the AWS provider. Ignored
    # pre-emptively here, as a new resource, for the same reason as every
    # prior policy addition.
    ignore_changes = [description]

    precondition {
      condition     = local.deployment_shared_kms_secrets_permissions_json_length <= local.iam_managed_policy_size_quota
      error_message = "aws_iam_policy.deployment_shared_kms_secrets_permissions's rendered JSON (${local.deployment_shared_kms_secrets_permissions_json_length} characters) exceeds AWS's managed-policy size quota (${local.iam_managed_policy_size_quota} characters). Do not respond by merging statements or dropping tag/condition enforcement to save space -- split further into an additional managed policy, reviewed separately."
    }
  }

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "deployment_shared_kms_secrets_permissions" {
  role       = aws_iam_role.deployment.name
  policy_arn = aws_iam_policy.deployment_shared_kms_secrets_permissions.arn
}

# ---------------------------------------------------------------------------
# Phase 0 Cost Controls (2026-08-07). Implements the approved design in
# 10_Cost_and_FinOps/Cost_Controls.md and
# 01_Architecture/ADRs/ADR-0005-cost-controls-foundation.md: permissions for
# the deployment role to manage a new, Terraform-managed AWS Budget
# (replacing the existing manually created one -- the manual budget is left
# untouched by this policy and by every other part of this task, per
# explicit instruction; its retirement is a separate, later, manual step);
# to create and manage exactly one new EventBridge Scheduler schedule and
# its exact-ARN-scoped execution IAM role (infrastructure/terraform/
# environments/dev/main.tf). This is this project's fifth "new domain gets
# its own dedicated managed policy," following the same precedent as
# deployment_dev_networking_observability_permissions and
# deployment_shared_kms_secrets_permissions -- named "shared" because it
# spans one genuinely shared/account-wide resource (the Budget) and one
# dev-scoped resource (the shutdown schedule/scheduler role), the same
# mixed-scope naming precedent already used for
# deployment_shared_kms_secrets_permissions.
#
# CORRECTED 2026-08-07 (real, explicit instruction, before any apply): this
# policy does NOT grant the deployment role ec2:StopInstances (or any other
# EC2 action). The deployment role's job here is limited to creating and
# managing the Scheduler schedule and its dedicated execution role -- it
# does not need permission to stop the workstation itself merely to do
# that. ec2:StopInstances lives ONLY on the dedicated EventBridge Scheduler
# execution role's own policy (environments/dev/main.tf's
# aws_iam_role_policy.workstation_shutdown_scheduler), scoped to the exact
# dev workstation instance ARN. See the "EC2 -- deliberately NOT granted
# here" comment below for the full corrected rationale and the intended
# trust/permission chain.
#
# Explicitly NOT granted anywhere in this policy, per Cost_Controls.md
# Section 11 and the approved implementation instructions: budgets:*,
# scheduler:* (only the 7 specific lifecycle/tagging actions below),
# iam:* (every IAM action below is scoped to exactly one new role's exact
# ARN), lambda:* (no Lambda function exists in this design at all), ssm:*
# (no SSM Automation permission exists in this design at all), and (as of
# this correction) no ec2: action of any kind.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "deployment_shared_cost_controls_permissions" {
  # --- AWS Budgets -- exact, deterministic budget name ----------------------
  # AWS Budgets exposes budgets:ViewBudget/budgets:ModifyBudget as the two
  # actions covering its create/read/update/delete/notification/subscriber
  # surface -- there is no separate budgets:CreateBudget or
  # budgets:DeleteBudget action to grant (Cost_Controls.md Section 11). No
  # aws:RequestedRegion condition here, unlike every EC2/IAM/KMS/Secrets
  # Manager/SSM statement elsewhere in this file -- AWS Budgets is a global
  # service; its ARNs carry no region segment (arn:aws:budgets::
  # <account-id>:budget/<name>, empty region field), so this condition key
  # would never match and is correctly omitted rather than added merely for
  # superficial consistency with every other statement.
  #
  # CORRECTED 2026-08-07 (real, first cost-controls apply -- CreateBudget
  # succeeded, then denied on budgets:TagResource against the real budget
  # ARN arn:aws:budgets::732264765658:budget/enterprise-data-platform-
  # shared-monthly-budget). This project's original design assumption
  # ("the budget itself is not directly taggable via aws_budgets_budget,"
  # Cost_Controls.md Section 4/10, cost-controls/main.tf's own comment) was
  # technically incomplete: aws_budgets_budget DOES support tags -- via this
  # provider's own default_tags block (cost-controls/providers.tf), applied
  # automatically even though no explicit `tags` argument was set on the
  # resource itself. AWS Budgets' tagging surface uses a separate,
  # generic-resource-tagging IAM action set (budgets:TagResource/
  # UntagResource/ListTagsForResource), NOT covered by budgets:ModifyBudget.
  # Fixed by adding all three tagging actions below -- ListTagsForResource
  # for Terraform's own post-create/refresh read (same category as
  # secretsmanager:GetResourcePolicy's addition during KMS and Secrets
  # Foundation), UntagResource for symmetry with any future tag removal/
  # drift correction, matching this project's established pattern of
  # granting the full Tag/Untag/ListTagsForResource lifecycle together
  # rather than only the one action a single failure exposed. All three
  # scoped to the exact same budget ARN already used above -- AWS Budgets'
  # tagging API operates on the same resource ARN as ViewBudget/
  # ModifyBudget. Not budgets:*.
  statement {
    sid    = "CostControlsBudgetsManage"
    effect = "Allow"
    actions = [
      "budgets:ViewBudget",
      "budgets:ModifyBudget",
      "budgets:TagResource",
      "budgets:UntagResource",
      "budgets:ListTagsForResource",
    ]
    resources = ["arn:aws:budgets::${var.aws_account_id}:budget/${var.cost_controls_budget_name}"]
  }

  # --- EventBridge Scheduler -- exact, deterministic schedule ARN -----------
  # Scoped to the one schedule this design creates, in the default schedule
  # group (no dedicated aws_scheduler_schedule_group is created -- one
  # schedule does not warrant a dedicated group). Not scheduler:* -- only
  # the specific lifecycle and tagging actions this project's own Terraform
  # workflow actually calls.
  statement {
    sid    = "CostControlsSchedulerManage"
    effect = "Allow"
    actions = [
      "scheduler:CreateSchedule",
      "scheduler:GetSchedule",
      "scheduler:UpdateSchedule",
      "scheduler:DeleteSchedule",
      "scheduler:TagResource",
      "scheduler:UntagResource",
      "scheduler:ListTagsForResource",
    ]
    resources = ["arn:aws:scheduler:${var.aws_region}:${var.aws_account_id}:schedule/default/${var.cost_controls_schedule_name}"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.aws_region]
    }
  }

  # --- Scheduler execution role -- exact, deterministic role ARN ------------
  # Same shape as DevWorkstationRoleManage (workstation-IAM policy above):
  # full lifecycle management of exactly one new role, by exact ARN, never
  # a wildcard or naming-pattern match. This grants the deployment role
  # permission to CREATE the scheduler execution role and write its inline
  # policy (environments/dev/main.tf) -- it does not itself grant the
  # deployment role ec2:StopInstances via this statement; that is a
  # separate, explicit grant below.
  statement {
    sid    = "CostControlsSchedulerRoleManage"
    effect = "Allow"
    actions = [
      "iam:CreateRole",
      "iam:GetRole",
      "iam:UpdateRole",
      "iam:UpdateAssumeRolePolicy",
      "iam:DeleteRole",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:PutRolePolicy",
      "iam:GetRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies",
    ]
    resources = ["arn:aws:iam::${var.aws_account_id}:role/${var.dev_workstation_shutdown_scheduler_role_name}"]
  }

  statement {
    sid       = "CostControlsPassSchedulerRoleOnly"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = ["arn:aws:iam::${var.aws_account_id}:role/${var.dev_workstation_shutdown_scheduler_role_name}"]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["scheduler.amazonaws.com"]
    }
  }

  # --- EC2 -- deliberately NOT granted here ---------------------------------
  # CORRECTED 2026-08-07 (real, explicit instruction, before any apply): this
  # policy previously also granted the deployment role its own
  # ec2:StopInstances statement against the workstation instance. Removed --
  # the deployment role's job is to create/manage the EventBridge Scheduler
  # schedule and its dedicated execution role (the two statement groups
  # above); it does not itself need to call ec2:StopInstances to do that.
  # The intended trust/permission chain is: deployment role creates/manages
  # the schedule and execution role -> the Scheduler service assumes the
  # dedicated execution role -> that execution role (and ONLY that role)
  # calls ec2:StopInstances, scoped to the exact dev workstation instance
  # ARN (environments/dev/main.tf's aws_iam_role_policy.
  # workstation_shutdown_scheduler). ec2:StartInstances and
  # ec2:TerminateInstances remain deliberately absent from both this policy
  # and the execution role's own policy.
}

resource "aws_iam_policy" "deployment_shared_cost_controls_permissions" {
  name        = "${var.project_name}-shared-cost-controls-scope-policy"
  description = "Cost Controls foundation permissions (Budgets, EventBridge Scheduler, workstation shutdown) for the Enterprise Data Platform."
  policy      = data.aws_iam_policy_document.deployment_shared_cost_controls_permissions.json

  lifecycle {
    # Same rationale as every other managed policy in this file: description
    # is immutable (Forces new resource) in the AWS provider. Ignored
    # pre-emptively here, as a new resource, for the same reason as every
    # prior policy addition.
    ignore_changes = [description]

    precondition {
      condition     = local.deployment_shared_cost_controls_permissions_json_length <= local.iam_managed_policy_size_quota
      error_message = "aws_iam_policy.deployment_shared_cost_controls_permissions's rendered JSON (${local.deployment_shared_cost_controls_permissions_json_length} characters) exceeds AWS's managed-policy size quota (${local.iam_managed_policy_size_quota} characters). Do not respond by merging statements or dropping tag/condition enforcement to save space -- split further into an additional managed policy, reviewed separately."
    }
  }

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "deployment_shared_cost_controls_permissions" {
  role       = aws_iam_role.deployment.name
  policy_arn = aws_iam_policy.deployment_shared_cost_controls_permissions.arn
}

# ---------------------------------------------------------------------------
# cost-controls Terraform state access -- SPLIT OUT 2026-08-07 into this
# fourth, separate, dedicated managed policy, purely to stay under AWS's
# per-policy size quota (see the comment block above
# data.aws_iam_policy_document.deployment_dev_permissions's now-removed
# CostControlsState* statements for the full incident: a real
# terraform plan reported deployment_dev_permissions's own rendered JSON at
# 6715 characters against the 6144-character quota, 571 characters over --
# caught entirely by that policy's own lifecycle.precondition at plan time,
# NOT by a real iam:CreatePolicyVersion AWS API call; no AWS command was
# run and no AWS change occurred). All three statements below are moved
# here UNCHANGED (same Sid, actions, resources, conditions) from where they
# previously lived inside deployment_dev_permissions -- nothing was merged,
# combined, dropped, or weakened to save space. Scoped ONLY to the two
# exact cost-controls state object keys -- no access to dev/*,
# kms-secrets/*, bootstrap/*, or any other prefix in this bucket, and no
# bucket metadata read statement is duplicated here (DevStateBucketMetadataRead,
# still in deployment_dev_permissions and still attached to the same
# shared deployment role, already covers it -- IAM evaluates the union of
# every policy attached to a role, not each policy in isolation).
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "deployment_shared_cost_controls_state_permissions" {
  statement {
    sid       = "CostControlsStateListBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.terraform_state.arn]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values = [
        "cost-controls/terraform.tfstate",
        "cost-controls/terraform.tfstate.tflock",
      ]
    }
  }

  statement {
    sid    = "CostControlsStateObjectReadWrite"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
    ]
    # No s3:DeleteObject on the state object itself -- same intentional
    # omission as DevStateObjectReadWrite/KmsSecretsStateObjectReadWrite.
    resources = ["${aws_s3_bucket.terraform_state.arn}/cost-controls/terraform.tfstate"]
  }

  statement {
    sid    = "CostControlsStateLockObjectManage"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject", # delete IS needed here -- releasing a native S3 lock removes the lock object, same as DevStateLockObjectManage/KmsSecretsStateLockObjectManage.
    ]
    resources = ["${aws_s3_bucket.terraform_state.arn}/cost-controls/terraform.tfstate.tflock"]
  }
}

resource "aws_iam_policy" "deployment_shared_cost_controls_state_permissions" {
  name        = "${var.project_name}-shared-cost-controls-state-scope-policy"
  description = "cost-controls Terraform remote-state access for the Enterprise Data Platform."
  policy      = data.aws_iam_policy_document.deployment_shared_cost_controls_state_permissions.json

  lifecycle {
    # Same rationale as every other managed policy in this file: description
    # is immutable (Forces new resource) in the AWS provider. Ignored
    # pre-emptively here, as a new resource.
    ignore_changes = [description]

    precondition {
      condition     = local.deployment_shared_cost_controls_state_permissions_json_length <= local.iam_managed_policy_size_quota
      error_message = "aws_iam_policy.deployment_shared_cost_controls_state_permissions's rendered JSON (${local.deployment_shared_cost_controls_state_permissions_json_length} characters) exceeds AWS's managed-policy size quota (${local.iam_managed_policy_size_quota} characters). Do not respond by merging statements or dropping tag/condition enforcement to save space -- split further into an additional managed policy, reviewed separately."
    }
  }

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "deployment_shared_cost_controls_state_permissions" {
  role       = aws_iam_role.deployment.name
  policy_arn = aws_iam_policy.deployment_shared_cost_controls_state_permissions.arn
}

# ---------------------------------------------------------------------------
# NOTE (2026-08-07): the comment block that used to live here described
# Bootstrap Update 2 (the workstation-role trust addition) as "NOT
# implemented ... deferred." That work is long since complete -- see
# data.aws_iam_policy_document.deployment_role_trust's
# AllowDevWorkstationRoleAssumeRoleNoMfa statement above, applied and
# validated 2026-08-04 (PROJECT_EXECUTION_JOURNAL.md Section 27ai). Left
# uncorrected until now only because no task touching this file had reason
# to revisit it; noted here rather than silently deleted, consistent with
# this project's standing rule against rewriting past documentation without
# a visible trace.
# ---------------------------------------------------------------------------

# =============================================================================
# PHASE 0 CI/CD FOUNDATION -- IMPLEMENTATION SLICE 1: AWS OIDC TRUST ONLY
# (2026-08-07)
# =============================================================================
#
# Implements ONLY the AWS-side OIDC trust chain approved in
# 02_Infrastructure/CI_CD.md and 01_Architecture/ADRs/ADR-0006-cicd-
# foundation.md: the GitHub OIDC identity provider, the dedicated,
# near-empty enterprise-data-platform-shared-github-actions-role, and the
# one additive trust statement on the existing deployment role (added to
# data.aws_iam_policy_document.deployment_role_trust above, not here).
#
# Explicitly NOT part of this slice (per the approved scope): no GitHub
# Actions workflow YAML; no terraform apply has been run; no change to any
# application/data stack (kms-secrets/, cost-controls/, environments/dev);
# no change to bootstrap's or logging/'s own authentication behavior (both
# remain human-direct, unaffected by anything below); no permission beyond
# a single, exact-resource-scoped sts:AssumeRole grant on the GitHub
# Actions role.
#
# Trust chain this slice establishes (CI_CD.md Section 2):
#   GitHub OIDC (token.actions.githubusercontent.com)
#     -> aws_iam_role.github_actions (sts:AssumeRoleWithWebIdentity,
#        restricted to var.github_repository's exact "sub" claims)
#     -> aws_iam_role.deployment (sts:AssumeRole, additive trust statement
#        above -- deployment role's own permissions are UNCHANGED)
#     -> Terraform-managed resources, via the deployment role's existing,
#        already-reviewed permission policies (unchanged by this slice)
#
# Exact GitHub repository this trust is scoped to: var.github_repository
# (DataEngAA/Enterprise_Data_Platform, per explicit authorization -- not
# invented, not a placeholder).

# -----------------------------------------------------------------------
# The GitHub OIDC identity provider itself -- one, shared, account-level
# resource (analogous in scope to the state bucket and the deployment role
# above: not owned by any single environment or stack). client_id_list is
# the OIDC "audience" GitHub Actions presents when requesting a token for
# this AWS account (var.github_actions_oidc_audience, fixed AWS-documented
# value "sts.amazonaws.com" -- not account-specific).
#
# CORRECTED 2026-08-07 (real-documentation review, before any Terraform
# validation was run): an earlier version of this resource included a
# data "tls_certificate" lookup (a live network fetch of GitHub's own
# well-known OIDC configuration endpoint at plan/apply time) purely to
# populate thumbprint_list, on the assumption that argument was still
# schema-required. Re-checked against current Terraform Registry
# documentation for hashicorp/aws (this configuration's installed
# constraint, versions.tf, is >= 6.0.0 -- well past the 5.81.0 release,
# December 2024, that made this change): thumbprint_list has been OPTIONAL
# on aws_iam_openid_connect_provider since v5.81.0
# (github.com/hashicorp/terraform-provider-aws PR #37255, closing issue
# #35112). AWS's own IAM service validates the OIDC provider's TLS
# certificate against its own library of trusted root CAs for providers
# like GitHub's, rather than relying on a caller-supplied thumbprint; when
# thumbprint_list is omitted, IAM derives it itself. thumbprint_list is
# therefore deliberately OMITTED below -- not left blank, not populated
# via any certificate-fetching data source. This removes this
# configuration's only dependency on a provider other than hashicorp/aws
# (the hashicorp/tls entry has been removed from versions.tf accordingly).
# -----------------------------------------------------------------------

resource "aws_iam_openid_connect_provider" "github_actions" {
  url            = "https://${var.github_oidc_provider_hostname}"
  client_id_list = [var.github_actions_oidc_audience]

  # thumbprint_list deliberately omitted -- see the correction note above.
  # Do not reintroduce a hand-copied literal thumbprint or a certificate-
  # fetching data source without a newly identified, concrete reason.

  tags = local.common_tags
}

# -----------------------------------------------------------------------
# Trust policy for the new, dedicated, near-empty GitHub Actions workload-
# identity role. Trusts ONLY the OIDC provider above, and ONLY via
# sts:AssumeRoleWithWebIdentity (never plain sts:AssumeRole, which the OIDC
# provider as a Federated principal cannot call anyway, but the action list
# is scoped explicitly regardless of what AWS itself would reject).
#
# Two conditions, both required, both exact-match (StringEquals -- no
# StringLike, no wildcard anywhere in this statement):
#   - aud must equal var.github_actions_oidc_audience exactly
#     ("sts.amazonaws.com").
#   - sub must equal ONE of exactly two approved values, both derived from
#     local.github_repository_immutable (locals.tf -- itself Terraform-
#     derived from var.github_repository, var.github_owner_id, and
#     var.github_repo_id, not a second hand-copied literal) -- no other
#     repository, ref, environment, pull request, or tag can ever satisfy
#     this condition:
#       repo:<github_repository_immutable>:ref:refs/heads/main
#       repo:<github_repository_immutable>:environment:<github_actions_environment_name>
#     CORRECTED 2026-08-08 (Slice 2B): these were the legacy, login-name-only
#     subjects (repo:<github_repository>:...) until a real GitHub Actions run
#     failed sts:AssumeRoleWithWebIdentity against them -- GitHub's OIDC
#     issuer now emits the immutable-ID format shown above. See the
#     condition block below and locals.tf's github_repository_immutable
#     comment for the full incident and derivation.
#     StringEquals against a list of values is an OR match against any one
#     of them -- this is not a wildcard; each of the two strings must match
#     GitHub's token claim exactly, character for character. Explicitly NOT
#     trusted, by construction (no statement or condition anywhere in this
#     policy would match them): wildcard/org-wide repositories
#     (repo:DataEngAA/*), any-ref patterns (refs/heads/*), pull_request or
#     pull_request_target event contexts, tag refs, or any GitHub
#     Environment name other than var.github_actions_environment_name.
# -----------------------------------------------------------------------

data "aws_iam_policy_document" "github_actions_trust" {
  statement {
    sid    = "AllowGitHubActionsOIDCAssumeRoleWebIdentity"
    effect = "Allow"

    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github_actions.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.github_oidc_provider_hostname}:aud"
      values   = [var.github_actions_oidc_audience]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.github_oidc_provider_hostname}:sub"
      # CORRECTED 2026-08-08 (Phase 0 CI/CD Slice 2B, real observed failure):
      # a real GitHub Actions run failed at
      # aws-actions/configure-aws-credentials@v4 with "Not authorized to
      # perform sts:AssumeRoleWithWebIdentity" against the legacy
      # login-name-only subjects this condition previously used
      # (repo:${var.github_repository}:...). GitHub's OIDC token issuer now
      # emits "sub" claims in an immutable-ID format
      # (repo:<org>@<owner_id>/<repo>@<repo_id>:...) -- local.
      # github_repository_immutable (locals.tf) is the Terraform-derived
      # equivalent, built from var.github_repository (org/repo login names,
      # unchanged, still the single source of truth for those) plus
      # var.github_owner_id/var.github_repo_id (GitHub's own immutable
      # numeric IDs for this exact repository). Still StringEquals against a
      # list of exactly two values -- still no wildcard, no org-wide
      # pattern, no other repository/ref/environment/pull-request/tag can
      # ever satisfy this condition.
      values = [
        "repo:${local.github_repository_immutable}:ref:refs/heads/main",
        "repo:${local.github_repository_immutable}:environment:${var.github_actions_environment_name}",
      ]
    }
  }
}

resource "aws_iam_role" "github_actions" {
  name        = var.github_actions_role_name
  description = "External GitHub Actions OIDC workload identity for ${var.project_name} -- CI_CD.md."

  assume_role_policy   = data.aws_iam_policy_document.github_actions_trust.json
  max_session_duration = var.github_actions_role_max_session_duration

  # NOTE: no wrong-account precondition is added here referencing
  # aws_iam_role.deployment (unlike aws_iam_role.deployment's own
  # precondition above, which checks var.human_bootstrap_principal_arn's
  # account). Doing so would create a real Terraform dependency cycle: this
  # role's own trust policy is independent of the deployment role (it only
  # depends on aws_iam_openid_connect_provider.github_actions), while
  # data.aws_iam_policy_document.deployment_role_trust (used by
  # aws_iam_role.deployment) already depends on THIS role's ARN
  # (AllowGitHubActionsRoleAssumeRoleNoMfa, above) -- a precondition here
  # that also referenced aws_iam_role.deployment.arn would make each role
  # depend on the other, which Terraform cannot resolve. The provider's own
  # allowed_account_ids check (providers.tf) already fails the whole
  # configuration if the active credentials' account doesn't match
  # var.aws_account_id, which is sufficient protection against the same
  # wrong-account class of mistake without introducing this cycle.
  tags = local.common_tags
}

# -----------------------------------------------------------------------
# Permissions on the GitHub Actions role -- deliberately near-empty
# (CI_CD.md Section 4, ADR-0006 Option 2). Exactly one statement, one
# action, one resource: permission to call sts:AssumeRole on the existing
# deployment role's exact ARN, and nothing else. No administrator access,
# no iam:*, no sts:* wildcard, no Terraform resource-management permission
# (s3:*, ec2:*, kms:*, etc.) of any kind is granted here or anywhere else
# in this policy document -- this role's only capability, once assumed via
# OIDC, is to make a second, separate AssumeRole call onto the deployment
# role; every actual infrastructure-management permission continues to
# live entirely on the deployment role's own, already-reviewed, unchanged
# policies.
#
# CORRECTED 2026-08-07 (real terraform plan review, dependency-propagation
# fix): resources below uses local.deployment_role_arn, not the resource
# reference aws_iam_role.deployment.arn -- see locals.tf's comment above
# deployment_role_arn for the full root-cause record (the same
# resource-reference-vs-deterministic-local issue as
# AllowGitHubActionsRoleAssumeRoleNoMfa and
# DevRuntimeIamGuardrailDenyProtectedRoles above). Byte-identical ARN
# value; only the dependency edge changes.
# -----------------------------------------------------------------------

data "aws_iam_policy_document" "github_actions_permissions" {
  statement {
    sid    = "AllowAssumeDeploymentRoleOnly"
    effect = "Allow"

    actions   = ["sts:AssumeRole"]
    resources = [local.deployment_role_arn]
  }
}

resource "aws_iam_policy" "github_actions_permissions" {
  name        = "${var.github_actions_role_name}-policy"
  description = "Minimal permission for the GitHub Actions OIDC role: assume the deployment role only. CI_CD.md."
  policy      = data.aws_iam_policy_document.github_actions_permissions.json

  lifecycle {
    ignore_changes = [description] # Same ForcesNew/no-update-API reason as every other aws_iam_policy in this file.

    precondition {
      condition     = local.github_actions_permissions_json_length <= local.iam_managed_policy_size_quota
      error_message = "aws_iam_policy.github_actions_permissions's rendered JSON (${local.github_actions_permissions_json_length} characters) exceeds AWS's managed-policy size quota (${local.iam_managed_policy_size_quota} characters) -- unexpected for a one-statement policy; investigate before proceeding rather than merging into another policy to save space."
    }
  }

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "github_actions_permissions" {
  role       = aws_iam_role.github_actions.name
  policy_arn = aws_iam_policy.github_actions_permissions.arn
}
