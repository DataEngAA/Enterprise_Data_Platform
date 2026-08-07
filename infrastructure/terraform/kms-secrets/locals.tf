# Computed, root-module-local values for the kms-secrets stack.

locals {
  # Required tags (Naming_Convention.md "Required tags"), same merge-order
  # correction already applied throughout this project (additional_tags
  # merged FIRST, required tags SECOND, so a key collision resolves to the
  # required value).
  common_tags = merge(
    var.additional_tags,
    {
      Project            = var.project_name
      Environment        = var.environment
      ManagedBy          = "terraform"
      Owner              = var.owner
      CostCenter         = var.cost_center
      DataClassification = var.data_classification
    }
  )

  # Tags for the two dev-scoped demonstration resources (KMS_and_Secrets.md
  # Section 10's flagged, deliberate scope mix) -- same merge order, but
  # Environment fixed to "dev" (not var.environment, which stays "shared"
  # for this module's own key/alias) and DataClassification using the
  # separate demo_data_classification variable.
  demo_tags = merge(
    var.additional_tags,
    {
      Project            = var.project_name
      Environment        = "dev"
      ManagedBy          = "terraform"
      Owner              = var.owner
      CostCenter         = var.cost_center
      DataClassification = var.demo_data_classification
    }
  )

  # Naming (01_Architecture/Naming_Convention.md).
  cmk_name  = "${var.project_name}-shared-cmk"
  cmk_alias = "alias/${var.project_name}-shared-primary"

  # Approved demonstration Secrets Manager secret name
  # (KMS_and_Secrets.md Section 13; naming pattern already approved in
  # IAM_and_Access.md's Secrets Manager access pattern:
  # <project>/<environment>/<component>/<purpose>).
  demo_secret_name = "${var.project_name}/dev/demo/ingestion-api"

  # Approved demonstration Parameter Store parameter name. Leading "/" per
  # SSM's own hierarchical-parameter naming convention (distinct from
  # Secrets Manager's no-leading-slash convention above) -- mirrors the
  # CloudWatch Logs log-group naming shape already used elsewhere in this
  # project (/<project>/<environment>/<component>), with an added "demo"
  # segment for this non-production, non-real-config placeholder.
  demo_parameter_name = "/${var.project_name}/dev/demo/ingestion-config"

  # Exact-ARN resource scopes used both here (for reference/consistency) and
  # in infrastructure/terraform/bootstrap/main.tf's new deployment-role
  # policy -- computed identically in both places from the same inputs,
  # since bootstrap/main.tf cannot reference this stack's own resource
  # attributes (separate root module, separate state).
  cmk_alias_arn = "arn:aws:kms:${var.aws_region}:${var.aws_account_id}:${local.cmk_alias}"

  # Secrets Manager appends a random 6-character suffix to every secret's
  # real ARN, even though the "name" itself is fully deterministic -- this
  # is Secrets Manager's own documented ARN convention, distinct from KMS's
  # and SSM's fully deterministic ARNs below. The trailing "-*" is required
  # for any IAM resource-scope statement to match the real, deployed secret.
  demo_secret_arn_pattern = "arn:aws:secretsmanager:${var.aws_region}:${var.aws_account_id}:secret:${local.demo_secret_name}-*"

  # SSM parameter ARNs are fully deterministic from the parameter name --
  # no random suffix, unlike Secrets Manager above.
  demo_parameter_arn = "arn:aws:ssm:${var.aws_region}:${var.aws_account_id}:parameter${local.demo_parameter_name}"
}
