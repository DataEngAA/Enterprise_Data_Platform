# Workstation identity module -- owns the EC2 workstation's IAM role, its
# trust policy, its SSM managed-policy attachment, its narrow AssumeRole
# inline policy, and its instance profile (Dev_Environment_Terraform_
# Implementation_Plan.md Section 3.2 "Does the instance profile belong in
# iam-workstation-role or ec2-workstation? APPROVED -- iam-workstation-role").
#
# This module grants NO user/group/access-key/arbitrary-role/broad-IAM-
# administration permission of any kind. Its only capability, beyond SSM
# connectivity, is sts:AssumeRole against exactly one caller-supplied ARN.
#
# This file has not been applied. Nothing below has been created in AWS.

# ---------------------------------------------------------------------------
# Trust policy -- only the EC2 service principal may assume this role.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "workstation_trust" {
  statement {
    sid     = "AllowEC2ServiceAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "workstation" {
  name                 = var.role_name
  description          = "EC2 instance role for the ${var.environment} development workstation. Narrow scope: SSM connectivity plus sts:AssumeRole against the shared deployment role only. No direct infrastructure-management permission on this role itself."
  assume_role_policy   = data.aws_iam_policy_document.workstation_trust.json
  max_session_duration = 3600

  tags = var.tags
}

# ---------------------------------------------------------------------------
# SSM connectivity -- required for Session Manager to function at all
# (Dev_Environment_Terraform_Implementation_Plan.md Section 15).
# ---------------------------------------------------------------------------

resource "aws_iam_role_policy_attachment" "ssm_managed_instance_core" {
  role       = aws_iam_role.workstation.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# ---------------------------------------------------------------------------
# Narrow AssumeRole permission -- exactly one ARN, no wildcard
# (Dev_Environment_Terraform_Implementation_Plan.md Section 13).
#
# This is the workstation role's ONLY path to any infrastructure-management
# capability. It cannot create, modify, or delete any AWS resource directly
# -- it can only assume the shared deployment role, which itself is scoped
# by the policy Bootstrap Update 1 attaches in infrastructure/terraform/
# bootstrap/main.tf.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "assume_deployment_role" {
  statement {
    sid       = "AllowAssumeSharedDeploymentRoleOnly"
    effect    = "Allow"
    actions   = ["sts:AssumeRole"]
    resources = [var.deployment_role_arn]
  }
}

resource "aws_iam_role_policy" "assume_deployment_role" {
  name   = "${var.role_name}-assume-deployment-role"
  role   = aws_iam_role.workstation.id
  policy = data.aws_iam_policy_document.assume_deployment_role.json
}

# ---------------------------------------------------------------------------
# Instance profile -- strict 1:1 wrapper around the role above. Co-located
# here (not in modules/ec2-workstation) per the approved module-boundary
# decision (Section 3.2): an instance profile has no meaningful input beyond
# the role name this module already owns.
# ---------------------------------------------------------------------------

resource "aws_iam_instance_profile" "workstation" {
  name = var.role_name
  role = aws_iam_role.workstation.name

  tags = var.tags
}
