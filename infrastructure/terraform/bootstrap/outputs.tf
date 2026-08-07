# Outputs -- identifiers only. No secrets, credentials, or policy documents
# are output.

output "state_bucket_name" {
  description = "Name of the Terraform remote-state S3 bucket created by this configuration."
  value       = aws_s3_bucket.terraform_state.bucket
}

output "state_bucket_arn" {
  description = "ARN of the Terraform remote-state S3 bucket."
  value       = aws_s3_bucket.terraform_state.arn
}

output "deployment_role_name" {
  description = "Name of the Terraform deployment IAM role."
  value       = aws_iam_role.deployment.name
}

output "deployment_role_arn" {
  description = "ARN of the Terraform deployment IAM role. main.tf defines three dev-scoped managed permissions policies for this role (aws_iam_policy.deployment_dev_permissions, non-networking/non-workstation-IAM; aws_iam_policy.deployment_dev_networking_permissions, networking; and aws_iam_policy.deployment_dev_workstation_iam_permissions, workstation IAM role/instance-profile/PassRole -- split 2026-07-26 in two stages: first a two-policy split after a real iam:CreatePolicyVersion size-quota failure against the original single combined policy, then a second split of the resulting non-networking policy after its own lifecycle.precondition reported 6212 characters against the 6144 quota). The REAL, deployed role in AWS reflects whatever the most recent successful real apply produced -- neither size-quota-triggered split involved any successful AWS change prior to a future real apply (the first was caught by a failed CreatePolicyVersion call, which makes no AWS change at all; the second was caught entirely at plan time by a lifecycle.precondition, before any AWS API call was made). Needed as an input for environments/dev's own provider and backend assume_role blocks, and later for Bootstrap Update 2's trust-policy addition (a separate, later, reviewed change)."
  value       = aws_iam_role.deployment.arn
}

output "deployment_dev_permissions_policy_arn" {
  description = "ARN of the non-networking, non-workstation-IAM dev-scoped managed policy (dev Terraform state/lock access, EC2 read-only Describe, RunInstances + instance/volume lifecycle, instance metadata options, RunInstances tag-on-create). Split out on 2026-07-26; further split the same day (workstation-IAM statements moved to aws_iam_policy.deployment_dev_workstation_iam_permissions) after this document's own lifecycle.precondition reported it was still over the size quota -- see main.tf's comment block above data.aws_iam_policy_document.deployment_dev_permissions."
  value       = aws_iam_policy.deployment_dev_permissions.arn
}

output "deployment_dev_networking_permissions_policy_arn" {
  description = "ARN of the networking dev-scoped managed policy (VPC/subnet/Internet-Gateway/route-table/security-group create + manage, security-group egress rules, networking CreateTags/DeleteTags). Created 2026-07-26 as part of the first size-quota-failure split -- see main.tf's comment block above data.aws_iam_policy_document.deployment_dev_permissions. Unaffected by the second (workstation-IAM) split."
  value       = aws_iam_policy.deployment_dev_networking_permissions.arn
}

output "deployment_dev_workstation_iam_permissions_policy_arn" {
  description = "ARN of the dev-workstation-IAM-scoped managed policy (dev workstation IAM role/instance-profile creation-management, and PassRole restricted to iam:PassedToService = ec2.amazonaws.com), scoped to exactly the dev workstation role/instance-profile name. Created 2026-07-26 as part of the SECOND size-quota-failure split, after aws_iam_policy.deployment_dev_permissions's own lifecycle.precondition reported its rendered JSON (6212 characters) exceeded the 6144-character quota by 68 characters -- caught entirely at plan time, no AWS command run, no AWS change occurred. See main.tf's comment block above data.aws_iam_policy_document.deployment_dev_permissions."
  value       = aws_iam_policy.deployment_dev_workstation_iam_permissions.arn
}

output "deployment_dev_permissions_policy_json_length" {
  description = "Real, Terraform-computed length (characters) of the non-networking, non-workstation-IAM policy's compact rendered JSON -- a close proxy for, not a guaranteed exact match to, AWS's own managed-policy size-quota count (currently 6144 characters, not counting whitespace). Not an estimate: this is length(data.aws_iam_policy_document.deployment_dev_permissions.json), the exact string Terraform submits to AWS. This exact value (6212, pre-workstation-IAM-split) is what the lifecycle.precondition on aws_iam_policy.deployment_dev_permissions used to catch the second size-quota failure at plan time."
  value       = local.deployment_dev_permissions_json_length
}

