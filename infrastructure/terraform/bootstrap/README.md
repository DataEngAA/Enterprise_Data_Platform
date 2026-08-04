# Terraform Bootstrap

Status: **The Terraform Bootstrap phase is FORMALLY COMPLETE (2026-07-25).** See "Bootstrap Phase Completion Summary" below for the itemized closeout. Historical detail follows: code created, statically reviewed, formatted, initialized (local, `-backend=false`), validated, linted (TFLint, zero findings), security-scanned twice (Trivy, including an input-aware rerun), break-glass-documented (not drilled), planned (reviewed), `terraform apply` succeeded against real AWS with AWS-side verification completed, and the local-state-to-S3 migration succeeded with post-migration verification complete. `terraform apply "bootstrap.tfplan"` **succeeded** (2026-07-25): `Apply complete! Resources: 7 added, 0 changed, 0 destroyed.` All seven resources were created by Terraform, not manually in the AWS Console, and AWS CLI verification confirmed the state bucket's and deployment role's controls match the design -- see "Terraform Apply Results and AWS Verification" below. **State migration is now COMPLETE (2026-07-25): `terraform init -backend-config="backend.hcl" -migrate-state` succeeded, `terraform state list` returned all seven managed resources, `terraform plan` showed `0 to add, 0 to change, 0 to destroy.`, and `aws s3api head-object` confirmed the remote state object exists at `bootstrap/terraform.tfstate`** -- see "State Migration Results and Post-Migration Verification" below. **Native S3 locking (`use_lockfile = true`) is configured and active, and every backend operation run since migration (`state list`, `plan`, this migration itself) has succeeded without error -- this is passive evidence that the backend configuration works, not a deliberate contention test.** A real concurrent-lock scenario has not been exercised and is **not claimed as verified**. That deliberate test is **deferred to the `environments/dev` Terraform phase**, where a genuinely longer-running operation provides a safer and more natural window to observe lock contention than manufacturing an artificial one against the bootstrap configuration now -- see "Native S3 Locking Explanation" below. **Local-state cleanup is now COMPLETE (2026-07-25): a final `terraform state list` and `terraform plan` both succeeded (all seven resources present; `0 to add, 0 to change, 0 to destroy.`), and the obsolete local `terraform.tfstate` (a 0-byte local placeholder left behind by the backend migration) and `terraform.tfstate.backup` (Terraform's own automatic local backup, containing the prior local state copy, 19320 bytes) were both successfully removed from `infrastructure/terraform/bootstrap/`; no local `terraform.tfstate*` file remains in that directory.** See "Final Remote-State Checks and Local State Cleanup" below. **The temporary external backup created per "Future State Migration Sequence" step c has since been reviewed and successfully deleted (2026-07-25)** -- see "External Temporary Backup Deletion and Bootstrap Phase Closeout" below. This closes out all Terraform state cleanup for the bootstrap phase. **Native S3 locking contention testing remains deferred to the `environments/dev` Terraform phase and break-glass drilling remains untested** -- neither is implied by this cleanup, or by the bootstrap phase closeout, having succeeded. `terraform plan -out "bootstrap.tfplan"` **succeeded** (2026-07-25): `Plan: 7 to add, 0 to change, 0 to destroy.` -- see "Terraform Plan Results" below. `terraform fmt`, `terraform init -backend=false`, and `terraform validate` have all **succeeded** (2026-07-25) -- see "Local Validation Results" below. TFLint 0.64.0 found and corrected one unused-variable warning (`bootstrap_state_key`, since removed) and is now **completed with zero findings**. Trivy 0.72.0 completed a first Terraform misconfiguration scan with **two findings, both reviewed and accepted as Phase 0 design exceptions**, then a **second, input-aware rerun against a real, gitignored `terraform.tfvars`** confirmed the same two findings with no new findings and no unresolved-variable warning -- see "Security Scan Evidence" and "Input-Aware Security Scan Rerun" below; this is still not a clean/zero-findings scan. The break-glass and recovery procedure is documented (`16_Implementation_Notes/Terraform_Bootstrap_Break_Glass_Procedure.md`, see "Break-Glass Warning" below) -- **procedure documented, validation evidence pending** (it has not been tested or drilled). See "Commands Run So Far, and What Still Has Not Happened" at the end of this document for the full list of what has, and has not, actually been run. Two static-review correction passes (2026-07-25) have been applied -- see the per-file comments marked "corrected 2026-07-25" / "2026-07-25 static review" for specifics. The second pass changed the deployment role's permission model: it is now created with **no permissions policy attached at all** (see "Unresolved Permission Scope" below) -- an earlier draft's narrowly-scoped placeholder S3 policy was removed as part of that pass.

**Bootstrap Update 1 — code added 2026-07-26, reviewed and corrected 2026-07-26, then APPLIED FOR REAL, and now FULLY COMPLETE AND STABLE (verified 2026-07-26).** `main.tf` defines the deployment role's dev-scoped permissions, now split across **three** managed policies for real AWS IAM managed-policy size-quota reasons (see below): `aws_iam_policy.deployment_dev_permissions` (10 statements — dev Terraform state/lock access, EC2 read-only Describe, RunInstances + instance/volume lifecycle, instance metadata options, RunInstances tag-on-create), `aws_iam_policy.deployment_dev_networking_permissions` (12 statements — dev VPC/EC2 networking create-manage permissions), and `aws_iam_policy.deployment_dev_workstation_iam_permissions` (4 statements — IAM permissions scoped to exactly the dev workstation role/instance-profile name), each attached to `aws_iam_role.deployment` via its own `aws_iam_role_policy_attachment`. The role's trust policy is **unchanged** — it still trusts only the human bootstrap principal (MFA-conditioned); the workstation role is **not** trusted yet (that is Bootstrap Update 2, not yet implemented — see the comment block at the end of `main.tf`).

**Real-world history since the original 18-statement, single-policy version was first applied:** a review found and corrected a `DevRunInstances` condition-scoping defect (split into `DevRunInstancesAmi`/`DevRunInstancesSupportingResources`); a real, partial `environments/dev` apply surfaced a missing `ec2:DescribeVpcAttribute` permission, corrected; a second real partial apply surfaced a multi-resource-type `aws:RequestTag` authorization gap in networking create actions, corrected by restructuring into 8+2 statements (policy grew to 26 statements total); an attempt to apply that combined 26-statement policy then failed at `iam:CreatePolicyVersion` with `LimitExceeded: Cannot exceed quota for PolicySize: 6144` (no AWS-side change resulted) — corrected by splitting into two managed policies; the resulting `deployment_dev_permissions` document's own `lifecycle.precondition` then caught a SECOND size overage (6212 > 6144) entirely at plan time — corrected by splitting into a third managed policy; a real, reviewed `terraform plan` against that three-policy split then found an unexpected forced replacement of `deployment_dev_permissions` (caused by `description` being an immutable/`ForceNew` argument in the AWS provider, rewritten by both size-quota corrections) — corrected via `lifecycle.ignore_changes = [description]`; a real apply against that fix then detached and deleted the live `deployment_dev_permissions` policy and failed to recreate it with a real `ValidationError` (`description` exceeded IAM's 1,000-character hard limit) — corrected by shortening all three policies' descriptions and completing the `ignore_changes` rollout on the remaining two policies. **Following these corrections, a real `terraform apply` completed successfully, and a subsequent, fresh `terraform plan` reported `No changes. Your infrastructure matches the configuration.`** All three managed policies are confirmed attached to the shared deployment role in real AWS, exactly matching source. **Bootstrap Update 1 is now the stable project baseline.** Full incident-by-incident detail: `PROJECT_EXECUTION_JOURNAL.md` Sections 27r–27z; `16_Implementation_Notes/Bootstrap_Checklist.md`; `16_Implementation_Notes/Bootstrap_Update_1_Execution_Checklist.md`. `environments/dev` itself remains **NOT complete** — its own two real partial applies (a VPC, an Internet Gateway, and the workstation IAM role/instance-profile/attachment already created in real AWS) require a separate recovery sequence, not yet run against this now-stable permission set; this is a separate, still-open concern from Bootstrap Update 1's own completion. **Known, deliberately unfixed gap in this repository:** a separate comment elsewhere in `main.tf`, predating this update, may still describe Bootstrap Update 1 as not yet applied — if found, it should be treated as stale and superseded by this section, and corrected in a future, dedicated source-only pass rather than assumed accurate.

