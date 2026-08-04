# Compute module -- owns the workstation's security group and the EC2
# instance itself, including its root volume and metadata-service
# configuration. NO AMI lookup lives in this module (moved to the root
# module, environments/dev/main.tf, Section 3.2/22) -- var.ami_id is
# required and used directly.
#
# This file has not been applied. Nothing below has been created in AWS.

# ---------------------------------------------------------------------------
# Security group -- ZERO inbound rules, no exception, ever (Section 16).
# Unrestricted outbound access initially (REVISED 2026-07-26, Section 16) --
# see the module README for the documented trade-off. No port 22 rule, no
# database/Docker/Jupyter port opened inbound, regardless of source CIDR.
# ---------------------------------------------------------------------------

resource "aws_security_group" "workstation" {
  name        = "${var.project_name}-${var.environment}-workstation-sg"
  description = "Zero-inbound security group for the ${var.environment} development workstation. No ingress rule of any kind. Unrestricted egress (revised 2026-07-26) -- see module README for the documented trade-off."
  vpc_id      = var.vpc_id

  # No ingress block -- deliberately absent, not merely empty. Zero inbound
  # rules is the primary security control this design relies on (Section
  # 16), independent of the egress posture below.

  egress {
    description = "Unrestricted outbound IPv4 (revised 2026-07-26, Section 16) -- accepted trade-off, primary security control is the zero-inbound rule set above, not a scoped egress rule."
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}-workstation-sg"
    }
  )
}

# ---------------------------------------------------------------------------
# EC2 instance -- the development workstation itself.
# ---------------------------------------------------------------------------

resource "aws_instance" "workstation" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [aws_security_group.workstation.id]
  iam_instance_profile   = var.instance_profile_name

  associate_public_ip_address = true
  monitoring                  = var.enable_detailed_monitoring

  user_data                   = var.user_data
  user_data_replace_on_change = true

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size
    encrypted             = true
    delete_on_termination = true

    tags = merge(
      var.tags,
      {
        Name = "${var.project_name}-${var.environment}-workstation-root"
      }
    )
  }

  # IMDSv2 enforcement -- FINALIZED 2026-07-26 (Section 27). Token-required
  # metadata requests, hop limit 1 (no proxy/container hop can retrieve
  # metadata), instance tags not exposed via the metadata service.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "disabled"
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}-workstation"
    }
  )

  lifecycle {
    # Disposable-workstation model (Section 32) -- no prevent_destroy here,
    # unlike bootstrap's protected state bucket/deployment role. This
    # instance is explicitly designed to be replaceable, not precious.
    create_before_destroy = false
  }
}
