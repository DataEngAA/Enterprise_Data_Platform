# Terraform Bootstrap — Design Document

Status: **Design REVIEWED AND APPROVED by user (2026-07-24). Still documentation only — no Terraform files, modules, environments, bootstrap, shared, or global folders created. No AWS resources created or modified. No `terraform init`/`plan`/`apply` run.** The architecture below reflects approved decisions, not open recommendations, except where a section is explicitly marked as still open (§30).

This document is the authoritative design for the Terraform Bootstrap step (`PROJECT_BLUEPRINT.md` Section 20 sequence: ... → GitHub Repository → EC2 Development Workstation → Development Tool Installation → **Terraform Bootstrap** → Phase 0 → ...). It builds on decisions already approved and verified in `02_Infrastructure/AWS_Account_Preparation.md`, `02_Infrastructure/EC2_Development_Workstation.md`, `02_Infrastructure/IAM_and_Access.md`, and `01_Architecture/Naming_Convention.md`, and does not repeat their reasoning in full.

**Approval traceability.** The user's approval gate for this document requires the following to be clearly documented; each maps to a section below:

| Required item | Section |
|---|---|
| Bootstrap state lifecycle | §2, §5, §11 |
| Selected state-locking mechanism | §6 |
| Selected deployment-role creation path | §21, §22 |
| Selected backend configuration method | §19 |
| Partial-apply recovery process | §28 |
| State-bucket hardening requirements | §9, §28 |
| Protection of critical bootstrap resources from accidental destruction | §11, §28 |

---

## 1. Purpose and Scope

Define, on paper only, how this project will bootstrap Terraform: where its state lives, how state is locked, how a Terraform deployment identity is created and used, how the repository and module layout will look, and how the dedicated VPC and EC2 workstation will later be brought under Terraform management. This document does not create any of it. Actual implementation is a separate, future task that requires explicit user authorization after this design is reviewed.

Out of scope: writing `.tf` files, running any Terraform command, creating IAM roles/policies in AWS, creating the VPC or EC2 instance, and any GitHub Actions/CI implementation (deferred to the CI/CD phase, §27).

## 2. Bootstrap Problem and Dependency Order — APPROVED EXECUTION LOCATION

Terraform needs two things before it can manage anything durably: a place to store state remotely, and an identity with permission to create resources. Neither can exist yet under Terraform's own management, because the tool that would manage them (Terraform, via a backend and a role) doesn't have anywhere to run from or any identity to assume until those very resources exist. This is the classic bootstrap chicken-and-egg problem, and the design must avoid two failure modes: (a) a circular dependency where resource X requires resource Y which requires resource X, and (b) silently leaving foundational resources unmanaged and undocumented forever.

**Resolution — who does what, in order:**

