# Terraform Bootstrap — Implementation Plan

Status: **REVIEWED AND APPROVED by user (2026-07-25), for the bootstrap-only file scope described in this document.** This is still a planning document: **no `.tf` files, no Terraform directories, no Terraform commands, and no AWS resources have been created.** Approval of this plan authorizes the **next** task — creating the `bootstrap/` files listed below — but not running `terraform init`/`plan`/`apply`, which remains a separate, later authorization (§30–31).

This revision supersedes the 2026-07-25 draft version of this document. The scope has narrowed and several previously-open decisions are now resolved, per the user's final decisions below. Where this version changes a conclusion from the prior draft, that change is called out explicitly rather than silently overwritten.

---

## 1. Exact Scope of the First Implementation Task

The **first implementation task creates exactly one thing: the `bootstrap/` root module's files**, and nothing else — no `modules/` directory, no `environments/` directory, no AWS resources. Concretely, the task after this one is: write `versions.tf`, `providers.tf`, `backend.tf`, `variables.tf`, `locals.tf`, `main.tf`, `outputs.tf`, `terraform.tfvars.example`, `backend.hcl.example`, and `README.md` under `infrastructure/terraform/bootstrap/`. **No `terraform init`, `plan`, or `apply` is part of that next task either** — file creation and command execution are two separate, separately authorized steps (§25, §30–31).

