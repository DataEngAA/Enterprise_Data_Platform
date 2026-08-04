# Inputs for the networking module. No account-specific value has a
# default here -- CIDR ranges are approved, non-sensitive design values
# (Dev_Environment_Terraform_Implementation_Plan.md Section 21) supplied by
# the caller (environments/dev), not invented inside this module.

variable "project_name" {
  description = "Project identifier used as the base token in resource names and tags (01_Architecture/Naming_Convention.md)."
  type        = string
}

variable "environment" {
  description = "Deployment environment this VPC belongs to (e.g. \"dev\"). Used in resource names and the Environment tag."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC. Approved value for dev: 10.20.0.0/16 (Dev_Environment_Terraform_Implementation_Plan.md Section 21). No default -- supplied explicitly by the caller so the value is visible in the root module's own configuration, not hidden inside this module."
  type        = string
}

variable "public_subnet_cidr" {
  description = "CIDR block for the single public subnet created by this module. Approved value for dev: 10.20.1.0/24 (Section 21). Must be a subset of var.vpc_cidr -- not validated here since Terraform cannot easily cross-validate two variables against each other without a resource-level check; reviewed manually at plan time instead."
  type        = string
}

variable "availability_zone_override" {
  description = <<-EOT
    Optional explicit Availability Zone name to use instead of the dynamic
    first-AZ lookup (Section 20). Defaults to null, meaning: query
    data.aws_availability_zones and deterministically use index 0. Do not
    hardcode a literal AZ name (e.g. "ap-south-1a") anywhere that calls this
    module -- AZ name-to-physical-location mappings are account-specific.
    This override exists only for a future, deliberate second-AZ need; it is
    not used by the first dev implementation.
  EOT
  type        = string
  default     = null
}

variable "tags" {
  description = "Common tag map (Project, Environment, ManagedBy, Owner, CostCenter, DataClassification) computed by the caller's locals.tf and merged with each resource's own Name tag inside this module."
  type        = map(string)
  default     = {}
}
