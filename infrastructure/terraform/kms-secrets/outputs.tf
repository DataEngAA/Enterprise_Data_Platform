# Outputs -- non-secret operational identifiers only. No secret value,
# SecureString plaintext, or key-policy JSON is output.

output "kms_key_id" {
  description = "ID of the shared customer-managed KMS key."
  value       = aws_kms_key.this.key_id
}

output "kms_key_arn" {
  description = "ARN of the shared customer-managed KMS key."
  value       = aws_kms_key.this.arn
}

output "kms_key_alias_name" {
  description = "Alias name of the shared customer-managed KMS key (alias/enterprise-data-platform-shared-primary)."
  value       = aws_kms_alias.this.name
}

output "kms_key_alias_arn" {
  description = "ARN of the KMS key alias."
  value       = aws_kms_alias.this.arn
}

output "demo_secret_name" {
  description = "Name of the demonstration Secrets Manager secret (metadata only -- no value/version exists via Terraform)."
  value       = aws_secretsmanager_secret.demo.name
}

output "demo_secret_arn" {
  description = "ARN of the demonstration Secrets Manager secret."
  value       = aws_secretsmanager_secret.demo.arn
}

output "demo_parameter_name" {
  description = "Name of the demonstration Parameter Store parameter (String type -- non-sensitive)."
  value       = aws_ssm_parameter.demo.name
}

output "demo_parameter_arn" {
  description = "ARN of the demonstration Parameter Store parameter."
  value       = aws_ssm_parameter.demo.arn
}
