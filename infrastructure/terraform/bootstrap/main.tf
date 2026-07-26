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
  description          = "Terraform deployment role for ${var.project_name}. Currently assumable only by the bootstrap-scoped human identity (with MFA); trust will be extended to the EC2 workstation role in a separate, later apply once that role exists. NO PERMISSIONS ARE ATTACHED YET -- see the comment block below this resource."
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
# Deployment role permissions -- DELIBERATELY NONE ATTACHED, for now.
#
# Bootstrap management model (decided 2026-07-25, superseding the previous
# static-review draft's narrowly-scoped placeholder policy):
#
#   - This bootstrap root module remains a human-administered exception.
#     Its own provider and backend continue to run as the authorized human
#     IAM identity directly (providers.tf) -- never via this role.
#   - aws_iam_role.deployment exists so its name, ARN, and trust
#     relationship are established now (environments/dev will need to
#     reference deployment_role_arn, output below, once that work begins).
#   - The Terraform deployment role's actual job is to LATER manage
#     environments/dev (VPC, workstation IAM role, EC2) -- not this
#     bootstrap configuration's own state.
#   - The deployment role therefore does NOT receive access to
#     bootstrap/terraform.tfstate (or its lock object). Granting it that
#     access would let a role whose purpose is managing dev infrastructure
#     also read/write the very state object that defines the deployment
#     role itself and the state bucket's hardening -- a self-referential,
#     unnecessary blast-radius expansion this design avoids by simply not
#     granting it.
#
# A future, separately reviewed change will attach a permissions policy (or
# policies) to this role covering, at minimum:
#   - exact-object access (not bucket-wide) to the dev environment's state
#     object and its native-locking lock object, once environments/dev has
#     its own state key
#   - approved VPC, IAM (narrowly, for the workstation role only), and EC2
#     deployment permissions once environments/dev is designed and approved
#     (Terraform_Bootstrap_Design.md Section 30;
#     Terraform_Bootstrap_Implementation_Plan.md Section 29)
#
# Until that future change lands, this role has NO permissions policy
# attached at all -- not AdministratorAccess, not a wildcard placeholder,
# nothing. A session that assumes this role (subject to the MFA-conditioned
# trust policy above) can authenticate but cannot call any AWS API that
# requires permissions, because none are granted.
# ---------------------------------------------------------------------------
