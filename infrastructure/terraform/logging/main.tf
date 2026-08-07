# Phase 0 Logging and Audit Foundation.
#
# Implements the approved design in 02_Infrastructure/Logging_and_Audit.md
# and 01_Architecture/ADRs/ADR-0002-logging-and-audit-foundation.md:
# multi-region CloudTrail with global service events and full read/write
# management events (no data events, no Insights); a dedicated, hardened S3
# bucket for centralized log storage; CloudWatch Logs integration via a
# narrowly scoped IAM role; 7 approved security-event metric filters/alarms
# (modules/cis-alarm); one SNS topic with an email subscription. VPC Flow
# Logs are explicitly OUT of scope -- owned by the networking workstream
# (Logging_and_Audit.md Section 6).
#
# NOT YET APPLIED. No `terraform apply` has been run against this
# configuration.

# -----------------------------------------------------------------------
# Dedicated CloudTrail audit-log S3 bucket
# -----------------------------------------------------------------------

resource "aws_s3_bucket" "cloudtrail" {
  bucket = var.cloudtrail_bucket_name

  # Protection against accidental deletion (Logging_and_Audit.md Section 2)
  # -- matches the pattern already used on aws_iam_role.deployment in
  # bootstrap/main.tf. Removing this bucket requires a deliberate,
  # conscious change to this lifecycle block first, not an ordinary
  # `terraform destroy` or resource removal.
  lifecycle {
    prevent_destroy = true
  }

  tags = local.common_tags
}

