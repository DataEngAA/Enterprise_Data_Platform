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
}

# ---------------------------------------------------------------------------
# VPC
# ---------------------------------------------------------------------------

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
