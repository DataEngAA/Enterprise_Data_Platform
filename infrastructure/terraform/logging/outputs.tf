# Outputs -- identifiers only. No secrets, credentials, or policy documents
# are output.

output "cloudtrail_arn" {
  description = "ARN of the CloudTrail trail (constructed value, see locals.tf; matches the real resource's ARN once applied)."
  value       = aws_cloudtrail.this.arn
}

output "cloudtrail_name" {
  description = "Name of the CloudTrail trail."
  value       = aws_cloudtrail.this.name
}

output "cloudtrail_bucket_name" {
  description = "Name of the dedicated, hardened S3 bucket CloudTrail delivers logs to."
  value       = aws_s3_bucket.cloudtrail.bucket
}

output "cloudtrail_bucket_arn" {
  description = "ARN of the dedicated CloudTrail S3 bucket."
  value       = aws_s3_bucket.cloudtrail.arn
}

output "cloudtrail_log_group_name" {
  description = "Name of the CloudWatch Logs log group CloudTrail publishes to."
  value       = aws_cloudwatch_log_group.cloudtrail.name
}

output "cloudtrail_log_group_arn" {
  description = "ARN of the CloudTrail CloudWatch Logs log group."
  value       = aws_cloudwatch_log_group.cloudtrail.arn
}

output "cloudtrail_cloudwatch_role_arn" {
  description = "ARN of the least-privilege IAM role CloudTrail assumes to publish to CloudWatch Logs."
  value       = aws_iam_role.cloudtrail_cloudwatch.arn
}

output "security_alerts_topic_arn" {
  description = "ARN of the SNS topic security-event alarms publish to."
  value       = aws_sns_topic.security_alerts.arn
}

output "security_alerts_subscription_arn" {
  description = "ARN of the email subscription to the security-alerts SNS topic. Remains in PendingConfirmation state until a human clicks the confirmation link delivered to var.alert_email."
  value       = aws_sns_topic_subscription.security_alerts_email.arn
}

output "cis_alarm_names" {
  description = "Names of the 7 approved security-event metric filter/alarm pairs created via modules/cis-alarm."
  value       = [for k, v in module.cis_alarms : k]
}

output "cis_alarm_arns" {
  description = "ARNs of the 7 approved security-event CloudWatch alarms, keyed by alarm name."
  value       = { for k, v in module.cis_alarms : k => v.alarm_arn }
}