**Changed from the prior draft:** the earlier version of this plan proposed `modules/state-backend/` and `modules/iam-deployment-role/` as separate reusable modules composed by `bootstrap/`. The user has now decided against that for this small scope — **all bootstrap resources live directly in `bootstrap/main.tf`**, with no module indirection. Modules remain available to introduce later "if genuine reuse appears" (the user's own framing), not by default.

---

## 2. Approved First Terraform Tree

```text
infrastructure/terraform/
└── bootstrap/
    ├── versions.tf
    ├── providers.tf
    ├── backend.tf
    ├── variables.tf
    ├── locals.tf
    ├── main.tf
    ├── outputs.tf
    ├── terraform.tfvars.example
    ├── backend.hcl.example
    └── README.md
```

This is the **entire** tree this plan authorizes creating next. No `modules/`, no `environments/`, no `shared/`.

### Approved future structure (not created now)

```text
infrastructure/terraform/
├── bootstrap/
├── modules/
│   ├── vpc/
│   ├── iam-workstation-role/
│   └── ec2-workstation/
└── environments/
    └── dev/
```

Three changes from the module list in the prior draft of this plan, all per the user's final decisions:

- **`modules/state-backend/` and `modules/iam-deployment-role/` are removed from the plan entirely**, not merely deferred — bootstrap's resources stay directly in `bootstrap/main.tf` for this small scope (§1). If bootstrap's configuration grows enough later that extracting a module becomes genuinely useful, that would be a deliberate, separately reviewed refactor, not an assumed next step.
- **`modules/security-group/` is removed as a standalone module.** The workstation security group belongs inside `modules/ec2-workstation/` from the start — the prior draft's "borderline, kept separate for future reuse" reasoning is superseded by this explicit decision.
- `modules/vpc/`, `modules/iam-workstation-role/`, and `modules/ec2-workstation/` remain as previously planned, for the same reasons given before (§7 of the prior draft): they are the resources the `dev` VPC/workstation implementation will need, and none of that work is created now.

`environments/dev/`'s own file-by-file shape (files, inputs/outputs, exact resources) is **not restated in full detail in this revision** — it was already documented in the prior draft and remains a correct forward reference for when the dev VPC implementation plan is written, but it is out of scope for the task this document currently authorizes. Do not treat anything below about `environments/dev/` as approved for creation now; only `bootstrap/` is.

---

## 3. Purpose of Every File in `bootstrap/`

| File | Purpose |
|---|---|
| `versions.tf` | `required_version` (Terraform >= 1.10, < 2.0) and `required_providers` (AWS provider constraint) — §14. |
| `providers.tf` | Configures the `aws` provider using the human identity's own credentials directly (no `assume_role` — bootstrap runs as the human identity itself, `Terraform_Bootstrap_Design.md` §2, §19). |
| `backend.tf` | Declares an empty `backend "s3" {}` block. **Present in the file tree from the start** (per the approved tree, §2) but **not active for the very first apply** — see §11's two-phase explanation. This is a deliberate change from the prior draft, which proposed adding `backend.tf` only after the bucket existed; the user's approved tree includes it from the beginning instead. |
| `variables.tf` | Typed inputs, descriptions, and defaults only for non-account-specific values (§10). |
| `locals.tf` | A merged common-tags map (`Project`, `Environment = "shared"`, `ManagedBy`, `Owner`, `CostCenter`) and any other small computed values bootstrap needs — kept local to this root module; no `shared/` directory exists to hold it centrally (§7). |
| `main.tf` | All bootstrap resources, defined directly — the state bucket and its hardening, and the deployment IAM role and its policies (§9). No `module` blocks. |
| `outputs.tf` | `state_bucket_name`, `state_bucket_arn`, `deployment_role_arn`, `deployment_role_name` (§10). |
| `terraform.tfvars.example` | Committed template of variable names with placeholder values — no real values (§12). |
| `backend.hcl.example` | Committed template for `-backend-config`, placeholders only (§11). |
| `README.md` | What `bootstrap/` does, its inputs/outputs, and the manual steps it does not itself automate — the local-state-first-then-migrate sequence (§15) and the later trust-policy-update apply (§16). |

Not created as part of this task, and not listed above: `terraform.tfvars` and `backend.hcl` (real values, gitignored, created only when the configuration is actually initialized/applied) and `.terraform.lock.hcl` (generated only by an actual `terraform init`, which is not part of this task, §1).

---

## 4. Files Belonging to Bootstrap

All ten files in §2's tree belong to `bootstrap/` — there is no split between "bootstrap-owned" and "module-owned" files anymore, since no module exists for this scope.

## 5. Files Belonging to environments/dev

None are created by this task. For continuity, the file set documented in the prior draft of this plan (`versions.tf`, `providers.tf`, `backend.tf`, `variables.tf`, `locals.tf`, `main.tf`, `outputs.tf`, `terraform.tfvars.example`, `backend.hcl.example`, `README.md`, plus the three modules `modules/vpc/`, `modules/iam-workstation-role/`, `modules/ec2-workstation/` — the last of these now also containing the workstation security group, §2) remains the expected shape when that work is actually planned in detail, but it is not re-approved or finalized here. The dev VPC implementation plan is a separate future task.

---

## 6. Reusable Modules Needed Immediately

**None.** For this task's scope (`bootstrap/` only), zero modules are created — all resources are direct (§1–2).

## 7. Modules That Must Be Deferred

- `modules/vpc/`, `modules/iam-workstation-role/`, `modules/ec2-workstation/` (the latter now including the workstation security group) — deferred until the **dev VPC implementation plan** is written and separately authorized; not created by this task.
- Private application/private-data subnet handling — CIDR ranges remain deferred until the dev VPC implementation plan (per the user's decision this task incorporates), not decided or reserved as concrete values here.
- NAT Gateway / VPC endpoint egress module — future hardening option only.
- Autostop module (EventBridge/Lambda), monitoring/alarm module, budget-as-code module, any CI/CD module or role — all still deferred, unchanged from the prior draft.
- `shared/` tags/locals directory — still deferred; `bootstrap/`'s own `locals.tf` covers its tagging needs for now (§3).
- **`modules/state-backend/` and `modules/iam-deployment-role/` are not deferred — they are not planned at all.** Deferred implies "later, if needed"; these two are simply not part of the design anymore for this scope (§1–2). Revisit only if bootstrap's configuration grows enough that module extraction becomes genuinely useful, as a deliberate future decision.

---

## 8. Exact Resources Proposed for the Bootstrap Configuration

All defined directly in `bootstrap/main.tf` — no module composition:

**State bucket and hardening:**

- `aws_s3_bucket` — the state bucket (name per `Terraform_Bootstrap_Design.md` §7's approved pattern, `enterprise-data-platform-tfstate-<AWS_ACCOUNT_ID>`; no real account ID or bucket name invented here)
- `aws_s3_bucket_versioning` — `Enabled`
- `aws_s3_bucket_server_side_encryption_configuration` — SSE-S3 (`AES256`)
- `aws_s3_bucket_public_access_block` — all four settings blocking
- `aws_s3_bucket_ownership_controls` — `BucketOwnerEnforced`
- `aws_s3_bucket_policy` — deny any request where `aws:SecureTransport` is `false`
- `lifecycle { prevent_destroy = true }` on the `aws_s3_bucket` resource

**Terraform deployment IAM role and policies:**

- `aws_iam_role` — the deployment role (`enterprise-data-platform-shared-deployment-role`, per the corrected naming convention, §9 below); trust policy (assume-role policy document) trusts **only the human identity**, with an `aws:MultiFactorAuthPresent: true` condition on that trust statement (`Terraform_Bootstrap_Design.md` §21, §23); `max_session_duration = 3600` (1 hour, approved)
- `aws_iam_policy` (or `aws_iam_role_policy`) + `aws_iam_role_policy_attachment` — least-privilege permission policy scoped to what this project currently manages (S3 for the state bucket; EC2/VPC and narrowly-scoped IAM actions for the two roles this design defines once `environments/dev/` exists — not written broader than currently needed); explicitly excludes `iam:CreateUser`, `iam:CreateAccessKey`, and any self-escalation action (`Terraform_Bootstrap_Design.md` §23)
- `lifecycle { prevent_destroy = true }` considered on the `aws_iam_role` resource, per `Terraform_Bootstrap_Design.md` §28.2

No VPC, EC2, security-group, or workstation-role resource is part of this configuration. No `aws_dynamodb_table` (native S3 locking only, no DynamoDB). No customer-managed KMS key (SSE-S3 only).

## 9. Tagging for Bootstrap Resources — Environment = shared

Per the user's final decision: **all bootstrap-level resources use `Environment = "shared"`**, recorded now in `01_Architecture/Naming_Convention.md` (this task's companion edit). `shared` is a **resource-scope tag value**, not a fifth deployment environment — it never appears as a Terraform workspace, an `environments/` directory, or a value passed to anything that means "which environment does this serve." The deployment role's name is corrected accordingly to `enterprise-data-platform-shared-deployment-role` (from an earlier, incorrect `-dev-` example in `Naming_Convention.md`, now fixed). The state bucket's name keeps the already-approved `enterprise-data-platform-tfstate-<AWS_ACCOUNT_ID>` pattern (`Terraform_Bootstrap_Design.md` §7, which predates and is unaffected by this tag decision) — its `Environment` **tag** is `shared` even though its **name** doesn't carry an environment token, consistent with §7's own reasoning for that pattern.

`locals.tf` (§3) computes the common tags map once: `{ Project = var.project_name, Environment = "shared", ManagedBy = "terraform", Owner = "DataEngAA", CostCenter = "personal-learning" }`, merged with any resource-specific tags (e.g., `DataClassification = "internal"`) at the resource level.

---

## 10. Inputs and Outputs for the Bootstrap Root Module

**Inputs (`variables.tf`):**

- `project_name` — default `"enterprise-data-platform"`
- `region` — default `"ap-south-1"`
- `environment` — default `"shared"` (documented as fixed for this root module; not meant to be overridden — bootstrap resources are always `shared`, §9)
- `deployment_role_max_session_duration` — default `3600`
- `trusted_principal_arns` — list, starts containing only the human identity's ARN; updated in a later, separate apply once the workstation role exists (§16) — **no ARN invented here**
- `state_bucket_name` — **no default**; account-specific, supplied via `terraform.tfvars` (§12)
- `tags` — optional map for any additional resource-specific tags beyond the common set in `locals.tf`

**Outputs (`outputs.tf`):** `state_bucket_name`, `state_bucket_arn`, `deployment_role_arn`, `deployment_role_name`.

`environments/dev/`'s inputs/outputs are not restated here (§5) — see the prior draft of this document for the forward-reference version, to be finalized when that work is actually planned.

---

## 11. Backend Template and Local Real-Value Configuration Approach

Per `Terraform_Bootstrap_Design.md` §19 (approved): partial backend configuration via `-backend-config` files, not hardcoded backend blocks.

**Two-phase handling of `backend.tf` (revised from the prior draft):** the approved file tree (§2) includes `backend.tf` from the moment `bootstrap/` is created — it is **not** added later as a separate step. To reconcile this with the already-approved local-state-first-then-migrate sequence (`Terraform_Bootstrap_Design.md` §5, still in force), `backend.tf`'s `backend "s3" {}` block is written but **commented out** (or otherwise inactive) when the file is first created, with a clear comment explaining why and pointing at the migration step. The **very first** `terraform init`/`apply` therefore still runs against local state, exactly as designed — the file's presence in the committed tree does not change the mechanics, only where the block physically lives before it's switched on. At the migration step (§15), the block is uncommented (no new file needed) and `terraform init -backend-config=backend.hcl -migrate-state` is run.

- `backend.hcl.example` is committed with placeholder values (`bucket = "<STATE_BUCKET_NAME>"`, `key = "bootstrap/terraform.tfstate"`, `region = "ap-south-1"`, `use_lockfile = true`). The region value is not sensitive and appears literally.
- The real `backend.hcl` is **not committed** — gitignored, created only when the configuration is actually initialized (not part of this task).

---

## 12. Placeholder Strategy for Account-Specific Values

Unchanged from the prior draft: no AWS account ID, ARN, globally-unique bucket name, or credential is invented anywhere in this plan or in the eventual committed files.

- Account-specific values (`state_bucket_name`, resolved account ID, role ARNs) have **no default** in `variables.tf` — supplied only via gitignored `terraform.tfvars`/`backend.hcl`.
- Committed example files use bracketed placeholder tokens (`<AWS_ACCOUNT_ID>`, `<STATE_BUCKET_NAME>`).
- Where Terraform can derive a value itself (`data "aws_caller_identity"` for the account ID used in the bucket-name pattern), that data source is preferred over a manually supplied placeholder.

---

## 13. Terraform and AWS Provider Version Strategy

Unchanged, and now explicitly reconfirmed as the user's final decision: **exact Terraform and AWS provider versions are verified immediately before code creation**, not fixed in this plan. `versions.tf` will declare `required_version = ">= 1.10.0, < 2.0.0"` and a pessimistic AWS provider constraint (e.g., `~> 5.0`) against whatever is confirmed current and compatible at that time — the literal constraint string is written when `versions.tf` is actually created (the next task), using a version check performed at that moment, not asserted here in advance.

---

## 14. .terraform.lock.hcl Policy

Unchanged: committed once it exists, per root module, never hand-edited, regenerated only via `terraform init`/`terraform init -upgrade`. **Not created by the next task** — it does not exist until a real `terraform init` runs, which is explicitly out of scope for file creation (§1).

---

## 15. State Migration Sequence

Unchanged from the prior draft, still the approved sequence for when `bootstrap/` is actually applied (not part of the next task):

1. `terraform init` + `plan` + `apply` for `bootstrap/` with the `backend.tf` block still commented out (§11) — local state.
2. Single encrypted, access-controlled temporary backup of the local `bootstrap/terraform.tfstate`.
3. Uncomment `backend.tf`'s `s3` block; create `backend.hcl` (gitignored) with real values.
4. `terraform init -backend-config=backend.hcl -migrate-state`.
5. Verify: `terraform state list` returns expected resources; `terraform plan` shows no changes.
6. Delete the local state file and the temporary backup only after step 5 passes.

---

## 16. Role Creation and Trust-Policy Update Sequence

Unchanged in substance from the prior draft, restated for the now-module-free bootstrap configuration:

1. `bootstrap/main.tf` creates the deployment role directly, trust policy trusting only the human identity (MFA condition).
2. Later (a separate, future task, not this one): the human identity, assuming the deployment role, applies `environments/dev/` — creating the VPC, workstation role, and EC2 instance.
3. A small, separate, reviewed follow-up apply of `bootstrap/` updates the `trusted_principal_arns` variable to add the now-real workstation role ARN, copied from `environments/dev/`'s output — never guessed.
4. From then on, the EC2 workstation assumes the deployment role for routine Terraform runs; the human identity's direct use becomes the exception.

---

## 17. Dependency Order

```text
1. bootstrap/ (direct resources: state bucket + hardening, deployment role)
                    │
                    ▼
         state migration (local → S3, native locking)
                    │
                    ▼
   [future, separately planned] environments/dev/: VPC → workstation role/SG → EC2
                    │
                    ▼
   [future] bootstrap/ (separate apply): trust-policy update
                    │
                    ▼
   [future] workstation bootstrap script + tool verification
```

Only the first box (`bootstrap/` file creation) is in scope for the task that follows this plan's approval.

---

## 18. Validation Commands to Run Before Plan

Unchanged, documented for the eventual (not-yet-authorized) `terraform plan`/`apply` step:

```text
terraform fmt -check -recursive
terraform validate
```

**Not run as part of the next task** — that task creates files only (§1).

---

## 19. Security and Linting Checks

Unchanged:

```text
tflint
tfsec .          # or: checkov -d .
```

Run manually once files exist and are being prepared for `plan`/`apply`; no CI enforcement yet.

---

## 20. Review Checkpoints Before Apply

1. **File-creation diff review** (applies to the next task): each new `bootstrap/*.tf` file reviewed per `Git_Workflow.md`'s PR process before merging, even though no `apply` happens yet.
2. **`plan` output review** (future, not this task): resource count/names match §8, tags present with `Environment = shared`, `prevent_destroy` present on the bucket and (if used) the role.
3. **Post-apply hardening check** (future): real `aws s3api ...` output confirming versioning, encryption, Block Public Access, ownership controls, TLS-only policy.
4. **Post-migration verification** (future): `terraform state list` + no-diff `plan` before deleting local state.
5. **Pre-trust-policy-update check** (future): workstation role ARN copied from real output, not retyped.

---

## 21. Partial-Apply Recovery Steps

Unchanged from `Terraform_Bootstrap_Design.md` §28.3 — inspect (`state list`, `plan`, targeted `aws` CLI checks) before any corrective action; `terraform import` for resources present in AWS but missing from state; re-`apply` for partially configured resources; never blind delete/recreate. Applies once `bootstrap/` is actually applied — not relevant to file creation alone.

---

## 22. Rollback and Cleanup Boundaries

Unchanged: `bootstrap/` resources (state bucket, deployment role) are not to be casually destroyed once anything depends on them; `prevent_destroy` plus a deliberate, reviewed process are the guardrails; no destroy-and-recreate as a routine recovery step.

---

## 23. Files That Must Not Be Created Yet

- Any `.tf`, `.tfvars`, or `.hcl` file **outside** the exact ten files listed in §2 — including `terraform.tfvars` and `backend.hcl` themselves (real-value files, not created until actual `init`/`apply`).
- `infrastructure/terraform/modules/` — the entire directory, including `vpc/`, `iam-workstation-role/`, `ec2-workstation/`.
- `infrastructure/terraform/environments/` — the entire directory, including `dev/`.
- `infrastructure/terraform/shared/`.
- Any `.github/workflows/*.yml` CI/CD file.
- `.terraform.lock.hcl` (only generated by a real `terraform init`, not part of this task).

## 24. AWS Resources That Must Not Be Created Yet

- The state bucket and deployment role themselves — writing the `.tf` files does not create anything in AWS; only a real `terraform apply` would, and that is not authorized by this plan.
- VPC, subnets, Internet Gateway, route tables.
- Workstation IAM role, instance profile, security group.
- EC2 instance.
- NAT Gateway, private subnets.
- Any CloudWatch alarm, EventBridge rule, or Lambda function for automatic shutdown.
- `aws_budgets_budget` (existing Budget stays manually managed).
- Any customer-managed KMS key, DynamoDB table, additional IAM user/access key, or CI/CD role.
- `test`, `stage`, `prod` resources of any kind.

---

## 25. Exact Commands That Will Eventually Be Run (Documented Only — Not Run Now, and Not Part of the Next Task Either)

```text
# bootstrap — first apply (local state, backend.tf block still commented out)
terraform -chdir=infrastructure/terraform/bootstrap fmt -check -recursive
terraform -chdir=infrastructure/terraform/bootstrap init
terraform -chdir=infrastructure/terraform/bootstrap validate
terraform -chdir=infrastructure/terraform/bootstrap plan
terraform -chdir=infrastructure/terraform/bootstrap apply

# verification (real AWS CLI output required, not assumed)
aws s3api get-bucket-versioning --bucket <STATE_BUCKET_NAME>
aws s3api get-bucket-encryption --bucket <STATE_BUCKET_NAME>
aws s3api get-public-access-block --bucket <STATE_BUCKET_NAME>
aws s3api get-bucket-ownership-controls --bucket <STATE_BUCKET_NAME>
aws s3api get-bucket-policy --bucket <STATE_BUCKET_NAME>

# bootstrap — migrate to remote backend (after uncommenting backend.tf's s3 block)
terraform -chdir=infrastructure/terraform/bootstrap init -backend-config=backend.hcl -migrate-state
terraform -chdir=infrastructure/terraform/bootstrap state list
terraform -chdir=infrastructure/terraform/bootstrap plan     # expect: no changes

# linting / security
tflint
tfsec .

# recovery commands (used only if needed)
terraform import <resource_address> <resource_id>
terraform force-unlock <lock_id>
aws s3api list-object-versions --bucket <STATE_BUCKET_NAME> --prefix <key>
```

The `environments/dev/` command block from the prior draft is omitted here since that work is not yet planned in detail for creation; it will be restated when the dev VPC implementation plan is written. No placeholder above is a real value.

---

## 26. Evidence to Capture After Each Step

Unchanged in kind from the prior draft — `terraform apply` output, real `aws s3api` verification output, `state list`/no-diff `plan` output for migration, `tflint`/`tfsec` output — captured only when each step is actually executed, recorded in `Memory.md`/`Bootstrap_Checklist.md`/`PRE_PHASE_CHECKLIST.md` at that time. None of this exists yet.

---

## 27. Checklist Mapping

| This plan's step | `PRE_PHASE_CHECKLIST.md` item | `Bootstrap_Checklist.md` item |
|---|---|---|
| `bootstrap/` file creation (next task) | Step 8 items remain unchecked — file creation alone doesn't satisfy any AWS-facing checklist item | "Bootstrap Terraform state" remains unchecked until actually applied |
| `bootstrap/` first apply (future) | Step 8: "Remote state created" (local-state stage), "Terraform deployment role created" | "Bootstrap Terraform state (remote S3 backend + locking)" |
| State migration (future) | Step 8: "Remote state created", "State locking verified" | Same item, remote-state stage |
| `environments/dev/` work (future, separate plan) | Step 8: "Dedicated VPC created", "Workstation IAM role created", "EC2 workstation created via Terraform" | "Deploy VPC", "Deploy EC2 workstation" |
| Trust-policy update apply (future) | Step 4/Step 8 IAM items | "Configure secure AWS access" |
| Validation/lint/security (future) | Step 8: "Terraform validation ... run successfully" | n/a |

All items remain **unchecked** — this plan's approval and the next task (file creation) do not check off any AWS-facing checklist item.

---

## 28. Risks and Mitigations

| Risk | Mitigation |
|---|---|
| `backend.tf` being present (though commented out) from the start is accidentally left active on the first `init`, causing a confusing failure against a non-existent bucket | README.md documents the two-phase state explicitly (§11); the commented block carries an inline comment pointing at the migration step |
| Inlining all bootstrap resources into one `main.tf` (no modules) makes the file harder to read as it grows | Small, well-known resource count (bucket + ~5 hardening resources + role + policy) is manageable in one file for this scope; revisit modularization only if it genuinely grows |
| `Environment = shared` tag value used incorrectly on a resource that actually belongs to a deployment environment | `Naming_Convention.md` now explicitly documents `shared` as reserved for account-level bootstrap resources only, not a deployment environment (§9) |
| Deployment role trust policy updated with a wrong/guessed ARN (future step) | Explicit requirement to copy the real output value (§16 step 3) |
| Bootstrap resources accidentally destroyed (future) | `prevent_destroy`, no delete permission on the role's own policy, documented rollback boundary (§22) |
| This plan drifting from `Terraform_Bootstrap_Design.md` if the design changes later | This plan remains explicitly subordinate to and derived from the design document |

---

## 29. Decisions — Resolved by This Task, and Genuinely Still Open

**Resolved by the user's final decisions in this task:**

- ~~Whether `modules/state-backend`/`modules/iam-deployment-role` are created~~ — **No**, resources stay directly in `bootstrap/main.tf` (§1).
- ~~Whether `modules/security-group` is a separate module~~ — **No**, folded into `modules/ec2-workstation` (§2).
- ~~Environment tag value for bootstrap-level resources~~ — **`shared`**, now recorded in `Naming_Convention.md` (§9).
- ~~Exact Terraform/AWS provider versions~~ — confirmed as **verified immediately before code creation** (§13), not a blocking open item.
- ~~Private subnet CIDR ranges~~ — confirmed as **deferred until the dev VPC implementation plan**, not decided or blocking now.
- ~~Whether break-glass procedure blocks code creation~~ — **No**; it must be documented **before apply**, not before file creation (§30).

**Still genuinely open (do not block the next task, §30):**

- Exact deployment-role permission policy content (which specific IAM actions/resources) — drafted when `main.tf` is actually written.
- Exact break-glass identity/procedure — must exist and be documented before any `apply`, not before file creation.
- Carried from `EC2_Development_Workstation.md` §28, unrelated to bootstrap scope: EBS snapshot cadence/retention, exact autostop schedule, timing for the private-subnet hardening alternative, whether `t3.small` is adopted, whether an ADR is written for the ARM64→x86_64 reversal.

---

## 30. Exit Criteria

**Exit criteria for the next task (creating `bootstrap/` files) — already met:** this plan has been reviewed and approved (this document's status line); the tree, resources, and tagging convention are fully specified (§2, §8–9); no blocking decision remains for file creation specifically (§29). The next task may proceed to create exactly the ten files in §2, with no `terraform` command run.

**Exit criteria for later running `terraform init`/`plan`/`apply` (separate, future authorization, not granted by this document):**

1. The bootstrap files exist and have passed self-review (§20 checkpoint 1).
2. The break-glass identity/procedure is documented (§29) — required before `apply`, not before file creation.
3. The exact deployment-role permission policy content has been drafted and reviewed.
4. The user has given a separate, explicit authorization to run `terraform init`/`plan`, and, later, a further explicit authorization for `apply`.

---

*This plan is derived entirely from already-approved decisions in `02_Infrastructure/Terraform_Bootstrap_Design.md`, `02_Infrastructure/EC2_Development_Workstation.md`, `02_Infrastructure/AWS_Account_Preparation.md`, `02_Infrastructure/IAM_and_Access.md`, `02_Infrastructure/Networking.md`, `01_Architecture/Naming_Convention.md`, `01_Architecture/Standards.md`, `03_Development/Git_Workflow.md`, and `10_Cost_and_FinOps/Cost.md`, plus the final scope decisions in this task. Nothing in this document has been implemented, applied, or verified in AWS.*

Last updated: 2026-07-25
