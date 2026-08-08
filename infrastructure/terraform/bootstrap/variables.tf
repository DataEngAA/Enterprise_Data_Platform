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

# -----------------------------------------------------------------------
# NOTE (2026-08-07): a dev_workstation_instance_id variable previously lived
# here, for deployment_shared_cost_controls_permissions's own
# ec2:StopInstances grant (main.tf). Removed, along with the corresponding
# dev_workstation_instance_arn local (locals.tf), when that policy's
# ec2:StopInstances statement was removed -- the deployment role does not
# call ec2:StopInstances at all; only the dedicated EventBridge Scheduler
# execution role does (environments/dev/main.tf), scoped there to
# module.ec2_workstation.instance_id directly, which needs no separately
# supplied instance-ID variable in this stack. See main.tf's comment above
# deployment_shared_cost_controls_permissions for the full, corrected
# rationale.
# -----------------------------------------------------------------------

variable "dev_workstation_shutdown_scheduler_role_name" {
  description = "Name of the environments/dev EventBridge Scheduler execution IAM role for the automatic workstation-shutdown schedule (Naming_Convention.md IAM role pattern), used ONLY to scope deployment_shared_cost_controls_permissions's IAM-management and iam:PassRole statements (main.tf) to exactly this one role -- not to create the role itself, which remains environments/dev's own responsibility. Must match the role name environments/dev/main.tf actually creates. Fixed, non-account-specific naming-convention value, so a real default is given here."
  type        = string
  default     = "enterprise-data-platform-dev-workstation-shutdown-scheduler-role"
}

variable "cost_controls_budget_name" {
  description = "Name of the shared, account-wide AWS Budget managed by infrastructure/terraform/cost-controls/, used ONLY to scope deployment_shared_cost_controls_permissions's budgets:ViewBudget/ModifyBudget statement (main.tf) to this exact budget -- not to create the budget itself, which remains cost-controls/'s own responsibility. Must match the budget name cost-controls/main.tf actually creates. Fixed, non-account-specific naming-convention value."
  type        = string
  default     = "enterprise-data-platform-shared-monthly-budget"
}

variable "cost_controls_schedule_name" {
  description = "Name of the EventBridge Scheduler schedule (in the default schedule group) for the automatic workstation-shutdown schedule, used ONLY to scope deployment_shared_cost_controls_permissions's scheduler:* statement (main.tf) to this exact schedule -- not to create the schedule itself, which remains environments/dev's own responsibility. Must match the schedule name environments/dev/main.tf actually creates. Fixed, non-account-specific naming-convention value."
  type        = string
  default     = "enterprise-data-platform-dev-workstation-shutdown"
}

# -----------------------------------------------------------------------
# Added for the Phase 0 CI/CD Foundation implementation slice 1 task
# (2026-08-07) -- 02_Infrastructure/CI_CD.md, ADR-0006-cicd-foundation.md.
# None of these are account-specific in the sense variables.tf's own
# header comment warns against (no account ID, no ARN, no globally unique
# bucket name) -- they are either fixed, publicly documented AWS/GitHub
# OIDC integration values, or this project's own real, explicitly
# authorized GitHub repository identity, so real defaults are given here
# rather than requiring them via terraform.tfvars.
# -----------------------------------------------------------------------

variable "github_repository" {
  description = <<-EOT
    Exact GitHub organization/repository (in the form <org>/<repo>) this
    project's GitHub Actions OIDC trust is restricted to. Used ONLY to
    build the exact "sub" claim values
    data.aws_iam_policy_document.github_actions_trust (main.tf) checks via
    StringEquals -- no wildcard, no org-wide pattern, no other repository
    can ever satisfy that condition. Explicitly authorized value, not
    invented: DataEngAA/Enterprise_Data_Platform.
  EOT
  type        = string
  default     = "DataEngAA/Enterprise_Data_Platform"

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repository))
    error_message = "github_repository must be in the form <org>/<repo>."
  }
}

