output "metric_filter_id" {
  description = "ID of the CloudWatch Logs metric filter."
  value       = aws_cloudwatch_log_metric_filter.this.id
}

output "alarm_arn" {
  description = "ARN of the CloudWatch alarm."
  value       = aws_cloudwatch_metric_alarm.this.arn
}

output "alarm_name" {
  description = "Name of the CloudWatch alarm."
  value       = aws_cloudwatch_metric_alarm.this.alarm_name
}
