# Terraform Bootstrap — Break-Glass and Recovery Procedure

Status: **Documentation only. This procedure has not been executed, drilled, or tested against real AWS resources — no incident described here has actually occurred.** Creating this document does not run any Terraform or AWS CLI command and does not modify AWS in any way. It exists to satisfy the requirement in `02_Infrastructure/Terraform_Bootstrap_Design.md` Section 28.2 and `16_Implementation_Notes/Terraform_Bootstrap_Implementation_Plan.md` Section 29 that a break-glass procedure be written and reviewed **before** any `terraform apply` against real AWS resources — it does not, by itself, authorize `apply`. That remains a separate, later, explicit authorization.

Every recovery step below that depends on actually running a command is marked **"Validation evidence pending."** Every statement that depends on an AWS resource existing is marked **"Implementation evidence pending."** No project resource (state bucket, deployment role, VPC, EC2 instance) currently exists in AWS.

No second IAM user, role ARN, AWS account ID, email address, phone number, credential, or named emergency operator is invented anywhere in this document. Where a real identity, contact method, or ownership assignment is not yet defined, this document says exactly that: **"Operational owner confirmation pending."**

---

## 1. Purpose and Scope

This procedure exists so that, if the normal Terraform bootstrap workflow becomes unusable — because the deployment role's trust policy is wrong, the bootstrap operator's own access is lost, the state bucket or its contents become unreachable, or a native S3 lock is stuck — there is a written, reviewed path to recover **without** improvising destructive actions under time pressure. It covers only the `infrastructure/terraform/bootstrap/` configuration described in `Terraform_Bootstrap_Design.md` and `Terraform_Bootstrap_Implementation_Plan.md`: the Terraform remote-state S3 bucket and its hardening, and the Terraform deployment IAM role. It does not cover `environments/dev/` or any later phase, since neither exists yet.

Break-glass is, by definition, an exception path. Every section below assumes the normal path (Section 3) has already failed or is not usable, and states the least-privileged, least-destructive way to recover, not the fastest one.

## 2. What Qualifies as a Break-Glass Incident

A situation qualifies as break-glass only when the **normal, human-administered bootstrap workflow** (Section 3) cannot proceed through ordinary means. Concretely, that means one or more of:

- The bootstrap IAM user cannot authenticate, cannot satisfy MFA, or has had its permissions removed or altered unexpectedly.
- The Terraform deployment role's trust policy no longer trusts the bootstrap identity, or trusts an unexpected principal.
- The Terraform state (local or, after migration, remote in S3) is inaccessible, inconsistent, or apparently corrupted.
- A native S3 state lock (`.tflock` object) appears stuck with no genuinely in-flight Terraform operation holding it.
- `prevent_destroy` is blocking a change that is genuinely intended and has been explicitly approved (Section 19).

A situation does **not** qualify as break-glass merely because a `plan` looks unexpected, a command is slow, or a first attempt at something failed once — those are ordinary troubleshooting (Section 3), not incidents. Escalating routine friction to break-glass status defeats the purpose of keeping this path exceptional.

## 3. Normal Access Path

Per `Terraform_Bootstrap_Design.md` Section 2 and the current `providers.tf`: this bootstrap configuration is a deliberate, permanent exception to normal Terraform execution elsewhere in this project. It is **human-administered** — there is no `assume_role` block in `providers.tf`, and the bootstrap operator (the IAM user identified by `human_bootstrap_principal_arn` in a real, gitignored `terraform.tfvars`) runs `terraform` directly, using their own AWS credentials, with MFA satisfied where required by the deployment role's trust policy.

The normal path, end to end:

1. The bootstrap operator (the bootstrap IAM user) authenticates to AWS with their own credentials and MFA.
2. They run Terraform commands (`fmt`, `init`, `validate`, and — once separately authorized — `plan`/`apply`) directly from wherever they're working (their own machine, or in the future, the EC2 workstation), against `infrastructure/terraform/bootstrap/`.
3. The Terraform deployment role (`aws_iam_role.deployment`, `main.tf`) exists with a trust policy scoped to this same bootstrap identity, requiring `aws:MultiFactorAuthPresent = true`. It currently has **no permissions policy attached at all** — see `README.md` "Unresolved Permission Scope." It is not part of the normal bootstrap execution path today; it is established now for the future `environments/dev` work.
4. Nothing in this path routes through AWS root credentials. Root is not part of normal operation (Section 22-23).

This is the path that should be used whenever it is available. Break-glass exists only for when it is not.

## 4. Approved Emergency Access Path

There is currently **one** approved emergency access path beyond the normal bootstrap identity: the **AWS account root user**, which has verified MFA enabled (`02_Infrastructure/AWS_Account_Preparation.md` Section 8). Root is reserved strictly for situations where the bootstrap IAM user's own access cannot be restored by any other means (Section 8) or where an IAM-level misconfiguration (e.g., a locked trust policy, Section 6) cannot be corrected by the bootstrap identity itself because it lacks the necessary IAM permissions.

