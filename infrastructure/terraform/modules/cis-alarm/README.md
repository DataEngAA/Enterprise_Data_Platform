# modules/cis-alarm

Status: **Code created (2026-08-04), not yet planned or applied.** Part of the Phase 0 Logging and Audit Foundation workstream (`02_Infrastructure/Logging_and_Audit.md`, `01_Architecture/ADRs/ADR-0002-logging-and-audit-foundation.md`).

## Responsibility

Owns exactly one repeated pattern: a CloudWatch Logs metric filter paired with a CloudWatch alarm that publishes to a caller-supplied SNS topic. Nothing else. Deliberately kept generic and small — **this module does not own CloudTrail, the audit-log S3 bucket, the CloudTrail-to-CloudWatch IAM role, or the SNS topic itself** — those are all owned by the calling root module (`infrastructure/terraform/logging/main.tf`), per the approved scope (`02_Infrastructure/Logging_and_Audit.md` Section 8, ADR-0002 Option 5).

## Resources owned

- `aws_cloudwatch_log_metric_filter.this`
- `aws_cloudwatch_metric_alarm.this`

## Inputs

| Variable | Description | Default |
|---|---|---|
| `log_group_name` | Log group the filter reads from. | none (required) |
| `filter_name` | Name for both the filter and the alarm. | none (required) |
| `filter_pattern` | CloudWatch Logs metric filter pattern. | none (required) |
| `metric_name` | Custom metric name the filter emits. | none (required) |
| `metric_namespace` | Namespace the metric is published under. | none (required) |
| `alarm_description` | Human-readable description of what the underlying event means. | none (required) |
| `sns_topic_arn` | SNS topic the alarm notifies. | none (required) |
| `threshold` | Alarm threshold. | `1` |
| `period` | Evaluation period, seconds. | `300` |
| `evaluation_periods` | Number of periods before the alarm fires. | `1` |
| `tags` | Common tag map (alarms only — metric filters do not support tags). | `{}` |

## Outputs

`metric_filter_id`, `alarm_arn`, `alarm_name`.

## Usage

Called once per approved security-event pattern via `for_each` from `infrastructure/terraform/logging/main.tf`, over the `local.cis_alarms` map (7 entries as of 2026-08-04 — see `02_Infrastructure/Logging_and_Audit.md` Section 4 for the full list and the rationale for combining the design's "IAM policy changes" and "IAM role/trust-policy changes" items into one filter).

## What this module intentionally does not manage

- No CloudTrail trail, no S3 bucket, no CloudWatch log group — it only reads from a log group name passed in.
- No IAM role or policy of any kind.
- No SNS topic — it only publishes to a topic ARN passed in.
- `treat_missing_data = "notBreaching"` is fixed, not exposed as a variable — a period with zero matching events should never be treated as a breach for this class of security alarm.