output "deployment_dev_networking_permissions_policy_json_length" {
  description = "Real, Terraform-computed length (characters) of the networking policy's compact rendered JSON -- see deployment_dev_permissions_policy_json_length's description for the same caveat and provenance."
  value       = local.deployment_dev_networking_permissions_json_length
}

output "deployment_dev_workstation_iam_permissions_policy_json_length" {
  description = "Real, Terraform-computed length (characters) of the workstation-IAM policy's compact rendered JSON -- see deployment_dev_permissions_policy_json_length's description for the same caveat and provenance."
  value       = local.deployment_dev_workstation_iam_permissions_json_length
}

output "runtime_role_permission_boundary_policy_arn" {
  description = "ARN of the project-wide (shared) IAM permission boundary for future runtime roles (Lambda/Step Functions v1 scope). Added 2026-08-04 as the first approved Phase 0 IAM Foundation Terraform task -- see 02_Infrastructure/IAM_and_Access.md 'Permission Boundary -- Version 1 Specification' and ADR-0001. Not yet attached to any runtime role -- modules/iam-runtime-role does not exist yet."
  value       = aws_iam_policy.runtime_role_permission_boundary.arn
}

output "runtime_role_permission_boundary_policy_json_length" {
  description = "Real, Terraform-computed length (characters) of the permission boundary's compact rendered JSON -- see deployment_dev_permissions_policy_json_length's description for the same caveat and provenance."
  value       = local.runtime_role_permission_boundary_json_length
}

output "deployment_dev_runtime_iam_permissions_policy_arn" {
  description = "ARN of the deployment role's new, narrowly scoped runtime-role lifecycle managed policy (create/read/manage/delete/attach/PassRole for the 'enterprise-data-platform-dev-runtime-*' role pattern only, boundary-enforced on creation, with an explicit Deny guardrail naming the deployment and workstation roles). Added 2026-08-04 -- see 02_Infrastructure/IAM_and_Access.md 'Runtime-Role Lifecycle -- Version 1' and ADR-0001."
  value       = aws_iam_policy.deployment_dev_runtime_iam_permissions.arn
}

output "deployment_dev_runtime_iam_permissions_policy_json_length" {
  description = "Real, Terraform-computed length (characters) of the runtime-role lifecycle policy's compact rendered JSON -- see deployment_dev_permissions_policy_json_length's description for the same caveat and provenance."
  value       = local.deployment_dev_runtime_iam_permissions_json_length
}

output "deployment_dev_networking_observability_permissions_policy_arn" {
  description = "ARN of the deployment role's new, narrowly scoped managed policy covering the S3 Gateway VPC endpoint, VPC Flow Logs, the Flow Logs CloudWatch Logs log group, and the Flow Logs delivery IAM role (exact-ARN-scoped, not a wildcard pattern). Added 2026-08-07 -- see 02_Infrastructure/Networking.md Section 5 and the Phase 0 Networking Hardening remaining-resource authorization gap record in PROJECT_EXECUTION_JOURNAL.md."
  value       = aws_iam_policy.deployment_dev_networking_observability_permissions.arn
}

output "deployment_dev_networking_observability_permissions_policy_json_length" {
  description = "Real, Terraform-computed length (characters) of the networking-observability policy's compact rendered JSON -- see deployment_dev_permissions_policy_json_length's description for the same caveat and provenance."
  value       = local.deployment_dev_networking_observability_permissions_json_length
}

output "deployment_shared_kms_secrets_permissions_policy_arn" {
  description = "ARN of the deployment role's new, narrowly scoped managed policy covering KMS key/alias lifecycle, Secrets Manager secret metadata (never GetSecretValue/PutSecretValue), and Parameter Store parameter lifecycle for the exact demonstration resources infrastructure/terraform/kms-secrets/ creates. Added 2026-08-07 -- see 02_Infrastructure/KMS_and_Secrets.md and ADR-0004."
  value       = aws_iam_policy.deployment_shared_kms_secrets_permissions.arn
}

output "deployment_shared_kms_secrets_permissions_policy_json_length" {
  description = "Real, Terraform-computed length (characters) of the KMS/Secrets/Parameter Store policy's compact rendered JSON -- see deployment_dev_permissions_policy_json_length's description for the same caveat and provenance."
  value       = local.deployment_shared_kms_secrets_permissions_json_length
}

output "deployment_shared_cost_controls_permissions_policy_arn" {
  description = "ARN of the deployment role's new, narrowly scoped managed policy covering AWS Budgets (ViewBudget/ModifyBudget on the one exact budget), EventBridge Scheduler lifecycle/tagging (on the one exact schedule), the scheduler execution role's IAM lifecycle (on the one exact role), a PassRole grant conditioned to scheduler.amazonaws.com, and ec2:StopInstances scoped to the one, real, already-existing dev workstation instance. Added 2026-08-07 -- see 10_Cost_and_FinOps/Cost_Controls.md and ADR-0005."
  value       = aws_iam_policy.deployment_shared_cost_controls_permissions.arn
}

