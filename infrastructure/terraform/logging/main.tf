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

#checkov:skip=CKV_AWS_18:No access-logging destination bucket exists yet -- same disposition already accepted for the Terraform state bucket (Trivy AWS-0089, Bootstrap_Checklist.md); a correct implementation needs its own hardened bucket, IAM, and retention policy, deferred to a future monitoring/hardening phase. Checkov triage CKV_AWS_18 (B).
#checkov:skip=CKV2_AWS_62:Event notifications (EventBridge/SNS on object create/delete) were never part of the Logging design's threat model; only the CloudTrail service principal can write to this bucket today (narrow IAM), bounding the realistic threat surface. Genuinely new design work, not yet scoped. Checkov triage CKV2_AWS_62 (D -- deferred hardening, not an accepted trade-off).
#checkov:skip=CKV_AWS_144:Cross-region replication explicitly out of scope -- single-region, personal-portfolio project with no DR requirement in PROJECT_BLUEPRINT.md Phase 0; DR belongs to the roadmap's later Phase 9. Checkov triage CKV_AWS_144 (B).
#checkov:skip=CKV_AWS_145:SSE-S3 (AES256) is an explicit ADR-0002 Option 2 deferral -- CMK migration for logging/storage is a separate, later, explicitly reviewed change now that kms-secrets/ exists in source. Checkov triage CKV_AWS_145 (B).
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

#checkov:skip=CKV_AWS_158:CMK encryption for this log group explicitly deferred to a later, separate migration task (ADR-0002 Option 2) -- CloudWatch Logs already encrypts at rest by default (AWS-managed key). Checkov triage CKV_AWS_158 (B).
#checkov:skip=CKV_AWS_338:90-day retention is an explicit design choice (Logging_and_Audit.md Section 3) -- this log group is for near-term searchability/alarming, not long-term audit retention; the CloudTrail S3 bucket already retains the same content for 365 days. Checkov triage CKV_AWS_338 (B).
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

#checkov:skip=CKV_AWS_35:Trail inherits SSE-S3 from the CloudTrail bucket's own encryption configuration -- CMK-encrypted CloudTrail is the same ADR-0002 Option 2 deferral as the log group above, tracked as one future "adopt the CMK for logging" task. Checkov triage CKV_AWS_35 (B). (CKV_AWS_252, the SNS-notification finding on this same resource, is a REAL DEFECT already fixed in source -- NOT skipped.)
resource "aws_cloudtrail" "this" {
  name           = local.trail_name
  s3_bucket_name = aws_s3_bucket.cloudtrail.id

  is_multi_region_trail         = true
  include_global_service_events = true
  enable_log_file_validation    = true

  # REAL DEFECT remediation (CKV_AWS_252, real GitHub Actions Checkov run
  # 2026-08-07, 16_Implementation_Notes/Checkov_Triage_CI_CD_Slice_2A.md).
  # Wires this trail's own native log-delivery notifications to the
  # EXISTING aws_sns_topic.security_alerts (defined later in this same
  # file, already used for the CIS metric-filter alarms below) -- no new
  # SNS topic is created, and no existing subscription
  # (aws_sns_topic_subscription.security_alerts_email) is changed. This is
  # a distinct notification path from the metric-filter alarms: CloudTrail
  # publishes to this topic on its own log-delivery events (e.g. delivery
  # failures), independent of what those events' log CONTENT says, which
  # the metric filters evaluate separately.
  sns_topic_name = aws_sns_topic.security_alerts.name

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
  #
  # aws_sns_topic_policy.security_alerts (below) is included here for the
  # identical reason, added 2026-08-07 after a real `terraform apply`
  # failed at this exact resource: AWS's UpdateTrail API call rejected the
  # sns_topic_name argument with InsufficientSnsTopicPolicyException,
  # because aws_sns_topic.security_alerts previously had no explicit
  # Terraform-managed policy authorizing cloudtrail.amazonaws.com to
  # publish to it (AWS's own auto-generated default topic policy grants
  # the topic owner account full access but grants no other service or
  # principal anything). Without this depends_on, Terraform's implicit
  # graph would order aws_cloudtrail.this only after aws_sns_topic.
  # security_alerts itself (a direct reference via .name), not after the
  # separate policy resource that actually authorizes the publish -- the
  # same class of ordering gap the bucket-policy depends_on above already
  # guards against.
  depends_on = [
    aws_s3_bucket_policy.cloudtrail,
    aws_iam_role_policy.cloudtrail_cloudwatch,
    aws_sns_topic_policy.security_alerts,
  ]

  tags = local.common_tags
}

