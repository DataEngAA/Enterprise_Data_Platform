# Variable declarations for the bootstrap root module.
#
# Account-specific values (aws_account_id, state_bucket_name,
# human_bootstrap_principal_arn) have no default -- they must be supplied
# via a gitignored terraform.tfvars (see terraform.tfvars.example). No AWS
# account ID, ARN, or globally unique bucket name is invented anywhere in
# this file.

variable "aws_region" {
  description = "AWS region this bootstrap configuration operates in."
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
    Resource-scope tag/name value for this root module. This bootstrap
    configuration only ever manages account-level, project-wide resources
    (the Terraform state bucket and the Terraform deployment role) that are
    not owned by any single deployment environment, so this is fixed to
    "shared" -- a resource-scope tag value, NOT a fifth deployment
    environment (Naming_Convention.md "Environment values", corrected
    2026-07-25). Deployment-environment-scoped resources (dev/test/stage/
    prod) belong in a future environments/<environment>/ root module, not
    in this one.
  EOT
  type        = string
  default     = "shared"

  validation {
    condition     = var.environment == "shared"
    error_message = "This root module (bootstrap) only manages account-level, project-wide resources and must use environment = \"shared\"."
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
  description = "Value for the required DataClassification tag (Naming_Convention.md). Bootstrap resources are infrastructure, not data, so \"internal\" is the approved default."
  type        = string
  default     = "internal"

  validation {
    condition     = contains(["public", "internal", "confidential", "restricted"], var.data_classification)
    error_message = "data_classification must be one of: public, internal, confidential, restricted (Naming_Convention.md required tags)."
  }
}

variable "aws_account_id" {
  description = <<-EOT
    12-digit AWS account ID this bootstrap configuration is expected to run
    against. No default -- account-specific. Used to configure the AWS
    provider's `allowed_account_ids` (providers.tf): the provider checks
    the active credentials' account via AWS STS during provider
    configuration and prevents any resource-management operation
    (plan/apply against any resource here) if it does not match, rather
    than silently operating against an unapproved account. Not invented
    here -- obtain with:
      aws sts get-caller-identity --query Account --output text
    See terraform.tfvars.example.
  EOT
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "aws_account_id must be exactly 12 digits (a real AWS account ID, not invented)."
  }
}

variable "state_bucket_name" {
  description = <<-EOT
    Globally unique S3 bucket name for Terraform remote state. No default
    -- this is account-specific and must be supplied via terraform.tfvars
    (gitignored, never committed). Recommended pattern
    (Terraform_Bootstrap_Design.md Section 7):
      enterprise-data-platform-tfstate-<AWS_ACCOUNT_ID>
    Obtain your account ID with:
      aws sts get-caller-identity --query Account --output text
    See terraform.tfvars.example.
  EOT
  type        = string

  validation {
    condition     = length(var.state_bucket_name) > 0
    error_message = "state_bucket_name must be supplied via terraform.tfvars -- see terraform.tfvars.example."
  }
}

variable "human_bootstrap_principal_arn" {
  description = <<-EOT
    ARN of the human bootstrap principal that runs this bootstrap apply and
    is the sole principal trusted by the deployment role's trust policy
    (main.tf). No default -- account-specific. Obtain with:
      aws sts get-caller-identity --query Arn --output text

    Scope of this implementation (corrected 2026-07-25 static review): this
    trust-policy design currently supports an IAM USER only, in the form
      arn:aws:iam::<12-digit-account-id>:user/<user-name>
    IAM Identity Center identities and other STS assumed-role ARNs
    (arn:aws:sts::...:assumed-role/...) are NOT supported by this
    configuration's trust policy as written -- an assumed-role session's
    effective principal ARN does not match a static IAM user ARN, so
    trusting one here would not work as intended. Federated/IAM Identity
    Center support is deliberately deferred to a future, separate
    trust-policy design (see README.md "Prerequisites"), not silently
    assumed to already work.
    See terraform.tfvars.example.
  EOT
  type        = string

  validation {
    condition     = can(regex("^arn:aws:iam::[0-9]{12}:user/.+$", var.human_bootstrap_principal_arn))
    error_message = "human_bootstrap_principal_arn must be an IAM user ARN of the form arn:aws:iam::<12-digit-account-id>:user/<user-name> -- IAM Identity Center / STS assumed-role ARNs are not supported by this trust-policy design yet."
  }
}

variable "deployment_role_name" {
  description = "Name of the Terraform deployment IAM role (Naming_Convention.md IAM role naming pattern: <project>-<environment>-deployment-role, corrected 2026-07-25 to use the \"shared\" environment token since this role is project-wide, not dev-specific)."
  type        = string
  default     = "enterprise-data-platform-shared-deployment-role"
}

variable "deployment_role_max_session_duration" {
  description = "Maximum session duration, in seconds, for the deployment role. Approved value: 1 hour / 3600 seconds (Terraform_Bootstrap_Design.md Sections 21, 23)."
  type        = number
  default     = 3600

  validation {
    condition     = var.deployment_role_max_session_duration >= 3600 && var.deployment_role_max_session_duration <= 43200
    error_message = "deployment_role_max_session_duration must be between 3600 (1 hour, the approved value) and 43200 (12 hours, the IAM maximum)."
  }
}

variable "additional_tags" {
  description = "Optional additional resource-specific tags, merged with the required common tags computed in locals.tf. Leave empty ({}) if none are needed."
  type        = map(string)
  default     = {}
}

# -----------------------------------------------------------------------
# Added for Bootstrap Update 1 (Dev_Environment_Terraform_Implementation_
# Plan.md Section 11) -- the deployment role's dev-scoped permissions
# policy needs to reference the exact workstation-role/instance-profile
# name it is permitted to create/manage. Not account-specific -- this is a
# fixed, approved naming-convention value, so a real default is given here
# rather than requiring it via terraform.tfvars.
# -----------------------------------------------------------------------

variable "dev_workstation_role_name" {
  description = <<-EOT
    Name of the environments/dev workstation IAM role and its instance
    profile (Naming_Convention.md IAM role pattern), used ONLY to scope the
    deployment role's dev-permissions policy (main.tf) to exactly this one
    role/instance-profile name -- not to create the role itself, which
    remains environments/dev's own responsibility. Must match the role_name
    passed into modules/iam-workstation-role from environments/dev/main.tf.
  EOT
  type        = string
  default     = "enterprise-data-platform-dev-workstation-role"
}
