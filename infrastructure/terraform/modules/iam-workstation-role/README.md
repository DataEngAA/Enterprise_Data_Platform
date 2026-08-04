# modules/iam-workstation-role

Status: **Code created; first local validation gate run (2026-07-26) via real `terraform fmt`/`init`/`validate`/TFLint on the user's own Windows machine — TFLint flagged this module's `project_name` input as unused (module resources are named entirely from `var.role_name`, which the caller already composes from `project_name`) and it has been removed.** This module has since been **planned and partially applied for real** as part of two `environments/dev terraform apply` attempts (2026-07-26) — both attempts partially succeeded then failed on unrelated, since-corrected deployment-role permission gaps (see `environments/dev/README.md` and `PROJECT_EXECUTION_JOURNAL.md` Sections 27s-27t), but this module's own resources were created successfully both times and remain live in real AWS: `aws_iam_role.workstation`, its `AmazonSSMManagedInstanceCore` attachment, its `assume_deployment_role` inline policy, and its instance profile. **This module's deployment is not confirmed reconciled or final** — `environments/dev` as a whole has not completed a successful apply, and a fresh `terraform plan` (against the deployment role's now-stable Bootstrap Update 1 permissions, see `infrastructure/terraform/bootstrap/README.md`) has not yet been run to confirm these existing resources are still current and correctly configured, rather than needing replacement.

## Responsibility

Owns the EC2 workstation's IAM identity end to end: its role, trust policy, SSM managed-policy attachment, narrow `sts:AssumeRole` inline policy, and its 1:1 instance profile. Kept separate from `modules/ec2-workstation` so the identity-and-permissions review surface never has to be read alongside EC2/networking configuration (`Dev_Environment_Terraform_Implementation_Plan.md` Section 3.1).

## Resources owned

- `aws_iam_role.workstation`
- `aws_iam_role_policy_attachment.ssm_managed_instance_core`
- `aws_iam_role_policy.assume_deployment_role`
- `aws_iam_instance_profile.workstation`
- `data.aws_iam_policy_document.workstation_trust`, `data.aws_iam_policy_document.assume_deployment_role`

## Inputs

| Variable | Description | Default |
|---|---|---|
| `environment` | Deployment environment (e.g. `"dev"`). | none (required) |
| `role_name` | Name of the workstation role (`enterprise-data-platform-dev-workstation-role`). | none (required) |
| `deployment_role_arn` | Exact ARN of the shared deployment role this role may assume. No default — account-specific. | none (required) |
| `tags` | Common tag map. | `{}` |

## Outputs

`role_name`, `role_arn` (needed later for Bootstrap Update 2's trust-policy addition — copy from real output, never retype), `instance_profile_name`, `instance_profile_arn`.

## Security decisions

- **Trust policy allows only the `ec2.amazonaws.com` service principal** — no human identity, no other AWS account, no wildcard principal can assume this role.
- **`sts:AssumeRole` is scoped to exactly one ARN** (`var.deployment_role_arn`) — no wildcard resource, no second role. This is the workstation role's *only* path to any infrastructure-management capability; it has no direct EC2/VPC/IAM permission of its own.
- **`AmazonSSMManagedInstanceCore`** (AWS-managed policy) is the only other attachment — required for Session Manager connectivity, nothing more.
- **The instance profile has a strict 1:1 relationship with this role** — no shared or multi-role instance profile.

## What this module intentionally does not manage

- **No IAM user, group, or access key** of any kind.
- **No `iam:CreateRole`/`iam:CreateUser`/`iam:CreateAccessKey`/`iam:CreatePolicy`** or any other broad IAM-administration permission is ever granted *to* this role — it can act as an assumable identity and nothing else.
- **No CloudWatch Logs or S3 artifact-bucket permission** — deliberately deferred until a concrete target (a real Log Group, a real bucket/prefix) exists (`Dev_Environment_Terraform_Implementation_Plan.md` Section 13); granting either now would mean permitting access to a resource that doesn't exist, or granting broader-than-necessary access just to have *something*.
- **No modification of the shared deployment role.** This module only ever *consumes* `var.deployment_role_arn` as an input string — it never creates, reads, or modifies the deployment role's own definition, trust policy, or permissions. That resource lives exclusively in `infrastructure/terraform/bootstrap/`.
- **No `ssm:StartSession` permission for any human identity** — that is a separate, operator-facing IAM concern outside this Terraform configuration's resources entirely (who is allowed to *start* a session is not the same question as what the *instance itself* needs to register with Session Manager).