No second, dedicated "break-glass IAM user" or "break-glass role" currently exists in this project's design, and this document does not invent one. If a project decision is later made to create a dedicated break-glass identity distinct from root, that would be a separate, explicit design change to `Terraform_Bootstrap_Design.md`, not something introduced here. **Operational owner confirmation pending** on who specifically holds and is authorized to use root credentials in practice, and on any additional contact/escalation path beyond "the account owner uses root MFA."

## 5. Identity Assumptions and Limitations

- The **bootstrap IAM user** is the normal bootstrap operator. It is an IAM user (not a federated/Identity Center identity), per the trust-policy design in `variables.tf`/`main.tf`. Its exact ARN is account-specific and supplied only via a real, gitignored `terraform.tfvars` — never invented here.
- The **Terraform deployment role** currently has a trust policy only, trusting solely the bootstrap IAM user's ARN, conditioned on MFA. It has **no permissions attached** (Section 1 of `README.md`'s "Unresolved Permission Scope"), so even a successfully assumed session can authenticate but cannot call any AWS API requiring permissions. This means the deployment role, as it exists today, **cannot itself be used to recover anything** — it has no ability to read state, modify IAM, or touch the state bucket. Any recovery action that requires actually doing something in AWS must be performed by the bootstrap IAM user directly (or, if that identity itself is unavailable, root — Section 4).
- **Root user** has verified MFA (`AWS_Account_Preparation.md` Section 8) and is capable of any action in the account, which is exactly why it is reserved for genuine emergencies (Section 22-23), not normal use.
- There is no workstation IAM role yet (`environments/dev` has not been created) and no CI/CD identity of any kind. Neither is a factor in bootstrap break-glass today.

## 6. Recovery if the Deployment-Role Trust Policy Is Incorrect

Scenario: `aws_iam_role.deployment`'s trust policy (`data.aws_iam_policy_document.deployment_role_trust`, `main.tf`) is found to trust the wrong principal, is missing the MFA condition, or otherwise does not match what `main.tf` defines — for example, after an out-of-band manual change, or a suspected drift between applied state and configuration.

Recovery:

