# A single, generic CloudWatch Logs metric filter + CloudWatch alarm pair,
# wired to publish to a caller-supplied SNS topic. This module owns exactly
# this repeated pattern and nothing else -- no CloudTrail, S3, IAM-role, or
# SNS-topic resource is created here (those are owned by the calling root
# module, infrastructure/terraform/logging/main.tf), per the approved scope
# (02_Infrastructure/Logging_and_Audit.md Section 8; ADR-0002 Option 5).

resource "aws_cloudwatch_log_metric_filter" "this" {
  name           = var.filter_name
  log_group_name = var.log_group_name
  pattern        = var.filter_pattern

  metric_transformation {
    name          = var.metric_name
    namespace     = var.metric_namespace
    value         = "1"
    default_value = "0"
  }
}

resource "aws_cloudwatch_metric_alarm" "this" {
  alarm_name          = var.filter_name
  alarm_description   = var.alarm_description
  namespace           = var.metric_namespace
  metric_name         = var.metric_name
  statistic           = "Sum"
  period              = var.period
  evaluation_periods  = var.evaluation_periods
  threshold           = var.threshold
  comparison_operator = "GreaterThanOrEqualToThreshold"

  # A period with zero matching events should not be treated as a breach --
  # only real matching events should trigger ALARM state.
  treat_missing_data = "notBreaching"

  alarm_actions = [var.sns_topic_arn]

  tags = var.tags
}
