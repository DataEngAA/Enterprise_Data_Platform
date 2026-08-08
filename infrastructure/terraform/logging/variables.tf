# Variable declarations for the logging root module.
#
# Account-specific values (aws_account_id, cloudtrail_bucket_name,
# alert_email) have no default -- they must be supplied via a gitignored
# terraform.tfvars (see terraform.tfvars.example). No AWS account ID, ARN,
# bucket name, or email address is invented anywhere in this file.

variable "aws_region" {
  description = "AWS region this logging configuration operates in. Matches bootstrap/ and environments/dev."
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
    Resource-scope tag/name value for this root module. CloudTrail, the
    audit-log bucket, the CloudTrail-to-CloudWatch role, and the security
    SNS topic are all account-level, shared resources, not owned by any
    single deployment environment -- fixed to "shared", the same convention
    bootstrap/ uses for its own account-level resources
    (01_Architecture/Naming_Convention.md "Environment values").
  EOT
  type        = string
  default     = "shared"

  validation {
    condition     = var.environment == "shared"
    error_message = "This root module (logging) only manages account-level, shared resources and must use environment = \"shared\"."
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
  description = "Value for the required DataClassification tag (Naming_Convention.md). Audit logs are infrastructure/security records, not project data, so \"internal\" is the approved default -- matches bootstrap's own state-bucket classification."
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
    `allowed_account_ids` (providers.tf) and to construct the CloudTrail
    trail's ARN ahead of the trail's own creation (locals.tf), so the audit
    bucket's delivery policy can reference it without a resource cycle.
    Obtain with:
      aws sts get-caller-identity --query Account --output text
    See terraform.tfvars.example.
  EOT
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "aws_account_id must be exactly 12 digits (a real AWS account ID, not invented)."
  }
}

variable "cloudtrail_bucket_name" {
  description = <<-EOT
    Globally unique S3 bucket name for centralized CloudTrail log delivery.
    No default -- this is account-specific (S3 bucket names are globally
    unique across all AWS accounts, per 01_Architecture/Naming_Convention.md
    "S3 bucket naming pattern"). Recommended pattern:
      enterprise-data-platform-shared-cloudtrail-logs
    If that collides with an existing bucket name anywhere in AWS (cannot be
    verified without an AWS account), append a short account-ID-derived
    suffix, e.g. enterprise-data-platform-shared-cloudtrail-logs-<AWS_ACCOUNT_ID>.
    See terraform.tfvars.example.
  EOT
  type        = string

  validation {
    condition     = length(var.cloudtrail_bucket_name) > 0
    error_message = "cloudtrail_bucket_name must be supplied via terraform.tfvars -- see terraform.tfvars.example."
  }
}

variable "cloudtrail_s3_ia_transition_days" {
  description = "Days after object creation before transitioning to S3 Standard-IA (02_Infrastructure/Logging_and_Audit.md Section 2). AWS's own minimum for this transition is 30 days."
  type        = number
  default     = 30

  validation {
    condition     = var.cloudtrail_s3_ia_transition_days >= 30
    error_message = "S3 does not permit a Standard-IA transition sooner than 30 days after object creation."
  }
}

variable "cloudtrail_s3_glacier_transition_days" {
  description = "Days after object creation before transitioning to S3 Glacier (02_Infrastructure/Logging_and_Audit.md Section 2)."
  type        = number
  default     = 90

  validation {
    condition     = var.cloudtrail_s3_glacier_transition_days > var.cloudtrail_s3_ia_transition_days
    error_message = "The Glacier transition must occur after the Standard-IA transition."
  }
}

variable "cloudtrail_s3_expiration_days" {
  description = <<-EOT
    Days after object creation before the audit-log object is permanently
    expired (deleted) from S3 -- approved at 365 days for Phase 0
    (ADR-0002 Decision 4; 02_Infrastructure/Logging_and_Audit.md Section 2).
    THIS IS A PORTFOLIO-PROJECT PLACEHOLDER, NOT A COMPLIANCE-DERIVED
    NUMBER -- explicitly subject to revision during a future cost/governance
    or compliance-maturity phase (ADR-0002 "Conditions for Reconsideration").
  EOT
  type        = number
  default     = 365

  validation {
    condition     = var.cloudtrail_s3_expiration_days > var.cloudtrail_s3_glacier_transition_days
    error_message = "The expiration must occur after the Glacier transition."
  }
}

variable "cloudwatch_log_retention_days" {
  description = <<-EOT
    Retention period, in days, for the CloudTrail CloudWatch Logs log group.
    Approved at 90 days for Phase 0 (02_Infrastructure/Logging_and_Audit.md
    Section 3) -- deliberately shorter than the S3 retention above, since
    CloudWatch Logs exists for near-term searchability/alarming, not
    long-term audit-evidence storage. Must be one of the exact values the
    CloudWatch Logs API accepts for log group retention.
  EOT
  type        = number
  default     = 90

  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731,
      1096, 1827, 2192, 2557, 2922, 3288, 3653
    ], var.cloudwatch_log_retention_days)
    error_message = "cloudwatch_log_retention_days must be one of the exact values CloudWatch Logs accepts for log group retention (see the AWS provider documentation for aws_cloudwatch_log_group.retention_in_days)."
  }
}

variable "alert_email" {
  description = <<-EOT
    Email address that receives security-event alarm notifications via the
    SNS topic's email subscription (02_Infrastructure/Logging_and_Audit.md
    Section 5). No default -- account/operator-specific, never invented or
    committed. Supplying this value creates a PENDING subscription only --
    AWS requires a human to click the confirmation link delivered to this
    address; no Terraform or AWS API call can complete that confirmation.
    See terraform.tfvars.example.
  EOT
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.alert_email))
    error_message = "alert_email must look like a valid email address."
  }
}

variable "additional_tags" {
  description = "Optional additional resource-specific tags, merged with the required common tags computed in locals.tf. Leave empty ({}) if none are needed."
  type        = map(string)
  default     = {}
}
