# environments/dev

Status: **Code created (2026-07-26); `fmt`/`validate`/`tflint` have since passed for real, twice, and Trivy has run once (see `PROJECT_EXECUTION_JOURNAL.md` Sections 27n-27o) — but this configuration itself is NOT yet fully planned, applied, or complete.** A real `backend.hcl`/`terraform.tfvars` now exist (private, gitignored). **Bootstrap Update 1 (this configuration's hard dependency, described below) is now FULLY COMPLETE and stable** (2026-07-26, see `PROJECT_EXECUTION_JOURNAL.md` Sections 27r-27z) — the deployment role's dev-scoped permissions, now split across three managed policies, are confirmed attached in real AWS with a real, successful `terraform apply` and a real, independent follow-up `terraform plan` reporting `No changes`. **Two real, partial `environments/dev terraform apply` attempts have already been run against earlier states of Bootstrap Update 1's permissions, and real AWS resources from those attempts DO exist**: a VPC, an Internet Gateway, and the workstation IAM role/its `AmazonSSMManagedInstanceCore` attachment/its instance profile. **`environments/dev` itself is NOT complete** — a fresh `terraform plan` against the now-stable Bootstrap Update 1 permissions has not yet been run or reviewed, and no `apply` should be attempted here until that review determines whether the existing partial resources reconcile or a replacement is proposed. See "Expected execution sequence" and "What has NOT been done" below for the current, precise state.

This is the first implementation of the design in `16_Implementation_Notes/Dev_Environment_Terraform_Implementation_Plan.md` (REVIEWED AND APPROVED, 2026-07-26). Read that document before making any change here — it is the authoritative source for every decision this configuration implements.

## Architecture

A single, composing root module (`environments/dev/`) wiring together three reusable modules:

- **`modules/vpc`** — a dedicated VPC (`10.20.0.0/16`), one public subnet (`10.20.1.0/24`, in a dynamically-selected Availability Zone), an Internet Gateway, and a public route table. No private subnet, no NAT Gateway, no VPC endpoint.
- **`modules/iam-workstation-role`** — the workstation's IAM role, its SSM connectivity, its narrow `sts:AssumeRole` permission against the shared deployment role, and its instance profile.
- **`modules/ec2-workstation`** — a zero-inbound security group and one EC2 instance (Amazon Linux 2023, x86_64, `t3.medium` by default), IMDSv2-enforced, with a 30 GiB encrypted `gp3` root volume.

No infrastructure resource is defined directly in this root module — only data sources (AMI lookup, caller-identity check), locals (tags, resolved AMI ID, bootstrap-script content), and the three `module` blocks above.

## Access through Session Manager

The workstation has **zero inbound security-group rules** — no port 22, no rule for any development port, to any CIDR. All access is via **AWS Systems Manager Session Manager**, which authenticates and authorizes through IAM policy rather than a distributed SSH key pair, requires no open inbound port, and centralizes session start/stop auditing in CloudTrail. The workstation role's `AmazonSSMManagedInstanceCore` attachment (`modules/iam-workstation-role`) is what lets the *instance* register with and respond to Session Manager; *who* is allowed to call `ssm:StartSession` against it is a separate, human-identity-side IAM concern not created by this configuration's own resources.

## SSH-over-SSM concept

For tools that expect a normal SSH connection (e.g., VS Code Remote-SSH), Session Manager supports **port forwarding over an SSM session** rather than a real SSH-over-TCP-port-22 connection: the AWS CLI's `aws ssm start-session` with the `AWS-StartSSHSession` document tunnels SSH traffic through the same IAM-authenticated, CloudTrail-audited channel Session Manager already uses — no inbound port 22 is ever opened on the security group for this to work. This is documented, not yet exercised — Session Manager and SSH-over-SSM testing are both explicitly out of scope for this file-creation task.

## Backend setup process (no real values)

1. Copy `backend.hcl.example` to `backend.hcl` (gitignored, never committed).
2. Replace `<STATE_BUCKET_NAME>` with the real state bucket name (same bucket `infrastructure/terraform/bootstrap` created — see its `state_bucket_name` output).
3. Replace `<DEPLOYMENT_ROLE_ARN>` with the real deployment role ARN (`infrastructure/terraform/bootstrap`'s `deployment_role_arn` output).
4. **Bootstrap Update 1 has now landed for real** (see below) — the deployment role has real, confirmed permissions to read/write `dev/terraform.tfstate`. A real `backend.hcl` already exists privately for this configuration; `terraform init` against it is no longer blocked by missing deployment-role permissions, though a fresh `terraform plan`/review (not yet run against the now-stable permission set) should precede any further `apply` here.
5. `key = "dev/terraform.tfstate"` is already correct and non-sensitive — do not change it without a deliberate, reviewed reason.

None of this has been executed as part of this task.

## Provider role assumption

`providers.tf`'s `aws` provider assumes the shared deployment role via its own `assume_role` block (`session_name = "terraform-dev-provider"`), functionally separate from `backend.hcl`'s own `assume_role` block (`session_name = "terraform-dev-backend"`) even though both point at the same role ARN — one governs state storage calls, the other governs resource-management API calls, and the distinct session names keep the two `AssumeRole` calls individually visible in CloudTrail. Neither block contains a credential — the identity used to reach the deployment role in the first place comes from whatever invokes Terraform (a human's MFA-authenticated session during the interim period before Bootstrap Update 2 lands; the EC2 workstation's own instance-profile credentials afterward).

## Expected execution sequence (current real status per step)

1. **Bootstrap Update 1** (`infrastructure/terraform/bootstrap/`) — attach the deployment role's permissions policy. **COMPLETE** — applied for real, three managed policies confirmed attached, a real follow-up `terraform plan` reported `No changes` (2026-07-26, see `PROJECT_EXECUTION_JOURNAL.md` Sections 27r-27z).
2. `terraform init -backend-config=backend.hcl` — **has been run in the course of the two real, partial apply attempts described below**; not confirmed clean and current against the now-stable Bootstrap Update 1 permissions.
3. `terraform fmt -check -recursive`, `terraform validate`, `tflint` — **run for real, twice, and passed/clean** (`PROJECT_EXECUTION_JOURNAL.md` Sections 27n-27o). Trivy — **run once**, five findings, all reviewed and dispositioned, not fully input-aware (Section 27o).
4. `terraform plan -out dev.tfplan`, manually reviewed — **run twice against earlier, now-superseded Bootstrap Update 1 permission states** (`dev_initial.tfplan`, `dev_recovery.tfplan`, both stale and not to be reused); **a fresh plan against the now-stable, final Bootstrap Update 1 permissions has NOT yet been run or reviewed.**
5. `terraform apply "dev.tfplan"` — **attempted twice, both times PARTIALLY SUCCEEDED THEN FAILED** on real, since-corrected deployment-role permission gaps (see `PROJECT_EXECUTION_JOURNAL.md` Sections 27s-27t). Real AWS resources from these attempts exist: a VPC, an Internet Gateway, the workstation IAM role, its `AmazonSSMManagedInstanceCore` attachment, its inline `AssumeRole` policy, and its instance profile. **No apply has been run since Bootstrap Update 1 reached its final, stable state — do not rerun `apply` until step 4's fresh plan is reviewed.**
6. AWS-side verification (`aws ec2 describe-*`, etc.) — not run against a completed, reconciled `environments/dev` state.
7. Session Manager connectivity test — not run.
8. **Bootstrap Update 2** (`infrastructure/terraform/bootstrap/`) — add the now-real `workstation_role_arn` output to the deployment role's trust policy. Not started, not coded. A separate, small, reviewed apply, strictly after step 5 succeeds and produces a real, final workstation-role ARN.

## Bootstrap Update 1 dependency

**Bootstrap Update 1 has been applied for real and is now fully complete and stable** — the shared deployment role has real, confirmed permissions attached in AWS (three managed policies), verified by both a successful `terraform apply` and a subsequent, independent `terraform plan` reporting `No changes` (2026-07-26, see `PROJECT_EXECUTION_JOURNAL.md` Sections 27r-27z and `infrastructure/terraform/bootstrap/README.md`). This configuration's provider and backend are therefore no longer blocked by missing deployment-role permissions. What remains outstanding is `environments/dev`'s OWN recovery: a fresh `terraform plan` against this now-stable permission set has not yet been run, and the two real partial resources created by the earlier, superseded apply attempts (the VPC, Internet Gateway, and workstation-role resources listed above) have not yet been reviewed for reconciliation vs. replacement under that fresh plan.

## Bootstrap Update 2 deferred step

Adding the workstation role's real ARN to the deployment role's trust policy (`infrastructure/terraform/bootstrap/`) is **strictly deferred** until *after* this configuration's own `apply` succeeds and produces a real `workstation_role_arn` output — the ARN cannot be referenced before the role exists. This is not part of this file-creation task and is not implemented in `bootstrap/main.tf` yet (only Update 1 is).

## No inbound ports

Zero `ingress` rules on the workstation security group (`modules/ec2-workstation`), with no exception — not for port 22, not for any development port, not for the operator's own IP. This holds regardless of the public subnet's IGW route. See that module's README for the accepted unrestricted-egress trade-off, which is a separate, independent decision from the (unconditional) zero-inbound posture.

## Cost-related decisions

- **`t3.medium` default instance sizing**, with `t3.large`/`t3.xlarge` available only via a deliberate, temporary, uncommitted `terraform.tfvars` edit — not a permanent default change.
- **Detailed monitoring disabled** (`false`) — basic 5-minute CloudWatch metrics, no additional per-instance charge.
- **No NAT Gateway** — the public-subnet/IGW model avoids a genuine, non-trivial recurring cost; the explicit trade-off (public IPv4 exposure, mitigated by the zero-inbound security group) is documented in the plan's Section 19.
- **`delete_on_termination = true`** on the root volume — no orphaned, still-billing EBS volume survives instance termination.
- **No customer-managed KMS key** — root volume encryption uses the default AWS-managed `aws/ebs` key, consistent with the project's existing SSE-S3/no-CMK cost posture.
- **Manual shutdown only** — no automatic-stop Lambda/EventBridge resource is created in this phase; the developer stops the instance manually at the end of each session.

## What has NOT been done (updated 2026-07-26 — supersedes the original file-creation-only status above)

**Still NOT done:** a fresh `terraform plan` against Bootstrap Update 1's final, stable permission set; any `terraform apply` since that permission set stabilized; AWS-side verification of a completed, reconciled `environments/dev` state; a Session Manager connectivity test; an SSH-over-SSM test; Bootstrap Update 2 (not coded); the native S3 lock contention test originally scheduled for this phase's own apply (still pending a successful, non-partial apply); reconciliation review of the VPC/Internet Gateway/workstation-role resources already created by the two earlier, partial apply attempts.

**Now done, updating this file's original "code evidence only" status:** `terraform fmt -check -recursive`/`terraform validate`/`tflint` have been run for real, twice, and passed clean; Trivy has run once with five findings, all dispositioned; two real `terraform init`/`plan`/`apply` sequences have been run against this configuration (both partially succeeded then failed on real, since-corrected Bootstrap Update 1 permission gaps); a real `backend.hcl`/`terraform.tfvars` exist privately for this configuration; Bootstrap Update 1, this configuration's hard dependency, is now fully complete. This configuration's own evidence therefore now spans multiple tiers of this project's seven-tier framework — Tier 2 (code), Tier 4 (validation), and Tier 6-adjacent (two real, partial deployment attempts) — but does **not** yet reach a completed Tier 6/7 (deployment/operational-verification) state for `environments/dev` as a whole, since no apply has succeeded in full and no fresh plan has been reviewed against the current, stable Bootstrap Update 1 permissions.
