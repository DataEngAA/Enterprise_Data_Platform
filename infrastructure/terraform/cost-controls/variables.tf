# Variable declarations for the cost-controls root module.
#
# Account-specific values (aws_account_id, deployment_role_arn,
# sns_topic_arn) have NO default -- they must be supplied via a gitignored
# terraform.tfvars (see terraform.tfvars.example). No AWS account ID, ARN,
# or topic is invented anywhere in this file.

variable "aws_region" {
  description = "AWS region this configuration operates in. Matches bootstrap/, environments/dev, logging/, and kms-secrets/."
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
    Resource-scope tag/name value for this root module. The AWS Budget
    managed here is a genuinely shared, account-wide resource, not owned by
    any single deployment environment -- same convention bootstrap/,
    logging/, and kms-secrets/ use for their own account-level resources
    (01_Architecture/Naming_Convention.md "Environment values").
  EOT
  type        = string
  default     = "shared"

  validation {
    condition     = var.environment == "shared"
    error_message = "This root module's own resources (the account-wide AWS Budget) are shared-scope and must use environment = \"shared\"."
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
  description = "Value for the required DataClassification tag (Naming_Convention.md). The budget is infrastructure/cost-governance configuration, not data -- \"internal\" is the approved default, matching every other account-level infrastructure resource in this project."
  type        = string
  default     = "internal"

  validation {
    condition     = contains(["public", "internal", "confidential", "restricted"], var.data_classification)
    error_message = "data_classification must be one of: public, internal, confidential, restricted (Naming_Convention.md required tags)."
  }
}

variable "aws_account_id" {
  description = <<-EOT
    12-digit AWS account ID this configuration is expected to run against.
    No default -- account-specific. Used to configure the AWS provider's
    `allowed_account_ids` (providers.tf). Obtain with:
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
    AssumeRole calls against the SAME role, matching every other
    assume_role-routed stack's identical pattern. Requires
    bootstrap/main.tf's new deployment_shared_cost_controls_permissions
    policy to already be applied before this configuration's provider/
    backend can do anything useful with it.
  EOT
  type        = string

  validation {
    condition     = can(regex("^arn:aws:iam::[0-9]{12}:role/.+$", var.deployment_role_arn))
    error_message = "deployment_role_arn must be an IAM role ARN of the form arn:aws:iam::<12-digit-account-id>:role/<role-name>."
  }
}

# -----------------------------------------------------------------------
# Approved design (10_Cost_and_FinOps/Cost_Controls.md Section 1): reuse
# the EXISTING Logging and Audit Foundation SNS topic for budget
# notifications rather than creating a second topic. No default -- the real
# ARN is account-specific and not deterministic from any naming convention
# alone (obtain it from infrastructure/terraform/logging's own
# security_alerts_topic_arn output), so it must be supplied via
# terraform.tfvars, the same pattern already used for aws_account_id and
# deployment_role_arn above.
# -----------------------------------------------------------------------

variable "sns_topic_arn" {
  description = <<-EOT
    Exact ARN of the EXISTING Logging and Audit Foundation SNS
    security-alert topic (infrastructure/terraform/logging/, output as
    security_alerts_topic_arn). No default -- account-specific. This stack
    does NOT create a new SNS topic; budget notifications are routed
    through this existing, already-validated topic
    (10_Cost_and_FinOps/Cost_Controls.md Section 1). Obtain with:
      terraform output -raw security_alerts_topic_arn
    (run from infrastructure/terraform/logging/).
  EOT
  type        = string

  validation {
    condition     = can(regex("^arn:aws:sns:[a-z0-9-]+:[0-9]{12}:.+$", var.sns_topic_arn))
    error_message = "sns_topic_arn must be a real SNS topic ARN of the form arn:aws:sns:<region>:<12-digit-account-id>:<topic-name> -- the existing Logging and Audit topic, not invented or newly created."
  }
}

# -----------------------------------------------------------------------
# Budget design (10_Cost_and_FinOps/Cost_Controls.md Sections 1-2). Real,
# literal defaults are given below because these values are already
# reasoned, user-confirmed, and unchanged from the existing manually
# created budget this stack replaces -- not account-specific placeholders.
# -----------------------------------------------------------------------

variable "budget_name" {
  description = "Name of the shared, account-wide AWS Budget. Must match bootstrap/main.tf's cost_controls_budget_name variable (which scopes the deployment role's budgets:ViewBudget/ModifyBudget grant to exactly this name) -- kept as two separately supplied, matching defaults rather than a cross-stack reference, since this project's convention is tfvars-supplied values, not terraform_remote_state data sources between independent stacks."
  type        = string
  default     = "enterprise-data-platform-shared-monthly-budget"
}

variable "budget_limit_amount_usd" {
  description = "Monthly budget ceiling in USD. Approved, unchanged value from the existing manually created budget (10_Cost_and_FinOps/Cost.md)."
  type        = string
  default     = "30"
}

variable "budget_actual_thresholds_usd" {
  description = "Actual-spend alert thresholds, in USD, ABSOLUTE_VALUE (not percentage). Approved, unchanged four-rung ladder from the existing manually created budget (Cost_Controls.md Section 2): early warning, serious warning, hard attention threshold, ceiling reached."
  type        = list(number)
  default     = [5, 15, 24, 30]

  validation {
    condition     = length(var.budget_actual_thresholds_usd) > 0
    error_message = "budget_actual_thresholds_usd must contain at least one threshold."
  }
}

variable "budget_forecasted_threshold_usd" {
  description = "Forecasted-spend alert threshold, in USD, ABSOLUTE_VALUE. Approved, unchanged value from the existing manually created budget: fires when AWS's own trend projection says the month will end over this amount, independent of and potentially earlier than any actual-spend threshold above."
  type        = number
  default     = 30
}

variable "additional_tags" {
  description = "Optional additional resource-specific tags, merged with the required common tags computed in locals.tf. Leave empty ({}) if none are needed."
  type        = map(string)
  default     = {}
}