output "deployment_shared_cost_controls_permissions_policy_json_length" {
  description = "Real, Terraform-computed length (characters) of the Cost Controls policy's compact rendered JSON -- see deployment_dev_permissions_policy_json_length's description for the same caveat and provenance."
  value       = local.deployment_shared_cost_controls_permissions_json_length
}

output "deployment_shared_cost_controls_state_permissions_policy_arn" {
  description = "ARN of the deployment role's dedicated managed policy covering ONLY cost-controls Terraform remote-state access (s3:ListBucket prefix-scoped to cost-controls/terraform.tfstate*, GetObject/PutObject on the exact state object, GetObject/PutObject/DeleteObject on the exact lock object). Split out 2026-08-07 from deployment_dev_permissions after a real terraform plan reported that policy's rendered JSON (6715 characters) exceeded the 6144-character quota -- caught entirely at plan time by that policy's own lifecycle.precondition, no AWS command run, no AWS change occurred. See 10_Cost_and_FinOps/Cost_Controls.md and ADR-0005."
  value       = aws_iam_policy.deployment_shared_cost_controls_state_permissions.arn
}

output "deployment_shared_cost_controls_state_permissions_policy_json_length" {
  description = "Real, Terraform-computed length (characters) of the cost-controls state-access policy's compact rendered JSON -- see deployment_dev_permissions_policy_json_length's description for the same caveat and provenance."
  value       = local.deployment_shared_cost_controls_state_permissions_json_length
}

# Added for the Phase 0 CI/CD Foundation implementation slice 1 task
# (2026-08-07) -- 02_Infrastructure/CI_CD.md, ADR-0006-cicd-foundation.md.
# Identifiers only, matching this file's own header comment -- no trust
# policy document, no condition-key values, and no repository identity are
# reproduced here (those are already visible in main.tf/variables.tf
# source, not secret, but not duplicated in outputs for their own sake).

output "github_oidc_provider_arn" {
  description = "ARN of the GitHub Actions OIDC identity provider (token.actions.githubusercontent.com). Needed as an input for any future workflow-file-authoring task's own documentation/verification, and for a real `aws iam get-open-id-connect-provider` confirmation after apply."
  value       = aws_iam_openid_connect_provider.github_actions.arn
}

output "github_actions_role_arn" {
  description = "ARN of the dedicated, near-empty external GitHub Actions OIDC workload-identity role (enterprise-data-platform-shared-github-actions-role). This is the ARN a future GitHub Actions workflow file's own `role-to-assume` input would reference -- not created by this task."
  value       = aws_iam_role.github_actions.arn
}

output "github_actions_role_name" {
  description = "Name of the GitHub Actions OIDC workload-identity role."
  value       = aws_iam_role.github_actions.name
}

output "github_actions_permissions_policy_arn" {
  description = "ARN of the GitHub Actions role's own minimal permissions policy (sts:AssumeRole on the deployment role's exact ARN only)."
  value       = aws_iam_policy.github_actions_permissions.arn
}

output "deployment_dev_default_sg_adoption_permissions_policy_arn" {
  description = "ARN of the deployment role's dedicated managed policy covering ONLY default-security-group adoption (ec2:RevokeSecurityGroupIngress/RevokeSecurityGroupEgress/CreateTags/DeleteTags), scoped to the exact, real, already-existing default security group for the dev VPC (arn:aws:ec2:ap-south-1:732264765658:security-group/sg-043396862de555680), deliberately without any aws:ResourceTag condition (the default SG carries no tags before this first adoption). Split out 2026-08-07 from deployment_dev_networking_permissions after a real terraform plan reported that policy's rendered JSON (6282 characters) exceeded the 6144-character quota -- caught entirely at plan time by that policy's own lifecycle.precondition, no AWS command run, no AWS change occurred. See 16_Implementation_Notes/Checkov_Triage_CI_CD_Slice_2A.md's CKV2_AWS_12 entry."
  value       = aws_iam_policy.deployment_dev_default_sg_adoption_permissions.arn
}

output "deployment_dev_default_sg_adoption_permissions_policy_json_length" {
  description = "Real, Terraform-computed length (characters) of the default-security-group-adoption policy's compact rendered JSON -- see deployment_dev_permissions_policy_json_length's description for the same caveat and provenance."
  value       = local.deployment_dev_default_sg_adoption_permissions_json_length
}
