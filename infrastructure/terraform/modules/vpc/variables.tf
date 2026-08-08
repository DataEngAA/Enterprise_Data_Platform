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

# -----------------------------------------------------------------------
# Phase 0 Networking Hardening (2026-08-04) -- 02_Infrastructure/Networking.md
# "Phase 0 Networking Hardening -- Target State Design";
# 01_Architecture/ADRs/ADR-0003-networking-hardening-multi-az-nat-and-
# endpoint-strategy.md. Extends this module to a second AZ and adds
# private-application/private-data subnets, an S3 Gateway VPC endpoint, and
# VPC Flow Logs. The existing public subnet (above) and its CIDR/AZ
# selection logic are NOT modified by any of this -- every variable below
# describes a NEW resource only.
#
# Reserved for a future third AZ, DOCUMENTATION ONLY, not modeled as a
# Terraform variable and not created by this module (ADR-0003 Option 1;
# ready for later): 10.20.3.0/24 (public), 10.20.13.0/24 (private-app),
# 10.20.23.0/24 (private-data).
# -----------------------------------------------------------------------

variable "public_subnet_cidr_az2" {
  description = "CIDR block for the second public subnet (AZ index 1). Approved value: 10.20.2.0/24 (02_Infrastructure/Networking.md Section 1)."
  type        = string
}

variable "private_app_subnet_cidr_az1" {
  description = "CIDR block for the private-application subnet in AZ index 0. Approved value: 10.20.11.0/24 -- this CIDR was already reserved (Dev_Environment_Terraform_Implementation_Plan.md Section 21) and is created by this module for the first time here."
  type        = string
}

variable "private_app_subnet_cidr_az2" {
  description = "CIDR block for the private-application subnet in AZ index 1. Approved value: 10.20.12.0/24."
  type        = string
}

variable "private_data_subnet_cidr_az1" {
  description = "CIDR block for the private-data subnet in AZ index 0. Approved value: 10.20.21.0/24 -- this CIDR was already reserved (Dev_Environment_Terraform_Implementation_Plan.md Section 21) and is created by this module for the first time here."
  type        = string
}

variable "private_data_subnet_cidr_az2" {
  description = "CIDR block for the private-data subnet in AZ index 1. Approved value: 10.20.22.0/24."
  type        = string
}

variable "enable_s3_gateway_endpoint" {
  description = "Whether to create the S3 Gateway VPC endpoint. Approved: true for Phase 0 (free, real existing S3 dependency -- Networking.md Section 4). Every other evaluated endpoint (DynamoDB Gateway, all interface endpoints) is deliberately NOT given its own toggle variable -- each is added individually, exactly when a real dependency exists, per ADR-0003."
  type        = bool
  default     = true
}

variable "enable_vpc_flow_logs" {
  description = "Whether to create VPC Flow Logs (CloudWatch Logs destination, its log group, and its delivery IAM role). Approved: true for Phase 0 (Networking.md Section 5)."
  type        = bool
  default     = true
}

variable "flow_log_retention_days" {
  description = "Retention period, in days, for the VPC Flow Logs CloudWatch Logs log group. Approved value: 30 (Networking.md Section 5) -- deliberately shorter than the CloudTrail log group's 90-day retention."
  type        = number
  default     = 30
}

variable "flow_log_traffic_type" {
  description = "Traffic type captured by VPC Flow Logs. Approved value: ALL, not REJECT-only (Networking.md Section 5)."
  type        = string
  default     = "ALL"

  validation {
    condition     = contains(["ACCEPT", "REJECT", "ALL"], var.flow_log_traffic_type)
    error_message = "flow_log_traffic_type must be one of: ACCEPT, REJECT, ALL."
  }
}

variable "flow_log_max_aggregation_interval" {
  description = "Maximum aggregation interval, in seconds, for VPC Flow Logs records. Approved value: 60 (the most granular option) -- Networking.md Section 5."
  type        = number
  default     = 60

  validation {
    condition     = contains([60, 600], var.flow_log_max_aggregation_interval)
    error_message = "flow_log_max_aggregation_interval must be 60 or 600 -- the only two values the VPC Flow Logs API accepts."
  }
}
