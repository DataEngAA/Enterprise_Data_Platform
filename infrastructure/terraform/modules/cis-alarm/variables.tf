variable "log_group_name" {
  description = "Name of the CloudWatch Logs log group the metric filter reads from."
  type        = string
}

variable "filter_name" {
  description = "Name for both the metric filter and the alarm (must be unique within the log group / account, per resource type)."
  type        = string
}

variable "filter_pattern" {
  description = "CloudWatch Logs metric filter pattern, e.g. a CIS AWS Foundations Benchmark-style CloudTrail JSON pattern."
  type        = string
}

variable "metric_name" {
  description = "Name of the custom CloudWatch metric this filter emits."
  type        = string
}

variable "metric_namespace" {
  description = "CloudWatch namespace the emitted metric is published under."
  type        = string
}

variable "alarm_description" {
  description = "Human-readable description attached to the CloudWatch alarm, explaining what the underlying event means."
  type        = string
}

variable "sns_topic_arn" {
  description = "ARN of the SNS topic the alarm publishes to when it transitions into ALARM state."
  type        = string
}

variable "threshold" {
  description = "Alarm threshold -- the metric value that triggers ALARM state."
  type        = number
  default     = 1
}

variable "period" {
  description = "Alarm evaluation period, in seconds."
  type        = number
  default     = 300
}

variable "evaluation_periods" {
  description = "Number of periods over which the threshold must be breached before the alarm fires."
  type        = number
  default     = 1
}

variable "tags" {
  description = "Common tag map, merged onto the alarm resource (metric filters do not support tags)."
  type        = map(string)
  default     = {}
}
