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

# Trust policy: limited to the human bootstrap principal only, with an MFA
# condition. The future EC2 workstation role is deliberately NOT trusted
# here -- it does not exist yet. Adding it is a separate, later, reviewed
# change to this same resource once that role has been created
# (Terraform_Bootstrap_Design.md Section 2 step 5, Section 22;
# Terraform_Bootstrap_Implementation_Plan.md Section 16).
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
}

resource "aws_iam_role" "deployment" {
  name                 = var.deployment_role_name
  description          = "Terraform deployment role for ${var.project_name}. Three dev-scoped managed permissions policies are attached (see aws_iam_policy.deployment_dev_permissions, aws_iam_policy.deployment_dev_networking_permissions, and aws_iam_policy.deployment_dev_workstation_iam_permissions, and the comment block below this resource) -- split across three policies as of the 2026-07-26 IAM managed-policy size-quota corrections (Bootstrap Update 1: first a two-policy split after a real iam:CreatePolicyVersion LimitExceeded failure, then a second split of the non-networking policy after its own lifecycle.precondition reported 6212 characters against a 6144 quota). Trust remains limited to the bootstrap-scoped human identity, with MFA required, only -- it has not been extended to the EC2 workstation role yet; that trust addition is Bootstrap Update 2, a separate, later, reviewed change to this same resource's trust policy once the workstation role exists."
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

    # DIAGNOSTIC CONDITIONS RESTORED (2026-07-26) -- investigation closed.
    # A three-round diagnostic sequence (removing ec2:Owner, then
    # ec2:InstanceType, then aws:RequestedRegion, one at a time, on real
    # applies) was run against a real, unexplained ec2:RunInstances
    # UnauthorizedOperation on this exact AMI resource. The true root cause
    # turned out to be unrelated to this statement entirely: Terraform was
    # not actually operating under the deployment role's assumed-role
    # session during that testing (an MFA/STS credential-flow issue,
    # resolved separately -- see PROJECT_EXECUTION_JOURNAL.md for the full
    # incident record). With a genuine deployment-role session in place, the
    # bare, condition-free version of this statement authorized the launch
    # successfully, confirming none of these three conditions was ever the
    # actual blocker. All three are restored below to their intended,
    # reviewed scope. ec2:Owner and aws:RequestedRegion are restored exactly
    # as originally designed. ec2:InstanceType's value list additionally
    # includes t3.small here, matching the still-active, separately-tracked
    # temporary account-specific workaround on
    # DevRunInstancesSupportingResources below and in both
    # environments/dev/variables.tf and modules/ec2-workstation/variables.tf
    # -- restoring this condition without t3.small would reintroduce a real
    # regression against the currently-working deployment if ec2:InstanceType
    # turns out to be evaluated for this resource type after all, even though
    # it is not expected to apply to the "image" resource type per AWS's own
    # EC2 condition-key documentation. Revert to ["t3.medium", "t3.large",
    # "t3.xlarge"] (no t3.small) together with the identical, separately
    # tracked t3.small removal on DevRunInstancesSupportingResources and in
    # both variables.tf files once this account's Free Tier launch
    # restriction is resolved -- see PROJECT_EXECUTION_JOURNAL.md for the
    # full incident record and revert conditions.
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
    sid       = "DevRunInstancesTagOnCreate"
    effect    = "Allow"
    actions   = ["ec2:CreateTags"]
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
# Bootstrap Update 2 (Stage C, Dev_Environment_Terraform_Implementation_
# Plan.md Section 12) is NOT implemented by this update -- it is a
# TRUST-POLICY-ONLY change (adding the, by-then-real, workstation role ARN
# as a second trusted principal on aws_iam_role.deployment's trust policy
# above), strictly deferred until AFTER environments/dev's own apply
# produces that real ARN. This section will be added as its own, separate,
# later, reviewed change -- not part of this file-creation task.
# ---------------------------------------------------------------------------
