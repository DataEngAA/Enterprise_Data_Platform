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

#checkov:skip=CKV_AWS_382:Unrestricted egress is an explicit, revised 2026-07-26 design decision (module README) -- no NAT Gateway/VPC endpoints exist yet to scope egress through (ADR-0003's NAT deferral). Zero-inbound rules (no exception, ever) is this design's primary control. Checkov triage CKV_AWS_382 (B).
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

#checkov:skip=CKV_AWS_88:Public IP required for outbound internet reachability -- no NAT Gateway exists yet (ADR-0003, deferred); the zero-inbound security group (aws_security_group.workstation above) is the real control preventing exploitation of the public IP's reachability. Checkov triage CKV_AWS_88 (B).
#checkov:skip=CKV_AWS_126:enable_detailed_monitoring = false is a deliberate cost decision for this single, disposable, manually operated dev workstation, consistent with this project's Cost Controls posture (ADR-0005); CloudTrail/CIS alarms/VPC Flow Logs already provide security-relevant monitoring -- this is a performance-observability setting, not a security control. Checkov triage CKV_AWS_126 (B).
#checkov:skip=CKV_AWS_135:ebs_optimized = true was added and then reverted after a real terraform plan against environments/dev proved it forces replacement of this real, existing dev workstation (2 to add, 2 to change, 1 to destroy) -- the real instance's ebs_optimized value is false, and the argument is ForceNew in the installed AWS provider schema. This project will not replace a functioning workstation solely for static-analysis compliance. Checkov triage CKV_AWS_135, reclassified A -> D 2026-08-07 with full live-evidence record; revisit only during an intentional workstation rebuild/instance-type migration.
resource "aws_instance" "workstation" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [aws_security_group.workstation.id]
  iam_instance_profile   = var.instance_profile_name

  associate_public_ip_address = true
  monitoring                  = var.enable_detailed_monitoring

  # NOTE (2026-08-07): an ebs_optimized = true argument briefly lived here,
  # added as a proposed remediation for CKV_AWS_135. REVERTED the same day
  # after a real `terraform plan` against environments/dev (run by the
  # user, on their own machine) confirmed it forces replacement of the
  # real, existing dev workstation: the real instance's current value is
  # ebs_optimized = false, not true as this project's design source had
  # assumed, and ebs_optimized is a ForceNew argument in the installed AWS
  # provider's schema -- the plan showed `2 to add, 2 to change, 1 to
  # destroy`, including a forced replacement of module.ec2_workstation.
  # aws_instance.workstation and follow-on updates to the dependent
  # EventBridge Scheduler shutdown resources. This project will not
  # replace a functioning workstation solely for static-analysis
  # compliance -- see 16_Implementation_Notes/Checkov_Triage_CI_CD_Slice_
  # 2A.md's CKV_AWS_135 entry (reclassified from REAL DEFECT to deferred
  # hardening) for the full disposition. Revisit only during an
  # intentional workstation rebuild or instance-type migration, when a
  # replacement is already happening for an unrelated reason.
  user_data = var.user_data

  # REVISED 2026-08-07 -- was `true`. Real Phase 0 Networking Hardening
  # deployment exposed a forced-replacement regression: routine, substantive
  # bootstrap-script evolution (Terraform installation, ssm-user-aware
  # installation, uv execution-context changes, ownership changes, the root
  # execution guard, v1.1.x revisions) triggered an automatic destroy/create
  # of the real, long-lived dev workstation (i-03fa5eeb7739b941b) as a side
  # effect of an unrelated, additive networking plan.
  #
  # SUPERSEDED same day: setting this to `false` alone only downgraded the
  # forced replacement to an in-place `~ user_data` modification -- a real
  # plan still showed a change on the existing instance. `user_data` is now
  # also listed in this resource's own `lifecycle.ignore_changes` (below),
  # so for this long-lived dev workstation, bootstrap user_data is treated
  # as launch-time configuration: subsequent bootstrap-script evolution is
  # source-controlled but is not pushed automatically into the existing EC2
  # instance by Terraform, in-place or otherwise. Workstation rebuilds/
  # re-bootstrap operations are explicit maintenance actions. See Dev_
  # Environment_Terraform_Implementation_Plan.md Section 29.7 and Section
  # 32, and this module's README ("No prevent_destroy" note).
  user_data_replace_on_change = false

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
    # instance is explicitly designed to be replaceable, not precious --
    # but, per the 2026-08-07 revision above, replacement must now be a
    # deliberate action, not an implicit side effect of an unrelated plan.
    create_before_destroy = false

    # REVISED 2026-08-07 -- real Phase 0 Networking Hardening regression
    # (see PROJECT_EXECUTION_JOURNAL.md and Networking.md for the incident
    # record). associate_public_ip_address is a launch-time-only argument
    # with no in-place update path; AWS's provider reads its post-launch
    # value back from whether the instance's primary ENI currently has an
    # associated public IP, which is null while the instance is stopped.
    # The source value below (true) remains the correct, unchanged, intended
    # design (Section 17) -- there is no different "restored" value to set.
    # Ignoring drift here only suppresses this stopped-instance refresh
    # artifact; it can never mask a real, actionable, in-place-fixable
    # difference, since no value of this argument can ever be applied
    # in-place to an existing instance.
    #
    # REVISED 2026-08-07 (second correction, same day) -- user_data added.
    # Setting user_data_replace_on_change = false (above) only converted the
    # forced replacement into an in-place modification; a real plan still
    # showed `~ user_data` on the existing, long-lived dev workstation. For
    # this workstation, bootstrap user_data is treated as launch-time
    # configuration: subsequent bootstrap-script evolution stays
    # source-controlled but is not pushed into the existing instance by
    # Terraform at all, in-place or otherwise. A rebuild/re-bootstrap onto a
    # newer script version is an explicit maintenance action (e.g. a manual
    # SSM-run of the updated script, or a deliberate `terraform apply
    # -replace`), not a side effect of routine `plan`/`apply`.
    ignore_changes = [
      associate_public_ip_address,
      user_data
    ]
  }
}
