# Variable declarations for the environments/dev root module.
#
# Account-specific values (aws_account_id, deployment_role_arn) have NO
# default -- they must be supplied via a gitignored terraform.tfvars (see
# terraform.tfvars.example). No AWS account ID or role ARN is invented
# anywhere in this file. CIDR values ARE given real, literal defaults here
# (not left as placeholders) because the CIDR scheme itself is finalized,
# non-account-sensitive design (Dev_Environment_Terraform_Implementation_
# Plan.md Section 21, Section 41).

variable "project_name" {
  description = "Project identifier used as the base token in resource names and tags (01_Architecture/Naming_Convention.md)."
  type        = string
  default     = "enterprise-data-platform"
}

variable "region" {
  description = "AWS region this configuration operates in."
  type        = string
  default     = "ap-south-1"
}

variable "aws_account_id" {
  description = <<-EOT
    12-digit AWS account ID this configuration is expected to run against.
    No default -- account-specific. Used to configure the AWS provider's
    `allowed_account_ids` (providers.tf), the same wrong-account safety
    pattern bootstrap/providers.tf already uses. Not invented here -- obtain
    with:
      aws sts get-caller-identity --query Account --output text
    See terraform.tfvars.example.
  EOT
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "aws_account_id must be exactly 12 digits (a real AWS account ID, not invented)."
  }
}

variable "environment" {
  description = "Deployment environment for this root module. Fixed to \"dev\" -- this root module manages exactly one environment (Naming_Convention.md \"Environment values\")."
  type        = string
  default     = "dev"

  validation {
    condition     = var.environment == "dev"
    error_message = "This root module (environments/dev) only manages the dev environment and must use environment = \"dev\"."
  }
}

variable "deployment_role_arn" {
  description = <<-EOT
    Exact ARN of the shared Terraform deployment role (infrastructure/
    terraform/bootstrap/, output as deployment_role_arn). No default --
    account-specific. Used by BOTH backend.hcl's own assume_role block (state
    access) and this file's provider assume_role block (resource-management
    API calls) -- two functionally separate AssumeRole calls against the
    SAME role ARN (Section 9). Requires Bootstrap Update 1 (the deployment
    role's permissions policy) to have already landed before this
    configuration's provider/backend can do anything with it -- see the
    README's "Bootstrap Update 1 Dependency" section.
    See terraform.tfvars.example.
  EOT
  type        = string

  validation {
    condition     = can(regex("^arn:aws:iam::[0-9]{12}:role/.+$", var.deployment_role_arn))
    error_message = "deployment_role_arn must be an IAM role ARN of the form arn:aws:iam::<12-digit-account-id>:role/<role-name>."
  }
}

variable "vpc_cidr" {
  description = "CIDR block for the dev VPC. Approved, finalized value (Section 21)."
  type        = string
  default     = "10.20.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for the single public subnet created now. Approved, finalized value (Section 21)."
  type        = string
  default     = "10.20.1.0/24"
}

# -----------------------------------------------------------------------
# Phase 0 Networking Hardening (2026-08-04) -- 02_Infrastructure/
# Networking.md "Phase 0 Networking Hardening -- Target State Design";
# 01_Architecture/ADRs/ADR-0003-networking-hardening-multi-az-nat-and-
# endpoint-strategy.md. CIDR values, like vpc_cidr/public_subnet_cidr
# above, are given real, literal defaults here because the scheme is
# finalized, non-account-sensitive design, not account-specific.
# -----------------------------------------------------------------------

variable "public_subnet_cidr_az2" {
  description = "CIDR block for the second public subnet (AZ index 1). Approved, finalized value."
  type        = string
  default     = "10.20.2.0/24"
}

variable "private_app_subnet_cidr_az1" {
  description = "CIDR block for the private-application subnet in AZ index 0. Approved, finalized value -- previously reserved-only (Section 21), created for the first time by this workstream."
  type        = string
  default     = "10.20.11.0/24"
}

variable "private_app_subnet_cidr_az2" {
  description = "CIDR block for the private-application subnet in AZ index 1. Approved, finalized value."
  type        = string
  default     = "10.20.12.0/24"
}

variable "private_data_subnet_cidr_az1" {
  description = "CIDR block for the private-data subnet in AZ index 0. Approved, finalized value -- previously reserved-only (Section 21), created for the first time by this workstream."
  type        = string
  default     = "10.20.21.0/24"
}

variable "private_data_subnet_cidr_az2" {
  description = "CIDR block for the private-data subnet in AZ index 1. Approved, finalized value."
  type        = string
  default     = "10.20.22.0/24"
}

variable "enable_s3_gateway_endpoint" {
  description = "Whether to create the S3 Gateway VPC endpoint. Approved: true for Phase 0."
  type        = bool
  default     = true
}

variable "enable_vpc_flow_logs" {
  description = "Whether to create VPC Flow Logs. Approved: true for Phase 0."
  type        = bool
  default     = true
}