# -----------------------------------------------------------------------
# SNS topic for security-event notifications
# -----------------------------------------------------------------------

#checkov:skip=CKV_AWS_26:No kms_master_key_id set -- same Phase 0 KMS-deferral pattern as the log group/trail above; this topic carries alert notifications only (metric-filter descriptions, CloudTrail delivery status), not sensitive application data. Checkov triage CKV_AWS_26 (B).
resource "aws_sns_topic" "security_alerts" {
  name = local.sns_topic_name

  tags = local.common_tags
}

# ---------------------------------------------------------------------------
# SNS topic policy -- ADDED 2026-08-07, real-apply-failure remediation.
#
# Incident: the CKV_AWS_252 remediation (aws_cloudtrail.this's
# sns_topic_name argument, added earlier the same day) was applied for
# real. The apply failed:
#   aws_cloudtrail.this: Modifying...
#   FAILED: InsufficientSnsTopicPolicyException: SNS Topic does not exist
#   or the topic policy is incorrect
# Root cause: no aws_sns_topic_policy resource existed for
# aws_sns_topic.security_alerts before this change. A topic with no
# explicit Terraform-managed policy still has SOME policy in AWS (SNS
# always auto-generates a default owner-only policy on topic creation),
# but that default policy authorizes only the topic-owner account -- it
# grants no permission to any AWS service principal, including
# cloudtrail.amazonaws.com. CloudTrail's own UpdateTrail/CreateTrail SNS
# integration requires the target topic's policy to explicitly authorize
# sns:Publish for the cloudtrail.amazonaws.com service principal; AWS does
# not grant this implicitly just because the topic exists in the same
# account.
#
# Fix: one aws_sns_topic_policy resource for this exact, already-existing
# topic (not a second topic, not a second aws_sns_topic_policy competing
# for the same topic -- none existed before this change, so there is
# nothing to merge with). Its policy document has exactly two statements:
#   1. AllowAccountOwnerManageTopic -- reproduces the topic-owner
#      permissions AWS's own auto-generated default policy already grants,
#      so that attaching this explicit policy does not silently narrow
#      what the account/CIS-alarm-module path can already do. Principal is
#      the exact account root ARN (arn:aws:iam::<account>:root), not
#      Principal = "*" -- functionally equivalent for "this AWS account
#      only" scoping, without using an unconditioned wildcard principal.
#   2. AllowCloudTrailPublish -- the new authorization this incident
#      requires: principal cloudtrail.amazonaws.com, action sns:Publish
#      only (not sns:*), resource the exact topic ARN (not Resource = "*"),
#      restricted with both aws:SourceArn (the exact CloudTrail trail ARN,
#      local.cloudtrail_arn -- the same deterministic, cycle-free ARN
#      construction already used by the CloudTrail bucket policy and the
#      CloudWatch Logs trust policy above) and aws:SourceAccount (this
#      account only) -- the tightest scoping AWS's CloudTrail-to-SNS
#      publish integration supports, matching the confused-deputy pattern
#      already established by data.aws_iam_policy_document.
#      cloudtrail_cloudwatch_trust above.
#
# Preserved, unchanged by this addition: aws_sns_topic.security_alerts's
# own ARN/name/tags; aws_sns_topic_subscription.security_alerts_email
# (the existing email subscription); every module.cis_alarms alarm's use
# of this same topic ARN for its own notification action (unrelated to
# this topic's resource-based policy, which only governs who may act ON
# the topic, not what the topic notifies).
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "security_alerts_topic_policy" {
  statement {
    sid    = "AllowAccountOwnerManageTopic"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${var.aws_account_id}:root"]
    }

    actions = [
      "SNS:GetTopicAttributes",
      "SNS:SetTopicAttributes",
      "SNS:AddPermission",
      "SNS:RemovePermission",
      "SNS:DeleteTopic",
      "SNS:Subscribe",
      "SNS:ListSubscriptionsByTopic",
      "SNS:Publish",
    ]

    resources = [aws_sns_topic.security_alerts.arn]
  }

  statement {
    sid    = "AllowCloudTrailPublish"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    actions   = ["SNS:Publish"]
    resources = [aws_sns_topic.security_alerts.arn]

    # Confused-deputy protection, as tight as AWS's CloudTrail SNS
    # integration supports -- restricted to this exact trail's ARN and
    # this exact account, not any CloudTrail trail in any account.
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

resource "aws_sns_topic_policy" "security_alerts" {
  arn    = aws_sns_topic.security_alerts.arn
  policy = data.aws_iam_policy_document.security_alerts_topic_policy.json
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