This is the authoritative implementation of the design in `02_Infrastructure/Terraform_Bootstrap_Design.md` and the plan in `16_Implementation_Notes/Terraform_Bootstrap_Implementation_Plan.md`. Read both before making any change here.

**For the full chronological process history** — what was attempted, why, what was found and corrected, every command actually run and its result, and the evidence level behind every claim in this README — see `16_Implementation_Notes/PROJECT_EXECUTION_JOURNAL.md`. This README states current status; the journal explains how that status was reached.

## Bootstrap Phase Completion Summary (2026-07-25)

**The Terraform Bootstrap phase (`infrastructure/terraform/bootstrap/`) is formally complete.** This section is the itemized closeout; every claim below is backed by a dedicated section elsewhere in this README (linked) and by `16_Implementation_Notes/PROJECT_EXECUTION_JOURNAL.md`.

Completed, with real, independently obtained evidence:

- **Code created** — all ten approved files written to `infrastructure/terraform/bootstrap/`, matching the approved design.
- **Validated** — `terraform fmt`, `terraform init -backend=false`, and `terraform validate` all succeeded. See "Local Validation Results" below.
- **Linted** — TFLint found and corrected one warning, then reran clean (zero findings).
- **Security-scanned** — Trivy scanned twice (once against unresolved variables, once input-aware against real, gitignored values); two findings both times, both reviewed and accepted as Phase 0 design exceptions, no new findings on the rerun. See "Security Scan Evidence" and "Input-Aware Security Scan Rerun" below.
- **Planned** — `terraform plan` succeeded and was manually reviewed in full against the approved design. See "Terraform Plan Results" below.
- **Applied** — `terraform apply` succeeded against real AWS; all seven resources were created by Terraform, not manually. See "Terraform Apply Results and AWS Verification" below.
- **AWS-verified** — AWS CLI checks confirmed the state bucket's and deployment role's real, deployed controls match the design. Same section as above.
- **Remote state migrated** — `terraform init -backend-config="backend.hcl" -migrate-state` succeeded, moving state into the S3 backend. See "State Migration Results and Post-Migration Verification" below.
- **No-change plan confirmed** — a `terraform plan` against the now-remote, now-real infrastructure showed `0 to add, 0 to change, 0 to destroy.`, both immediately after migration and again as a final recheck before cleanup. Same section as above and "Final Remote-State Checks and Local State Cleanup" below.
- **Obsolete local and temporary state backups removed** — the local `terraform.tfstate` (0-byte placeholder) and `terraform.tfstate.backup` (prior local state copy) were deleted from `infrastructure/terraform/bootstrap/`, and the separate, temporary external backup created for the migration window was also reviewed and deleted. See "Final Remote-State Checks and Local State Cleanup" and "External Temporary Backup Deletion and Bootstrap Phase Closeout" below.

**Deliberately still pending, not implied complete by any of the above:**

- **Native S3 locking contention testing** — `use_lockfile = true` is configured and active, and has only been exercised passively (error-free single-operation use); a deliberate concurrent-lock test has not been performed and is **deferred to the `environments/dev` Terraform phase**, where a genuinely longer-running operation gives a safer, more natural window to observe real contention.
- **Break-glass drill** — the recovery procedure (`16_Implementation_Notes/Terraform_Bootstrap_Break_Glass_Procedure.md`) is documented but has not been tested or drilled against any real incident.
- **`environments/dev`** — does not exist. No VPC, subnet, Internet Gateway, route table, workstation IAM role, security group, EC2 instance, or Session Manager access has been designed, planned, or created. Planning for it is the next task, tracked separately from this closeout.

No AWS resource was created, modified, or deleted as part of closing out this phase. No account ID, IAM username, ARN, bucket name, or state contents are reproduced anywhere in this document.

## Local Validation Results (2026-07-25)

The handoff sequence documented below (originally written after the Cowork-sandbox tooling blocker) was run from `infrastructure/terraform/bootstrap/` on a machine with a working `terraform` binary, with these verified results:

- `terraform fmt -recursive` **succeeded** and reformatted `variables.tf` (style/whitespace only -- no semantic change).
- `terraform fmt -check -recursive` **succeeded with no output**, confirming the tree was fully formatted after the pass above.
- `terraform init -backend=false` **succeeded**. The remote S3 backend was **not** configured or accessed -- `backend.tf`'s `s3` block remains commented out, and `-backend=false` skips backend initialization entirely regardless.
- AWS provider **`hashicorp/aws` v6.56.0** was installed, satisfying `versions.tf`'s `>= 6.0.0, < 7.0.0` constraint.
- **`.terraform.lock.hcl` was generated** (recording `hashicorp/aws` `6.56.0` and its checksums) -- **this file must be retained and committed to version control**, and never hand-edited (see "Provider Version Reproducibility" note in `versions.tf`'s own comments).
- `terraform validate` **succeeded**: `Success! The configuration is valid.`
- `terraform plan` and `terraform apply` were **not** run. No AWS CLI command was run. No AWS resource was created or modified. No real `terraform.tfvars` or `backend.hcl` file was created.
- **State migration and native S3 locking remain untested** -- neither `-migrate-state` nor a real concurrent-lock scenario is exercised by `init -backend=false`/`validate`.

This confirms Terraform-validation evidence (tier 4 of the seven evidence tiers in `17_Interview_Guide/Phase_0.md` Q63) for the first time. Plan, deployment, and operational-verification evidence (tiers 5-7) remain unobtained -- validation succeeding does not, by itself, authorize `plan` or `apply` (see "Break-Glass Warning" below, which still blocks `apply` regardless of validation status).

## Security Scan Evidence (Trivy, 2026-07-25)

**Trivy version 0.72.0** was run against this configuration with:

```text
trivy config --misconfig-scanners=terraform .
```

Terraform misconfiguration scanning completed. Trivy could not fully evaluate three required variables that have no default and no real value in this repository (`aws_account_id`, `human_bootstrap_principal_arn`, `state_bucket_name` -- all account-specific, gitignored-only inputs, see "Required Human Inputs" above) and warned accordingly. **This scan must be repeated once real, gitignored input values exist** (a real `terraform.tfvars`), since a scan run against unknown/unresolved values cannot fully evaluate every rule that depends on them.

**This run is not being described as clean or zero-findings.** It completed with **two findings, both reviewed and accepted as Phase 0 design exceptions** -- not false positives, and not suppressed or ignored in code:

| ID | Severity | Finding | Decision | Rationale | Residual risk | Reconsideration trigger |
|---|---|---|---|---|---|---|
| AWS-0089 | LOW | S3 bucket access logging is disabled on the state bucket | **Accepted Phase 0 design exception.** No access-logging bucket added now. | A correct access-logging implementation needs a separate, hardened destination bucket, its own IAM permissions, a retention policy, a cost estimate, and its own operational review -- none of which is in scope for a single-developer Pre-Phase bootstrap. Deferred to a later monitoring/hardening phase, not silently dropped. | Without access logs, there is no independent record of who read/wrote objects in the state bucket beyond what CloudTrail data events would separately provide (not configured here either). The bucket retains **versioning, SSE-S3 encryption, Block Public Access, `BucketOwnerEnforced` ownership controls, and a TLS-only bucket policy** regardless -- this finding does not indicate those controls are absent. | Revisit once a monitoring/hardening phase is reached, or sooner if a specific need for object-level access history arises (e.g., investigating unexpected state-bucket activity). |
| AWS-0132 | HIGH | S3 bucket does not use a customer-managed KMS key | **Accepted Phase 0 design exception.** Kept SSE-S3 (`AES256`); no customer-managed KMS key introduced. | Adding a CMK now merely to make the scanner pass would be adopting real, ongoing complexity (key policy design, key rotation, access-policy coordination between the key and the bucket) and cost for a single-developer bootstrap bucket that, by design, should not contain long-lived secrets in the first place (`Terraform_Bootstrap_Design.md` Section 9). It would also introduce a real bootstrap-lockout risk: a misconfigured key policy on the very state bucket bootstrap depends on could lock the bootstrap operator out of their own state. | Encryption at rest is still provided (SSE-S3/AES256) -- what's absent is customer control over the key itself (independent rotation, fine-grained decrypt-vs-read separation, per-key CloudTrail audit trail). | Revisit if a clear security/governance requirement emerges: a compliance mandate for customer-managed keys, a need for cross-account key-usage control, or a requirement for per-key audit granularity beyond S3 access logs (mirrors `Terraform_Bootstrap_Design.md` Section 9's existing SSE-S3-vs-SSE-KMS reconsideration trigger, Q20 in `17_Interview_Guide/Phase_0.md`). |

