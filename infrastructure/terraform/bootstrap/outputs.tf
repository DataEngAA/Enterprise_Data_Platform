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