variable "instance_type" {
  description = "EC2 instance type for the workstation. Only t3.medium (default), t3.large, and t3.xlarge are permitted (Sections 24-25). t3.small is deliberately excluded from the project's approved design -- see EC2_Development_Workstation.md Section 6."
  type        = string
  default     = "t3.medium"

  # TEMPORARY, ACCOUNT-SPECIFIC WORKAROUND (2026-07-26) -- NOT a design
  # change. This account rejects t3.medium/t3.large/t3.xlarge with
  # `InvalidParameterCombination: instance type is not eligible for Free
  # Tier` at RunInstances time (confirmed via manual launch testing:
  # t3.small, t3.micro, and m7i-flex.large succeed in this account,
  # t3.medium does not). t3.small is added to this validation ONLY so this
  # specific, restricted account can proceed with implementation work. The
  # project's approved default and design target REMAIN t3.medium
  # (unchanged above) -- this widening does NOT constitute the "testing
  # evidence" EC2_Development_Workstation.md Section 6/28 describes as the
  # condition for adopting t3.small permanently, since the cause here is an
  # account eligibility restriction, not evidence about whether 2 GiB is
  # sufficient for the actual workload. Revert this validation to
  # `["t3.medium", "t3.large", "t3.xlarge"]` once this account's
  # restriction is resolved (e.g., via an AWS Support request) or once
  # development moves to an unrestricted account -- see
  # PROJECT_EXECUTION_JOURNAL.md for the incident record.
  validation {
    condition     = contains(["t3.medium", "t3.large", "t3.xlarge", "t3.small"], var.instance_type)
    error_message = "instance_type must be one of: t3.medium (default), t3.large, t3.xlarge, or (temporary, account-specific workaround) t3.small."
  }
}

variable "ami_id_override" {
  description = "Optional explicit AMI ID to pin instead of the automatic latest-Amazon-Linux-2023-x86_64 lookup in main.tf. Leave null (default) to always use the current AL2023 AMI (Section 22)."
  type        = string
  default     = null
}

variable "additional_tags" {
  description = "Optional additional resource-specific tags, merged with the required common tags computed in locals.tf. Leave empty ({}) if none are needed."
  type        = map(string)
  default     = {}
}

# -----------------------------------------------------------------------
# Phase 0 Cost Controls (10_Cost_and_FinOps/Cost_Controls.md Section 5;
# ADR-0005). Automatic EC2 shutdown ONLY -- no automatic startup variable
# exists anywhere in this file, deliberately (Cost_Controls.md Section 5's
# explicit "shutdown only, never automatic startup" requirement).
# -----------------------------------------------------------------------

variable "workstation_shutdown_scheduler_role_name" {
  description = "Name of the EventBridge Scheduler execution IAM role for the automatic workstation-shutdown schedule (Naming_Convention.md IAM role pattern). Must match bootstrap/variables.tf's dev_workstation_shutdown_scheduler_role_name default, which scopes the deployment role's IAM-management and iam:PassRole grants to exactly this name -- kept as two separately supplied, matching defaults rather than a cross-stack reference, consistent with this project's tfvars-supplied-value convention between independent stacks."
  type        = string
  default     = "enterprise-data-platform-dev-workstation-shutdown-scheduler-role"
}

variable "cost_controls_schedule_name" {
  description = "Name of the EventBridge Scheduler schedule (default schedule group) for the automatic workstation-shutdown schedule. Must match bootstrap/variables.tf's cost_controls_schedule_name default, which scopes the deployment role's scheduler:* grant to exactly this name."
  type        = string
  default     = "enterprise-data-platform-dev-workstation-shutdown"
}

variable "workstation_shutdown_schedule_expression" {
  description = <<-EOT
    EventBridge Scheduler cron expression for the automatic dev workstation
    shutdown. Approved default (2026-08-07): 21:00 daily --
    "cron(0 21 * * ? *)" (minute hour day-of-month month day-of-week year;
    "?" required in exactly one of the day-of-month/day-of-week fields per
    AWS's own cron syntax). Configurable, not hardcoded policy -- change
    this variable, not a resource block, to adjust the schedule
    (Cost_Controls.md Section 5).
  EOT
  type        = string
  default     = "cron(0 21 * * ? *)"
}

variable "workstation_shutdown_timezone" {
  description = <<-EOT
    IANA timezone the schedule expression above is evaluated in. Approved
    default (2026-08-07): "Asia/Kolkata", matching this account's
    ap-south-1 region and the user's own operating timezone. EventBridge
    Scheduler evaluates cron expressions in UTC unless this argument is
    explicitly set -- leaving it unset would silently shift the effective
    local stop time (Cost_Controls.md Section 5's explicit "timezone
    explicitly handled" requirement).
  EOT
  type        = string
  default     = "Asia/Kolkata"
}
