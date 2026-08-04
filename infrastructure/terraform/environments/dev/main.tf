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