1. Do not attempt to fix this by hand in the AWS Console under time pressure. First, confirm what the *committed configuration* says the trust policy should be (`main.tf`'s `data.aws_iam_policy_document.deployment_role_trust` block) and what is *actually* attached, using a read-only check:
   ```text
   # Documented example only — NOT RUN as part of this task.
   aws iam get-role --role-name <DEPLOYMENT_ROLE_NAME>
   ```
2. If the actual trust policy differs from the committed configuration, the correct recovery is a normal, reviewed `terraform plan`/`apply` cycle by the bootstrap identity (Section 3) — Terraform will show the exact diff between current and desired trust policy, and applying it restores the correct policy through the same reviewed path used to create it originally, not a manual Console edit.
3. If the bootstrap identity itself cannot authenticate or lacks permission to read/update the role (e.g., its own IAM permissions were also affected), escalate to the root-user emergency access path (Section 4, Section 22).
4. Capture evidence (Section 25) before and after any correction: the `get-role` output showing the incorrect state, and after remediation, output showing the corrected trust policy matches `main.tf`.

**Implementation evidence pending** — no role currently exists in AWS to have an incorrect trust policy against.

## 7. Recovery if MFA-Based Role Assumption Fails

Scenario: the bootstrap identity has valid IAM credentials but cannot successfully assume the deployment role because the trust policy's `aws:MultiFactorAuthPresent` condition is not being satisfied (e.g., MFA device lost, MFA session expired, or a genuine tooling issue passing the MFA context through).

Recovery:

1. First confirm this is genuinely an MFA-condition failure, not a different problem (wrong ARN, wrong account, revoked permissions) by checking the actual caller identity:
   ```text
   # Documented example only — NOT RUN as part of this task.
   aws sts get-caller-identity
   ```
2. If the bootstrap identity's own MFA device is lost or unavailable, this is fundamentally an account-level MFA-recovery problem for that IAM user, not something this Terraform configuration can work around — **do not** recommend disabling the MFA condition on the trust policy, and **do not** recommend removing MFA from the IAM user, as a way to route around this. MFA recovery for the IAM user itself follows standard AWS IAM account-recovery practice, which is outside this document's scope (it is not a Terraform-specific procedure).
3. If the IAM user's MFA is intact but the *deployment role* specifically cannot be assumed, remember the deployment role currently has no attached permissions (Section 5) — there is nothing to recover by assuming it today, since it is not part of the normal execution path yet (Section 3). This scenario is more relevant to a future state once `environments/dev` depends on this role.
4. If the bootstrap identity cannot be restored to a working MFA state at all, escalate to root (Section 4).

**Validation evidence pending** — no MFA-based role assumption has been attempted against this configuration.

## 8. Recovery if the Bootstrap IAM User Loses Access

Scenario: the bootstrap IAM user's credentials are revoked, deleted, expired, or otherwise unusable, and the normal path (Section 3) is unavailable.

Recovery:

1. Confirm the loss of access is real and specific to this identity, not a transient network/credentials-file issue, using the same read-only check as Section 7 (`aws sts get-caller-identity`) from a session that should be using that identity.
2. If access genuinely cannot be restored (e.g., the IAM user's access keys were deactivated or deleted, or the user itself was removed), this becomes an account-level IAM recovery problem. Escalate to the root-user emergency access path (Section 4) to restore or recreate the necessary access for a bootstrap operator — root has full IAM permissions to do so.
3. Do **not** create a brand-new, undocumented IAM user or set of credentials informally as a workaround. Any change to who the bootstrap operator is (a new IAM user ARN) must be reflected as a deliberate update to the real `terraform.tfvars`'s `human_bootstrap_principal_arn` and, if the trust policy needs to change to match, a reviewed `terraform plan`/`apply` (Section 6), not an unreviewed manual IAM change.
4. **Operational owner confirmation pending** on the exact process/contact for requesting root-level intervention in practice — this document does not assume a specific person, phone number, or escalation channel beyond "the account owner, using verified root MFA."

**Implementation evidence pending** — no bootstrap IAM user's real credentials exist in this repository, and no such loss-of-access event has occurred.

## 9. Recovery if the State Bucket Is Inaccessible

Scenario: after the state bucket exists (it does not yet — Section 1), `terraform` commands or direct AWS checks show the bucket is unreachable — permission denied, not found, or region/endpoint mismatch.

Recovery:

1. Confirm the bucket's existence and basic reachability with a read-only check before assuming anything is broken:
   ```text
   # Documented example only — NOT RUN as part of this task.
   aws s3api head-bucket --bucket <STATE_BUCKET_NAME>
   ```
2. If the bucket does not exist at all and was expected to, treat this as a "resource exists in AWS but missing from state" or "resource missing entirely" scenario — see Section 17-18, not a deletion-recovery scenario, unless there is specific evidence the bucket was actually deleted.
3. If the bucket exists but access is denied, this is almost always an IAM permissions problem on the calling identity, not a problem with the bucket itself — check the calling identity (`aws sts get-caller-identity`, Section 7) and confirm it has the bootstrap-scoped permissions described in `README.md` "Prerequisites," rather than assuming the bucket itself is corrupted.
4. If access is denied for the bootstrap identity specifically, and that identity's own permissions cannot be corrected without a higher-privileged identity, escalate to root (Section 4) to review and correct IAM permissions — not to bypass the bucket's own access controls.

**Implementation evidence pending** — the state bucket does not exist yet.

## 10. Recovery if the First Local-State Apply Fails Partially

Scenario: the very first `terraform apply` against `bootstrap/` (still local state, per `Terraform_Bootstrap_Design.md` Section 5) fails partway through — for example, the state bucket is created but a hardening sub-resource (versioning, encryption, public-access-block, ownership controls, or the bucket policy) fails to apply.

Recovery — this restates and grounds `README.md`'s existing "Partial-Apply Recovery Guidance" for this specific scenario:

1. **Do not improvise deletion.** Inspect first:
   ```text
   # Documented examples only — NOT RUN as part of this task.
   terraform state list
   terraform plan
   aws s3api head-bucket --bucket <STATE_BUCKET_NAME>
   aws iam get-role --role-name <DEPLOYMENT_ROLE_NAME>
   ```
2. If a resource exists in AWS but is missing from the (still-local) state file, use `terraform import` (Section 18) before doing anything else with it.
3. If a resource is only partially configured (e.g., the bucket exists but its encryption configuration doesn't), re-running `terraform apply` against the same, unmodified configuration is the normal, safe path — every resource in `main.tf` is designed to be idempotent, with no non-idempotent provisioners.
4. Treat the bucket, each of its hardening sub-resources, and the deployment role as individually re-checkable, not as one atomic unit that must be torn down and recreated together.

**Validation evidence pending** — no apply, partial or complete, has been run against this configuration.

## 11. Recovery if Local `terraform.tfstate` Is Lost Before S3 Migration

Scenario: during the local-state-first phase (before migration to S3, `Terraform_Bootstrap_Design.md` Section 5), the local `terraform.tfstate` file is lost, deleted, or corrupted before it has been migrated to the remote backend.

Recovery:

1. Check for the one sanctioned temporary backup described in `README.md`'s "Future State Migration Sequence" step 1 — a single encrypted, access-controlled backup made immediately before migration. If bootstrap has not yet reached the migration step, no such backup is expected to exist yet, and its absence is not itself a defect.
2. If no usable copy of the local state file exists, and the bucket and role described in `main.tf` may already exist in AWS from a prior apply, do **not** attempt to recreate them via a fresh `terraform apply` against blank state — that risks a naming collision (the bucket/role already exist) or, worse, an attempted destructive replace. Instead, rebuild state via `terraform import` for each resource that already exists in AWS (Section 17-18), confirming each with `terraform plan` before proceeding.
3. If neither AWS resource exists yet either (i.e., state was lost before the very first successful apply), there is nothing to reconcile — a fresh `terraform apply` from the unmodified, reviewed configuration is the correct next step, since nothing has been created yet.
4. This scenario is exactly why Terraform state, even before S3 migration, should never be treated as disposable scratch data — the local phase is short-lived by design specifically to minimize this window (`Terraform_Bootstrap_Design.md` Section 5).

**Implementation evidence pending** — no local state file has been created by any real apply yet.

## 12. Recovery if Remote State Is Unavailable After Migration

Scenario: after migration to the S3 backend (a future, separately authorized step — Section 1), the remote state object becomes unavailable — bucket unreachable (Section 9), object missing, or object corrupted/unreadable.

Recovery:

1. First distinguish "bucket unreachable" (Section 9, an access/connectivity problem) from "object present but the specific state version is bad" (a content problem) using read-only checks:
   ```text
   # Documented example only — NOT RUN as part of this task.
   aws s3api list-object-versions --bucket <STATE_BUCKET_NAME> --prefix bootstrap/terraform.tfstate
   ```
2. Because the state bucket is designed with **versioning enabled** (`aws_s3_bucket_versioning.terraform_state`, `main.tf`), a bad or missing current version can often be recovered by identifying and restoring a prior good version from that same listing — a deliberate, inspected action (compare the candidate version's content/timestamp against what's expected), not an automatic rollback.
3. If no usable version exists at all (an extreme scenario, mitigated by `prevent_destroy` and the deployment role's lack of any delete permission, Section 21 and "Destruction Protection Warning" in `README.md`), the fallback is to rebuild state entirely via `terraform import` (Section 18) against whatever AWS resources genuinely exist, guided by real AWS inventory, not assumption.
4. Never treat "state is temporarily unavailable" as license to bypass the backend and hand-edit a local copy — reconcile through the backend, not around it.

**Implementation evidence pending** — no remote state migration has occurred; this bucket does not have any state object in it yet.

## 13. Recovery from a Stale Native S3 `.tflock` Object

Scenario: a `terraform` command reports the state as locked (via the native S3 locking mechanism, `use_lockfile = true`, `backend.hcl.example`), but no genuine concurrent Terraform operation is actually in progress — for example, a prior `terraform plan`/`apply` was killed (process killed, machine lost power, network dropped) without releasing its lock.

This is the scenario `Terraform_Bootstrap_Design.md` Section 6 anticipated when choosing native S3 locking over S3+DynamoDB — no DynamoDB table exists or is used; the lock is a `.tflock` object in the same state bucket, at the same key plus a `.tflock` suffix.

Recovery — **diagnosis before any corrective action, always**:

1. Do **not** treat `force-unlock` or manual `.tflock` deletion as the first response to a locked-state message. A lock message is the intended, correct behavior when a concurrent operation is genuinely running — the failure mode being addressed here is specifically a *stale* lock from a *dead* process, and that must be established, not assumed.
2. Confirm there is no other Terraform process actually running against this same configuration right now — check with whoever else might reasonably be running Terraform against `bootstrap/` (in this project's current single-operator context, that means confirming with yourself that no other terminal/session/CI job is mid-`apply`), and check for any recent, still-active process on the machine that last ran Terraform.
3. Inspect the lock object itself and its metadata (holder identity, timestamp) before acting:
   ```text
   # Documented example only — NOT RUN as part of this task.
   aws s3api list-object-versions --bucket <STATE_BUCKET_NAME> --prefix bootstrap/terraform.tfstate.tflock
   ```
   A lock timestamp that is old relative to how long any single `plan`/`apply` should reasonably take is supporting evidence of staleness — not proof by itself.
4. Only once staleness is reasonably established (Section 14) does either `terraform force-unlock` (preferred, Section 14) or, as a last resort, direct deletion of the `.tflock` object (Section 15) become appropriate — and only with the evidence capture in Section 16.

**Validation evidence pending** — no lock, stale or otherwise, has ever been created against this configuration; no backend exists yet to hold one.

## 14. Conditions Under Which `force-unlock` Is Allowed

`terraform force-unlock` is the **preferred** mechanism for clearing a confirmed-stale lock, over direct object deletion, because it goes through Terraform's own lock-management logic (requiring the specific lock ID Terraform itself reports) rather than an out-of-band S3 object delete.

`force-unlock` is allowed only when **all** of the following hold:

1. A lock is actually reported by Terraform (not assumed).
2. Diagnosis per Section 13 has been completed and reasonably establishes no genuine concurrent operation is running.
3. The exact lock ID being unlocked is the one Terraform itself reported for the current locked-state error — not guessed or reused from an unrelated prior message.
4. Evidence has been captured (Section 16) before the unlock is performed.

Documented example only:

```text
# Documented example only — NOT RUN as part of this task.
terraform force-unlock <LOCK_ID>
```

`force-unlock` must never be run reflexively the moment a lock message appears — see Section 13's ordering. **Validation evidence pending** — this command has never been run against this configuration.

## 15. Conditions Under Which Direct `.tflock` Deletion Is Allowed

Direct deletion of the `.tflock` object via the AWS CLI/Console (bypassing `terraform force-unlock` entirely) is a **last resort**, used only when `force-unlock` itself is unavailable or has failed (for example, the Terraform binary or backend configuration needed to run `force-unlock` is itself unavailable, but direct AWS access to the bucket is not).

Direct deletion requires **all** of the following, in addition to everything required for `force-unlock` (Section 14):

1. Explicit, documented approval from the operational owner of this configuration before the deletion is performed — not a unilateral action taken silently under time pressure. **Operational owner confirmation pending** on exactly who provides this approval in practice, beyond "the bootstrap operator/account owner."
2. Confirmation that `terraform force-unlock` was attempted and did not resolve the situation, or is genuinely unavailable, with that attempt/unavailability documented.
3. Full evidence capture (Section 16) before the deletion, including the lock object's key, version ID, and last-modified timestamp.
4. Immediate follow-up with `terraform plan` after deletion to confirm no unexpected state drift resulted, before any further `apply`.

This is explicitly **not** a routine step, and this document does not present it as one. It exists only because a native-S3-locking design (no DynamoDB) has exactly one lock artifact, and an operator who has lost access to Terraform itself but still has AWS access needs a documented, gated path rather than no path at all.

## 16. Required Verification Before Removing a Lock

Before either `force-unlock` (Section 14) or direct `.tflock` deletion (Section 15) is performed, the following must be verified and recorded (see also Section 25):

1. **No genuine concurrent operation is running** — confirmed by checking for any other active Terraform session/process against this configuration, per Section 13 step 2.
2. **The lock's age and holder metadata** have been inspected (`list-object-versions`, Section 13 step 3) and are consistent with staleness (e.g., far older than any single `plan`/`apply` should reasonably take, or attributable to a session that is confirmed to have ended).
3. **The exact lock ID/object key** being acted on has been recorded, not assumed.
4. **A timestamp and identity** for who is performing the unlock/deletion has been recorded.
5. For direct deletion specifically (Section 15), **explicit approval** has been obtained and recorded, not just intended.

Skipping this verification and proceeding straight to unlocking is exactly the failure mode Section 13 warns against — a genuinely active operation whose lock is force-cleared can corrupt state.

## 17. Recovery When AWS Resources Exist but Are Absent from Terraform State

Scenario: an AWS resource that `main.tf` defines (the state bucket or any of its hardening sub-resources, or the deployment role) is confirmed to exist in AWS, but `terraform state list` does not show it — for example, after a partial apply (Section 10), a state-loss event (Section 11), or a manual out-of-band creation that should not have happened but did.

Recovery: this is precisely what `terraform import` exists for (Section 18) — never respond to this situation by running `terraform apply` against blank/incomplete state for a resource that already exists, since Terraform would either fail on a naming collision or, in the worse case, attempt to create a duplicate or replace something that's already correctly configured.

**Implementation evidence pending** — no AWS resource from this configuration currently exists, so this scenario has not occurred.

## 18. `terraform import` Process and Review Requirements

This restates and grounds `README.md`'s existing "`terraform import` Guidance" as a break-glass recovery tool specifically:

1. **Inspect before importing** — confirm via a real AWS check (`aws s3api head-bucket`, `aws iam get-role`, etc.) that the resource actually exists and roughly matches what's expected, rather than importing blindly.
2. Import the resource using its Terraform resource address and its real AWS identifier:
   ```text
   # Documented examples only — NOT RUN as part of this task.
   terraform import aws_s3_bucket.terraform_state <STATE_BUCKET_NAME>
   terraform import aws_s3_bucket_versioning.terraform_state <STATE_BUCKET_NAME>
   terraform import aws_s3_bucket_server_side_encryption_configuration.terraform_state <STATE_BUCKET_NAME>
   terraform import aws_s3_bucket_public_access_block.terraform_state <STATE_BUCKET_NAME>
   terraform import aws_s3_bucket_ownership_controls.terraform_state <STATE_BUCKET_NAME>
   terraform import aws_s3_bucket_policy.terraform_state <STATE_BUCKET_NAME>
   terraform import aws_iam_role.deployment <DEPLOYMENT_ROLE_NAME>
   ```
3. **Always follow an import with `terraform plan`** to confirm the imported resource matches the committed configuration with no unexpected diff, before any further `apply`. A diff after import means either the real resource doesn't match what `main.tf` expects, or the import target was wrong — either way, that must be resolved and understood before proceeding, not applied through blindly.
4. As of the 2026-07-25 bootstrap-management-model decision, there is no `aws_iam_policy`/`aws_iam_role_policy_attachment` resource to import for the deployment role — it has no permissions policy attached (`README.md` "Unresolved Permission Scope").
5. Every import is a reviewed action: record which resource, which real identifier, and the `terraform plan` output confirming no diff, as part of incident evidence (Section 25).

**Validation evidence pending** — no `terraform import` has ever been run against this configuration.

## 19. Recovery When `prevent_destroy` Blocks an Intentional Action

Scenario: `lifecycle { prevent_destroy = true }` (present on both `aws_s3_bucket.terraform_state` and `aws_iam_role.deployment`, `main.tf`) blocks a `terraform destroy` or a `plan` that would replace/remove one of these resources — and that action is genuinely, deliberately intended (not an accident the guard rail is correctly catching).

Recovery:

1. First confirm this really is an intended action, not `prevent_destroy` correctly catching an unintended replace triggered by an unrelated configuration change (e.g., a change to an argument that forces resource replacement) — re-read the `plan` output carefully; `prevent_destroy` blocking an *accidental* destroy/replace is it working as designed, not an obstacle to route around.
2. If the destructive action is genuinely intended, `prevent_destroy` can only be removed through a deliberate, reviewed **source code change** to `main.tf` — never a quick local workaround, a `-target` trick, or a temporary hand-edit that gets reverted after the fact without review.
3. That source change requires the explicit approval described in Section 20 before it is merged or applied.
4. Once the intended action is complete, `prevent_destroy` should normally be restored (re-added) in a follow-up reviewed change, unless the explicit approval also covers permanently removing that protection going forward.

## 20. Explicit Approval Required Before Temporarily Removing `prevent_destroy`

Removing `prevent_destroy` — even temporarily, even for a genuinely intended action — is never a routine step and is never to be treated as a quick workaround to unblock a `plan`/`apply`. Before it is removed:

1. The specific intended action (what is being destroyed/replaced and why) must be written down.
2. Explicit approval must be obtained and recorded from the operational owner of this configuration. **Operational owner confirmation pending** on exactly who grants this approval in practice, beyond "the bootstrap operator/account owner" — no specific named approver is invented here.
3. The change to remove `prevent_destroy` must go through the same review path as any other `.tf` change (per `03_Development/Git_Workflow.md`'s PR process), not an unreviewed local edit applied directly.
4. Evidence (Section 25) must be captured: the approval record, the diff removing `prevent_destroy`, the resulting `plan`/`apply` output, and — if `prevent_destroy` is meant to be restored afterward — the follow-up change doing so.

This document does not recommend removing `prevent_destroy` as a way to get past an inconvenient blocker; it recommends the above gated process for the rare case where the destructive action is actually correct.

## 21. State Backup Handling and Sensitive-Data Precautions

Terraform state (local, and later the remote object) can contain sensitive values — resource attributes marked sensitive, and potentially other configuration detail that shouldn't be broadly exposed. This governs every backup/recovery action above:

- The only sanctioned backup of state is the single, temporary, encrypted, access-controlled copy described in `README.md`'s "Future State Migration Sequence" step 1, made immediately before migration and deleted once migration is verified (per `Terraform_Bootstrap_Design.md` Section 11) — not a routine or repeated practice.
- No ad hoc, uncontrolled, or plaintext copy of state should be created during any recovery action in this document — including during import, force-unlock diagnosis, or version-recovery from S3 versioning (Section 12). Any temporary copy made for diagnosis must be encrypted/access-controlled and deleted once no longer needed, exactly like the migration backup.
- Evidence captured during an incident (Section 25) should reference state content by resource address/attribute name where possible, rather than pasting full state file contents into incident notes, to avoid spreading sensitive values further than necessary.
- S3 versioning on the state bucket (`aws_s3_bucket_versioning.terraform_state`, `main.tf`) is itself a form of backup/recovery mechanism and does not require a separate, additional backup process beyond what's already described (`Terraform_Bootstrap_Design.md` Section 11).

## 22. AWS Root-User Role in Emergency Recovery

Root is the account's most privileged identity and has verified MFA enabled (`AWS_Account_Preparation.md` Section 8). In this break-glass procedure, root's role is strictly limited to situations where:

- The bootstrap IAM user's own access cannot be restored by any other means (Section 8), or
- An IAM-level misconfiguration (trust policy, permissions) cannot be corrected by the bootstrap identity itself because it lacks the necessary IAM permissions to fix its own or the deployment role's configuration (Section 6).

When root is used, the same evidence-capture and post-incident review requirements apply (Sections 25-27) as to any other break-glass action — root use is not exempt from being recorded and reviewed; if anything, it warrants more scrutiny given its privilege level.

## 23. Why Root Is Not the Normal Administrative Path

Root credentials, by AWS's own design, have no IAM policy boundary — there is no way to scope root down to "just enough" permission for a specific task. Using root for routine bootstrap work would mean every day-to-day action carries the full blast radius of the most privileged identity in the account, which is the opposite of the least-privilege principle this entire bootstrap design is built around (narrow workstation role, narrow-then-zero deployment role permissions, MFA-gated trust policies). Root is reserved for exactly the failure modes ordinary least-privileged identities cannot recover from by definition — losing access to themselves, or needing a change to IAM policy that only a more-privileged identity can make. This document does not recommend using root routinely for any bootstrap task, and no step above treats root as a first response to any scenario.

## 24. Required MFA and Audit Evidence for Emergency Actions

Every emergency action taken under this procedure — whether by the bootstrap IAM user or by root — must have:

- **MFA satisfied** at the time of the action, consistent with the verified-enabled MFA on both the bootstrap IAM user and root (`AWS_Account_Preparation.md` Section 8). This document does not recommend disabling MFA under any circumstance, including as a workaround during an incident.
- **CloudTrail-attributable identity** — every AWS API call made during recovery is, by AWS's own logging, attributable to the specific IAM principal (including root) that made it. This procedure relies on that existing CloudTrail coverage rather than proposing a separate audit mechanism; no additional logging infrastructure is created by this document (creating one would itself be a Terraform change requiring the normal review path).
- **A contemporaneous record** (Section 25) of what was done, by whom, and why — CloudTrail records *that* an action happened; this document's evidence-capture requirement additionally records the *reasoning* and *approval* behind it, which CloudTrail alone does not capture.

**Implementation evidence pending** on reviewing actual CloudTrail output for any bootstrap-related event, since no such event has occurred yet.

## 25. Evidence to Capture During an Incident

For any break-glass action taken under this procedure, capture and retain:

1. **What triggered it** — the exact error message, lock message, or observed symptom that indicated a break-glass scenario (Section 2), not just "it seemed broken."
2. **Diagnosis performed** — the read-only checks run (Sections 6-13) and their output, showing why the situation was classified as it was.
3. **The identity that performed the action** — bootstrap IAM user or root, and confirmation MFA was satisfied.
4. **Approval, where required** — for `prevent_destroy` removal (Section 20) or direct lock deletion (Section 15), the explicit approval obtained, by whom, and when. **Operational owner confirmation pending** on the exact form this approval record takes (e.g., a PR comment, a written sign-off) — not yet defined in project process beyond "must be explicit and recorded."
5. **The exact recovery command(s) run** and their output (`terraform import`, `terraform force-unlock`, `terraform plan`, or the applicable `aws` CLI check).
6. **Post-recovery verification output** (Section 26).
7. **Timestamps** throughout, sufficient to reconstruct the sequence of events afterward.

This evidence is what the post-incident review (Section 27) is conducted against — a review with no contemporaneous record to examine cannot meaningfully assess whether the response was correct.

## 26. Post-Recovery Validation

After any break-glass recovery action, before considering the configuration back to a known-good state:

1. `terraform plan` must be run and show **no unexpected diff** — any remaining diff must be explained (either it's an intentional follow-up change already planned, or it indicates the recovery is incomplete).
   ```text
   # Documented example only — NOT RUN as part of this task.
   terraform plan
   ```
2. For anything touching the state bucket's hardening, real AWS output should be checked against what `main.tf` expects (per `README.md`'s "Verification Commands" — versioning, encryption, Block Public Access, ownership controls, bucket policy), not just assumed from the Terraform config.
3. For anything touching the deployment role, confirm its trust policy and (currently expected to be empty) permissions match what `main.tf` defines.
4. Only once these checks pass should the incident be considered technically resolved — separate from the post-incident review (Section 27), which is a process step, not a technical one.

**Validation evidence pending** — no post-recovery validation has ever been performed, since no recovery has ever been needed.

## 27. Post-Incident Review Requirements

After any break-glass incident (Section 2) is technically resolved (Section 26), a review must occur before the incident is considered closed (Section 30):

1. Walk through the captured evidence (Section 25) end to end: was the classification as a break-glass incident correct (Section 2)? Was the diagnosis before acting sufficient (Sections 6-13, 16)? Was the least-destructive available option chosen?
2. Identify whether anything in this procedure was unclear, insufficient, or wrong when actually followed — and if so, this document should be updated as a deliberate, reviewed documentation change (not silently patched), per `CLAUDE.md`'s general rule that documentation reflects actual, evidenced state.
3. If root was used (Section 22), specifically review whether it was genuinely necessary or whether a narrower path existed that wasn't tried first.
4. If `prevent_destroy` was removed (Section 20) or a lock object was directly deleted (Section 15), confirm any required follow-up (restoring `prevent_destroy`, documenting why direct deletion was necessary instead of `force-unlock`) was completed.
5. Record the outcome of this review in `00_Project_Management/Memory.md` as part of normal project memory hygiene (`CLAUDE.md` Section 8), since a break-glass incident is exactly the kind of "new blocker" / "new decision" event that rule anticipates.

## 28. Actions Explicitly Prohibited

The following are not permitted under this procedure, under any circumstance framed as convenience or urgency:

- Disabling or bypassing MFA on the bootstrap IAM user, root, or the deployment role's trust-policy condition.
- Using root credentials for routine, non-emergency bootstrap work (Section 23).
- Running `terraform force-unlock` or deleting a `.tflock` object as a first response, without the diagnosis in Sections 13 and 16.
- Deleting the state bucket, any state object, or any lock object without first establishing no active Terraform operation exists and, where applicable, obtaining explicit approval (Sections 15-16).
- Removing `prevent_destroy` as a quick workaround to unblock a `plan`/`apply`, without the approval and review process in Section 20.
- Creating an undocumented, informal second IAM user or credential set as a workaround for lost access (Section 8).
- Keeping an uncontrolled, plaintext, or long-lived copy of Terraform state outside the versioned bucket or the one sanctioned temporary migration backup (Section 21).
- Suppressing or hiding evidence of an incident, or skipping the post-incident review (Section 27).

## 29. Decision Tree for Common Failure Scenarios

```text
Terraform command fails or state looks wrong
│
├─ Is it a "state is locked" message?
│   ├─ Is a genuine concurrent operation actually running? ── YES → wait / coordinate; not an incident.
│   └─ NO (confirmed via Section 13 diagnosis) → Section 14 (force-unlock) → Section 15 (direct
│       deletion, only if force-unlock unavailable/failed) → Section 16 (verification, always first)
│
├─ Is it "resource already exists" / "resource missing from state"?
│   └─ Section 17 → Section 18 (terraform import) → terraform plan to confirm no diff
│
├─ Is it "access denied" / "cannot authenticate"?
│   ├─ Bootstrap IAM user's own credentials/MFA broken? → Section 8 (and Section 7 if MFA-specific)
│   ├─ Deployment role trust policy wrong? → Section 6
│   └─ Neither resolvable by the bootstrap identity itself? → Section 4 / Section 22 (root, emergency only)
│
├─ Is it "bucket/object unreachable"?
│   ├─ Before migration (local state only) → Section 11
│   └─ After migration (remote state) → Section 9 (bucket-level) or Section 12 (object/version-level)
│
├─ Is it "prevent_destroy is blocking an apply"?
│   └─ Section 19 → is the destructive action genuinely intended?
│       ├─ NO → this is prevent_destroy working correctly; fix the underlying config change instead.
│       └─ YES → Section 20 (explicit approval + reviewed source change), never a silent workaround.
│
└─ Anything not covered above → do not improvise; inspect first (state list, plan, targeted
    real AWS checks), escalate per Section 4 if the bootstrap identity's own access is insufficient,
    and treat this document as needing a reviewed update once resolved (Section 27).
```

## 30. Exit Criteria for Closing a Break-Glass Incident

A break-glass incident is considered closed only when **all** of the following are true:

1. The triggering condition (Section 2) no longer applies — the normal access path (Section 3) is confirmed usable again.
2. Post-recovery validation (Section 26) has passed: `terraform plan` shows no unexpected diff, and any touched resource's real AWS configuration matches `main.tf`.
3. Full evidence (Section 25) has been captured and is retrievable.
4. The post-incident review (Section 27) has been completed and its outcome recorded in `Memory.md`.
5. Any temporary state (a removed `prevent_destroy`, an emergency root session, a temporary state backup) has been returned to its normal, protected condition, or a deliberate, reviewed decision has been made and recorded to leave it changed.
6. If this procedure itself was found to be unclear or incomplete during the incident, that gap has been fixed here as a reviewed documentation update, not left for the next incident to rediscover.

Until all six hold, the incident remains open, regardless of whether AWS resources appear to be working again.

---

*This document is derived from `02_Infrastructure/Terraform_Bootstrap_Design.md` (Sections 2, 6, 11, 21-23, 28.2-28.4), `16_Implementation_Notes/Terraform_Bootstrap_Implementation_Plan.md` (Section 29-30), `infrastructure/terraform/bootstrap/README.md`, `infrastructure/terraform/bootstrap/main.tf`, `02_Infrastructure/AWS_Account_Preparation.md` Section 8, and `02_Infrastructure/IAM_and_Access.md`. It documents a procedure only — no command in this document has been run, no AWS resource has been modified, and no recovery scenario described here has actually occurred. Last updated: 2026-07-25.*
