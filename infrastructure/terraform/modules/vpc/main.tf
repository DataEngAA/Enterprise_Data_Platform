# Networking module -- owns the dedicated VPC, its single public subnet,
# the Internet Gateway, and the public route table (Dev_Environment_
# Terraform_Implementation_Plan.md Section 3.2 "Do route tables belong in
# vpc? APPROVED -- Yes"). No private subnet, NAT Gateway, VPC endpoint, or
# IPv6 resource is created by this module (Section 6, approved exclusions).
#
# This file has not been applied. Nothing below has been created in AWS.

# ---------------------------------------------------------------------------
# Availability Zone selection (Section 20 -- FINALIZED)
#
# Never hardcode a literal AZ name (e.g. "ap-south-1a") anywhere in this
# module. AZ name-to-physical-location mappings are account-specific --
# AWS deliberately randomizes them per account. Querying dynamically and
# picking a fixed, deterministic index (0) avoids depending on an
# account-specific assumption that might not hold.
# ---------------------------------------------------------------------------

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  selected_availability_zone = coalesce(
    var.availability_zone_override,
    data.aws_availability_zones.available.names[0]
  )

  # Short suffix for resource naming (Naming_Convention.md subnet pattern:
  # <project>-<environment>-public-<az-suffix>), e.g. "1a" out of
  # "ap-south-1a". This is a naming convenience only -- it does not affect
  # which AZ is actually selected above.
  az_suffix = substr(
    local.selected_availability_zone,
    length(local.selected_availability_zone) - 2,
    2
  )

  # ---------------------------------------------------------------------
  # Phase 0 Networking Hardening (2026-08-04) -- second AZ selection, ADDED
  # ALONGSIDE the existing single-AZ locals above, which are left completely
  # unchanged (Networking.md "Migration Strategy"; ADR-0003 Option 5). Index
  # 1 of the same data.aws_availability_zones lookup already used above --
  # no new data source, no literal AZ name hardcoded.
  # ---------------------------------------------------------------------
  selected_availability_zone_2 = data.aws_availability_zones.available.names[1]

  az_suffix_2 = substr(
    local.selected_availability_zone_2,
    length(local.selected_availability_zone_2) - 2,
    2
  )
}

# ---------------------------------------------------------------------------
# VPC
# ---------------------------------------------------------------------------

#checkov:skip=CKV2_AWS_11:VPC Flow Logs are real, deployed, and ACTIVE (aws_flow_log.this below, confirmed via a real describe-flow-logs-equivalent check and a live CloudWatch log stream -- PROJECT_EXECUTION_JOURNAL.md Section 27ao). Re-verified 2026-08-08: aws_flow_log.this uses count = var.enable_vpc_flow_logs ? 1 : 0 (true by default), a documented Checkov graph-resolution limitation for count-conditional resources on either side of an expected edge. Checkov triage CKV2_AWS_11 (C).
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}-vpc"
    }
  )
}

# ---------------------------------------------------------------------------
# Public subnet (single AZ, single subnet -- Section 17)
#
# map_public_ip_on_launch is deliberately NOT set here (defaults to false).
# Per Section 17, public-IP assignment is set explicitly on the instance
# itself (modules/ec2-workstation's associate_public_ip_address = true),
# not implied by a subnet-wide default that could silently affect a future
# second instance placed in this same subnet.
# ---------------------------------------------------------------------------

resource "aws_subnet" "public" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.public_subnet_cidr
  availability_zone = local.selected_availability_zone

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}-public-${local.az_suffix}"
    }
  )
}

# ---------------------------------------------------------------------------
# Internet Gateway + public route table (Section 18)
#
# No private route table is created -- no private subnet exists yet
# (Section 6, deferred). No NAT Gateway (Section 19, accepted trade-off).
# ---------------------------------------------------------------------------

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}-igw"
    }
  )
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}-public-rt"
    }
  )
}

resource "aws_route" "public_internet_ipv4" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}
# NOTE: exact column alignment above will be normalized by `terraform fmt`
# in the validation task (not run as part of this file-creation task).

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# ---------------------------------------------------------------------------
# Phase 0 Networking Hardening (2026-08-04). Everything below is a PURE
# ADDITION -- no resource above this point is modified. See
# 02_Infrastructure/Networking.md "Phase 0 Networking Hardening -- Target
# State Design" and 01_Architecture/ADRs/ADR-0003-networking-hardening-
# multi-az-nat-and-endpoint-strategy.md for the full design and rationale.
#
# NOT YET APPLIED. No `terraform apply` has been run against this addition.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Second public subnet (AZ index 1) -- shares the EXISTING public route
# table (aws_route_table.public, above), not a new one -- both public
# subnets get an identical 0.0.0.0/0 -> IGW route (Networking.md Section 2).
# ---------------------------------------------------------------------------