resource "aws_s3_bucket_versioning" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_ownership_controls" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  rule {
    apply_server_side_encryption_by_default {
      # SSE-S3 (AES256) now; a customer-managed KMS key is deferred to
      # Phase 0 Step 7 (Logging_and_Audit.md Section 2; ADR-0002 Option 2),
      # matching the same accepted precedent already applied to the
      # Terraform state bucket in bootstrap/main.tf.
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  rule {
    id     = "cloudtrail-log-retention"
    status = "Enabled"

    filter {}

    transition {
      days          = var.cloudtrail_s3_ia_transition_days
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = var.cloudtrail_s3_glacier_transition_days
      storage_class = "GLACIER"
    }

    expiration {
      # Approved 365-day Phase 0 placeholder (var default) -- see
      # variables.tf's cloudtrail_s3_expiration_days description and
      # ADR-0002 "Conditions for Reconsideration."
      days = var.cloudtrail_s3_expiration_days
    }
  }

  rule {
    id     = "abort-incomplete-multipart-uploads"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# TLS-only bucket policy statement, plus the CloudTrail delivery statements
# required for a trail to write to this bucket (AWS's documented required
# policy shape: GetBucketAcl + PutObject, both scoped to the
# cloudtrail.amazonaws.com service principal and this trail's ARN).
data "aws_iam_policy_document" "cloudtrail_bucket_policy" {
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    actions   = ["s3:*"]
    resources = [aws_s3_bucket.cloudtrail.arn, "${aws_s3_bucket.cloudtrail.arn}/*"]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  statement {
    sid    = "AWSCloudTrailAclCheck"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.cloudtrail.arn]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.cloudtrail_arn]
    }
  }

  statement {
    sid    = "AWSCloudTrailWrite"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.cloudtrail.arn}/AWSLogs/${var.aws_account_id}/*"]

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.cloudtrail_arn]
    }
  }
}

resource "aws_s3_bucket_policy" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  policy = data.aws_iam_policy_document.cloudtrail_bucket_policy.json
}

# -----------------------------------------------------------------------
# CloudWatch Logs integration
# -----------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "cloudtrail" {
  name              = local.cloudtrail_log_group_name
  retention_in_days = var.cloudwatch_log_retention_days

  tags = local.common_tags
}

# Least-privilege service role for CloudTrail to publish to CloudWatch
# Logs (Logging_and_Audit.md Section 3). Deliberately narrower than AWS's
# own published sample policy: no logs:CreateLogGroup (the log group is
# pre-created above by Terraform, so CloudTrail never needs permission to
# create one itself).
data "aws_iam_policy_document" "cloudtrail_cloudwatch_trust" {
  statement {
    sid     = "AllowCloudTrailAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    # Confused-deputy protection (AWS best practice): the trust is further
    # restricted to only this account's specific trail, not any CloudTrail
    # trail in any account that happens to assume a role named this.
    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.cloudtrail_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [var.aws_account_id]
    }
  }
}

resource "aws_iam_role" "cloudtrail_cloudwatch" {
  name               = local.cloudtrail_cloudwatch_role_name
  assume_role_policy = data.aws_iam_policy_document.cloudtrail_cloudwatch_trust.json

  tags = local.common_tags
}

data "aws_iam_policy_document" "cloudtrail_cloudwatch_permissions" {
  statement {
    sid    = "AllowPublishToCloudTrailLogGroup"
    effect = "Allow"

    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]

    resources = ["${aws_cloudwatch_log_group.cloudtrail.arn}:*"]
  }
}

resource "aws_iam_role_policy" "cloudtrail_cloudwatch" {
  name   = "${local.cloudtrail_cloudwatch_role_name}-policy"
  role   = aws_iam_role.cloudtrail_cloudwatch.id
  policy = data.aws_iam_policy_document.cloudtrail_cloudwatch_permissions.json
}

# -----------------------------------------------------------------------
# CloudTrail trail
# -----------------------------------------------------------------------

resource "aws_cloudtrail" "this" {
  name           = local.trail_name
  s3_bucket_name = aws_s3_bucket.cloudtrail.id

  is_multi_region_trail         = true
  include_global_service_events = true
  enable_log_file_validation    = true

  # Management events only, both Read and Write -- the first copy is free
  # regardless of trail scope (Logging_and_Audit.md Section 7). No data
  # event selector is configured -- data events are explicitly out of
  # scope for Phase 0 (Section 8).
  event_selector {
    read_write_type           = "All"
    include_management_events = true
  }

  cloud_watch_logs_group_arn = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
  cloud_watch_logs_role_arn  = aws_iam_role.cloudtrail_cloudwatch.arn

  # The bucket policy must exist and already grant CloudTrail delivery
  # access before the trail can be created against this bucket -- see
  # locals.tf's cloudtrail_arn comment for why this is an explicit
  # depends_on rather than an implicit reference-based dependency.
  depends_on = [
    aws_s3_bucket_policy.cloudtrail,
    aws_iam_role_policy.cloudtrail_cloudwatch,
  ]

  tags = local.common_tags
}

# -----------------------------------------------------------------------
# SNS topic for security-event notifications
# -----------------------------------------------------------------------

resource "aws_sns_topic" "security_alerts" {
  name = local.sns_topic_name

  tags = local.common_tags
}

resource "aws_sns_topic_subscription" "security_alerts_email" {
  topic_arn = aws_sns_topic.security_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email

  # AWS creates this subscription in PendingConfirmation state -- a human
  # must click the confirmation link delivered to var.alert_email. No
  # Terraform resource or AWS API call can complete that confirmation
  # (Logging_and_Audit.md Section 5).
}

# -----------------------------------------------------------------------
# Security-event metric filters and alarms (modules/cis-alarm)
# -----------------------------------------------------------------------

module "cis_alarms" {
  source = "../modules/cis-alarm"

  for_each = local.cis_alarms

  log_group_name    = aws_cloudwatch_log_group.cloudtrail.name
  filter_name       = each.key
  filter_pattern    = each.value.pattern
  metric_name       = each.value.metric_name
  metric_namespace  = "${var.project_name}/SecurityMetrics"
  alarm_description = each.value.description
  sns_topic_arn     = aws_sns_topic.security_alerts.arn
  tags              = local.common_tags
}
