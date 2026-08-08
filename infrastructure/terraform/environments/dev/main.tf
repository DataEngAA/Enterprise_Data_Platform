# environments/dev -- a single, COMPOSING root module (Terraform_Bootstrap_
# Design.md Section 17). No infrastructure resource is defined directly
# here -- only data sources, a wrong-account check, and the three module
# blocks that do the actual resource creation
# (Dev_Environment_Terraform_Implementation_Plan.md Section 5).
#
# This file has not been applied. Nothing below has been created in AWS.
# Requires Bootstrap Update 1 (infrastructure/terraform/bootstrap/) to have
# already landed before this configuration's provider/backend can do
# anything with the deployment role -- see README.md.

# ---------------------------------------------------------------------------
# Wrong-account guard (Section 36) -- belt-and-suspenders alongside
# providers.tf's own allowed_account_ids check. Fails the plan/apply loudly
# if the resolved caller identity's account does not match var.aws_account_id,
# rather than silently operating against an unexpected account.
# ---------------------------------------------------------------------------

data "aws_caller_identity" "current" {}

check "account_matches_expected" {
  assert {
    condition     = data.aws_caller_identity.current.account_id == var.aws_account_id
    error_message = "The AWS account reached via the assumed deployment role does not match var.aws_account_id. Check terraform.tfvars and the deployment_role_arn being used."
  }
}

# ---------------------------------------------------------------------------
# AMI lookup (Section 22, Section 3.2 -- REVISED 2026-07-26: lives in the
# root module, NOT modules/ec2-workstation). Only evaluated when
# var.ami_id_override is null (the default) -- see locals.tf's
# resolved_ami_id for how the override is applied when set.
# ---------------------------------------------------------------------------

data "aws_ami" "al2023" {
  count       = var.ami_id_override == null ? 1 : 0
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}

# ---------------------------------------------------------------------------
# Networking (Section 3, Section 8 dependency graph: no dependency on the
# other two modules, can resolve independently).
# ---------------------------------------------------------------------------

module "vpc" {
  source = "../../modules/vpc"

  project_name       = var.project_name
  environment        = var.environment
  vpc_cidr           = var.vpc_cidr
  public_subnet_cidr = var.public_subnet_cidr
  tags               = local.common_tags

  # Phase 0 Networking Hardening (2026-08-04) -- 02_Infrastructure/
  # Networking.md; ADR-0003. Every value below is additive to the existing
  # VPC/public subnet above -- none of it changes vpc_cidr/public_subnet_cidr
  # or anything already applied.
  public_subnet_cidr_az2       = var.public_subnet_cidr_az2
  private_app_subnet_cidr_az1  = var.private_app_subnet_cidr_az1
  private_app_subnet_cidr_az2  = var.private_app_subnet_cidr_az2
  private_data_subnet_cidr_az1 = var.private_data_subnet_cidr_az1
  private_data_subnet_cidr_az2 = var.private_data_subnet_cidr_az2
  enable_s3_gateway_endpoint   = var.enable_s3_gateway_endpoint
  enable_vpc_flow_logs         = var.enable_vpc_flow_logs
}

# ---------------------------------------------------------------------------
# Workstation IAM identity (Section 3, Section 8: no dependency on the
# other two modules, can resolve independently).
# ---------------------------------------------------------------------------

module "workstation_role" {
  source = "../../modules/iam-workstation-role"

  environment         = var.environment
  role_name           = "${var.project_name}-${var.environment}-workstation-role"
  deployment_role_arn = var.deployment_role_arn
  tags                = local.common_tags
}

# ---------------------------------------------------------------------------
# EC2 workstation (Section 3, Section 8: depends on ALL of the above --
# vpc_id/subnet_id from modules.vpc, instance_profile_name from
# modules.workstation_role, ami_id from this root's own lookup above).
# ---------------------------------------------------------------------------

module "ec2_workstation" {
  source = "../../modules/ec2-workstation"