## Input-Aware Security Scan Rerun (Trivy, 2026-07-25)

The rerun required above has now been performed. **Trivy version 0.72.0** was run again from `infrastructure/terraform/bootstrap/`, this time against a real, gitignored `terraform.tfvars`:

```text
trivy config --misconfig-scanners=terraform --tf-vars terraform.tfvars .
```

Verified results:

- Terraform variable values were **successfully loaded** from `terraform.tfvars` -- Trivy could resolve `aws_account_id`, `human_bootstrap_principal_arn`, and `state_bucket_name` this time.
- **The prior "could not fully evaluate" missing-variable warning did not appear** on this run.
- **No parser errors occurred.**
- **No new findings appeared.** The same two findings from the first scan remained, unchanged: **AWS-0089 (LOW, S3 access logging disabled)** and **AWS-0132 (HIGH, no customer-managed KMS key)** -- both **remain accepted Phase 0 design exceptions**, per the table above; neither was suppressed or ignored in code (no `.trivyignore`, no inline ignore annotation).
- **This is still not being described as a clean or zero-findings scan.** Two findings stand, reviewed and accepted, exactly as before -- what changed is that this scan could evaluate the configuration with real input values rather than unresolved placeholders, not that the finding count went to zero.
- No `terraform plan` or `terraform apply` was run. No AWS CLI command was run. No AWS resource was created or modified. The real `terraform.tfvars` used for this scan is gitignored and its values are not reproduced anywhere in this repository's documentation.

**This completes the pre-`plan` validation/security gate this project tracked**: `terraform fmt`/`init`/`validate` (tier 4), TFLint (zero findings), and now an input-aware Trivy scan (two findings, both reviewed and accepted) have all completed. `tfsec`/`checkov` have still not been run. `terraform plan`, `terraform apply`, AWS resource creation, remote backend migration, and native-locking verification all remain separate, later, explicit authorizations -- none of them is authorized by this scan passing.

No Terraform code was changed in response to these findings, and no `.trivyignore` file or in-code suppression annotation (e.g. `#trivy:ignore`) was added -- both findings remain visible to any future scan, exactly as reported, with the decision recorded here rather than hidden.

No `terraform plan` or `terraform apply` was run as part of this scan. No AWS CLI command was run. No AWS resource was created or modified.

## State Migration Results and Post-Migration Verification (2026-07-25)

**Local Terraform state has been successfully migrated into the S3 backend. This extends operational-verification evidence (tier 7) to remote-state configuration and readability. Native S3 locking behavior has NOT been separately tested and is NOT claimed here.**

Migration command executed from `infrastructure/terraform/bootstrap/` on the same local Windows machine used for every prior command:

```text
terraform init -backend-config="backend.hcl" -migrate-state
```

Result: **succeeded.**

- Terraform reported: **"Successfully configured the backend \"s3\"."**
- Terraform reported: **"Terraform has been successfully initialized!"**
- AWS provider **`hashicorp/aws` v6.56.0 was reused** from `.terraform.lock.hcl` -- no new provider download, no version change.
- **No migration error occurred.**

**Three post-migration checks were then run, each independently, rather than trusting the migration's own success messages alone:**

1. **`terraform state list`** -- **succeeded.** All seven managed bootstrap resources (the "Terraform Plan Results" list below) were present, now read from the S3 backend rather than local state.
2. **`terraform plan`** -- **succeeded, with no changes proposed:** `0 to add, 0 to change, 0 to destroy.` This confirms the migrated remote state, the configuration, and the real, already-applied AWS resources all agree with nothing left to reconcile -- not an assumption, an independently obtained result.
3. **`aws s3api head-object`** -- **succeeded** for the object key `bootstrap/terraform.tfstate`, confirming the remote state object actually exists in the verified S3 state bucket (bucket name not reproduced here -- see "Required Human Inputs"; it is account-specific and gitignored).

**Conclusion: remote backend configuration, state migration, and remote-state readability are all confirmed with real, independently obtained evidence -- not merely a successful command exit code.**

**What this does NOT establish:**

- **A deliberate native S3 locking contention test has not been performed.** `use_lockfile = true` is configured and active, and every backend operation since migration (this migration itself, `terraform state list`, `terraform plan`) has succeeded without error -- this is **passive evidence** that the backend configuration works, not evidence that concurrent-lock contention is handled correctly. No real concurrent-lock scenario (two simultaneous operations contending for the same lock) has been deliberately exercised. **Explicit contention verification is deferred to the `environments/dev` Terraform phase**, where a genuinely longer-running operation provides a safer and more natural test window than manufacturing an artificial contention scenario against the bootstrap configuration. No `.tflock` object has been, or will be, manually created, deleted, or otherwise manipulated as part of this or any prior step.
- The break-glass procedure remains documented but untested/undrilled.
- No `environments/dev` infrastructure has been designed, planned, or created.

No AWS resource was created or modified by this migration beyond the state object itself moving into the already-existing, already-verified bucket. No credentials, bucket name, account ID, IAM username, ARN, or state contents are reproduced in this documentation.

## Final Remote-State Checks and Local State Cleanup (2026-07-25)

**A final remote-state readability and no-change check was run immediately before touching any local artifact, and the obsolete local state files have now been successfully removed. This completes local-state cleanup. It does NOT constitute or claim native S3 locking contention evidence, and it does NOT include deletion of the separate, temporary external backup.**

Commands executed from `infrastructure/terraform/bootstrap/` on the same local Windows machine used for every prior command:

**Final remote-state checks (rerun immediately before cleanup, not merely relied on from the earlier migration verification):**

1. **`terraform state list`** -- **succeeded.** Remote state remained readable; all seven managed bootstrap resources were present.
2. **`terraform plan`** -- **succeeded, with no changes proposed:** `No changes. Your infrastructure matches the configuration.` / `0 to add, 0 to change, 0 to destroy.`

**Local state files found before cleanup** (`Get-ChildItem .\terraform.tfstate*`):

- `terraform.tfstate` -- present, **0 bytes**. This is **the local placeholder file left behind after the backend migration** -- not a source of state data itself (the migration in "State Migration Results and Post-Migration Verification" above moved the actual state content into the S3 backend).
- `terraform.tfstate.backup` -- present, **19320 bytes**. This is **Terraform's own automatic local backup file, containing the prior local state copy** from before migration -- distinct from the separate, temporary *external* backup created per "Future State Migration Sequence" step c.

**Cleanup performed:**

