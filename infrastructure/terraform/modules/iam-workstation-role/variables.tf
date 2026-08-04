# Inputs for the workstation IAM identity module. deployment_role_arn has
# no default -- it is account-specific (the real ARN comes from the
# bootstrap root module's own output) and must never be invented here.

variable "environment" {
  description = "Deployment environment this role belongs to (e.g. \"dev\")."
  type        = string
}

variable "role_name" {
  description = "Name of the workstation IAM role, following Naming_Convention.md's IAM role pattern (<project>-<environment>-<role-purpose>-role). Approved dev value: enterprise-data-platform-dev-workstation-role."
  type        = string
}

variable "deployment_role_arn" {
  description = <<-EOT
    Exact ARN of the shared Terraform deployment role (created in
    infrastructure/terraform/bootstrap/, output as deployment_role_arn) that
    this workstation role is permitted to assume via sts:AssumeRole. No
    default -- account-specific, supplied by the caller (environments/dev),
    never hardcoded inside this module. The workstation role's inline
    AssumeRole policy is scoped to exactly this one ARN, no wildcard.
  EOT
  type        = string
}

variable "tags" {
  description = "Common tag map (Project, Environment, ManagedBy, Owner, CostCenter, DataClassification) computed by the caller's locals.tf."
  type        = map(string)
  default     = {}
}