resource "aws_subnet" "public_az2" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.public_subnet_cidr_az2
  availability_zone = local.selected_availability_zone_2

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}-public-${local.az_suffix_2}"
    }
  )
}

resource "aws_route_table_association" "public_az2" {
  subnet_id      = aws_subnet.public_az2.id
  route_table_id = aws_route_table.public.id
}

# ---------------------------------------------------------------------------
# Private-application tier -- both AZs, one shared route table. NO
# 0.0.0.0/0 route of any kind (no NAT Gateway exists -- deliberately
# deferred, Networking.md Section 3). Both AZs share one route table since
# there is no per-AZ NAT target to route toward yet (Networking.md
# Section 2) -- if NAT is later adopted one-per-AZ, this route table would
# split per-AZ at that time, a route-table-only change.
# ---------------------------------------------------------------------------

resource "aws_subnet" "private_app_az1" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_app_subnet_cidr_az1
  availability_zone = local.selected_availability_zone

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}-private-app-${local.az_suffix}"
    }
  )
}

resource "aws_subnet" "private_app_az2" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_app_subnet_cidr_az2
  availability_zone = local.selected_availability_zone_2

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}-private-app-${local.az_suffix_2}"
    }
  )
}

resource "aws_route_table" "private_app" {
  vpc_id = aws_vpc.this.id

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}-private-app-rt"
    }
  )
}

resource "aws_route_table_association" "private_app_az1" {
  subnet_id      = aws_subnet.private_app_az1.id
  route_table_id = aws_route_table.private_app.id
}

resource "aws_route_table_association" "private_app_az2" {
  subnet_id      = aws_subnet.private_app_az2.id
  route_table_id = aws_route_table.private_app.id
}

# ---------------------------------------------------------------------------
# Private-data tier -- same pattern as private-application, above, own
# dedicated route table, no default route.
# ---------------------------------------------------------------------------

resource "aws_subnet" "private_data_az1" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_data_subnet_cidr_az1
  availability_zone = local.selected_availability_zone

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}-private-data-${local.az_suffix}"
    }
  )
}

resource "aws_subnet" "private_data_az2" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_data_subnet_cidr_az2
  availability_zone = local.selected_availability_zone_2

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}-private-data-${local.az_suffix_2}"
    }
  )
}

resource "aws_route_table" "private_data" {
  vpc_id = aws_vpc.this.id

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}-private-data-rt"
    }
  )
}

resource "aws_route_table_association" "private_data_az1" {
  subnet_id      = aws_subnet.private_data_az1.id
  route_table_id = aws_route_table.private_data.id
}

resource "aws_route_table_association" "private_data_az2" {
  subnet_id      = aws_subnet.private_data_az2.id
  route_table_id = aws_route_table.private_data.id
}

# ---------------------------------------------------------------------------
# S3 Gateway VPC endpoint (Networking.md Section 4) -- free, no hourly
# charge, no data-processing charge. Associated with all three route tables
# (public, private-app, private-data) so S3 traffic from any tier uses the
# AWS backbone rather than the public internet path. Every other evaluated
# endpoint (DynamoDB Gateway, all 9 interface endpoints) is deliberately NOT
# created here -- see variables.tf's enable_s3_gateway_endpoint description.
# ---------------------------------------------------------------------------

resource "aws_vpc_endpoint" "s3" {
  count = var.enable_s3_gateway_endpoint ? 1 : 0

  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${data.aws_region.current.region}.s3"
  vpc_endpoint_type = "Gateway"

  route_table_ids = [
    aws_route_table.public.id,
    aws_route_table.private_app.id,
    aws_route_table.private_data.id,
  ]

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}-s3-gateway-endpoint"
    }
  )
}

data "aws_region" "current" {}