- `Remove-Item .\terraform.tfstate` -- **succeeded.**
- `Remove-Item .\terraform.tfstate.backup` -- **succeeded.**

**Result confirmed** (`Get-ChildItem .\terraform.tfstate*`, after cleanup): **no local `terraform.tfstate*` files remain in the bootstrap directory.**

**Conclusion: local-state cleanup is complete.** Remote state (migrated and independently verified above) is now the sole copy of Terraform state for this configuration on disk in this directory. Remote-state migration, readability, and no-change-plan evidence obtained earlier (see "State Migration Results and Post-Migration Verification" above) are preserved unchanged by this cleanup -- this step only removes now-redundant local artifacts, it does not re-derive or replace that evidence.

**What this does NOT establish:**

- **A deliberate native S3 locking contention test has still not been performed and is not claimed.** This remains deferred to the `environments/dev` Terraform phase, unchanged by this cleanup -- see "Native S3 Locking Explanation" below. No `.tflock` object was touched as part of this cleanup.
- The break-glass procedure remains documented but untested/undrilled.
- No `environments/dev` infrastructure has been designed, planned, or created.

No AWS resource was created, modified, or queried as part of this cleanup beyond the two `terraform` commands above (which read existing state, they do not write to it). No credentials, bucket name, account ID, IAM username, ARN, or state contents are reproduced in this documentation.

## External Temporary Backup Deletion and Bootstrap Phase Closeout (2026-07-25)

**The separate, temporary external state backup -- created per "Future State Migration Sequence" step c, for the local-state-to-S3 migration window only -- has been reviewed and successfully deleted. This closes out all Terraform state cleanup for the bootstrap phase.**