variable "github_owner_id" {
  description = <<-EOT
    GitHub's own immutable numeric ID for the var.github_repository owner
    (organization/user) -- NOT the org/user login name, which GitHub allows
    to be renamed. Used ONLY to build the immutable-subject-format "sub"
    claim values data.aws_iam_policy_document.github_actions_trust (main.tf)
    checks via StringEquals, per GitHub's current documented OIDC subject
    format (repo:<org>@<owner_id>/<repo>@<repo_id>:...) -- required because
    the legacy, login-name-only subject format
    (repo:<org>/<repo>:...) stopped satisfying GitHub's own token issuance
    for this repository, causing a real, observed
    "Not authorized to perform sts:AssumeRoleWithWebIdentity" failure on
    aws-actions/configure-aws-credentials@v4. Explicitly authorized value,
    not invented: 172183384 (DataEngAA's real, immutable GitHub owner ID).
  EOT
  type        = string
  default     = "172183384"

  validation {
    condition     = can(regex("^[0-9]+$", var.github_owner_id))
    error_message = "github_owner_id must be a numeric GitHub owner ID (digits only)."
  }
}

variable "github_repo_id" {
  description = <<-EOT
    GitHub's own immutable numeric ID for the var.github_repository
    repository -- NOT the repository name, which GitHub allows to be
    renamed. Used ONLY alongside var.github_owner_id to build the
    immutable-subject-format "sub" claim values (see var.github_owner_id's
    description for the full rationale). Explicitly authorized value, not
    invented: 1312536466 (the real, immutable GitHub repo ID for
    DataEngAA/Enterprise_Data_Platform).
  EOT
  type        = string
  default     = "1312536466"

  validation {
    condition     = can(regex("^[0-9]+$", var.github_repo_id))
    error_message = "github_repo_id must be a numeric GitHub repository ID (digits only)."
  }
}

variable "github_oidc_provider_hostname" {
  description = "Hostname of GitHub's OIDC token issuer for GitHub Actions -- a fixed, GitHub-documented value, not account-specific. Used to build both the OIDC provider's own URL (aws_iam_openid_connect_provider.github_actions, main.tf) and the exact condition-key names (\"<this value>:aud\", \"<this value>:sub\") IAM evaluates against GitHub's federated token."
  type        = string
  default     = "token.actions.githubusercontent.com"
}

variable "github_actions_oidc_audience" {
  description = "OIDC audience (\"client ID\") GitHub Actions presents when requesting a token scoped to authenticate into AWS -- the fixed, AWS-documented value for the AWS STS OIDC integration, not account-specific. Used both as the OIDC provider's client_id_list entry and as the exact value the trust policy's \"aud\" condition requires (main.tf)."
  type        = string
  default     = "sts.amazonaws.com"
}

variable "github_actions_environment_name" {
  description = <<-EOT
    Name of the protected GitHub Environment whose required-reviewer
    approval gate is the only way a workflow run can present a "sub" claim
    of the form repo:<github_repository>:environment:<this value> -- the
    only sub pattern this workstream's trust policy accepts for a run
    capable of eventually reaching a mutating deployment-role action once
    a future workflow implementation slice adds one
    (02_Infrastructure/CI_CD.md Section 3, Section 8). The GitHub
    Environment itself, and its required-reviewer configuration, is a
    GitHub-side setting -- not created, and not creatable, by this
    Terraform configuration.
  EOT
  type        = string
  default     = "aws-dev"
}

variable "github_actions_role_name" {
  description = "Name of the dedicated, near-empty external GitHub Actions OIDC workload-identity IAM role (Naming_Convention.md IAM role naming pattern, \"shared\" environment token since this is a project-wide, not environment-specific, resource -- CI_CD.md)."
  type        = string
  default     = "enterprise-data-platform-shared-github-actions-role"
}

variable "github_actions_role_max_session_duration" {
  description = "Maximum session duration, in seconds, for the GitHub Actions role. Kept at the same 1-hour default as the deployment role -- this role only ever needs enough time to make a single sts:AssumeRole call onto the deployment role, never to hold a long-lived session of its own."
  type        = number
  default     = 3600

  validation {
    condition     = var.github_actions_role_max_session_duration >= 3600 && var.github_actions_role_max_session_duration <= 43200
    error_message = "github_actions_role_max_session_duration must be between 3600 (1 hour, the approved default) and 43200 (12 hours, the IAM maximum)."
  }
}