1. **The human IAM identity** (the user's own IAM user/IAM Identity Center identity, already MFA-verified per `AWS_Account_Preparation.md` §8) runs the **bootstrap Terraform configuration** (§12) directly — not from the EC2 workstation, because the workstation does not exist yet at this point. This can be run from the user's own laptop CLI or AWS CloudShell, using temporary, bootstrap-scoped permissions (§21).
2. That bootstrap apply creates, using **local state** initially (§5): the hardened remote-state S3 bucket (§9, §28), the state-locking configuration (§6), and the **Terraform deployment role** (§21) with a trust policy that, at this point, trusts only the human identity (the workstation role doesn't exist yet to be trusted).
3. The bootstrap state is then **migrated into the newly created S3 backend** (§2 lifecycle detail below, full process in §11).
4. The human identity — now itself assuming the deployment role, exercising the same path the workstation will use later — runs the `environments/dev` root module to create the dedicated VPC (§24), the workstation IAM role and instance profile, the security group, and the EC2 instance (§25).
5. Once the workstation role exists, a small, explicit Terraform change updates the **deployment role's trust policy** to add the workstation role as a trusted principal (§22). This is the only point where the deployment role's trust relationship changes.
6. From this point forward, **all routine Terraform runs happen from the EC2 workstation**, which assumes the deployment role via `sts:AssumeRole`. The human identity's direct use of the deployment role becomes the exception (break-glass / initial bootstrap only, §28), not the routine path.

This sequence has no circular dependency: nothing Terraform-manages depends on the resource it is simultaneously creating within the same apply, and the one identity change that depends on a later-created resource (step 5) is a deliberate, separate, documented step — not an attempt to create it all atomically.

**Approved:** the first bootstrap apply runs manually, using the existing human IAM identity, from the user's local laptop or AWS CloudShell — the EC2 workstation is explicitly **not** required to exist first. The initial bootstrap workload (state bucket + deployment role) is small and well-suited to local, one-off execution. Once the workstation exists, normal day-to-day Terraform execution moves to the EC2 workstation via role assumption (§22), and direct human-identity execution becomes the exception rather than the routine path (§28).

## 3. Terraform Version Strategy — APPROVED

- **Approved: Terraform 1.10 or later**, required specifically because native S3 state locking (§6) depends on the `use_lockfile` backend argument, introduced in Terraform 1.10.
- Pin via `required_version` in every root module, e.g. `required_version = ">= 1.10.0, < 2.0.0"`.
- **No exact patch version is fixed in this document.** Per the approved decision, the exact patch/minor release is verified immediately before implementation (not guessed now), and recorded via the committed `.terraform.lock.hcl` (§20) plus the workstation's installed Terraform binary version (`terraform version`) at that time.
- Do not jump to a hypothetical Terraform 2.x without a deliberate, separately reviewed decision (likely warranting an ADR given the blast radius of a major-version upgrade once state exists).

## 4. AWS Provider Version Strategy — APPROVED

- **Approved: the official `hashicorp/aws` provider, pinned with an explicit, compatible pessimistic version constraint** (e.g. `~> 5.0`, or whatever current stable major series is confirmed compatible with the pinned Terraform version at implementation time).
- **No exact provider version is fixed in this document**, consistent with the Terraform version decision (§3) — the final exact pin is verified immediately before implementation, not asserted here.
- Exact resolved version and checksums are recorded in `.terraform.lock.hcl` (§20), not just the constraint — this is what makes the provider version reproducible across machines/re-clones.
- Provider upgrades (e.g. moving the constraint to a new major version) should be a deliberate, separate change with its own `terraform plan` review, not an incidental side effect of an unrelated change.

## 5. Remote-State Design

- **Backend type:** `s3`, using the built-in S3 backend's native locking support (§6) — no separate state-tracking service beyond S3 itself.
- **Bootstrap state lifecycle (required item):**
  - **During the first apply**, the bootstrap configuration's own state exists as a **local state file** (`bootstrap/terraform.tfstate`) on whatever machine runs it (the human identity's laptop/CloudShell, §2) — there is no remote backend yet, because the remote backend is one of the things this apply creates.
  - **Immediately after** the S3 bucket and locking configuration exist, the bootstrap configuration's backend block is updated to point at the new S3 backend, and `terraform init -migrate-state` is run to move that local state into S3 under a dedicated key (§8: `bootstrap/terraform.tfstate` within the state bucket).
  - **Recommendation: migrate, do not leave local state permanently.** Leaving the bootstrap state local forever would mean the resources that protect and enable every other Terraform-managed resource in this project (the state bucket itself, the deployment role) are themselves unmanaged from a durability standpoint — defeating the purpose of adopting remote state at all, and creating a single point of loss (one laptop, one file).
  - **Migration/verification/backup/cleanup process:**
    1. Before migrating, make a single encrypted, access-controlled backup copy of the local `bootstrap/terraform.tfstate` (e.g., to an encrypted local volume or a temporary, access-restricted location) — not a casual plaintext copy, since state can contain sensitive values.
    2. Run `terraform init -migrate-state` after updating the backend block.
    3. Verify: `terraform state list` against the new backend returns the expected resources, and `terraform plan` shows **no changes** (confirming the migrated state accurately reflects reality).
    4. Only after that verification passes, delete the local `bootstrap/terraform.tfstate` (and any `.tfstate.backup`) from the working directory, and delete the temporary backup copy made in step 1. Do not keep an uncontrolled permanent copy of Terraform state anywhere outside the versioned S3 bucket.
  - **Proposed bootstrap state key pattern** (no real bucket name invented): `s3://<STATE_BUCKET_NAME>/bootstrap/terraform.tfstate`, where `<STATE_BUCKET_NAME>` follows the pattern in §7.
- Everything other than the bootstrap config itself (the `environments/*` root modules, §13) is remote-state-only from its very first apply — it never goes through a local-then-migrate step, because by the time it runs, the S3 backend already exists.

## 6. State-Locking Design: Native S3 Locking vs. S3+DynamoDB — APPROVED

**Approved: native S3 state locking via the backend's `use_lockfile = true` argument. No DynamoDB table is created.**

Comparison:

| Factor | Native S3 locking (`use_lockfile`) | S3 + DynamoDB (traditional) |
|---|---|---|
| Terraform version required | >= 1.10 | Any (long-standing pattern) |
| Extra AWS resource to create/manage | None | A DynamoDB table (plus its own IAM permissions, encryption, backup considerations) |
| Cost | None beyond the state bucket itself | Small, usually within Free Tier equivalents, but this account is confirmed **not** Free Tier eligible (`AWS_Account_Preparation.md` §2), so it's a small but non-zero recurring cost |
| Mechanism | Atomic conditional writes (`If-None-Match`) directly against S3 | A DynamoDB item with a conditional put, separate from the state object |
| Track record | Newer (Terraform 1.10, released late 2024) | Long-established, widely documented, the "traditional" pattern most tutorials still show |
| Operational surface | One resource (the bucket) to secure and reason about | Two resources (bucket + table) to secure, tag, and reason about |

**Justification:** simplicity (one fewer resource type to create, permission, and monitor), cost (strictly lower, and this account has no Free Tier cushion), and maintainability (less IAM surface — the deployment role needs S3 permissions it already needs anyway, rather than an additional DynamoDB permission set). The main trade-off accepted is a shorter track record than DynamoDB locking; this is judged acceptable for a single-developer portfolio project that is not under time pressure from a large team needing battle-tested tooling, and the underlying mechanism (S3 conditional writes) is a standard, well-understood AWS primitive even though Terraform's specific use of it is newer.

**This is not a default to DynamoDB "because it's the older common pattern"** — native locking is approved specifically because it is simpler and cheaper for this project's actual size, with the version dependency (Terraform >= 1.10, §3) called out explicitly as the condition that makes it viable. If the workstation's Terraform version cannot meet that floor for some reason discovered during implementation, the documented fallback is the traditional S3+DynamoDB pattern, added at that time — not silently assumed now.

## 7. State Bucket Naming Pattern

Following `01_Architecture/Naming_Convention.md`'s S3 bucket pattern and its own note that a uniqueness-guaranteeing suffix will be needed:

```text
enterprise-data-platform-tfstate-<AWS_ACCOUNT_ID>
```

`<AWS_ACCOUNT_ID>` is a placeholder for this AWS account's account ID (not invented or guessed here). Using the account ID as the suffix guarantees global uniqueness without introducing a separate random value to track, and is a common, well-understood convention. **A single state bucket is proposed for the whole project** (not one bucket per environment) — environment separation is achieved through the state **key** layout (§8), not through separate buckets, which keeps the bucket-hardening work (§9) a one-time exercise.

## 8. State Key Layout

```text
bootstrap/terraform.tfstate
<environment>/networking/terraform.tfstate
<environment>/iam/terraform.tfstate
<environment>/ec2-workstation/terraform.tfstate
```

Example for the initially deployed environment: `dev/networking/terraform.tfstate`, `dev/iam/terraform.tfstate`, `dev/ec2-workstation/terraform.tfstate`. Each root module (§16-17) owns exactly one state key; state is not shared across root modules. This is deliberately more granular than one giant per-environment state file, so that a mistake or `plan` inside, say, the EC2 workstation root module cannot accidentally propose changes to networking or IAM resources it doesn't own.

**Superseding note (added 2026-07-26, illustration above retained as history, not rewritten):** `environments/dev`'s actual implementation (`16_Implementation_Notes/Dev_Environment_Terraform_Implementation_Plan.md` §10) uses a **single** `dev/terraform.tfstate` key for the whole environment (VPC + workstation IAM role + EC2 instance together), not the three-key split illustrated above. This is consistent with, not a deviation from, §17 below, which already describes `environments/dev/` as **one composing root module** — a single root module logically implies a single state key. The three-key illustration above and §17's single-root-module description were in tension before this note; the single-key model is now the approved design. This was flagged and resolved via the implementation plan's §56 "Documentation Conflicts Flagged," conflict #1. If finer-grained per-concern state isolation (networking / IAM / compute split) is wanted later, that remains available as a deliberate, separate, future restructuring — not something silently reintroduced.

## 9. State Encryption — APPROVED

- **Approved: SSE-S3 (`AES256`)** bucket default encryption, enabled during the same bootstrap apply that creates the bucket (§28 — the bootstrap is not considered successful until this is verified, not just assumed).
- **No customer-managed KMS key is created during bootstrap.** SSE-KMS is deliberately not adopted now, and is only to be revisited **later, if a clear security or governance requirement emerges** (e.g., a need for independent key rotation control, cross-account access control, or a compliance requirement) — not adopted speculatively. SSE-S3 is an acceptable starting point for state that, per this design, should not contain long-lived secrets in the first place (§21, §28 — no credentials are ever written into `.tf`/state deliberately).
- All objects in the bucket inherit this default; no object is written unencrypted.

## 10. State Access Controls

- Bucket policy **requires TLS** (`aws:SecureTransport: true` deny condition) for all requests.
- Access to the state bucket is scoped to the **Terraform deployment role** (§21) for read/write, plus a separate, rarely-used **break-glass identity** (§28) for emergency recovery — not to the workstation role directly, and not account-wide.
- No public access of any kind (§9, §28 hardening requirements).
- IAM policy on the deployment role scopes S3 permissions to the specific bucket ARN and the `*` object path within it (or narrower, per-key-prefix scoping if later desired for stricter separation between `bootstrap/` and `<environment>/*` keys) — not to S3 generally.

## 11. State Recovery and Backup

- **Versioning: required, enabled** on the state bucket from the first bootstrap apply (§28) — this is the primary recovery mechanism for state corruption or an unwanted overwrite.
- **Recovering a previous version:** `aws s3api list-object-versions --bucket <STATE_BUCKET_NAME> --prefix <key>` to find the prior version ID, then either restore it as the current version (copy the old version over the current one) or `terraform state pull`/inspect it before deciding to restore — recovery is a deliberate, inspected action, not an automatic rollback.
- **The bootstrap configuration itself stays in Git.** If state were ever lost entirely (e.g., bucket-level failure with no recoverable version), the bootstrap resources could be **re-imported** into a fresh state using `terraform import` for each resource (state bucket, IAM role, etc.) after manually confirming their actual configuration in AWS — not recreated blindly, since re-running `apply` against empty state for resources that already exist in AWreturn would either fail (name collision) or, worse, attempt destructive replacement.
- No routine practice of keeping ad hoc copies of state outside the versioned bucket (state can contain sensitive values, e.g. resource attributes marked sensitive) — the one exception is the single, temporary, encrypted migration backup described in §5, which is deleted once migration is verified.

## 12. Separate Bootstrap Configuration vs. Main Infrastructure Configuration

**Separate, and deliberately minimal.** The `bootstrap/` root module's sole job is to create the state bucket, its hardening (§9, §28), the locking configuration (§6), and the Terraform deployment role (§21) — nothing else. It is the one Terraform configuration in this project that legitimately starts from local state (§5) and is migrated, rather than starting remote.

All other infrastructure (networking, IAM for the workstation, the EC2 instance, and everything in later phases) lives in the `environments/<environment>/` root modules (§13, §16-17), which use the S3 backend from their very first apply. This separation keeps the bootstrap blast radius small: routine infrastructure work never touches the bootstrap configuration, and the bootstrap configuration is rarely touched again once it has run successfully.

## 13. Environment Strategy for dev, test, stage, prod — APPROVED

- Four environment values are reserved per `Naming_Convention.md`: `dev`, `test`, `stage`, `prod`. These remain the only allowed future environment names.
- Each environment gets its **own root module directory** under `environments/` (§15-16), its own state keys (§8), and its own `backend.hcl`/`terraform.tfvars` (§19) — not Terraform's built-in workspaces feature. Directory-per-environment is chosen over workspaces because workspaces share the same backend configuration and the same root module code path by default, which makes it easier to accidentally run a `plan`/`apply` against the wrong environment; separate directories force an explicit `-chdir` or working-directory choice and make environment-specific variable differences (instance sizing, tags) explicit in version-controlled files rather than implicit workspace state.
- **Approved: only `dev` is deployed and scaffolded during the initial implementation.** `test`, `stage`, and `prod` directories are **not** created now — not even as empty placeholders or minimal scaffolding. They are added later, **only when their own implementation phase actually begins**, each created with real, needed configuration at that time rather than speculative scaffolding today.

## 14. Which Environments Will Actually Be Deployed First — APPROVED

**`dev` only.** This matches `PROJECT_BLUEPRINT.md` Section 11 Step 3 ("dev may be implemented first while the multi-environment design is documented") and the EC2 workstation design, which is a `dev`-environment resource. `test`, `stage`, `prod` remain design-only (not even scaffolded, §13) until a concrete need arises.

## 15. Proposed Repository Structure

Documented only — **not created** in this task.

```text
infrastructure/terraform/
├── README.md                          (exists today)
├── bootstrap/
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── versions.tf
│   ├── backend.tf                     (local at first; updated post-migration, see §5)
│   └── terraform.tfvars.example
├── modules/
│   ├── state-backend/                 (S3 bucket + hardening + locking config, used by bootstrap/)
│   ├── iam-deployment-role/
│   ├── iam-workstation-role/
│   ├── vpc/
│   ├── security-group/
│   └── ec2-workstation/
├── environments/
│   ├── dev/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   ├── versions.tf
│   │   ├── backend.tf                 (empty backend "s3" {} block, see §19)
│   │   ├── backend.hcl.example        (committed template, placeholders only)
│   │   ├── backend.hcl                (real values, gitignored, see §19)
│   │   ├── terraform.tfvars.example
│   │   └── terraform.tfvars           (real values, gitignored where account-specific)
│   │   (test/, stage/, prod/ do NOT exist yet — created only when their own implementation phase begins, §13)
└── shared/
    └── tags.tf / locals.tf            (shared tag/naming locals consumed by root modules, if not simply duplicated per environment)
```

**Approved: `test/`, `stage/`, and `prod/` directories are not created as part of the initial implementation** — only `bootstrap/`, `modules/`, and `environments/dev/` are (§31).

This matches the structure sketched in the task prompt, refined with the specific files each directory is expected to hold.

## 16. Proposed Module Structure

- `modules/state-backend` — S3 bucket, versioning, encryption, Block Public Access, bucket policy (TLS-only, least privilege), ownership controls. Used once, by `bootstrap/`.
- `modules/iam-deployment-role` — the Terraform deployment role, its trust policy (parameterized so the trusted principal can be updated per §2 step 5), and its permission policy (scoped per environment/phase, §23).
- `modules/iam-workstation-role` — the EC2 instance role/instance profile: SSM core, minimal CloudWatch Logs, narrow artifact access, `sts:AssumeRole` on the deployment role only (per `EC2_Development_Workstation.md` §13.1).
- `modules/vpc` — the dedicated VPC, public subnet, Internet Gateway, route table (§24). Private application and private data subnet CIDR ranges are reserved as variables/documentation; those subnet resources are not provisioned yet.
- `modules/security-group` — the zero-inbound-rule workstation security group (per `EC2_Development_Workstation.md` §11).
- `modules/ec2-workstation` — the EC2 instance itself: AMI lookup (Amazon Linux 2023, x86_64), instance type variable (default `t3.medium`), `gp3` encrypted root volume (30 GiB), instance profile attachment, public IP assignment (§9-10 of the EC2 design).

Modules stay small and composable rather than one large monolithic module, consistent with `Standards.md`'s "Modules" requirement and this project's goal of demonstrating clean Terraform practice for interview purposes.

## 17. Root-Module Responsibilities

- **`bootstrap/`**: composes `modules/state-backend` and `modules/iam-deployment-role` only. Supplies its own provider config (no `assume_role`, since it runs as the human identity directly — §21). Its state lives in the very bucket it creates (§5, §8).
- **`environments/dev/`**: composes `modules/vpc`, `modules/security-group`, `modules/iam-workstation-role`, `modules/ec2-workstation` (and, in later phases, additional modules as Phase 0+ resources are designed). Supplies `project_name`, `environment = "dev"`, `region`, and tag values as variables (§18). Provider config uses `assume_role` to run under the deployment role (§21-22) rather than whatever identity invoked Terraform directly.
- **`environments/test|stage|prod/`**: same composition pattern as `dev` will apply once each is created — but none of these directories exist yet; each is created only when its own implementation phase begins (§13-14), not scaffolded in advance.

## 18. Naming and Tagging Integration

- All modules and root configs consume `project_name` (`enterprise-data-platform`), `environment`, and a shared `tags` map (`Owner = "DataEngAA"`, `CostCenter = "personal-learning"`, `ManagedBy = "terraform"`, plus `Project`/`Environment` derived from the variables) as inputs, per `Naming_Convention.md`.
- Recommend setting these as **provider-level `default_tags`** in each root module's `aws` provider block, so every resource that supports tagging inherits them automatically without repeating a `tags = {...}` block on every resource — reduces the chance of a forgotten tag.
- `DataClassification` is set per-resource where meaningful (most Pre-Phase/bootstrap resources are infrastructure, not data, so a reasonable default like `internal` at the provider level, overridden per-resource once actual data resources exist in later phases).
- Resource names themselves (not just tags) follow `Naming_Convention.md`'s patterns exactly — e.g., the state bucket (§7), IAM roles (already named in `Naming_Convention.md`: `enterprise-data-platform-dev-workstation-role`, `enterprise-data-platform-dev-deployment-role`), security groups (`enterprise-data-platform-dev-workstation-sg`).

## 19. Provider and Backend Configuration Mechanics

**Selected backend configuration method (required item): partial backend configuration via `-backend-config` files, not hardcoded backend blocks.**

- Each root module's `backend.tf` declares an empty `backend "s3" {}` block (just the backend type, no values).
- Actual values (bucket, key, region, and `use_lockfile = true`) are supplied at `terraform init -backend-config=backend.hcl` time, from a per-root-module `backend.hcl` file.
- **Distinguishing committed templates from real-value files:** a `backend.hcl.example` file is **committed**, containing placeholders (`bucket = "<STATE_BUCKET_NAME>"`, `key = "<ENVIRONMENT>/<COMPONENT>/terraform.tfstate"`, `region = "ap-south-1"`). The real `backend.hcl` (with the actual bucket name once created) is **not committed** — added to `.gitignore` — even though a bucket name isn't a credential, because this repository may be public and there's no benefit to advertising exact resource identifiers (including any account-ID-derived bucket name, §7) more widely than necessary. The region (`ap-south-1`) itself is not sensitive and may be included in the committed example directly.
- **One reusable root configuration vs. one root module per environment:** **one root module per environment** (§13, §15) is recommended over a single parameterized root reused via workspaces or a `-var environment=dev` pattern. Each environment's `backend.hcl` and `terraform.tfvars` are then simple, explicit, environment-specific files rather than a shared root module branching on a variable — reducing the risk of applying the wrong environment's variables against the wrong state key.
- Provider blocks: `bootstrap/` configures the `aws` provider directly (human identity's own credentials, no assume_role). `environments/*/` configure the `aws` provider with an `assume_role` block pointing at the deployment role (§21-22).

## 20. Variable and Output Conventions

- Variable names: `snake_case`, per `Naming_Convention.md` (`project_name`, `environment`, `region`, `tags`, `instance_type`, `deployment_role_arn`, etc.).
- Every root module declares `variables.tf` with descriptions and, where safe, sensible defaults (e.g., `instance_type` defaults to `t3.medium`); account-specific values (bucket names, role ARNs) have **no default** and must be supplied via `terraform.tfvars`/`backend.hcl`, which are gitignored where they'd otherwise expose account-specific identifiers (§19).
- Outputs: each root module exposes the identifiers other configurations need (e.g., `environments/dev`'s networking might expose `vpc_id`, `public_subnet_id` for consumption by the EC2 workstation root module, if split into separate state keys per §8) via `outputs.tf`, consumed either through `terraform_remote_state` data sources or, if modules are composed within a single root module's `main.tf` as currently proposed (§17), simply as module outputs passed between `module` blocks in the same configuration.
- **Provider dependency lock files (required item):**
  - `.terraform.lock.hcl` is **committed** for every independent root module (`bootstrap/`, `environments/dev/`, and later `test`/`stage`/`prod`) — each root module initializes its own providers and keeps its own lock file; they are not shared.
  - This makes provider versions and checksums reproducible: `terraform init` will refuse to silently use a different provider build than what's recorded, unless `-upgrade` is explicitly requested.
  - `.terraform/` directories (the local provider/plugin cache) and any local plan files (`*.tfplan`) are **never committed**. The repository's `.gitignore` already excludes `.terraform/` and `*.tfstate*`; when Terraform files are actually created, it should also gain entries for `*.tfplan`, `crash.log`, and `backend.hcl` (excluding `backend.hcl.example`) — noted here as a follow-up for the implementation task, not applied to `.gitignore` now since this task is documentation-only and `.gitignore` wasn't in the list of files to modify.

## 21. Workstation IAM Role vs. Terraform Deployment Role

Reiterating and building on the already-approved split (`EC2_Development_Workstation.md` §13, `IAM_and_Access.md`):

- **Workstation instance role**: SSM core connectivity, minimal CloudWatch Logs write, narrowly scoped artifact access only where justified, and `sts:AssumeRole` limited to the deployment role's ARN. No direct infrastructure-management permissions, ever.
- **Terraform deployment role**: holds the actual infrastructure-management permissions Terraform needs to create/modify/destroy the resources this project manages. Never attached to anything directly — only reachable via `sts:AssumeRole`.

**Approved deployment-role creation path (required item): the deployment role is created by the bootstrap Terraform configuration (`bootstrap/` → `modules/iam-deployment-role`), executed using the human identity's temporary, bootstrap-scoped credentials — not created manually via clicking through the AWS Console.** Rationale: keeping it in Terraform from the start means it is version-controlled, reviewable via `plan`, and reproducible if the account ever needs to be rebuilt — consistent with `CLAUDE.md`'s "no manual, untracked production changes" rule, applied here even during bootstrap.

**Approved: deployment-role maximum session duration = 1 hour** (rather than the 12-hour default), reducing the exposure window of any single assumed session (§23).

**Temporary permissions the human identity needs during bootstrap:** enough to create and configure the state bucket (`s3:CreateBucket`, `s3:PutBucketVersioning`, `s3:PutBucketEncryption`, `s3:PutBucketPolicy`, `s3:PutPublicAccessBlock`, `s3:PutBucketOwnershipControls`) and the deployment role (`iam:CreateRole`, `iam:PutRolePolicy`/`iam:AttachRolePolicy`, `iam:CreateInstanceProfile` for later steps, `sts:GetCallerIdentity`), plus (for §2 step 4) the networking and EC2 permissions needed to stand up the VPC and workstation. Recommend defining a **dedicated, narrowly-scoped "bootstrap operator" policy** covering exactly these actions rather than granting the human identity a broad managed policy like `PowerUserAccess` or `AdministratorAccess`, even though the elevated access is temporary and human-controlled — least privilege applies to bootstrap too, not just to the roles it creates.

## 22. Role-Assumption Workflow

**How the workstation role assumes the deployment role after bootstrap (required item):**

1. Once the workstation IAM role exists (created in §2 step 4), a small, explicit Terraform change (applied via the human-assumed deployment role, or the human identity directly) updates the deployment role's **trust policy** to add the workstation role's ARN as an additional trusted principal, alongside (or eventually replacing, for routine use) the human identity.
2. From then on, when Terraform runs **on the EC2 workstation**, its `aws` provider block includes an `assume_role` argument:
   ```text
   provider "aws" {
     region = var.region
     assume_role {
       role_arn     = var.deployment_role_arn
       session_name = "terraform-dev"
     }
   }
   ```
3. The AWS SDK underneath Terraform first obtains the workstation's own temporary credentials via the EC2 instance metadata service (from the attached instance profile), then exchanges them for deployment-role session credentials via `sts:AssumeRole`. No static keys are involved at any point (`CLAUDE.md` §7).
4. The same pattern applies to any AWS CLI commands run manually from the workstation for verification (`aws sts assume-role ...` or a configured CLI profile with `role_arn` + `credential_source = Ec2InstanceMetadata`).

## 23. Least-Privilege Design

- The workstation role's **only** path to infrastructure permissions is the single `sts:AssumeRole` statement scoped to the deployment role's exact ARN — not a wildcard, not multiple roles.
- The deployment role's permissions should be scoped to **exactly the resources this project is currently managing**, expanded incrementally as new phases are reached, rather than granted as a broad `AdministratorAccess`-equivalent policy up front. Starting scope (bootstrap + Pre-Phase Step 4): S3 (state bucket + any dev artifact bucket), EC2/VPC (networking + the workstation instance), IAM (narrowly, to manage the two roles/policies this design defines — with an explicit deny or omission of `iam:CreateUser`, `iam:CreateAccessKey`, and any action that could create a new long-lived-credential identity, closing off a self-escalation path).
- **Max session duration on the deployment role: approved at 1 hour** (§21), rather than the 12-hour default, reducing the exposure window of any single assumed session (see §22's IAM trust-condition discussion, folded in below).
- **IAM trust-policy conditions (required detail):**
  - The deployment role's trust statement for the **workstation role** principal has no MFA condition — an unattended EC2 instance role obtained via instance metadata has no interactive MFA context to present, so an `aws:MultiFactorAuthPresent: true` condition on that statement would simply make the workstation permanently unable to assume the role. The compensating controls here are the workstation role's narrow scope, the short max session duration, and CloudTrail-audited `AssumeRole` events.
  - A **separate trust statement for the human identity** (used during bootstrap, §2, and for any future break-glass access, §28) **should** carry an `aws:MultiFactorAuthPresent: true` condition, since a human, interactive session can and should present MFA.
  - Stronger production-grade trust conditions (source identity tagging, IP-based restrictions, external ID) are **explicitly deferred** to Phase 0/production-readiness work, not silently omitted — noted as an open decision in §30.

## 24. Dedicated VPC Implementation Order — APPROVED

1. After the bootstrap role/state exist (§2), the VPC is the **first real resource** created in `environments/dev` via `modules/vpc`.
2. Creates **only what the current dev workstation needs**: the VPC itself, the public development subnet, the Internet Gateway, and the public route table (per the already-approved public-subnet/no-NAT initial design in `EC2_Development_Workstation.md` §9-10 and `AWS_Account_Preparation.md` §6-7).
3. **Approved: reserve CIDR address space for all three eventual subnet tiers — public, private application, and private data — as part of the VPC's overall addressing plan**, even though only the public tier is actually deployed now. This keeps the VPC's address space planned coherently from the start (avoiding a later re-addressing exercise) without creating unused resources today.
4. **Approved: do not deploy the private application or private data subnets now.** They are not created "for scaffolding's sake" — the reserved CIDR ranges are documentation/variables only, and the actual `aws_subnet` resources for those tiers are created later, when a concrete Phase 0+ workload (e.g., RDS, ECS/Fargate tasks) genuinely needs them, unless the eventual full VPC design is finalized to a point where creating them now is judged to add no meaningful risk or cost — that judgment call belongs to the implementation task, not asserted here.
5. **No NAT Gateway is created** (approved decision) — the future private-subnet hardening option (`EC2_Development_Workstation.md` §9) remains a documented alternative, not implemented now.

## 25. EC2 Workstation Implementation Order

Following directly from `EC2_Development_Workstation.md` §29, once the VPC (§24), security group (§16), and workstation IAM role (§21) exist in the same `environments/dev` apply (or a subsequent one, since they can share the same root module and state key per §8):

1. `modules/ec2-workstation` provisions the instance: Amazon Linux 2023, x86_64, `t3.medium` default, 30 GiB encrypted `gp3` root volume, the workstation instance profile attached, public IP assigned, the zero-inbound security group attached.
2. The bootstrap script (`EC2_Development_Workstation.md` §21) is run against the freshly launched instance — either manually over Session Manager for the first instance, or later via user data/`cloud-init` once the script is mature enough to trust unattended.
3. Session Manager connectivity and VS Code Remote-SSH-over-SSM are verified per the EC2 design's acceptance criteria (`EC2_Development_Workstation.md` §27) — this is evidence-gathering, not something this document performs.

## 26. Cost Controls — APPROVED

- **Approved: the existing AWS Budget and its five alerts (already created manually by the user, `AWS_Account_Preparation.md` §3) are recorded as an existing, manually managed account-level resource and are explicitly NOT imported into Terraform during this bootstrap.** Terraform does not create a second, potentially conflicting `aws_budgets_budget` resource with the same scope. The budget is tagged/documented as `ManagedBy = "manual"` (the exception `Naming_Convention.md` allows for resources genuinely outside Terraform's management).
- Reconsidering a `terraform import` of this budget is deferred indefinitely — **only revisit if there is a clear, specific benefit** (e.g., needing budget thresholds to vary per environment as new environments are deployed), not as a default cleanup task.
- Idle-resource cleanup (unattached EBS volumes, stale snapshots) and right-sizing discipline (default `t3.medium`, resize temporarily) remain as documented in `EC2_Development_Workstation.md` §22 and `Cost.md` — unchanged by this design.
- The state bucket itself is a negligible cost driver (small objects, S3 storage pricing), and native locking (§6) avoids adding a DynamoDB cost line entirely.

## 27. Validation Commands

Run manually from the workstation once it exists (or from the human identity's own environment during bootstrap) — no CI enforcement yet (§27a below):

```text
terraform fmt -check -recursive
terraform validate
terraform plan
```

Recommended additions, consistent with `Standards.md`'s "validation and security scans" requirement:

```text
tflint
tfsec .        # or: checkov -d .
```

**Execution and CI scope (required item):** initial bootstrap and all routine Terraform execution are **manual**, run from the EC2 workstation (once it exists) or, for the very first bootstrap apply, from the human identity's own environment (§2). GitHub Actions and any automated deployment pipeline are **out of scope until the CI/CD phase** (`PROJECT_BLUEPRINT.md` Phase 8) — this document does not create, propose the detailed design of, or stub any CI/CD workflow. `.github/workflows/README.md`'s existing note (initial validation workflows come after Terraform Bootstrap) still holds; "after" means later, not as part of this task.

## 28. Security Checks and Bootstrap Failure Recovery

### 28.1 State bucket hardening (required before bootstrap is considered successful)

The bootstrap apply is **not considered successful merely because `terraform apply` exits cleanly** — the following must be explicitly verified against AWS afterward, not just assumed from the Terraform config:

- **S3 Block Public Access**: all four settings enabled, verified via `aws s3api get-public-access-block`.
- **Encryption**: default bucket encryption enabled (§9), verified via `aws s3api get-bucket-encryption`.
- **Versioning**: `Enabled` (not `Suspended`), verified via `aws s3api get-bucket-versioning`.
- **Bucket ownership controls**: `BucketOwnerEnforced` (disables ACLs entirely, the recommended modern setting over ACL-based ownership), verified via `aws s3api get-bucket-ownership-controls`.
- **TLS-only access**: bucket policy denies any request where `aws:SecureTransport` is `false`, verified by reading the applied policy (`aws s3api get-bucket-policy`).
- **No public ACLs/policies**: covered by Block Public Access, but the bucket policy should also avoid any statement that could be read as granting public access, as a defense-in-depth measure.
- **Least-privilege access**: the bucket policy/IAM scoping (§10) grants access only to the deployment role and the break-glass identity (§28.3) — not to the account root, not to `*`.

### 28.2 Protection of critical bootstrap resources from accidental destruction (required item) — APPROVED

**Approved requirements, all mandatory in the implemented bootstrap config:**

- Apply a `lifecycle { prevent_destroy = true }` block on the state bucket resource in `modules/state-backend`, and consider the same on the deployment role resource in `modules/iam-deployment-role`.
- **`prevent_destroy` may only be removed through an explicit, reviewed manual change** — i.e., a deliberate edit to the `.tf` source, reviewed like any other change (per `Git_Workflow.md`'s PR process, even though this is infrastructure code, not routine documentation), never a quick local workaround to push through an unrelated apply.
- **The normal Terraform deployment role must not have permission to delete the state bucket** (or the deployment role itself) — `s3:DeleteBucket` and equivalent destructive IAM actions on these specific critical resources are absent from the deployment role's routine policy. Deletion capability is deliberately not available to the identity that does everyday work.
- **Limits of `prevent_destroy`, explicitly acknowledged:** it only blocks a Terraform-initiated destroy within a normal `plan`/`apply` cycle. It does **not** prevent: manual deletion via the AWS Console or CLI by any identity with sufficient IAM permission; a deliberate `terraform state rm` followed by manual deletion; or account-level deletion using root credentials. It is one layer, not a complete guarantee.
- **Supplement with:**
  - The IAM restriction above (no routine delete permission).
  - **Versioning** (§9, §11): protects object-level data even if something is deleted or overwritten, though it does not protect against bucket deletion itself.
  - **A documented break-glass process**: removing `prevent_destroy` or deleting a bootstrap-critical resource is a deliberate, out-of-band action — requiring the operator to consciously assume a separate, higher-privilege identity (not the routine deployment role) and follow a written procedure, rather than something that can happen accidentally through routine `apply` runs. The exact break-glass identity/procedure is still an open detail (§30) — approved in principle (it must exist, must be manual, must be reviewed), not yet fully specified.
- **Recovery and import procedures** (tying to §11, §28.3, §28.4) are already documented above and remain part of this approved design: versioned-object recovery, `terraform import` for resources present in AWS but missing from state, and full bootstrap-config-in-Git-based recreation as the last resort.

### 28.3 Partial-apply recovery process (required item)

If a bootstrap (or any) apply fails partway through:

1. **Do not improvise deletion.** First, inspect: `terraform state list` (what does Terraform believe exists?), `terraform plan` (what does Terraform think needs to change?), and targeted AWS CLI checks (`aws s3api head-bucket`, `aws iam get-role`, etc.) for each resource the config defines, to determine what actually exists in AWS versus what's recorded in state.
2. **Resource exists in AWS but missing from state** (e.g., the bucket was created by AWS before the apply was interrupted, but Terraform never recorded it): use `terraform import <resource_address> <resource_id>` to attach it to state, then immediately run `terraform plan` to confirm no unexpected diff before proceeding.
3. **Resource partially configured** (e.g., bucket created but versioning/encryption/policy not yet applied): this is the normal case Terraform is designed to handle — re-running `terraform apply` against the same, unmodified configuration should safely complete the remaining sub-resources, since each is its own resource/argument in the config. This is why the bootstrap configuration must be written to be **safe to re-run** (idempotent within Terraform's own model — no resources defined with side-effecting provisioners that aren't themselves idempotent).
4. **Cover each of**: the state bucket, the locking mechanism (§6 — for native locking, there's no separate resource, just the backend configuration itself, so "partial" mostly applies to the bucket's hardening sub-configurations), encryption, bucket hardening, and the deployment IAM role — each should be individually re-checked using the same inspect-then-import-or-reapply approach, not treated as one atomic all-or-nothing unit.
5. Only after the above inspection is complete and understood should any corrective `apply`, `import`, or (rare, deliberate) manual AWS-side fix be made.

### 28.4 Bootstrap State Backup and Disaster Recovery (tying together §5, §11, §28.1-28.3)

- The bootstrap state's own DR strategy **is** the migration-to-versioned-S3 process in §5 plus the bucket hardening in §28.1 — there is no separate, additional backup system proposed beyond what's already described. A temporary local backup exists only transiently during the migration window (§5) and is deleted once the remote copy is verified healthy; it is never a permanent parallel copy, because Terraform state can contain sensitive values and multiplying its copies multiplies risk.
- If the bucket itself were somehow lost (an extreme scenario, mitigated by `prevent_destroy` and IAM restrictions, §28.2), recovery is: recreate the bucket via the same bootstrap configuration, then `terraform import` any AWS resources that still exist (VPC, EC2, IAM roles) into fresh state, guided by the actual AWS Console/CLI inventory rather than assumption — the bootstrap configuration remaining in Git (§11) is what makes this possible at all.

## 29. Acceptance Criteria

This design — and, later, its actual implementation — is acceptance-ready when:

- All items in the traceability table at the top of this document are addressed (they are, as of this version).
- The remaining open decisions in §30 are resolved by the user.
- (For implementation, later, not now): the bootstrap apply's state-bucket hardening (§28.1) is verified with real AWS CLI output, not assumed; state locking is verified by a real concurrent-access test (e.g., two `terraform plan` attempts overlapping, confirming the second waits/fails on the lock); the deployment role is confirmed assumable from the workstation role (`aws sts assume-role` succeeds from the instance); and `prevent_destroy` is confirmed present on the state bucket resource in the applied configuration.
- This document has been reviewed and approved by the user (2026-07-24), before any `infrastructure/terraform/` files are created. Implementation still requires a separate minimal implementation plan (§31) and explicit authorization before any `terraform apply`.

## 30. Decisions Still Requiring User Approval

With Terraform/provider version strategy, state locking, state encryption, bootstrap execution location, deployment-role creation path and max session duration, the AWS Budget/import decision, VPC CIDR-reservation strategy, break-glass principles, and environment scaffolding all now **approved** (§2-4, §6, §9, §13-14, §21-24, §26, §28.2), the remaining genuinely open items are:

- **Exact** Terraform and AWS provider patch/minor versions to pin — approved as "1.10+ / a compatible current major provider series," but the literal version strings are verified immediately before implementation, not fixed now.
- Exact deployment-role permission policy content and any resource ARNs (deferred to actual bootstrap implementation, not invented here).
- Exact private application/private data subnet CIDR ranges to reserve in the VPC design (§24) — approved that space is reserved for all three tiers, but the literal ranges aren't chosen yet.
- Exact break-glass identity/procedure for bootstrap-critical-resource protection (§28.2) — approved in principle (must exist, must be manual, must be reviewed), not yet fully specified as a concrete identity/runbook.
- Whether a `shared/` directory (tags/locals) is worth the indirection versus simply repeating small tag/naming locals per root module, given the project's current small size (§15).
- Carried over from `EC2_Development_Workstation.md` §28 (still unresolved, relevant to when this bootstrap is implemented): EBS snapshot cadence/retention, exact automatic-shutdown schedule, timing for adopting the private-subnet hardening alternative, whether `t3.small` is adopted later, and whether an ADR should be written now for the earlier ARM64→x86_64 architecture reversal.

## 31. Exact Implementation Sequence for the Next Task

This design is now approved (2026-07-24). The next task is a **minimal Terraform bootstrap implementation plan and file-by-file change plan** — still documentation/planning, not `.tf` file creation, and still requiring separate, explicit authorization before any `terraform apply` against real AWS resources. Once that planning task is done and approved, implementation would proceed as:

1. Resolve the remaining §30 decisions that materially affect the bootstrap config (at minimum: exact break-glass identity/procedure, private subnet CIDR ranges, whether `shared/` is adopted).
2. Create `infrastructure/terraform/bootstrap/` with `modules/state-backend` and `modules/iam-deployment-role`, using local backend initially (§5).
3. Human identity runs `terraform init` + `plan` (review carefully) + `apply` for `bootstrap/`, using the temporary bootstrap-operator permissions (§21) — from their own laptop/CloudShell, not the (not-yet-existing) workstation.
4. Verify state-bucket hardening against real AWS output (§28.1) before proceeding.
5. Update `bootstrap/backend.tf` to point at the new S3 backend; run `terraform init -migrate-state`; verify (`state list`, `plan` shows no changes); back up and then clean up the local state per §5's process.
6. Create `infrastructure/terraform/environments/dev/` composing `modules/vpc`, `modules/security-group`, `modules/iam-workstation-role`, `modules/ec2-workstation`.
7. Human identity (assuming the deployment role, exercising the same path the workstation will use) runs `plan`/`apply` for `environments/dev` to create the VPC, security group, workstation role, and EC2 instance.
8. Update the deployment role's trust policy (a small, separate, reviewed change) to add the workstation role as a trusted principal (§2 step 5, §22).
9. From the newly created EC2 workstation, verify the assume-role path works (`aws sts assume-role` or a configured profile), then verify Session Manager and VS Code Remote-SSH per `EC2_Development_Workstation.md` §27.
10. Run the bootstrap script (`EC2_Development_Workstation.md` §21) on the instance; verify all required tools install.
11. Run the full validation command set (§27) from the workstation against both `bootstrap/` and `environments/dev/` as a final health check.
12. Update `Memory.md`, `PRE_PHASE_CHECKLIST.md`, and `16_Implementation_Notes/Bootstrap_Checklist.md` with real evidence (not assumptions) at each completed step, and write ADRs for any reversible-but-costly choices actually made along the way (native S3 locking vs. DynamoDB, directory-per-environment vs. workspaces, SSE-S3 vs. SSE-KMS) per `CLAUDE.md` §9.

---

Last updated: 2026-07-24