  project_name               = var.project_name
  environment                = var.environment
  vpc_id                     = module.vpc.vpc_id
  subnet_id                  = module.vpc.public_subnet_id
  instance_profile_name      = module.workstation_role.instance_profile_name
  ami_id                     = local.resolved_ami_id
  instance_type              = var.instance_type
  root_volume_size           = 30
  user_data                  = local.bootstrap_script
  enable_detailed_monitoring = false
  tags                       = local.common_tags
}

# ---------------------------------------------------------------------------
# Phase 0 Cost Controls -- automatic dev workstation shutdown (Section 5:
# depends on module.ec2_workstation, since it targets that module's real,
# already-managed instance by ID -- never a hardcoded or separately
# supplied instance ID, so this schedule can never silently drift to the
# wrong instance).
#
# Implements the approved design in 10_Cost_and_FinOps/Cost_Controls.md
# Section 5 and 01_Architecture/ADRs/ADR-0005-cost-controls-foundation.md:
# EventBridge Scheduler with a direct Universal Target `ec2:StopInstances`
# call -- no Lambda function, no SSM Automation document. Shutdown ONLY:
# no aws_scheduler_schedule for a start action exists anywhere in this
# file, and the execution role below is never granted ec2:StartInstances
# or ec2:TerminateInstances.
#
# Requires bootstrap/main.tf's new deployment_shared_cost_controls_
# permissions policy to already be applied (the deployment role needs
# iam:CreateRole/iam:PutRolePolicy/iam:PassRole scoped to exactly the role
# name below, and scheduler:CreateSchedule scoped to exactly the schedule
# name below) before this stack's own apply can succeed.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "workstation_shutdown_scheduler_trust" {
  statement {
    sid     = "AllowSchedulerAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["scheduler.amazonaws.com"]
    }

    # Confused-deputy protection (AWS's own documented recommendation for
    # any service-principal trust policy): restricts which EventBridge
    # Scheduler resources, in which account, may assume this role -- not
    # just "any schedule owned by any AWS account that happens to specify
    # this role ARN."
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [var.aws_account_id]
    }

    # CORRECTED 2026-08-07 (real AWS apply, first real cost-controls dev
    # deployment): a real terraform apply had already created
    # aws_iam_role.workstation_shutdown_scheduler and
    # aws_iam_role_policy.workstation_shutdown_scheduler, then failed to
    # create aws_scheduler_schedule.workstation_shutdown with a real
    # ValidationException: "The execution role you provide must allow AWS
    # EventBridge Scheduler to assume the role." Root cause: this
    # condition previously targeted the INDIVIDUAL SCHEDULE's own ARN
    # (arn:aws:scheduler:<region>:<account>:schedule/default/<schedule-name>)
    # under ArnLike. AWS EventBridge Scheduler's own confused-deputy
    # guidance requires aws:SourceArn to reference the SCHEDULE GROUP ARN,
    # not an individual schedule ARN -- Scheduler evaluates this trust
    # condition against the schedule GROUP the calling schedule belongs to,
    # so a condition scoped to the schedule's own ARN can never match,
    # unconditionally failing every real AssumeRole attempt regardless of
    # which schedule invokes it. Fixed: aws:SourceArn now targets the
    # default schedule group's ARN
    # (arn:aws:scheduler:<region>:<account>:schedule-group/default) --
    # still exact, still narrow (this account has no other schedule group;
    # every schedule this project creates lives in the default group), and
    # the operator changed from ArnLike to StringEquals for an exact-match
    # comparison rather than a wildcard-capable one, since no wildcard is
    # needed or wanted here. aws:SourceAccount is unchanged.
    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = ["arn:aws:scheduler:${var.region}:${var.aws_account_id}:schedule-group/default"]
    }
  }
}

