# Inputs for the compute module. ami_id is REQUIRED (no default, no
# internal data "aws_ami" lookup in this module) -- AMI resolution happens
# in the root module (environments/dev/main.tf), per the approved
# module-boundary revision (Dev_Environment_Terraform_Implementation_Plan.md
# Section 3.2, Section 22).

variable "project_name" {
  description = "Project identifier used as the base token in resource names and tags (01_Architecture/Naming_Convention.md)."
  type        = string
}

variable "environment" {
  description = "Deployment environment this instance belongs to (e.g. \"dev\")."
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC the workstation security group is created in. Supplied by the caller from modules/vpc's own vpc_id output."
  type        = string
}

variable "subnet_id" {
  description = "ID of the public subnet the workstation instance is launched into. Supplied by the caller from modules/vpc's own public_subnet_id output."
  type        = string
}

variable "instance_profile_name" {
  description = "Name of the IAM instance profile to attach to the instance. Supplied by the caller from modules/iam-workstation-role's own instance_profile_name output. This module never constructs or reasons about the profile itself."
  type        = string
}

variable "ami_id" {
  description = <<-EOT
    Exact AMI ID to launch. REQUIRED -- no default, and this module performs
    no AMI lookup of its own (revised 2026-07-26: AMI resolution moved to
    the root module, environments/dev/main.tf, because AMI selection is
    region- and environment-specific and should be visible directly in the
    root's own plan output). This module only ever uses whatever ami_id it
    is given.
  EOT
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type. Default t3.medium; only t3.medium, t3.large, and t3.xlarge are permitted (Dev_Environment_Terraform_Implementation_Plan.md Sections 24-25). t3.small is deliberately excluded from the project's approved design."
  type        = string
  default     = "t3.medium"

  # TEMPORARY, ACCOUNT-SPECIFIC WORKAROUND (2026-07-26) -- NOT a design
  # change. Mirrors the identical, identically-commented widening in
  # environments/dev/variables.tf -- see that file's comment for the full
  # incident record and revert conditions. This module's own validation
  # must stay in sync with the root module's, since either one alone would
  # otherwise reject a value the other permits.
  validation {
    condition     = contains(["t3.medium", "t3.large", "t3.xlarge", "t3.small"], var.instance_type)
    error_message = "instance_type must be one of: t3.medium (default), t3.large, t3.xlarge, or (temporary, account-specific workaround) t3.small."
  }
}

variable "root_volume_size" {
  description = "Size, in GiB, of the encrypted gp3 root volume. Approved default: 30 (Section 26)."
  type        = number
  default     = 30

  validation {
    condition     = var.root_volume_size >= 30
    error_message = "root_volume_size must be at least 30 GiB, the approved minimum for this workstation design."
  }
}

variable "user_data" {
  description = "Rendered content of the bootstrap script (infrastructure/terraform/scripts/bootstrap_workstation.sh), read by the root module via file()/templatefile() and passed in as a plain string. May be an empty string or a minimal placeholder before the script exists (Section 29.7) -- the instance remains fully usable via Session Manager either way. Contains no secret -- user_data is not a secret-storage location (Section 29.2)."
  type        = string
  default     = ""
}

variable "enable_detailed_monitoring" {
  description = "Whether to enable CloudWatch detailed (1-minute) monitoring. Approved default: false, i.e. basic 5-minute monitoring, for cost control (Section 28)."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Common tag map (Project, Environment, ManagedBy, Owner, CostCenter, DataClassification) computed by the caller's locals.tf."
  type        = map(string)
  default     = {}
}