Actions completed on the local Windows machine, against the external backup location (path not reproduced in this documentation, consistent with this project's practice of not reproducing machine-specific or account-specific paths/identifiers):

1. **Confirmed the temporary external backup existed** before taking any action on it.
2. **Deleted the backup file.** It was, by design, a single file created specifically to cover the local-state-to-S3 migration window (step c) -- not an ongoing or general-purpose backup.
3. **Confirmed the file no longer exists** after deletion.

**Context carried forward from the migration and cleanup already on record, unchanged by this step:** remote state had already been independently verified before this deletion -- `terraform state list` succeeded with all seven bootstrap resources present, `terraform plan` showed no changes, and the S3 state object's existence was confirmed (see "State Migration Results and Post-Migration Verification" above). The local `terraform.tfstate` and `terraform.tfstate.backup` files had already been removed (see "Final Remote-State Checks and Local State Cleanup" above). The S3 backend is the sole, authoritative Terraform state location for this configuration -- no local or external backup copy of bootstrap state remains anywhere.

**What was NOT touched by this deletion:** the S3 state object itself, `backend.hcl`, `terraform.tfvars`, `.terraform.lock.hcl`, and `.terraform/` contents were all left exactly as they were. No AWS resource was created, modified, or deleted.

**Conclusion: bootstrap state cleanup is complete in full** -- local placeholder, local automatic backup, and temporary external backup have all been removed, with remote S3 state as the sole remaining copy. **This does not constitute or claim native S3 locking contention evidence** (still deferred to `environments/dev`, unchanged) **and does not constitute break-glass testing** (the procedure remains documented, not drilled). See "Bootstrap Phase Completion Summary" near the top of this document for the full itemized closeout of the bootstrap phase as a whole.

## Terraform Apply Results and AWS Verification (2026-07-25)

**`terraform apply` has been run against real AWS and succeeded. This is deployment evidence (tier 6). AWS CLI verification of the created resources' controls has also been completed -- this is operational-verification evidence (tier 7) for the specific checks listed below. Native S3 locking contention verification and break-glass drilling remain separately incomplete (remote backend migration itself has since completed -- see "State Migration Results and Post-Migration Verification" above).**

Command executed from `infrastructure/terraform/bootstrap/` on the same local Windows machine used for all prior validation/lint/scan/plan work, applying the exact reviewed, saved plan file (not a fresh plan):

```text
terraform apply "bootstrap.tfplan"
```

Result: **succeeded.**

```text
Apply complete! Resources: 7 added, 0 changed, 0 destroyed.
```

All seven resources listed in "Terraform Plan Results" below were created by this apply -- **by Terraform, not manually through the AWS Console or CLI.** No resource was changed or destroyed. This is the first time any AWS resource belonging to this project has existed.

**AWS-side verification** was then performed using the AWS CLI to confirm the deployed resources actually match what was designed and applied, rather than trusting the apply's own success message alone. **AWS CLI output paging was encountered during these checks and resolved by adding `--no-cli-pager` to each command** -- a tooling/terminal detail, not a finding about the resources themselves.

**State bucket verification results** (bucket name not reproduced here -- see "Required Human Inputs"; it is account-specific and gitignored):

- Versioning: `Enabled`.
- Server-side encryption: `AES256` / SSE-S3, as designed -- no KMS key.
- Block Public Access: `BlockPublicAcls = true`, `IgnorePublicAcls = true`, `BlockPublicPolicy = true`, `RestrictPublicBuckets = true` -- all four confirmed.
- Object ownership: `BucketOwnerEnforced`, as designed.
- Bucket policy: contains an explicit `Deny` for `s3:*` when `aws:SecureTransport` is `false` -- the TLS-only policy applied correctly.

**Deployment role verification results** (full ARN and the trusted IAM user's identity not reproduced here):

- Role name: `enterprise-data-platform-shared-deployment-role`, matching the design.
- Maximum session duration: `3600` seconds (1 hour), as designed.
- Trust principal: the intended IAM user (the bootstrap identity), as designed.
- Trust condition: `aws:MultiFactorAuthPresent = true` is present, as designed.
- Attached managed policies: **none.**
- Inline policies: **none.**

This confirms the deployment role was created exactly as intended -- assumable only by the correct principal with MFA, and with **no permissions granted at all**, consistent with "Unresolved Permission Scope" below.

**Conclusion: the applied, real AWS resources match the reviewed plan and the approved design.** This satisfies `Terraform_Bootstrap_Design.md` Section 28.1's requirement that an apply is not considered successful until its hardening is verified against real AWS output, not just the applied configuration.

**What this does NOT establish:** remote backend migration has not happened (state is still local); native S3 locking has not been exercised or verified against a real concurrent-lock scenario; a no-change `terraform plan` has not yet been run against the now-real infrastructure to confirm the configuration and deployed state agree with nothing left to reconcile; the break-glass procedure remains documented but untested/undrilled; and no `environments/dev` infrastructure has been designed, planned, or created. Each of these is a separate, later, explicit task.

## Terraform Plan Results (2026-07-25)

**`terraform plan` has been run and saved, and manually reviewed. This is plan evidence (tier 5) -- it is not deployment evidence. No AWS resource exists yet.**

Command executed from `infrastructure/terraform/bootstrap/` on the local Windows machine used for all prior validation/lint/scan runs:

```text
terraform plan -out "bootstrap.tfplan"
```

Result: **succeeded.** Plan summary:

```text
Plan: 7 to add, 0 to change, 0 to destroy.
```

**A failed first attempt preceded this, preserved here as part of the real process:** the command form `terraform plan -out=bootstrap.tfplan` (equals sign, no space, no quotes) was tried first and failed with `Too many command line arguments.` The corrected form, `terraform plan -out "bootstrap.tfplan"` (space-separated, quoted), succeeded. This was a command-syntax error, not a configuration defect -- no file under `bootstrap/` was changed because of it.

**Seven resources proposed, matching the approved bootstrap scope exactly, with no unexpected resource, replacement, or destruction:**

1. `aws_iam_role.deployment`
2. `aws_s3_bucket.terraform_state`
3. `aws_s3_bucket_ownership_controls.terraform_state`
4. `aws_s3_bucket_policy.terraform_state`
5. `aws_s3_bucket_public_access_block.terraform_state`
6. `aws_s3_bucket_server_side_encryption_configuration.terraform_state`
7. `aws_s3_bucket_versioning.terraform_state`

**Manual review conclusions** (plan output reviewed in full, not just the summary line):

- Region: `ap-south-1`.
- Tags present as expected: `Environment = shared`, `Project = enterprise-data-platform`, `Owner = DataEngAA`, `CostCenter = personal-learning`, `DataClassification = internal`.
- S3 encryption: `AES256` / SSE-S3, as designed -- no KMS key referenced.
- S3 versioning: `Enabled`.
- S3 object ownership: `BucketOwnerEnforced`.
- All four S3 Block Public Access settings proposed as `true`.
- The TLS-only bucket policy denies `s3:*` when `aws:SecureTransport` is `false`, as designed.
- Deployment role name: `enterprise-data-platform-shared-deployment-role`.
- Deployment role's trust principal is the intended IAM user, with the MFA condition present.
- Deployment role max session duration: `3600` seconds (1 hour), as designed.
- **No permissions policy or policy attachment is proposed for the deployment role** -- consistent with the bootstrap-management-model decision (see "Unresolved Permission Scope").
- No VPC, EC2, NAT Gateway, KMS key, DynamoDB table, Lambda, Budget, CI/CD, or `test`/`stage`/`prod` resource appears anywhere in the plan.
- No resource is proposed for change, replacement, or destruction.
- The account-consistency (`allowed_account_ids` / the deployment role's `lifecycle.precondition`) checks passed sufficiently for planning to complete.
- **Conclusion: this plan matches the approved bootstrap scope exactly.**

**`bootstrap.tfplan` is a sensitive local binary Terraform plan artifact.** It can contain resolved variable values and is already covered by this repository's `.gitignore` (`*.tfplan`) -- it **must remain local, must not be committed, and must not be uploaded or shared anywhere**, including in chat, screenshots, or issue trackers. Its contents are not inspected or reproduced in this documentation.

**This plan has since been applied -- see "Terraform Apply Results and AWS Verification" above.** Remote backend configuration, state migration, and native-locking verification remain separate, later, explicit authorizations -- none of them was authorized by this plan having been reviewed or by the subsequent apply. Break-glass procedure testing/drilling also remains incomplete (see "Break-Glass Warning" below).

## Terraform Tooling Blocker and Handoff (2026-07-25) -- historical record, now resolved

`terraform version` was originally run from this directory in the Cowork sandbox used for documentation/review tasks and failed: `bash: line 1: terraform: command not found` (exit 127). That sandbox has no Terraform binary installed and no viable path to install one (no root/sudo access; every known Terraform/GitHub-release/conda/Docker distribution source is blocked by the sandbox's network allowlist). `terraform fmt`, `terraform init`, and `terraform validate` were consequently **not** run in that sandbox at that time -- per the stop-on-failure rule, no later command in the sequence was attempted once the first one failed. **This was an environment/tooling availability gap in the Cowork sandbox specifically, not evidence of a defect in any file in this directory**, and it has since been resolved by running the same sequence on a different machine that does have Terraform installed -- see "Local Validation Results" above for that outcome. The exact sequence used follows; it remains accurate as the reference command list for re-running this validation elsewhere (e.g., after a future code change):

```text
cd infrastructure/terraform/bootstrap
terraform version
terraform fmt -recursive
terraform fmt -check -recursive
terraform init -backend=false
terraform validate
```

Notes that still apply every time this sequence is re-run:

- No real `terraform.tfvars` or `backend.hcl` is created or needed for these five commands: `terraform validate` does not require concrete values for the account-specific variables (`aws_account_id`, `state_bucket_name`, `human_bootstrap_principal_arn`), and `-backend=false` means no backend configuration is read at all.
- `terraform plan` and `terraform apply` are explicitly **not** part of this sequence and must not be run as part of it -- they remain separate, later, explicit authorizations, as do state migration, native-locking verification against real AWS output, and creation of the IAM role or S3 bucket.

## Purpose

Creates the two things every other Terraform configuration in this project depends on:

1. A hardened, versioned, encrypted S3 bucket to hold Terraform remote state (with native S3 locking, no DynamoDB).
2. A Terraform deployment IAM role, established now with its trust policy (assumable only by the human bootstrap identity, with MFA) but **no permissions policy attached** -- see "Unresolved Permission Scope" for why and what a future change will add.

Everything else (VPC, EC2 workstation, workstation IAM role) is explicitly out of scope for this configuration -- see "Items Deliberately Out of Scope" below.

## Prerequisites

- Terraform >= 1.10 installed. Confirm the exact installed version with `terraform version` immediately before running any command here -- see `versions.tf`.
- AWS provider version confirmed compatible against the constraint in `versions.tf` (>= 6.0.0, < 7.0.0) -- check https://registry.terraform.io/providers/hashicorp/aws/latest before `terraform init`.
- The 12-digit AWS account ID this configuration must run against, ready to put in `terraform.tfvars` as `aws_account_id`. `providers.tf`'s `allowed_account_ids` uses it as a safety check: the AWS provider checks the active credentials' account via AWS STS during provider configuration and prevents any resource-management operation in this configuration if the account doesn't match -- it does not stop that one STS check itself, it stops what would happen after it.
- AWS credentials for the human bootstrap identity available to the AWS provider (e.g. `aws configure`, an SSO profile, or environment variables). This configuration runs directly as that identity -- there is no `assume_role` (see `providers.tf`).
- **The human bootstrap identity must currently be an IAM user**, not an IAM Identity Center / federated identity. This implementation's trust-policy design (`main.tf`, `variables.tf`) only supports a static IAM user ARN (`arn:aws:iam::<account-id>:user/<user-name>`) -- an STS assumed-role ARN (which is what a federated/Identity Center sign-in produces) does not match this trust condition. Federated/IAM Identity Center support is deliberately deferred to a future, separate trust-policy design, not silently assumed to already work here.
- That IAM user needs sufficient bootstrap-scoped permissions of its own to create the resources in `main.tf` (state bucket + hardening, the deployment role) -- exact bootstrap-operator permissions are the human identity's own IAM setup, outside this configuration's scope. The deployment role itself is created with no permissions policy attached (see "Unresolved Permission Scope"), so assuming it currently grants no ability to call AWS APIs -- assumability with MFA present is nonetheless required and enforced by the trust policy (`main.tf`), since a future change will attach real permissions to this same role.
- `human_bootstrap_principal_arn`'s account ID must match `aws_account_id` -- `aws_iam_role.deployment`'s `lifecycle.precondition` (`main.tf`) fails the plan/apply if they don't, rather than silently creating a role trusting a principal from an unexpected account.
- Root and IAM user MFA already verified enabled (`02_Infrastructure/AWS_Account_Preparation.md` Section 8).
- The account-specific values below, ready to put in a real `terraform.tfvars`.

## Required Human Inputs

Three variables have no default and must be supplied via a real, gitignored `terraform.tfvars` (copy `terraform.tfvars.example`):

| Variable | How to obtain it |
|---|---|
| `aws_account_id` | The 12-digit account ID this apply must run against. Get it with `aws sts get-caller-identity --query Account --output text`. |
| `state_bucket_name` | Must be globally unique across all AWS accounts. Recommended: `enterprise-data-platform-tfstate-<AWS_ACCOUNT_ID>` (`Terraform_Bootstrap_Design.md` Section 7). |
| `human_bootstrap_principal_arn` | The ARN of the human **IAM user** running this apply, in the form `arn:aws:iam::<account-id>:user/<user-name>` -- not an IAM Identity Center or other STS assumed-role ARN (see "Prerequisites" above). Get it with `aws sts get-caller-identity --query Arn --output text`. |

No AWS account ID, ARN, or bucket name is invented anywhere in this configuration -- all three required inputs above have no default, and `variables.tf` validates their basic shape without asserting a real value.

**Backend configuration is intentionally separate from these input variables.** The state bucket's object key (`bootstrap/terraform.tfstate`, the approved bootstrap state key per `Terraform_Bootstrap_Design.md` Section 8) is supplied only via `backend.hcl` at `terraform init -backend-config=backend.hcl` time -- it is not, and does not need to be, a Terraform variable in `variables.tf`. Terraform backend settings are read before any variable is evaluated, so there was never a real need for a variable to "match" here; `backend.hcl.example`'s `key` value is the single source of truth for this state object's location.

## Local-State-First Bootstrap Sequence (all six steps below have now been exercised)

Corrected command order (2026-07-25 static review): `init` runs before `validate`, not after -- `validate` needs an initialized working directory (providers/modules downloaded) to check configuration internal consistency, so running it before `init` is not the intended order.

1. `terraform fmt -check -recursive` -- **already run and succeeded** (2026-07-25) as part of the validation-only handoff, see "Local Validation Results" above (that handoff also ran `fmt -recursive` first).
2. `terraform init` -- `backend.tf`'s `backend "s3" {}` block is still commented out at this point, so this uses Terraform's default **local** backend. This is deliberate: the S3 bucket the backend would point at does not exist yet, because this apply is what creates it. **Already run (as `terraform init -backend=false`) and succeeded** -- downloaded/verified AWS provider `hashicorp/aws` v6.56.0 and generated `.terraform.lock.hcl` (see "Local Validation Results" above; `-backend=false` and plain `init` are equivalent here since no backend is configured either way).
3. `terraform validate` -- **already run and succeeded**: `Success! The configuration is valid.` (see "Local Validation Results" above).
4. `terraform plan -out "bootstrap.tfplan"` -- **already run and succeeded** (2026-07-25): `Plan: 7 to add, 0 to change, 0 to destroy.` Reviewed and confirmed: the state bucket and its hardening resources (versioning, SSE-S3 encryption, Block Public Access, ownership controls, TLS-only bucket policy) and the deployment role (with no permissions policy attached, per "Unresolved Permission Scope" below) are the only resources proposed; no unexpected destroy/replace; tags include `Environment = shared`; `prevent_destroy` is present on the bucket and role; the role's account-consistency precondition (`main.tf`) passes. See "Terraform Plan Results" above for full detail. **Note the exact command syntax:** `-out "bootstrap.tfplan"` (space-separated, quoted) succeeds; `-out=bootstrap.tfplan` (equals sign) fails with `Too many command line arguments.`
5. `terraform apply "bootstrap.tfplan"` -- **already run and succeeded** (2026-07-25): `Apply complete! Resources: 7 added, 0 changed, 0 destroyed.` All seven resources were created by Terraform, not manually. See "Terraform Apply Results and AWS Verification" above.
6. Verify the bucket's hardening against **real AWS output**, not just the applied config (commands below) -- **already done** (2026-07-25) via the AWS CLI (with `--no-cli-pager`, see above): versioning, encryption, all four Block Public Access settings, ownership controls, and the TLS-only bucket policy all confirmed; the deployment role's name, trust principal, MFA condition, max session duration, and absence of any attached/inline policy all confirmed. See "Terraform Apply Results and AWS Verification" above for full detail.

## Future State Migration Sequence

**Steps (a) through (l) below have now been executed and succeeded (2026-07-25) -- see "State Migration Results and Post-Migration Verification" above for full detail. Step (m), a deliberate native-locking contention test, is deferred to the `environments/dev` Terraform phase rather than performed here -- see "Native S3 Locking Explanation" below. Step (n), cleanup, is now fully COMPLETE -- the local `terraform.tfstate`/`terraform.tfstate.backup` files and the separate, temporary external backup have all been reviewed and successfully removed. See "Final Remote-State Checks and Local State Cleanup" and "External Temporary Backup Deletion and Bootstrap Phase Closeout" above. This closes out the migration sequence and the bootstrap phase's Terraform state cleanup.**

a. **Confirm no Terraform operation is active.** No concurrent `plan`/`apply`/`init` should be running against this configuration, on this or any other machine, before starting. **Done.**

b. **Confirm the local `terraform.tfstate` exists.** It was generated by the 2026-07-25 apply and has not been removed. **Done.**

c. **Create one encrypted/access-controlled temporary backup of local state.** `terraform.tfstate` can contain sensitive values -- this is not a casual plaintext copy. **Done -- the backup was retained through the migration window and has since been reviewed and deleted** (see "State Safety" below and step (n)).

d. **Copy `backend.hcl.example` to `backend.hcl`.** `backend.hcl` is gitignored and must never be committed. **Done.**

e. **Replace only the `bucket` placeholder with the real bucket name.** `key` (`bootstrap/terraform.tfstate`), `region` (`ap-south-1`), `encrypt` (`true`), and `use_lockfile` (`true`) were already the approved real values and did not need to change. **Done.**

f. **Confirm `backend.hcl` is ignored by Git.** **Done** -- `.gitignore` already lists `backend.hcl` with a `!backend.hcl.example` negation.

g. **Run:**
   ```text
   terraform init -backend-config="backend.hcl" -migrate-state
   ```
   **Done and succeeded** -- see "State Migration Results and Post-Migration Verification" above.

h. **Review and answer Terraform's state-migration confirmation prompt.** **Done.**

i. **Run `terraform state list`.** **Done -- succeeded, all seven resources present.**

j. **Run `terraform plan`.** **Done -- succeeded.**

k. **Confirm the post-migration plan is `0 to add, 0 to change, 0 to destroy.`** **Done -- confirmed.** This is the actual verification that migrated remote state matches both the configuration and the real, already-applied AWS resources -- not an assumption.

l. **Verify the S3 state object exists at `bootstrap/terraform.tfstate`.** **Done -- confirmed via `aws s3api head-object`.**

m. **Deliberate native-locking contention test -- deferred, not skipped.** A real concurrent-lock scenario is not exercised by migration or a normal `plan`/`apply`, and is not manufactured artificially against the bootstrap configuration. `use_lockfile = true` is active and every backend operation run so far has succeeded without error, which is passive evidence the configuration works -- it is explicitly **not** claimed as contention-tested evidence. **This verification is deferred to the `environments/dev` Terraform phase**, where a genuinely longer-running operation gives a safer, more natural window to observe real lock contention than staging one now. No `.tflock` object is to be manually created, deleted, or otherwise manipulated to simulate this. *Deferred, not run in this task.*

n. **Cleanup, in two parts, no longer gated behind step (m) -- both parts now Done.** With remote-state verification (step k) independently confirmed, and a final remote-state readability/no-change recheck run immediately beforehand, the **obsolete local `terraform.tfstate` (0-byte placeholder) and `terraform.tfstate.backup` (prior local state copy) were both removed (2026-07-25) -- Done.** See "Final Remote-State Checks and Local State Cleanup" above. The **temporary external backup from step (c) was subsequently reviewed and deleted (2026-07-25) -- Done.** See "External Temporary Backup Deletion and Bootstrap Phase Closeout" above. No local or external copy of bootstrap Terraform state remains outside the S3 backend.

## State Safety

These rules apply throughout the migration sequence above and beyond it, for as long as any local or backup copy of `terraform.tfstate` exists:

- **`terraform.tfstate` may contain sensitive information** (resource attributes, sometimes values that look like secrets even when no secret was intentionally stored) and must be treated accordingly.
- **`terraform.tfstate` must not be committed or shared** -- already enforced by `.gitignore` (`*.tfstate`, `*.tfstate.*`).
- **`backend.hcl` must not be committed or shared** -- already enforced by `.gitignore` (`backend.hcl`, with `!backend.hcl.example` as the only tracked exception).
- **Any state backup must be encrypted or access-controlled** -- never a plain, world-readable copy, even temporarily.
- **Do not delete local state before confirming remote state is readable** -- step (n) above is explicitly gated behind step (k), not attempted earlier "to save a step."
- **Do not manually upload `terraform.tfstate` into S3.** Only `terraform init -backend-config=... -migrate-state` performs a correct migration; a manual upload bypasses Terraform's own state-handling and locking logic entirely.
- **Do not use `aws s3 cp` as a substitute for Terraform state migration**, for the same reason.
- **Do not edit the state file manually**, under any circumstance -- treat it as an opaque artifact Terraform itself manages.
- **Do not run `terraform state push` unless a separately reviewed recovery situation requires it** -- it is a break-glass-adjacent operation (`Terraform_Bootstrap_Break_Glass_Procedure.md`), not a normal migration step.
- **Do not use `force-unlock` during normal migration.** A lock during migration is expected, correct behavior while the operation is in flight, not an incident to clear.
- **Do not delete a `.tflock` object without first proving no active Terraform process exists** -- per `Terraform_Bootstrap_Break_Glass_Procedure.md` Sections 13-15, diagnosis always precedes any lock-clearing action, and direct object deletion is a last resort gated behind explicit approval, never a first response.

## Native S3 Locking Explanation

This configuration uses Terraform's native S3 state locking (`use_lockfile = true`, supplied via `backend.hcl` at init time), which requires Terraform >= 1.10. It performs atomic conditional writes directly against the state bucket to acquire/release a lock -- **no DynamoDB table is created or required**. This was an approved decision (`Terraform_Bootstrap_Design.md` Section 6) for simplicity, lower cost, and a smaller operational surface, accepted with the trade-off of a shorter track record than the traditional S3+DynamoDB pattern.

**Status (2026-07-25): `use_lockfile = true` is now active** -- it was supplied via the real `backend.hcl` used for the successful migration above, and every backend operation since migration (the migration itself, `terraform state list`, `terraform plan`) has implicitly exercised a single-operation lock acquire/release without error. **This is passive evidence that the backend configuration works -- it is not the same as verified concurrent-lock contention behavior, and is not claimed as such.** A real concurrent-lock scenario (two simultaneous operations contending for the same lock, one correctly blocked or made to wait) has not been deliberately exercised. Rather than manufacture an artificial contention test against the bootstrap configuration -- which normally runs single-operator, infrequent commands -- **this verification is deliberately deferred to the `environments/dev` Terraform phase**, where genuinely longer-running operations (VPC/EC2 applies) provide a safer and more natural window in which to observe real lock contention. No `.tflock` object is to be manually created, deleted, or otherwise manipulated in the interim.

## Verification Commands

**These commands have now actually been run** (2026-07-25) against the real, applied resources -- see "Terraform Apply Results and AWS Verification" above for the results. AWS CLI output paging was hit during this and resolved with `--no-cli-pager`; that flag is included below as the actually-used form:

```text
aws s3api get-bucket-versioning        --bucket <STATE_BUCKET_NAME> --no-cli-pager
aws s3api get-bucket-encryption        --bucket <STATE_BUCKET_NAME> --no-cli-pager
aws s3api get-public-access-block      --bucket <STATE_BUCKET_NAME> --no-cli-pager
aws s3api get-bucket-ownership-controls --bucket <STATE_BUCKET_NAME> --no-cli-pager
aws s3api get-bucket-policy            --bucket <STATE_BUCKET_NAME> --no-cli-pager
aws iam get-role                       --role-name <DEPLOYMENT_ROLE_NAME> --no-cli-pager
aws iam list-attached-role-policies    --role-name <DEPLOYMENT_ROLE_NAME> --no-cli-pager  # confirmed empty -- no managed policy attached (see "Unresolved Permission Scope")
aws iam list-role-policies             --role-name <DEPLOYMENT_ROLE_NAME> --no-cli-pager  # confirmed empty -- no inline policy either
```

## Partial-Apply Recovery Guidance

If an `apply` fails partway through (`Terraform_Bootstrap_Design.md` Section 28.3):

1. **Do not improvise deletion.** Inspect first: `terraform state list`, `terraform plan`, and targeted `aws` CLI checks (`aws s3api head-bucket`, `aws iam get-role`) for each resource in `main.tf`.
2. **Resource exists in AWS but missing from state:** use `terraform import` (see below), then `terraform plan` to confirm no unexpected diff.
3. **Resource partially configured** (e.g. bucket created but a hardening sub-resource not yet applied): re-running `terraform apply` against the same, unmodified configuration is the normal, safe path -- every resource here is idempotent, with no non-idempotent provisioners.
4. Treat the bucket, its hardening sub-resources, and the deployment role as individually re-checkable, not as one atomic unit.

## terraform import Guidance

**The commands below are illustrative, not exhaustive** -- the actual set of `import` commands needed after a partial apply depends on exactly which resources AWS shows as already created (README.md "Partial-Apply Recovery Guidance" step 1: inspect before acting). Every resource `main.tf` defines can potentially need an import, including the ones easy to forget because they don't feel like "the bucket" or "the role" on their own -- encryption configuration and bucket policy in particular:

```text
terraform import aws_s3_bucket.terraform_state <STATE_BUCKET_NAME>
terraform import aws_s3_bucket_versioning.terraform_state <STATE_BUCKET_NAME>
terraform import aws_s3_bucket_server_side_encryption_configuration.terraform_state <STATE_BUCKET_NAME>
terraform import aws_s3_bucket_public_access_block.terraform_state <STATE_BUCKET_NAME>
terraform import aws_s3_bucket_ownership_controls.terraform_state <STATE_BUCKET_NAME>
terraform import aws_s3_bucket_policy.terraform_state <STATE_BUCKET_NAME>
terraform import aws_iam_role.deployment <DEPLOYMENT_ROLE_NAME>
```

(No `aws_iam_policy`/`aws_iam_role_policy_attachment` import is listed -- as of the 2026-07-25 permission-model correction, `main.tf` defines no such resources; the deployment role has no permissions policy attached, see "Unresolved Permission Scope".)

Always follow an `import` with `terraform plan` to confirm the imported resource matches this configuration with no unexpected diff, before proceeding to any further `apply`.

## Break-Glass Warning

**Procedure documented; validation evidence pending.** The break-glass and recovery procedure required by `Terraform_Bootstrap_Design.md` Section 28.2 and the implementation plan (Section 29) is now written: `16_Implementation_Notes/Terraform_Bootstrap_Break_Glass_Procedure.md`. It covers the normal vs. emergency access path, recovery for a misconfigured deployment-role trust policy, lost bootstrap-operator access, an inaccessible or lost state bucket/state file, a stale native S3 `.tflock` object (including when `force-unlock` vs. direct lock-object deletion is and is not appropriate), `terraform import` for out-of-state resources, safe handling of `prevent_destroy`, root's emergency-only role, and required evidence capture and post-incident review. **This procedure has not been tested, drilled, or exercised against any real incident or AWS resource** -- writing it down satisfied the "documented before `apply`" requirement that gated the first `terraform apply` (now completed, see "Terraform Apply Results and AWS Verification" above), but it does not itself constitute evidence that any recovery step actually works. The same standing requirement applies again before the future state-migration apply and before any `environments/dev` apply -- documentation existing is not the same as the procedure having been tested.

## Destruction Protection Warning

`prevent_destroy = true` is set on both the state bucket and the deployment role. This blocks Terraform-initiated destruction (`terraform destroy`, or a plan that would replace/remove either resource) -- it is **not** a complete guarantee:

- It does **not** prevent deletion via the AWS Console/CLI by any identity with sufficient IAM permission outside Terraform.
- It does **not** prevent a deliberate `terraform state rm` followed by manual deletion.
- It does **not** prevent account-root-level deletion.

Supplementary controls this design relies on alongside it: the deployment role currently has **no permissions policy attached at all** (see "Unresolved Permission Scope" below), so it cannot call `s3:DeleteBucket` or any other destructive action, on these or any resources, full stop -- not because delete was specifically excluded from a granted policy, but because nothing is granted; S3 versioning protects object-level state data even if something is overwritten; and any removal of `prevent_destroy` itself must be a deliberate, reviewed source change, never a quick local workaround.

## Unresolved Permission Scope

**As of the 2026-07-25 bootstrap-management-model decision, `aws_iam_role.deployment` (`main.tf`) has NO permissions policy attached at all.** An earlier static-review draft attached a narrowly-scoped placeholder S3 policy (state-object and lock-object access only); that policy, and the `aws_iam_policy`/`aws_iam_role_policy_attachment` resources that defined and attached it, have been **removed**, not merely narrowed further. The role exists with only its trust policy (`data.aws_iam_policy_document.deployment_role_trust`) -- a session that assumes it can authenticate (subject to the MFA condition) but cannot call any AWS API that requires permissions.

Why: this bootstrap root module remains a human-administered exception -- its own provider and backend run as the human bootstrap identity directly (`providers.tf`), never via this role. The deployment role's actual purpose is to **later** manage `environments/dev` (VPC, workstation IAM role, EC2), not this bootstrap configuration's own state. Granting it access to `bootstrap/terraform.tfstate` would let a role whose job is managing dev infrastructure also read/write the state object that defines the deployment role itself and the state bucket's hardening -- an unnecessary, self-referential expansion of blast radius that this design avoids by granting it nothing here.

A future, separately reviewed change will attach a permissions policy (or policies) to this role covering, at minimum:

- Exact-object access (not bucket-wide) to the `environments/dev` state object and its native-locking lock object, once that root module has its own state key.
- Approved VPC, IAM (narrowly, for the workstation role only), and EC2 deployment permissions, once `environments/dev` is designed and approved (`Terraform_Bootstrap_Design.md` Section 30; `Terraform_Bootstrap_Implementation_Plan.md` Section 29).

That future policy is **not** `AdministratorAccess` and **not** a wildcard/account-wide grant -- and, until it exists, this role is not usable for any resource-management purpose at all. Do not treat the current no-permissions state as a placeholder that already grants something narrow; it grants nothing.

## Items Deliberately Out of Scope

Not created by this configuration, and not to be added to it without a separate, explicit task:

- `modules/`, `environments/`, `shared/`, and any `test/`/`stage/`/`prod/` directory.
- Any permissions policy attached to `aws_iam_role.deployment` -- see "Unresolved Permission Scope".
- VPC, subnets, Internet Gateway, route tables.
- The EC2 workstation IAM role, instance profile, or security group.
- The EC2 instance itself.
- Trust for the future workstation role in the deployment role's trust policy -- that role does not exist yet; adding it is a separate, later, reviewed change to `aws_iam_role.deployment`'s trust policy.
- A DynamoDB lock table (native S3 locking is used instead).
- A customer-managed KMS key (SSE-S3 only).
- A separate S3 access-logging bucket.
- Cross-region or cross-account replication for the state bucket.
- Lifecycle-expiration rules for old state object versions.
- Any CloudWatch alarm, EventBridge rule, or Lambda function (autostop, monitoring).
- `aws_budgets_budget` (the existing AWS Budget stays manually managed).
- Any CI/CD workflow or role.

## Commands Run So Far, and What Still Has Not Happened

`terraform fmt -recursive`, `terraform fmt -check -recursive`, `terraform init -backend=false`, and `terraform validate` **have been run and have succeeded** (2026-07-25) -- see "Local Validation Results" above. `tflint --init` and `tflint` runs **have been run**, found and corrected one unused-variable warning, and are now **completed with zero findings**. `trivy config --misconfig-scanners=terraform .` **has been run twice** -- once against unresolved variables, once (`--tf-vars terraform.tfvars`) against real, gitignored input values -- and both runs completed with the same two findings, both accepted as design exceptions; see "Security Scan Evidence" and "Input-Aware Security Scan Rerun" above. **A real, gitignored `terraform.tfvars` now exists on the machine used for these runs** (its values are not reproduced in this repository or its documentation). `tfsec`/`checkov` have not been run. **`terraform plan -out "bootstrap.tfplan"` has been run and succeeded** (2026-07-25): `Plan: 7 to add, 0 to change, 0 to destroy.`, manually reviewed and confirmed to match the approved bootstrap scope -- see "Terraform Plan Results" above. An earlier, differently-formed plan command (`-out=bootstrap.tfplan`) failed with `Too many command line arguments.` before the corrected form succeeded. **`terraform apply "bootstrap.tfplan"` has been run and succeeded** (2026-07-25): `Apply complete! Resources: 7 added, 0 changed, 0 destroyed.` -- all seven resources created by Terraform, not manually through the AWS Console. **The AWS CLI has been used** (`--no-cli-pager`, after paging was first encountered) to verify the state bucket's and deployment role's controls against real AWS output -- see "Terraform Apply Results and AWS Verification" above. `bootstrap.tfplan` is a sensitive local binary artifact, already `.gitignore`d, and must remain local, unshared, and uncommitted. A break-glass procedure **has been documented** (`16_Implementation_Notes/Terraform_Bootstrap_Break_Glass_Procedure.md`), though it has not been tested or drilled. **Backend-migration preparation was completed** (2026-07-25): `backend.tf`'s partial `backend "s3" {}` block was activated (uncommented, no hardcoded values, no `assume_role`, no DynamoDB), `backend.hcl.example` was confirmed to contain only the five approved placeholder settings, and the full migration sequence (steps a-n) plus state-safety rules were documented. **State migration has since been run and succeeded** (2026-07-25): `terraform init -backend-config="backend.hcl" -migrate-state` reported `Successfully configured the backend "s3".` and `Terraform has been successfully initialized!`, reusing AWS provider `hashicorp/aws` v6.56.0 from `.terraform.lock.hcl` with no migration error. **Post-migration verification succeeded on all three independent checks**: `terraform state list` returned all seven managed resources; `terraform plan` showed `0 to add, 0 to change, 0 to destroy.`; `aws s3api head-object` confirmed the remote state object exists at `bootstrap/terraform.tfstate`. See "State Migration Results and Post-Migration Verification" above for full detail. **A deliberate native S3 locking contention test has NOT been performed and is not claimed.** `use_lockfile = true` is active and has only been exercised passively (single-operation, error-free use since migration); explicit contention verification is **deferred to the `environments/dev` Terraform phase**, not performed here, and no `.tflock` object has been or will be manually created, deleted, or manipulated. **A final remote-state readability and no-change check has since been run and succeeded** (`terraform state list` -- all seven resources present; `terraform plan` -- `0 to add, 0 to change, 0 to destroy.`), immediately followed by **successful removal of the obsolete local `terraform.tfstate` (0-byte placeholder) and `terraform.tfstate.backup` (prior local state copy, 19320 bytes)** -- see "Final Remote-State Checks and Local State Cleanup" above. **No local `terraform.tfstate*` file remains in `infrastructure/terraform/bootstrap/`.** **The separate, temporary external backup created per "Future State Migration Sequence" step c has since been reviewed and successfully deleted** (2026-07-25) -- confirmed absent after deletion; see "External Temporary Backup Deletion and Bootstrap Phase Closeout" above. **No local or external copy of bootstrap Terraform state remains anywhere; the S3 backend is the sole, authoritative state location. This formally closes out the Terraform Bootstrap phase** -- see "Bootstrap Phase Completion Summary" near the top of this document. Native S3 locking contention testing remains deferred to the `environments/dev` Terraform phase, and the break-glass procedure remains documented but untested. Any `environments/dev` work remains a future, separately authorized task -- not something that has occurred.