resource "aws_iam_role" "workstation_shutdown_scheduler" {
  name               = var.workstation_shutdown_scheduler_role_name
  description        = "EventBridge Scheduler execution role for the automatic dev workstation shutdown schedule."
  assume_role_policy = data.aws_iam_policy_document.workstation_shutdown_scheduler_trust.json

  tags = local.common_tags
}

data "aws_iam_policy_document" "workstation_shutdown_scheduler_permissions" {
  statement {
    sid     = "AllowStopWorkstationOnly"
    effect  = "Allow"
    actions = ["ec2:StopInstances"]
    # The real, already-managed workstation instance -- module.ec2_workstation.instance_id,
    # never a hardcoded ID or a tag-based condition. ec2:StartInstances and
    # ec2:TerminateInstances are deliberately NOT included in this
    # statement or anywhere else in this policy document.
    resources = ["arn:aws:ec2:${var.region}:${var.aws_account_id}:instance/${module.ec2_workstation.instance_id}"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.region]
    }
  }
}

resource "aws_iam_role_policy" "workstation_shutdown_scheduler" {
  name   = "${var.workstation_shutdown_scheduler_role_name}-policy"
  role   = aws_iam_role.workstation_shutdown_scheduler.id
  policy = data.aws_iam_policy_document.workstation_shutdown_scheduler_permissions.json
}

resource "aws_scheduler_schedule" "workstation_shutdown" {
  #checkov:skip=CKV_AWS_297:Phase-0 accepted trade-off/deferred hardening -- the target input carries only the exact EC2 workstation instance ID, not secret material; a customer-managed KMS key here would add KMS policy/service-integration complexity without meaningful Phase-0 risk reduction. Revisit if scheduler payloads later carry sensitive data.
  name        = var.cost_controls_schedule_name
  group_name  = "default"
  description = "Automatic shutdown of the dev EC2 workstation -- shutdown only, never automatic startup (Cost_Controls.md Section 5)."

  # No flexible execution window -- a daily shutdown at a fixed local time
  # has no reason to jitter; OFF means the schedule fires at exactly the
  # configured time.
  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression          = var.workstation_shutdown_schedule_expression
  schedule_expression_timezone = var.workstation_shutdown_timezone
  state                        = "ENABLED"

  target {
    # EventBridge Scheduler's "Universal Target" ARN pattern for a direct
    # AWS SDK API call, with no intermediate Lambda function or SSM
    # Automation document (Cost_Controls.md Section 5's approved refinement
    # of Options A/B): arn:aws:scheduler:::aws-sdk:<service>:<operation>,
    # operation in camelCase. NOT independently verified against a real
    # `terraform apply` in this sandbox (no terraform binary here) -- flag
    # this exact ARN string for extra scrutiny during the first real `plan`
    # on the user's own machine.
    arn      = "arn:aws:scheduler:::aws-sdk:ec2:stopInstances"
    role_arn = aws_iam_role.workstation_shutdown_scheduler.arn

    # ec2:StopInstances against an already-stopped instance is itself a
    # safe, idempotent AWS API call (confirmed AWS EC2 API behavior, not a
    # design assumption) -- no additional guard logic is added here.
    input = jsonencode({
      InstanceIds = [module.ec2_workstation.instance_id]
    })
  }

  # CORRECTED 2026-08-07 (real terraform validate, on the user's own
  # machine): a `tags = local.common_tags` argument previously lived here.
  # Removed -- the installed AWS provider version rejects it with
  # "Unsupported argument": aws_scheduler_schedule does not expose a `tags`
  # argument in this provider version, unlike aws_iam_role.
  # workstation_shutdown_scheduler above (still tagged, unaffected) and
  # every other taggable resource in this project. This schedule is still
  # fully Terraform-managed and deterministically named
  # (var.cost_controls_schedule_name) -- it is simply not tag-labeled the
  # way most other resources in this project are, a real provider-schema
  # limitation, not a design choice. No workaround resource or CLI tagging
  # step was added.
}
