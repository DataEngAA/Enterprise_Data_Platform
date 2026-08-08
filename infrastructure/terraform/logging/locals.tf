# Computed, root-module-local values for the logging stack.

locals {
  # Required tags (Naming_Convention.md "Required tags"), same merge-order
  # correction already applied in bootstrap/locals.tf and
  # environments/dev/locals.tf (additional_tags merged FIRST, required tags
  # SECOND, so a key collision resolves to the required value).
  common_tags = merge(
    var.additional_tags,
    {
      Project            = var.project_name
      Environment        = var.environment
      ManagedBy          = "terraform"
      Owner              = var.owner
      CostCenter         = var.cost_center
      DataClassification = var.data_classification
    }
  )

  # Naming (01_Architecture/Naming_Convention.md).
  trail_name                      = "${var.project_name}-shared-trail"
  cloudtrail_cloudwatch_role_name = "${var.project_name}-shared-cloudtrail-cloudwatch-role"
  cloudtrail_log_group_name       = "/${var.project_name}/${var.environment}/cloudtrail"
  sns_topic_name                  = "${var.project_name}-shared-security-alerts"

  # The CloudTrail trail's ARN, constructed here rather than read from
  # aws_cloudtrail.this.arn -- the audit bucket's delivery policy
  # (main.tf, aws_s3_bucket_policy.cloudtrail) must reference the trail's
  # ARN in its aws:SourceArn condition, but the trail itself must be created
  # AFTER that bucket policy exists (AWS requires the bucket policy to
  # already grant CloudTrail delivery access before the trail can be
  # created against that bucket). Referencing the live resource's own
  # `.arn` attribute here would create a dependency cycle (policy needs
  # trail ARN; trail needs policy to exist first); constructing the ARN
  # from its own well-known, deterministic components (partition, region,
  # account ID, trail name -- all already known before either resource
  # exists) avoids the cycle entirely. `aws_cloudtrail.this` still carries
  # an explicit `depends_on = [aws_s3_bucket_policy.cloudtrail]` (main.tf)
  # to guarantee real creation order, independent of this ARN construction.
  cloudtrail_arn = "arn:aws:cloudtrail:${var.aws_region}:${var.aws_account_id}:trail/${local.trail_name}"

  # The 7 approved (Section 4, 02_Infrastructure/Logging_and_Audit.md)
  # security-event metric filter / alarm definitions, passed into
  # modules/cis-alarm via for_each. Patterns are adapted from the public CIS
  # AWS Foundations Benchmark filter recommendations -- verify against the
  # current CIS benchmark text before treating as certified/exact. The 8th
  # item from the design (KMS key disable/deletion) is deliberately NOT
  # included here -- no KMS key exists yet (Phase 0 Step 7 has not started);
  # see 02_Infrastructure/Logging_and_Audit.md Section 4 and Section 8
  # "resources explicitly out of scope."
  cis_alarms = {
    root-account-usage = {
      pattern     = "{ ($.userIdentity.type = \"Root\") && ($.userIdentity.invokedBy NOT EXISTS) && ($.eventType != \"AwsServiceEvent\") }"
      description = "Root account credentials were used for an API call or console sign-in. The root user should not be used for routine operations (CIS AWS Foundations Benchmark 3.3)."
      metric_name = "RootAccountUsage"
    }
    console-signin-failures = {
      pattern     = "{ ($.eventName = \"ConsoleLogin\") && ($.errorMessage = \"Failed authentication\") }"
      description = "A console sign-in attempt failed authentication -- possible credential-guessing activity (CIS AWS Foundations Benchmark 3.6)."
      metric_name = "ConsoleSigninFailures"
    }
    iam-policy-and-role-changes = {
      pattern     = "{ ($.eventSource = \"iam.amazonaws.com\") && (($.eventName = \"DeleteGroupPolicy\") || ($.eventName = \"DeleteRolePolicy\") || ($.eventName = \"DeleteUserPolicy\") || ($.eventName = \"PutGroupPolicy\") || ($.eventName = \"PutRolePolicy\") || ($.eventName = \"PutUserPolicy\") || ($.eventName = \"CreatePolicy\") || ($.eventName = \"DeletePolicy\") || ($.eventName = \"CreatePolicyVersion\") || ($.eventName = \"DeletePolicyVersion\") || ($.eventName = \"AttachRolePolicy\") || ($.eventName = \"DetachRolePolicy\") || ($.eventName = \"AttachUserPolicy\") || ($.eventName = \"DetachUserPolicy\") || ($.eventName = \"AttachGroupPolicy\") || ($.eventName = \"DetachGroupPolicy\") || ($.eventName = \"CreateRole\") || ($.eventName = \"DeleteRole\") || ($.eventName = \"UpdateRole\") || ($.eventName = \"UpdateAssumeRolePolicy\")) }"
      description = "An IAM policy, role, or trust-policy change was made -- combines the design's 'IAM policy changes' and 'IAM role/trust-policy changes' items into one filter (Logging_and_Audit.md Section 4, decision note) (CIS AWS Foundations Benchmark 3.4)."
      metric_name = "IamPolicyAndRoleChanges"
    }
    cloudtrail-changes = {
      pattern     = "{ ($.eventName = \"StopLogging\") || ($.eventName = \"DeleteTrail\") || ($.eventName = \"UpdateTrail\") }"
      description = "A CloudTrail trail was stopped, deleted, or reconfigured -- possible attempt to disable audit visibility (CIS AWS Foundations Benchmark 3.5)."
      metric_name = "CloudTrailChanges"
    }
    security-group-changes = {
      pattern     = "{ ($.eventName = \"AuthorizeSecurityGroupIngress\") || ($.eventName = \"AuthorizeSecurityGroupEgress\") || ($.eventName = \"RevokeSecurityGroupIngress\") || ($.eventName = \"RevokeSecurityGroupEgress\") || ($.eventName = \"CreateSecurityGroup\") || ($.eventName = \"DeleteSecurityGroup\") }"
      description = "A security group was created, deleted, or had an ingress/egress rule changed (CIS AWS Foundations Benchmark 3.10)."
      metric_name = "SecurityGroupChanges"
    }
    network-acl-changes = {
      pattern     = "{ ($.eventName = \"CreateNetworkAcl\") || ($.eventName = \"CreateNetworkAclEntry\") || ($.eventName = \"DeleteNetworkAcl\") || ($.eventName = \"DeleteNetworkAclEntry\") || ($.eventName = \"ReplaceNetworkAclEntry\") || ($.eventName = \"ReplaceNetworkAclAssociation\") }"
      description = "A Network ACL was created, deleted, or changed (CIS AWS Foundations Benchmark 3.11)."
      metric_name = "NetworkAclChanges"
    }
    unauthorized-api-calls = {
      pattern     = "{ ($.errorCode = \"*UnauthorizedOperation\") || ($.errorCode = \"AccessDenied*\") }"
      description = "An API call was denied due to insufficient permissions -- may indicate a misconfiguration or an unauthorized access attempt (CIS AWS Foundations Benchmark 3.1)."
      metric_name = "UnauthorizedApiCalls"
    }
  }
}
