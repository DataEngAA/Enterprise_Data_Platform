# Variable declarations for the kms-secrets root module.
#
# Account-specific values (aws_account_id, deployment_role_arn) have NO
# default -- they must be supplied via a gitignored terraform.tfvars (see
# terraform.tfvars.example). No AWS account ID or role ARN is invented
# anywhere in this file.

variable "aws_region" {
  description = "AWS region this configuration operates in. Matches bootstrap/, environments/dev, and logging/."
  type        = string
  default     = "ap-south-1"
}

variable "project_name" {
  description = "Project identifier used as the base token in resource names and tags (01_Architecture/Naming_Convention.md)."
  type        = string
  default     = "enterprise-data-platform"
}

variable "environment" {
  description = <<-EOT
    Resource-scope tag/name value for this root module's OWN, shared-scope
    resources (the KMS key and its alias) -- fixed to "shared", the same
    convention bootstrap/ and logging/ use for their own account-level
    resources (01_Architecture/Naming_Convention.md "Environment values").
    Deliberately does NOT govern the demonstration Secrets Manager secret or
    Parameter Store parameter created in this same stack -- both are
    dev-scoped by design (KMS_and_Secrets.md Section 10's flagged,
    deliberate scope mix) and use a separate, fixed "dev" value in
    locals.tf, not this variable.
  EOT
  type        = string
  default     = "shared"

  validation {
    condition     = var.environment == "shared"
    error_message = "This root module's own KMS key/alias are shared-scope resources and must use environment = \"shared\"."
  }
}

variable "owner" {
  description = "Value for the required Owner tag (Naming_Convention.md)."
  type        = string
  default     = "DataEngAA"
}

variable "cost_center" {
  description = "Value for the required CostCenter tag (Naming_Convention.md)."
  type        = string
  default     = "personal-learning"
}

variable "data_classification" {
  description = "Value for the required DataClassification tag (Naming_Convention.md) on the KMS key itself. The key is infrastructure that protects classified data, not classified data itself -- \"internal\" is the approved default, matching bootstrap's own state-bucket and logging's own audit-bucket classification. A judgment call, recorded as such in KMS_and_Secrets.md Section 2."
  type        = string
  default     = "internal"

  validation {
    condition     = contains(["public", "internal", "confidential", "restricted"], var.data_classification)
    error_message = "data_classification must be one of: public, internal, confidential, restricted (Naming_Convention.md required tags)."
  }
}

variable "demo_data_classification" {
  description = "Value for the required DataClassification tag on the demonstration Secrets Manager secret and Parameter Store parameter -- distinct from the KMS key's own classification, since these are (nominally) credential-bearing resource types even though this task creates no real secret value (KMS_and_Secrets.md Section 13). \"confidential\" is the approved default."
  type        = string
  default     = "confidential"

  validation {
    condition     = contains(["public", "internal", "confidential", "restricted"], var.demo_data_classification)
    error_message = "demo_data_classification must be one of: public, internal, confidential, restricted (Naming_Convention.md required tags)."
  }
}

variable "aws_account_id" {
  description = <<-EOT
    12-digit AWS account ID this configuration is expected to run against.
    No default -- account-specific. Used to configure the AWS provider's
    `allowed_account_ids` (providers.tf) and to construct exact-ARN resource
    scopes in locals.tf. Obtain with:
      aws sts get-caller-identity --query Account --output text
    See terraform.tfvars.example.
  EOT
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "aws_account_id must be exactly 12 digits (a real AWS account ID, not invented)."
  }
}

variable "deployment_role_arn" {
  description = <<-EOT
    Exact ARN of the shared Terraform deployment role (infrastructure/
    terraform/bootstrap/, output as deployment_role_arn). No default --
    account-specific. Used by BOTH backend.hcl's own assume_role block
    (state access) and this file's provider assume_role block
    (resource-management API calls) -- two functionally separate
    AssumeRole calls against the SAME role, matching
    environments/dev/variables.tf's identical pattern.
  EOT
  type        = string

  validation {
    condition     = can(regex("^arn:aws:iam::[0-9]{12}:role/.+$", var.deployment_role_arn))
    error_message = "deployment_role_arn must be an IAM role ARN of the form arn:aws:iam::<12-digit-account-id>:role/<role-name>."
  }
}

variable "additional_tags" {
  description = "Optional additional resource-specific tags, merged with the required common tags computed in locals.tf. Leave empty ({}) if none are needed."
  type        = map(string)
  default     = {}
}
