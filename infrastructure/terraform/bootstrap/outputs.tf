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
  description = "ARN of the Terraform deployment IAM role. This role currently has NO permissions policy attached (main.tf) -- it exists only with its trust policy. Needed as a future input when configuring environments/dev's provider assume_role block, when attaching that future permissions policy, and when updating this role's trust policy to add the workstation role (all future, separately authorized tasks)."
  value       = aws_iam_role.deployment.arn
}
