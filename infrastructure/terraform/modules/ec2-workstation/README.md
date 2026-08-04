# modules/ec2-workstation

Status: **Code created, not yet validated, planned, or applied.** No AWS resource described here exists.

## Responsibility

Owns the compute-adjacent resources for the development workstation: its security group, the EC2 instance itself, its root volume, and its instance-metadata-service configuration. Kept separate from networking (`modules/vpc`) and identity (`modules/iam-workstation-role`) so this module's own logic (instance configuration detail) doesn't crowd out those other concerns' review surface (`Dev_Environment_Terraform_Implementation_Plan.md` Section 3.1).

## Resources owned

- `aws_security_group.workstation`
- `aws_instance.workstation`

## Inputs

| Variable | Description | Default |
|---|---|---|
| `project_name`, `environment` | Naming/tag identifiers. | none (required) |
| `vpc_id` | VPC the security group is created in. | none (required) |
| `subnet_id` | Public subnet the instance launches into. | none (required) |
| `instance_profile_name` | Instance profile to attach. | none (required) |
| `ami_id` | Exact AMI ID to launch. **No lookup performed in this module.** | none (required) |
| `instance_type` | `t3.medium`, `t3.large`, or `t3.xlarge` only — validated, all other values rejected. | `"t3.medium"` |
| `root_volume_size` | Root EBS volume size in GiB, minimum 30. | `30` |
| `user_data` | Rendered bootstrap-script content, or empty/placeholder. | `""` |
| `enable_detailed_monitoring` | CloudWatch 1-minute monitoring. | `false` |
| `tags` | Common tag map. | `{}` |

## Outputs

`instance_id`, `public_ip`, `security_group_id`.

## Security decisions

- **Zero inbound security-group rules — no exception, ever.** No rule for port 22, no rule for any development port, to any CIDR, including an operator's own IP. This holds regardless of the subnet being public. This is the primary security control this module relies on.
- **Unrestricted outbound access (revised 2026-07-26).** A single egress rule (`protocol = "-1"`, all ports, `0.0.0.0/0`) replaces a previously-considered scoped HTTPS-only rule. **Trade-off, accepted deliberately, not silently adopted:** if the instance were ever compromised, unrestricted egress gives more exfiltration/command-and-control flexibility than a narrow rule would. Accepted because (1) the workstation's actual toolchain port needs are hard to enumerate in advance and would likely get widened reactively anyway, (2) the primary control here is the zero-inbound rule set — nothing can *initiate* a connection to the instance regardless of what it can *initiate* outward, and (3) tightening egress to an observed allow-list remains an available future hardening step once real traffic patterns exist. See `Dev_Environment_Terraform_Implementation_Plan.md` Section 16 and its Decision Rationale entry for the full write-up.
- **IMDSv2 enforced**: `http_tokens = "required"`, `http_put_response_hop_limit = 1`, `instance_metadata_tags = "disabled"`. Closes the SSRF-to-credential-theft class of vulnerability that tokenless IMDSv1 requests leave open; hop limit of 1 keeps metadata responses local to the host (no proxy/container hop can retrieve them).
- **Root volume is `gp3`, 30 GiB minimum, encrypted** with the default AWS-managed key (no customer-managed KMS key, consistent with the project's existing SSE-S3/no-CMK posture). `delete_on_termination = true` — no orphaned, still-billing volume survives instance termination, consistent with the disposable-workstation model.
- **Detailed monitoring is `false` by default** — basic 5-minute CloudWatch metrics, for cost control.
- **No `prevent_destroy` lifecycle rule** — unlike bootstrap's protected state bucket and deployment role, this instance is explicitly designed to be replaceable (`Dev_Environment_Terraform_Implementation_Plan.md` Section 32).

## What this module intentionally does not manage

- **No AMI lookup.** `var.ami_id` is required with no default and no internal `data "aws_ami"` block — AMI resolution happens once, in the root module (`environments/dev/main.tf`), because AMI selection is region- and environment-specific and should be visible directly in the root's own `plan` output, not buried inside this module.
- **No IAM role, policy, or instance profile of its own** — it only ever consumes a ready-to-use `instance_profile_name` string. It never reasons about IAM trust policies or permissions.
- **No key pair, no SSH access of any kind.** Access is exclusively via AWS Systems Manager Session Manager, using the instance profile's SSM connectivity (attached in `modules/iam-workstation-role`).
- **No automatic-shutdown, monitoring/alarm, or snapshot resource** — all explicitly deferred to a future, separately authorized task.