# ---------------------------------------------------------------------------
# VPC Flow Logs (Networking.md Section 5) -- CloudWatch Logs destination,
# ALL traffic, 60-second aggregation, 30-day retention, a dedicated,
# least-privilege delivery role. Environment-scoped log group name (not
# "shared" -- Flow Logs are per-VPC/per-environment, distinct from the
# CloudTrail log group in infrastructure/terraform/logging/). Ownership of
# this resource by this module/workstream is confirmed in
# 02_Infrastructure/Logging_and_Audit.md Section 6.
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "vpc_flow_logs" {
  count = var.enable_vpc_flow_logs ? 1 : 0

  name              = "/${var.project_name}/${var.environment}/vpc-flow-logs"
  retention_in_days = var.flow_log_retention_days

  tags = var.tags
}

data "aws_iam_policy_document" "vpc_flow_logs_trust" {
  count = var.enable_vpc_flow_logs ? 1 : 0

  statement {
    sid     = "AllowVpcFlowLogsAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "vpc_flow_logs" {
  count = var.enable_vpc_flow_logs ? 1 : 0

  name               = "${var.project_name}-${var.environment}-vpc-flow-logs-role"
  assume_role_policy = data.aws_iam_policy_document.vpc_flow_logs_trust[0].json

  tags = var.tags
}

data "aws_iam_policy_document" "vpc_flow_logs_permissions" {
  count = var.enable_vpc_flow_logs ? 1 : 0

  statement {
    sid    = "AllowPublishToFlowLogsLogGroup"
    effect = "Allow"

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
    ]

    resources = ["${aws_cloudwatch_log_group.vpc_flow_logs[0].arn}:*"]
  }
}

resource "aws_iam_role_policy" "vpc_flow_logs" {
  count = var.enable_vpc_flow_logs ? 1 : 0

  name   = "${var.project_name}-${var.environment}-vpc-flow-logs-policy"
  role   = aws_iam_role.vpc_flow_logs[0].id
  policy = data.aws_iam_policy_document.vpc_flow_logs_permissions[0].json
}

resource "aws_flow_log" "this" {
  count = var.enable_vpc_flow_logs ? 1 : 0

  vpc_id                   = aws_vpc.this.id
  traffic_type             = var.flow_log_traffic_type
  max_aggregation_interval = var.flow_log_max_aggregation_interval

  log_destination_type = "cloud-watch-logs"
  log_destination       = aws_cloudwatch_log_group.vpc_flow_logs[0].arn
  iam_role_arn          = aws_iam_role.vpc_flow_logs[0].arn

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}-vpc-flow-log"
    }
  )
}

# ---------------------------------------------------------------------------
# Default security group -- REAL DEFECT remediation (CKV2_AWS_12, real
# GitHub Actions Checkov run 2026-08-07, 16_Implementation_Notes/Checkov_
# Triage_CI_CD_Slice_2A.md). Every VPC gets an AWS-created default security
# group automatically, whether or not Terraform manages it -- until now,
# this project's Terraform never referenced it, leaving it unmanaged: not
# locked down, not tracked in state, driftable via the console with no
# plan/apply ever surfacing a change, and a silent fallback destination for
# any future resource that omits an explicit security group.
#
# aws_default_security_group ADOPTS the VPC's already-existing,
# automatically created default security group into Terraform management --
# it does NOT create a new, additional security group, and it is NOT a
# substitute/standalone SG used in place of the real default. This is the
# provider's documented, intended mechanism for managing an object AWS
# creates implicitly (the same category as aws_default_vpc/aws_default_
# route_table/aws_default_network_acl, none of which this project uses,
# since no other implicit default object exists in this design that isn't
# already otherwise governed).
#
# No ingress block and no egress block -- both deliberately absent, not
# merely empty lists assigned an empty value, matching this project's own
# established "absence, not an empty rule set" convention already used for
# modules/ec2-workstation's zero-inbound workstation security group.
# aws_default_security_group's own documented behavior: omitting ingress/
# egress blocks entirely, combined with Terraform managing the resource at
# all, is exactly how this resource type expresses "remove every rule AWS
# put here by default and keep it that way" -- Terraform reconciles the
# default group's rule set to nothing on every apply, so any rule added via
# the console (or by AWS's own default provisioning) is removed on the next
# apply, not merely left alone.
#
# No resource in this project currently relies on the default security
# group (the workstation uses its own explicit aws_security_group.
# workstation) -- this is a standing hardening measure for anything added
# in a later phase that might otherwise omit an explicit security group by
# mistake, not a fix for any current, real usage.
# ---------------------------------------------------------------------------

resource "aws_default_security_group" "this" {
  vpc_id = aws_vpc.this.id

  # No ingress block, no egress block -- see the comment above.

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}-default-sg-do-not-use"
    }
  )
}
