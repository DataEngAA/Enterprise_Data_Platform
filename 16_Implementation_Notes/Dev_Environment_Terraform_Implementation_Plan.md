# environments/dev — Terraform Implementation Plan

Status: **REVIEWED AND APPROVED (2026-07-26); PROPOSED SOURCE CODE CREATED (2026-07-26, code-creation task — see `PROJECT_EXECUTION_JOURNAL.md` Section 27l); FIRST LOCAL VALIDATION GATE ATTEMPTED AND BLOCKED IN THE COWORK SANDBOX (2026-07-26, see Section 27m); FIRST REAL LOCAL VALIDATION GATE RUN ON THE USER'S WINDOWS MACHINE (2026-07-26, see §42a) — nine TFLint findings, fixed in source; SECOND REAL LOCAL VALIDATION GATE RUN (2026-07-26, see §42b) — `terraform fmt -check -recursive` passed, `terraform validate` passed in all five directories, `tflint --recursive` completed with ZERO findings (confirming §42a's nine fixes), and Trivy ran for the first time (5 findings, all reviewed and dispositioned — §42b); AN IAM POLICY TAG-ENFORCEMENT BYPASS WAS FOUND AND CORRECTED (2026-07-26, §11) IN THE SAME TASK, AFTER THIS VALIDATION PASS COMPLETED.** Every file this plan's §7 describes exists on disk: `modules/vpc/`, `modules/iam-workstation-role/`, `modules/ec2-workstation/`, `environments/dev/` (including `backend.tf`, called for by this plan's own §2/§7 directory tree), and `infrastructure/terraform/scripts/bootstrap_workstation.sh` — plus Bootstrap Update 1's code (the deployment role's dev-scoped IAM policy, §11) added to `infrastructure/terraform/bootstrap/main.tf`.

**BOOTSTRAP UPDATE 1 IS NOW FULLY COMPLETE AND STABLE (verified 2026-07-26).** After the validation/review history recorded below (§11's multi-pass IAM correction, the RunInstances condition-scoping fix, two real partial `environments/dev` apply failures that each surfaced a real deployment-role permission gap and were corrected in source, two real IAM managed-policy size-quota failures that led to splitting the deployment role's dev-scoped permissions across THREE managed policies — `enterprise-data-platform-dev-deployment-scope-policy`, `enterprise-data-platform-dev-networking-scope-policy`, and `enterprise-data-platform-dev-workstation-iam-scope-policy` — and a forced-replacement defect from an immutable `description` argument, fixed via `lifecycle.ignore_changes = [description]` on all three policies), **Bootstrap Update 1 was applied for real, and a fresh `terraform plan` reported `No changes. Your infrastructure matches the configuration.`** All three managed policies are confirmed attached to the shared deployment role in real AWS, matching source exactly. **This is now the stable project baseline — Bootstrap Update 1 is complete.** Full incident-by-incident detail: `PROJECT_EXECUTION_JOURNAL.md` Sections 27r–27x; `00_Project_Management/Memory.md`; `16_Implementation_Notes/Bootstrap_Checklist.md`; `16_Implementation_Notes/Bootstrap_Update_1_Execution_Checklist.md`.

**§11 below (the matrix table and JSON) still documents the ORIGINAL, single-combined-policy design as it was approved and first coded — it has NOT been rewritten to reflect the final three-policy split, superseded pointer added at the top of §11 instead of duplicating the full matrix/JSON three times over.** The authoritative, current source is `infrastructure/terraform/bootstrap/main.tf` itself; see its own extensive comment history for the complete split rationale, including `DevRunInstancesAmi`'s restored diagnostic conditions and the temporary `t3.small` widening described below.

**AUTHENTICATION ROOT CAUSE RESOLVED; EXISTING `ENVIRONMENTS/DEV` INFRASTRUCTURE VALIDATED. BOOTSTRAP IAM-CONDITION DEPLOYMENT AND FUTURE-LAUNCH AUTHORIZATION VALIDATION REMAIN PENDING (2026-07-26). The `DevRunInstancesAmi` investigation is NOT fully closed.** Following Bootstrap Update 1's completion, a real `DevRunInstancesAmi` authorization investigation (real `matchedStatements: []` denials against the AMI resource; two false claims about missing permissions raised and corrected via direct source re-verification rather than complied with; a real MFA/STS session-credential root cause eventually identified) correctly identified why the earlier denials happened, alongside a real, account-specific Free Tier launch-time restriction on `t3.medium`/`t3.large`/`t3.xlarge` — worked around with a narrowly scoped, explicitly temporary `t3.small` allow-list widening in `environments/dev/variables.tf`, `modules/ec2-workstation/variables.tf`, and `bootstrap/main.tf`'s `DevRunInstancesSupportingResources` condition (approved default/design target remains `t3.medium`; exact revert condition recorded in all three files: revert once this account's Free Tier launch restriction is resolved, e.g. via an AWS Support request, or once development moves to an unrestricted account). `DevRunInstancesAmi`'s three diagnostic-stripped conditions were then restored **in source only** — `aws:RequestedRegion` and `ec2:Owner = amazon` exactly as originally designed, `ec2:InstanceType` restored with `t3.small` deliberately added for consistency with the workaround above.

**CORRECTION (2026-07-26, same day, flagged by the user before preparing a GitHub-facing copy of this documentation):** a real `environments/dev` `terraform plan`/`terraform apply` reported `No changes. Your infrastructure matches the configuration.` / `Apply complete! Resources: 0 added, 0 changed, 0 destroyed.`, and this was initially, incorrectly, described here as validating the `DevRunInstancesAmi` restoration. It does not. `environments/dev` and `bootstrap/` are separate Terraform root modules with separate state files — a plan/apply run from `environments/dev` reconciles only `environments/dev`'s own resources (VPC, subnet, Internet Gateway, route table, security group, workstation IAM role/instance-profile/attachment, EC2 workstation) against `dev/terraform.tfstate`; it never reads or applies anything in `bootstrap/main.tf`, and cannot confirm whether the deployment role's real, deployed IAM policy contains the restored conditions. The EC2 workstation visible in that state was originally launched during the diagnostic investigation, while `DevRunInstancesAmi` was still stripped bare — its existing, already-successful launch is not evidence about the restored, currently-undeployed conditions either.

**VERIFIED**: the MFA-backed `login.ps1` workflow works; stale session credentials are cleared; Terraform authenticates through the IAM user's MFA session; Terraform's provider successfully performs its own single `AssumeRole` hop to the deployment role; `environments/dev`'s existing infrastructure matches `environments/dev`'s Terraform state and configuration; the current dev apply completed with 0 added, 0 changed, 0 destroyed. A separate, later self-assume-role failure (ambient shell credentials already an assumed deployment-role session, causing `providers.tf`'s own `assume_role` block to attempt a self-assume, denied because the deployment role's trust policy trusts only the IAM user, never an assumed-role session) was diagnosed against the real trust-policy source and closed via this same `login.ps1` workflow — no code change was required. This part is genuinely resolved and verified.

**NOT YET VERIFIED**: whether the restored bootstrap IAM policy conditions have actually been applied to AWS; whether the deployed deployment-role policy currently contains all three restored conditions; whether a future, genuinely new, permitted `RunInstances` request succeeds under those conditions; whether `t3.small` can be removed once the instance-type/Free-Tier decision is finalized.

**Corrected status: authentication root cause resolved. Existing dev infrastructure validated. Bootstrap IAM-condition deployment and future-launch authorization validation remain pending.**

**Required next validation steps, before Bootstrap Update 2**: (1) authenticate via `login.ps1`; (2) run `terraform plan` in the **`bootstrap/`** stack (not `environments/dev`); (3) review and apply any proposed IAM policy changes; (4) confirm via `aws iam get-policy-version` against the real, deployed default version that it contains `aws:RequestedRegion`, `ec2:Owner = amazon`, and the approved `ec2:InstanceType` values; (5) perform a safe authorization validation via `aws iam simulate-principal-policy` or an explicitly approved controlled resource test — not an ordinary `environments/dev` plan/apply; (6) do not replace or destroy the existing workstation to test this without explicit approval. **A no-op `environments/dev` plan/apply must not be described as having validated the restored bootstrap IAM conditions.** Full incident-by-incident detail: `PROJECT_EXECUTION_JOURNAL.md` Sections 27aa-27af.

**Bootstrap Update 2 (the trust-policy addition) was, at the time of the above, the next implementation stage after the bootstrap IAM validation sequence completed. CORRECTION (2026-08-04): Bootstrap Update 2 is now completed and validated. The EC2 workstation role can successfully assume the shared deployment role.** On the user's own machine, `terraform fmt`, `terraform validate`, and `terraform plan` all ran against `bootstrap/`; the saved plan was reviewed and confirmed the human principal's MFA condition was preserved and the workstation-role trust was added as a fully separate, no-MFA statement; `terraform apply` completed with `Apply complete! Resources: 0 added, 1 changed, 0 destroyed.` On the real EC2 workstation, via Session Manager, `aws sts get-caller-identity` confirmed the workstation instance role, and that role successfully assumed the shared deployment role. **The only remaining IAM-related validation item in this project: future EC2 launch authorization validation for the deployed `DevRunInstancesAmi` conditions remains pending** (the six required steps above are unchanged and still open). Full record: `PROJECT_EXECUTION_JOURNAL.md` Section 27ai.

A first attempt to run `terraform fmt`/`init -backend=false`/`validate`/`tflint`/a Trivy config scan against this code was **blocked**: the working environment had no `terraform`/`tflint`/`trivy` binary, no root access to install one, and no network path to the hosts that would provide them. In their place, three clearly-labeled, non-equivalent supplementary checks were used: a Python `hcl2` grammar parse (confirmed all `.tf` files are syntactically valid HCL2 — not a substitute for `terraform validate`'s schema/reference checking), `bash -n` (confirmed the bootstrap script is syntactically valid Bash — did not execute it), and a heuristic equals-sign alignment scanner mimicking `terraform fmt`'s own behavior. A full manual review against the task's complete IAM/backend/provider/source-code checklist surfaced two genuine findings, both since resolved: (1) `bootstrap_workstation.sh`'s curl-pipe-shell install line — status unchanged by this update, still tracked separately; (2) the `DevNetworkingCreateManage`/`DevNetworkingCreateManageTaggedOnCreate` tag-enforcement bypass — corrected in source and confirmed via the real toolchain (§42b). **Real `fmt`/`validate`/`tflint`/Trivy have since been run for real on the user's own Windows machine multiple times across this plan's revision history (see below); Bootstrap Update 1's final, three-policy source has been applied for real with a confirmed no-changes plan, per the "BOOTSTRAP UPDATE 1 IS NOW FULLY COMPLETE" note above.** No AWS CLI command was run as part of producing or reviewing this documentation update itself. No real `backend.hcl` or `terraform.tfvars` exists for `environments/dev`.

## Revision History

- **2026-07-25 (original):** First draft, covering all 57 required plan elements, module justification, the A–I stage-separation table, and three flagged documentation conflicts.
- **2026-07-26 (this revision):** Six corrections applied following explicit review feedback:
  1. **Backend `assume_role` syntax corrected** — the plan previously described a non-existent standalone `role_arn` field in `backend.hcl`. Corrected to the real Terraform S3 backend syntax: a nested `assume_role = { role_arn = ..., session_name = ... }` block, kept separate from provider configuration (§9, §41, §7's `backend.hcl.example` row).
  2. **IAM sequencing restructured into three explicit ordered stages** (Bootstrap update 1 → `environments/dev` apply → Bootstrap update 2), with the chicken-and-egg dependency between deployment-role permissions, deployment-role trust, and workstation-role existence spelled out directly — see the new section immediately before §11.
  3. **AMI lookup boundary moved** from `modules/ec2-workstation` to `environments/dev` (the root module) — `ec2-workstation` now receives `ami_id` as a required input, with the rationale that AMI selection is region/environment-specific and should be visible in the root's own `plan` output (§3.2, §7, §22, §36).
  4. **Module boundaries explicitly confirmed/approved** (not merely proposed): route tables in `modules/vpc`; the workstation instance profile in `modules/iam-workstation-role`; the workstation security group in `modules/ec2-workstation`; the bootstrap script relocated to `infrastructure/terraform/scripts/bootstrap_workstation.sh` (previously proposed as a top-level `scripts/` directory outside `infrastructure/terraform/` — moved inside it per explicit instruction); no `shared/` directory yet (§2, §3.2, §7, §29).
  5. **Open decisions split into blocking vs. non-blocking** (§56) — Availability Zone strategy, the detailed-monitoring decision, and the allowed EC2 instance-type set are now resolved and no longer block code creation; the exact deployment-role permissions policy JSON and the VPC/public-subnet CIDR values remain explicit blockers; the bootstrap script's exact content blocks full user-data wiring but not the rest of Stage 2's apply.
  6. **Allowed EC2 instance types finalized**: `t3.medium` (default), `t3.large`, `t3.xlarge` — confirming, not changing, what §24 already proposed.
- **2026-07-26 (rationale pass, later the same day):** Two further items resolved, and a new **Decision Rationale** section added, covering the "why" behind twenty finalized design decisions:
  1. **VPC and subnet CIDR values FINALIZED** (§21) — previously a blocking, unapproved proposal; now resolved with specific values (`10.20.0.0/16` VPC, `10.20.1.0/24` public subnet, `10.20.11.0/24` and `10.20.21.0/24` reserved-not-deployed private tiers), moved out of the blocking list (§56.1 → §56.2).
  2. **IMDSv2 configuration FINALIZED** (§27, including the metadata hop limit) — previously a new, unreviewed proposal; now confirmed as settled, moved out of the pending-review list (§57).
  3. **Decision Rationale section added**, connecting each of twenty already-decided design choices (CIDR scheme, AZ selection, public networking, no-NAT, security group, Session Manager, SSH-over-SSM, IMDSv2, hop limit, monitoring, instance sizing, root volume, `delete_on_termination`, module boundaries, deployment-role sequencing, bootstrap-script restrictions, and the human-administered bootstrap root) explicitly to cost, security, portability, maintainability, or future-growth reasoning — documentation only, no implementation values altered beyond the two items above.
  4. **Only one blocking decision remains** after this pass: the exact deployment-role permissions policy JSON (§56.1, §11, IAM Sequencing Stage A). The bootstrap script's exact content remains a non-hard-blocking item per §56.1's existing distinction.
- **2026-07-26 (finalization pass, later the same day):** The plan's last blocking decision is resolved and the plan is approved:
  1. **§11 rewritten in full** with the complete action/resource/condition matrix, the complete proposed IAM policy JSON (placeholders only, no real account IDs/ARNs/bucket names), an explanation of every unavoidable `Resource = "*"` entry, a human-only-permissions list, a Bootstrap-Update-2-scope clarification (trust-only, no new permissions), and a residual-risks/future-tightening subsection.
  2. **Unrestricted outbound security-group egress adopted** (§16, revised from the prior scoped-HTTPS-443-only design), with an explicit trade-off write-up.
  3. **AZ-selection hardening made explicit** (§20) — no literal AZ name anywhere in the configuration, AZ names documented as account-specific, selected AZ exposed as an output.
  4. **`instance_metadata_tags = "disabled"` added to the IMDSv2 block** (§27) alongside the previously finalized `http_tokens`/hop-limit settings.
  5. **§29 rewritten in full** into an explicit permitted-scope / ten-item-prohibition-list / idempotency / logging / failure-handling / versioning specification for the bootstrap script (old §30 reduced to a cross-reference).
  6. **§56.1 emptied** — both remaining blocking items resolved; §56.2 updated accordingly.
  7. **All three flagged documentation conflicts resolved** with full per-conflict fields, and the affected source documents (`Terraform_Bootstrap_Design.md`, `Networking.md`, `IAM_and_Access.md`) edited in place.
  8. **§57 exit criteria confirmed met; plan status changed to REVIEWED AND APPROVED.**
- **2026-07-26 (partial-apply-failure correction, later the same day):** The first real `environments/dev terraform apply` was attempted and partially failed:
  1. **Real AWS error:** the shared deployment role was denied `ec2:DescribeVpcAttribute` while Terraform was creating the VPC and waiting for the `enable_dns_hostnames` attribute update to complete.
  2. **Partial resources created in real AWS before the stop:** the workstation IAM role, its `AmazonSSMManagedInstanceCore` attachment, its inline `AssumeRole` policy, its instance profile, and a VPC (creation began, a real VPC ID was returned) — Terraform then stopped before creating the remaining resources.
  3. **§11.1 row 8 and §11.2's JSON corrected** — `ec2:DescribeVpcAttribute` added to `DevReadOnlyDescribe`'s action list; no other statement changed. **§11.6 gained a resolved-defect bullet** recording this as a real deployment-evidence finding, not a design-review finding.
  4. **The original `dev_initial.tfplan` must not be reused** — it was generated against the deployment role's prior (missing-action) permission set and does not reflect current AWS reality after the partial apply.
  5. **No manual cleanup, state manipulation, or import was performed or is authorized by this correction.** State and AWS resources are to be reconciled through a fresh `terraform plan` after the bootstrap policy correction is applied — see `PROJECT_EXECUTION_JOURNAL.md` and `Bootstrap_Update_1_Execution_Checklist.md` for the required recovery sequence.
  6. **This correction is source and documentation only** — no Terraform command, no AWS CLI command, no plan/apply, no Bootstrap Update 2, no trust-policy change.
- **2026-07-26 (second partial-apply-failure correction, later the same day):** A second real `environments/dev terraform apply` was attempted (after the first correction above was applied) and again partially failed:
  1. **Created:** a replacement VPC and an Internet Gateway. **Already present from the first partial apply:** the workstation IAM role, its `AmazonSSMManagedInstanceCore` attachment, its inline `AssumeRole` policy, and its instance profile. **Failed with `AccessDenied`:** `ec2:CreateSubnet`, `ec2:CreateRouteTable`, `ec2:CreateSecurityGroup`, each against the parent VPC ARN.
  2. **Root cause:** `DevNetworkingCreateTaggedOnly` applied `aws:RequestTag` conditions to actions that authorize against two different resources per call (the new resource, and the existing parent VPC) — `aws:RequestTag` has no value for the existing-VPC side, causing an implicit deny there.
  3. **§11.1 rows 5/7 replaced** by rows 5c-5j (8 networking statements) and 7a-7b (2 tagging statements); **§11.2's JSON updated to match; §11.6 gained a resolved-defect bullet plus a new, unresolved policy-size risk bullet.**
  4. **`dev_recovery.tfplan` must not be reused** — generated against the deployment role's prior, still-incomplete permission set.
  5. **No manual cleanup, state manipulation, or import was performed or is authorized.** State and AWS resources are to be reconciled through a fresh `terraform plan` after this bootstrap policy correction is applied, and any tainted or partially created resource reviewed before any further apply — see `PROJECT_EXECUTION_JOURNAL.md` and `Bootstrap_Update_1_Execution_Checklist.md`.
  6. **This correction is source and documentation only** — no Terraform command, no AWS CLI command, no plan/apply, no Bootstrap Update 2, no trust-policy change. A real 2026-07-26 fetch of AWS's EC2 Service Authorization Reference was used to confirm the new statements' resource-type requirements (recorded above and in `bootstrap/main.tf`'s own comments) — the first time this project's own fetch tool successfully reached and used live AWS reference data within this sandbox, though it remained inconclusive for one specific sub-question (`ec2:CreateAction`'s support on `CreateTags` for these 5 actions).
- **2026-07-26 (code-creation task, later the same day):** This plan's proposed source code was created in full — see `PROJECT_EXECUTION_JOURNAL.md` Section 27l for complete detail. `modules/vpc/`, `modules/iam-workstation-role/`, `modules/ec2-workstation/`, `environments/dev/`, and `infrastructure/terraform/scripts/bootstrap_workstation.sh` now exist, plus Bootstrap Update 1's code in `bootstrap/main.tf`. Code evidence (Tier 2) only — no Terraform command has been run against any of it. This is not a further revision of this plan's design decisions; it is the plan's own §7 being carried out as written.
- **2026-07-26 (first local validation gate, later the same day):** A first attempt to run `terraform fmt`/`init -backend=false`/`validate`/`tflint`/Trivy against the code above was blocked — see `PROJECT_EXECUTION_JOURNAL.md` Section 27m for complete detail. No usable Terraform/TFLint/Trivy toolchain existed in the working environment and none could be obtained (no root access; the relevant download hosts are network-blocked). Supplementary, clearly-labeled checks (an `hcl2` grammar parse, `bash -n`, a heuristic `terraform fmt`-style alignment scanner) were used instead, correcting 44 lines of real formatting misalignment plus 5 pre-existing typos across 7 files. A manual review against the task's full checklist surfaced two genuine findings, left deliberately unfixed and reported: the bootstrap script's curl-pipe-shell install line, and an IAM statement (`DevNetworkingCreateManage`) that makes a sibling tag-on-create condition (`DevNetworkingCreateManageTaggedOnCreate`) unenforceable — the latter matching this plan's own already-disclosed §11.6 residual risk, not a new one. This is code evidence (Tier 2) plus a separately-labeled manual-review category, not Terraform-validation (Tier 4) evidence. This is not a further revision of this plan's design decisions; no design decision changed. Next task: obtain a real toolchain and re-run this gate for real.
- **2026-07-26 (first REAL local validation gate, later the same day):** The user ran the real toolchain — `terraform fmt -check -recursive`, `terraform init -backend=false`, `terraform validate`, and `tflint` — on their own Windows machine, superseding the sandbox-blocked attempt above with actual Tier 4 validation evidence. `fmt` passed; `validate` passed in all five directories; `tflint` reported exactly nine warnings. Nine source corrections were made in response (§42a): removed two unused reserved-CIDR variables (`private_application_subnet_cidr_reserved`, `private_data_subnet_cidr_reserved`) from `environments/dev/variables.tf` — the CIDR values remain documented, prose-only design reservations (§21); removed the unused `project_name` variable from `modules/iam-workstation-role` (never referenced by that module's resources) and the corresponding argument from `environments/dev/main.tf`'s `module "workstation_role"` call, without inventing a fake usage to silence the linter; added matching `required_version`/AWS-provider version constraints to all three child modules' `versions.tf` files. A documentation inaccuracy in §21 (misattributing the reserved-CIDR variables to `modules/vpc/variables.tf`, where they never lived) was also corrected while editing that section. Child-module `.terraform.lock.hcl` handling was formalized (§40) — those three files are standalone-`init` validation artifacts, not committed, and `.gitignore` now enforces this. **These nine fixes are source corrections only and have NOT yet been re-validated** — `fmt`/`validate`/`tflint` all need to be re-run for real before this is Tier 4 evidence again; Trivy has not yet been run at all. No `terraform plan`/`apply`, no AWS CLI command, and no AWS change occurred.
- **2026-07-26 (second REAL local validation gate + IAM bypass correction, later the same day):** The user re-ran the real toolchain (Terraform v1.15.8, AWS provider v6.56.0, TFLint v0.64.0, Trivy v0.72.0) on the same Windows machine. `fmt` passed; `validate` passed in all five directories; `tflint --recursive` completed with **zero findings**, confirming the prior entry's nine fixes are correct. Trivy ran for the first time against this code: five findings (`AWS-0089` LOW, `AWS-0132` HIGH, `AWS-0342` MEDIUM against `bootstrap/`; `AWS-0104` CRITICAL, `AWS-0178` MEDIUM against `environments/dev`/modules, each of the latter two reported twice via duplicate scan paths and consolidated to one disposition each) — all five reviewed and dispositioned (§42b): the two bootstrap findings accepted unchanged from their original bootstrap-phase disposition; `AWS-0342` (`iam:PassRole`) accepted after re-confirming its `Resource`/`iam:PassedToService` scoping is exactly as narrow as required; `AWS-0104` (unrestricted egress) accepted as a temporary, explicitly-risk-accepted dev-phase exception with documented future-tightening options; `AWS-0178` (Flow Logs disabled) accepted as a deferred control for a single disposable dev workstation. No `.trivyignore` or inline suppression was added. Trivy's scans were **not fully input-aware** (no `--tf-vars` supplied) — this is documented, not claimed otherwise; a future scan should use the real local, gitignored `tfvars` files without exposing their values. **Separately, in the same task, a manual IAM policy review found and corrected a real tag-enforcement bypass** in `bootstrap/main.tf`'s Bootstrap Update 1 policy: `DevNetworkingCreateManage` granted 5 create actions unconditionally, alongside `DevNetworkingCreateManageTaggedOnCreate`'s tagged grant of the same 5 actions — since IAM Allow statements are additive, the untagged grant made the tag condition unenforceable. Corrected by splitting into `DevNetworkingCreateTaggedOnly` (the 5 create actions, tag-on-create required, no untagged alternative exists) and `DevNetworkingManageTaggedResourceOnly` (the remaining 15 modify/delete/manage actions, conditioned on the target resource already carrying the required tags) — condition-key support verified against AWS's own EC2 Service Authorization Reference for 11 of the 15 "manage" actions directly, the remaining 7 by documented, flagged pattern inference. `DevReadOnlyDescribe` gained an `aws:RequestedRegion` condition (a universal AWS global condition key, added without adding any unsupported resource-tag condition to genuinely condition-incapable Describe* actions). `DevSecurityGroupEgressRulesOnly`, `DevInstanceLifecycleTaggedOnly`, and `DevInstanceMetadataOptionsTaggedOnly` were also updated/standardized to the `aws:ResourceTag`/`aws:RequestTag` global condition-key form. **This IAM correction was made after the `tflint --recursive`/Trivy results above were obtained and has NOT yet been re-validated by a fourth toolchain run.** No broader permission was introduced; no bootstrap-state access was introduced; no deployment-role self-management was introduced; §11.1/§11.2/§11.3/§11.6 updated to match the corrected code exactly. No `terraform plan`/`apply`, no AWS CLI command, no backend activation, and no AWS change occurred.
- **2026-07-26 (third review pass, later the same day):** Two focused reviews, no Terraform command run, no source logic changed. First, the user reported reviewing the 7 previously pattern-inferred `DevNetworkingManageTaggedResourceOnly` actions (`DeleteVpc`, `ModifyVpcAttribute`, `ModifySubnetAttribute`, `DetachInternetGateway`, `ReplaceRoute`, `ReplaceRouteTableAssociation`, `DeleteSecurityGroup`) directly against the current official AWS EC2 Service Authorization Reference and reported all 7 confirmed to support `aws:ResourceTag`/resource-level scoping — recorded here as **user-reported reference evidence**, since this project's own sandbox fetch tool still could not independently reach these 7 entries when re-attempted (§11.6 updated; `bootstrap/main.tf` comments updated to match, with the attribution distinction preserved rather than claimed as an independent re-fetch). Second, `bootstrap/main.tf` was reviewed to confirm `DevNetworkingManageTaggedResourceOnly`'s `Resource = "*"` element represents every AWS resource ARN type its 15 actions require (`vpc*`, `subnet*`, `internet-gateway*`, `route-table*`, `security-group*`, including the multi-resource-type actions `AttachInternetGateway`/`DetachInternetGateway` and `AssociateRouteTable`/`DisassociateRouteTable`/`ReplaceRouteTableAssociation`) — concluded that a bare `"*"` wildcard trivially covers every required type, so no ARN type was missing and no source change was made to that element. No condition already correct was altered.
- **2026-07-26 (deployed-v1-policy review, source correction):** The deployed-but-not-yet-applied v1 policy in `bootstrap/main.tf` was reviewed and a real condition-scoping defect was found in the single `DevRunInstances` statement: `ec2:Owner = amazon` was applied across a `Resource` list mixing the AMI resource type with five non-AMI resource types (`instance/*`, `volume/*`, `network-interface/*`, `subnet/*`, `security-group/*`) — broader than that condition key is meant to apply to, since `ec2:Owner` is only meaningful for the AMI being launched from. Corrected by splitting into `DevRunInstancesAmi` (AMI-only `Resource`, carries `ec2:Owner` plus region/instance-type conditions) and `DevRunInstancesSupportingResources` (the five non-AMI types, region/instance-type conditions only, no `ec2:Owner`) — §11.1 rows 9a-9c, §11.2 JSON, §11.6 updated to match. The pre-existing, separate `DevRunInstancesTagOnCreate` statement (tag-on-create for the launched instance) is unchanged and preserved. Policy statement count is now 18, not 17. Separately, `aws_iam_role.deployment`'s stale `NO PERMISSIONS ARE ATTACHED YET` description comment was corrected to accurately describe the dev-scoped managed policy Bootstrap Update 1 attaches, the unchanged human-MFA-only trust, and the still-future Bootstrap Update 2 workstation-role trust addition — no change to the trust policy itself. **This is a source and documentation correction only — not yet planned or applied; no Terraform/TFLint/Trivy/AWS CLI command was run; no AWS change occurred; the dev backend remains uninitialized and no `environments/dev` plan has run.**
- **2026-07-26 (first IAM managed-policy size-quota failure, real AWS rejection):** A real `terraform apply` against `bootstrap/` failed with `CreatePolicyVersion: LimitExceeded` — the single 26-statement `deployment_dev_permissions` policy's rendered JSON exceeded AWS's 6,144-character managed-policy-version quota. Zero AWS-side change occurred (the API rejected the call before creating a version). Fixed by splitting the policy in two: `deployment_dev_permissions` (14 non-networking statements) and a new `deployment_dev_networking_permissions` (12 networking statements), each attached separately to the shared deployment role, each with its own `lifecycle.precondition` computing real rendered-JSON length against `local.iam_managed_policy_size_quota = 6144`. Full detail: `PROJECT_EXECUTION_JOURNAL.md` §27u; `17_Interview_Guide/Phase_0.md` interview section covering this incident.
- **2026-07-26 (second IAM managed-policy size-quota failure, real Terraform precondition catch):** The `lifecycle.precondition` added above caught a SECOND overage before ever reaching AWS: `local.deployment_dev_permissions_json_length = 6212 > 6144`. Fixed by a second split: `deployment_dev_permissions` kept to 10 statements (state/lock, Describe, RunInstances, instance/volume lifecycle, metadata options, tag-on-create); a new `deployment_dev_workstation_iam_permissions` (`enterprise-data-platform-dev-workstation-iam-scope-policy`) created for the 4 workstation-IAM statements (`DevWorkstationRoleManage`, `DevWorkstationRolePolicyAttachApprovedOnly`, `DevWorkstationInstanceProfileManage`, `DevPassWorkstationRoleToEC2Only`), each with its own precondition and output. Final architecture: three managed policies (10/12/4 statements), matching the current, real, deployed state. Full detail: `PROJECT_EXECUTION_JOURNAL.md` §27v.
- **2026-07-26 (forced-replacement defect, real human-reviewed plan):** A real, human-reviewed `terraform plan` against the three-policy split above showed an unexpected `6 to add, 1 to change, 2 to destroy` — root cause: `description` is `Forces new resource` on `aws_iam_policy`, and the already-live `deployment_dev_permissions` policy's description text had been rewritten by the two size-quota corrections, queuing an unintended forced replacement (plus a cascading attachment replacement). Fixed by resetting the description to a stable string and adding `lifecycle.ignore_changes = ["description"]` to `deployment_dev_permissions`. Full detail: `PROJECT_EXECUTION_JOURNAL.md` §27w.
- **2026-07-26 (real partial-destructive apply + description-length validation failure, then full resolution):** A real `terraform apply` ran and progressed further than any prior attempt: the existing `deployment_dev_permissions` policy was detached and deleted, the new networking and workstation-IAM policies were created and attached, but recreation of `deployment_dev_permissions` failed with a real AWS `ValidationError`: policy `description` exceeded IAM's 1,000-character hard limit. AWS briefly contained only two of the three intended policies. Fixed in two steps: (1) all three policies' `description` arguments shortened to concise, comfortably-under-1000-character strings ("Core deployment permissions...", "Networking permissions...", "Workstation IAM permissions..." for the Enterprise Data Platform); (2) `lifecycle.ignore_changes = [description]` added to the remaining two policies (`deployment_dev_networking_permissions`, `deployment_dev_workstation_iam_permissions`), matching the structure already applied to `deployment_dev_permissions`, permanently eliminating this entire class of forced-replacement/validation failure across all three resources. **Following these fixes, a real `terraform apply` completed successfully, and a fresh `terraform plan` reported `No changes. Your infrastructure matches the configuration.`** Bootstrap Update 1 is now the stable, fully-applied project baseline. Full detail: `PROJECT_EXECUTION_JOURNAL.md` §27x (and following).
- **2026-08-04 (final `RunInstances --dry-run` success; Pre-Phase — Engineering Environment Setup completed and validated on real AWS):** A fresh `aws ec2 run-instances --dry-run` under the confirmed shared deployment-role session against the approved launch path returned `DryRunOperation: Request would have succeeded, but DryRun flag is set.` — no EC2 resource created, closing the last open IAM-related validation item. A request to record this as "Phase 0 complete" was checked against `PROJECT_BLUEPRINT.md` (authoritative for phase boundaries) and found to conflict with §11's Phase 0 completion criteria (CloudTrail, KMS, Secrets Manager, Budgets-in-Terraform, GitHub Actions CI/CD, VPC endpoints/Flow Logs, broader IAM, multi-environment, recovery/recreation testing — none built or evidenced); surfaced to the user, who confirmed the correct status is **"Pre-Phase Engineering Environment Setup completed and validated on real AWS"**, not Phase 0 completion. Documentation only. Full record: `PROJECT_EXECUTION_JOURNAL.md` Section 27ak.
- **2026-08-04 (`DevRunInstancesAmi` real authorization defect found and corrected — `ec2:InstanceType` removed from the AMI statement):** A real `ec2:RunInstances --dry-run` request under the confirmed deployment-role session was denied with `UnauthorizedOperation` on the AMI resource (`--dry-run` created no resource). Root cause: `DevRunInstancesAmi`'s `ec2:InstanceType` condition (`StringEquals`) is an instance-resource condition key, not populated during AMI-side authorization, so the statement failed to match entirely. **This corrects two prior claims in this project's own record** — that the earlier diagnostic-condition restoration had closed the `DevRunInstancesAmi` investigation, and that `ec2:InstanceType` on the AMI statement was harmless. Fixed in `bootstrap/main.tf`: that condition removed from `DevRunInstancesAmi` only; `ec2:Owner`/`aws:RequestedRegion` unchanged; `ec2:InstanceType` remains fully enforced on `DevRunInstancesSupportingResources`. §11.6 updated with the new resolved-defect entry. Source correction only, structurally verified — not yet planned or applied. Full record: `PROJECT_EXECUTION_JOURNAL.md` Section 27aj.
- **2026-08-04 (Bootstrap Update 2 completed and validated — status block corrected):** Real `fmt`/`validate`/`plan` ran against `bootstrap/` on the user's machine; the plan was reviewed and confirmed the human principal's MFA condition was preserved and the workstation-role trust was added as a separate, no-MFA statement; `terraform apply` completed with `Apply complete! Resources: 0 added, 1 changed, 0 destroyed.` On the real EC2 workstation, `aws sts get-caller-identity` confirmed the workstation role, and it successfully assumed the shared deployment role. The status block near the top of this document (previously stating fmt/validate/plan/apply for Bootstrap Update 2 had not been run) was corrected in place. **The only remaining IAM-related validation item in this project is future EC2 launch authorization validation for the deployed `DevRunInstancesAmi` conditions.** Documentation only — no script or infrastructure source changed. Full record: `PROJECT_EXECUTION_JOURNAL.md` Section 27ai.
- **2026-08-04 (`bootstrap_workstation.sh` v1.1.1 run for real against the EC2 workstation — success; §29.7 acceptance-criteria gap closed):** The user ran the script against the real EC2 development workstation (Amazon Linux 2023) and reported it completed successfully: AWS CLI available (preinstalled), Git installed, GitHub CLI installed (install-only), Terraform v1.15.8 installed via the checksum-verified official archive, `uv` installed for `ssm-user` (not root), `/home/ssm-user/projects` created, and the version marker set to `1.1.1`. §29.7 updated with a note recording this as the first real-instance execution evidence, closing the acceptance-criteria gap it had previously flagged against `EC2_Development_Workstation.md` §56.1. Documentation only — no script or infrastructure change. Full record: `PROJECT_EXECUTION_JOURNAL.md` Section 27ah.
- **2026-08-04 (`bootstrap_workstation.sh` revised to v1.1.1, real-instance `curl`/`curl-minimal` conflict fix):** A real run against an actual AL2023 instance failed: the core-tooling step's `dnf install -y git jq unzip curl tar less` tried to install the full `curl` package, which conflicts at the RPM level with `curl-minimal` (preinstalled by AL2023 by default) — `dnf` reported the conflict and the script exited under `set -e`. Fixed by removing `curl` from that install command entirely (now `dnf install -y git jq unzip tar less`) and adding a separate, idempotent availability check immediately after it: if no `curl` command is present, install `curl-minimal` explicitly; otherwise log that it's already available. This runs before the Terraform-download and `uv`-install steps, both of which need `curl`. No other v1.1.0 behavior changed — `WORKSTATION_USER` resolution, the root-execution guard, the pinned/checksum-verified Terraform install, `uv` installed as the workstation user, project-directory ownership, and all existing security restrictions (§29.2) are unchanged. Script version bumped 1.1.0 → 1.1.1. Verified via `bash -n` (clean syntax) only; not executed against any instance as part of this fix. Full script detail: `infrastructure/terraform/scripts/bootstrap_workstation.sh` itself.
- **2026-08-04 (`bootstrap_workstation.sh` revised to v1.1.0; §29 updated to match, documentation only):** The bootstrap script (authored after the entry below, and since revised) was found to have three real problems on review: hardcoded `ec2-user` paths/ownership that don't match this account's actual `ssm-user` SSM Session Manager environment; `uv` being installed in the wrong (root) user context instead of for the intended developer user; and no Terraform CLI installation, despite Terraform being a core workstation prerequisite. Fixed in the script (v1.0.0 → v1.1.0): a `WORKSTATION_USER` environment variable (default `ssm-user`) resolved and validated against the system user database, with home directory/primary group resolved the same way rather than hardcoded; a root-execution guard; `uv` now installed as the resolved non-root workstation user via `sudo -u ... env HOME=...`; a pinned (1.15.8), checksum-verified (against HashiCorp's published `SHA256SUMS`), install-only Terraform CLI installation to `/usr/local/bin/terraform`, idempotent on rerun. All pre-existing security constraints (§29.2) were preserved unchanged, including that the script never runs any Terraform command itself. §29 above (now titled to reflect both the original 2026-07-26 finalization and this update) and §29.1/new §29.1a were updated to document this v1.1.0 scope; no other section of this plan was changed. Verified via `bash -n` (clean syntax) only — the script was not executed against any instance. Full script detail: `infrastructure/terraform/scripts/bootstrap_workstation.sh` itself.
- **2026-07-26 (`DevRunInstancesAmi` investigation, Free Tier restriction, `t3.small` workaround; source restored but bootstrap deployment NOT yet verified):** Following Bootstrap Update 1's completion, real `RunInstances` denials against the AMI resource (`matchedStatements: []`) led to a one-variable-at-a-time diagnostic investigation; two false claims about missing permissions were raised and corrected via direct source re-verification rather than acted on; the real root cause was an MFA/STS session-credential issue, not any condition on `DevRunInstancesAmi`. A separate, real, account-specific Free Tier launch-time restriction then blocked `t3.medium`/`t3.large`/`t3.xlarge`, resolved via a narrowly scoped, explicitly temporary `t3.small` allow-list widening in `environments/dev/variables.tf`, `modules/ec2-workstation/variables.tf`, and `DevRunInstancesSupportingResources`'s condition — approved default/design target unchanged at `t3.medium`. `DevRunInstancesAmi`'s three diagnostic-stripped conditions were then restored in source, with `t3.small` deliberately added to `ec2:InstanceType` for consistency with the workaround. **A real `terraform plan`/`apply` was run from `environments/dev` — `No changes` / `0 added, 0 changed, 0 destroyed` — confirming `environments/dev`'s own resources (VPC, networking, workstation IAM role, EC2 workstation) still match `environments/dev`'s state and configuration. This does NOT confirm the `DevRunInstancesAmi` restoration was applied to the real, deployed IAM policy — `environments/dev` and `bootstrap/` are separate Terraform stacks with separate state; a `bootstrap/` plan/apply, an `aws iam get-policy-version` confirmation, and a safe authorization test remain required (flagged and corrected the same day, before a GitHub-facing copy of this documentation was prepared).** A separate, later self-assume-role failure (ambient credentials already an assumed deployment-role session) was diagnosed against the real trust policy and closed via the project's existing, already-correct `login.ps1` MFA workflow, now documented as the standing repeatable entry point for future Terraform commands in either stack — this part is genuinely resolved and verified. Full detail: `PROJECT_EXECUTION_JOURNAL.md` §27aa-§27af.

This plan builds on, and does not repeat in full, the reasoning already approved in `02_Infrastructure/Terraform_Bootstrap_Design.md`, `02_Infrastructure/EC2_Development_Workstation.md`, `02_Infrastructure/AWS_Account_Preparation.md`, `02_Infrastructure/IAM_and_Access.md`, `01_Architecture/Naming_Convention.md`, `01_Architecture/Standards.md`, and the real, operationally-verified evidence recorded in `16_Implementation_Notes/PROJECT_EXECUTION_JOURNAL.md` and `infrastructure/terraform/bootstrap/README.md` for the now-complete Terraform Bootstrap phase.

**Section index** (this plan's own numbering tracks the task's 57 required items 1:1, so a section number below is the same number as its corresponding requirement):

1. Exact scope · 2. Proposed final tree · 3. Modules needed immediately · 4. Resources remaining directly in `environments/dev` · 5. Deferred modules/resources · 6–7. File list and responsibility · 8. Dependency order · 9. Backend configuration · 10. Approved dev state key · 11. Deployment-role permission update · 12. Deployment-role trust update · 13. Workstation role permissions · 14. Instance profile design · 15. Session Manager prerequisites · 16. Zero-inbound security group · 17. Public subnet/IPv4 · 18. IGW/route table · 19. No-NAT trade-off · 20. AZ selection · 21. CIDR proposal · 22. AMI lookup strategy · 23. x86_64 enforcement · 24. `t3.medium` default · 25. `t3.large`/`t3.xlarge` override · 26. Root volume · 27. IMDSv2 · 28. Detailed monitoring · 29. User-data strategy · 30. Idempotent bootstrap requirements · 31. GitHub CLI/`uv` · 32. Disposable-workstation recovery · 33. Shutdown/cost control · 34. Tagging/naming · 35. Variables/outputs · 36. Data sources · 37. IAM policy boundaries · 38. Least-privilege decisions · 39. Terraform/provider compatibility · 40. `.terraform.lock.hcl` · 41. Example-file strategy · 42. Validation/lint/scan commands · 43. Plan review criteria · 44. Apply authorization gate · 45. AWS verification commands · 46. Session Manager connection test · 47. SSH-over-SSM/VS Code validation · 48. Session Manager logging limitations · 49. Native S3 lock contention test opportunity · 50. Partial-apply recovery · 51. Import guidance · 52. Rollback/cleanup boundaries · 53. Evidence to capture · 54. Interview-guide updates · 55. Risks and mitigations · 56. Open decisions · 57. Exit criteria.

A dedicated **Stage Separation (A–I)** section follows §8; a further **IAM Sequencing: Three Ordered Stages** section (added 2026-07-26) follows that and precedes §11, giving the higher-level, chicken-and-egg-resolving grouping of the same work; a **Documentation Conflicts Flagged** section appears near the end (§56), per `CLAUDE.md` §4's instruction to flag rather than silently resolve documentation disagreements; and a **Decision Rationale** section (added 2026-07-26, after §57) explains the "why" behind twenty already-finalized design decisions, connecting each to cost, security, portability, maintainability, or future-growth reasoning. §56 is further split (2026-07-26) into **blocking** and **non-blocking** open decisions.

---

## 1. Exact Scope of the First `environments/dev` Implementation

The first implementation creates exactly one thing, mirroring how `bootstrap/` was scoped: **a single `environments/dev/` root module, composing exactly three new reusable modules (`modules/vpc`, `modules/iam-workstation-role`, `modules/ec2-workstation`), producing exactly the resources needed for the already-approved minimal dev workstation design** — a dedicated VPC with one public subnet, an Internet Gateway, a public route table, a zero-inbound security group, a workstation IAM role and instance profile, and one EC2 instance. Nothing beyond that is in scope for the first implementation:

- No private subnets, no NAT Gateway, no VPC endpoints (approved exclusions, carried from `EC2_Development_Workstation.md` §9 and `AWS_Account_Preparation.md`).
- No `test`/`stage`/`prod` scaffolding of any kind.
- No CI/CD workflow or role.
- No automatic-shutdown Lambda/EventBridge resources (Section 22 of `EC2_Development_Workstation.md`'s "later" phase — not this task).
- No customer-managed KMS key, no DynamoDB table (native S3 locking only, unchanged from bootstrap).
- No second EC2 instance, no additional environments.

This plan itself does not create any of the above — approving it authorizes a **separate, later** file-creation task, which itself does not authorize `terraform init`/`plan`/`apply` (§44, §57).

---

## 2. Proposed Final Directory Tree

```text
infrastructure/terraform/
├── README.md                              (exists today, unchanged)
├── bootstrap/                              (exists today, formally complete)
│   └── ... (ten files, unchanged by this plan except the two described changes in §11–12)
├── modules/
│   ├── vpc/
│   │   ├── versions.tf
│   │   ├── variables.tf
│   │   ├── main.tf
│   │   └── outputs.tf
│   ├── iam-workstation-role/
│   │   ├── versions.tf
│   │   ├── variables.tf
│   │   ├── main.tf
│   │   └── outputs.tf
│   └── ec2-workstation/
│       ├── versions.tf
│       ├── variables.tf
│       ├── main.tf
│       └── outputs.tf
├── environments/
│   └── dev/
│       ├── versions.tf
│       ├── providers.tf
│       ├── backend.tf
│       ├── variables.tf
│       ├── locals.tf
│       ├── main.tf
│       ├── outputs.tf
│       ├── terraform.tfvars.example
│       ├── backend.hcl.example
│       └── README.md
│       (terraform.tfvars, backend.hcl, .terraform.lock.hcl -- generated/gitignored, not created by the file-creation task)
└── scripts/
    └── bootstrap_workstation.sh            (REVISED LOCATION, 2026-07-26: now inside infrastructure/terraform/, not a top-level repo directory -- per explicit instruction. NOT created by this plan or the eventual Terraform-file-creation task; a separate, small authoring-and-testing task, see §29)
```

No `modules/state-backend/`, no `modules/iam-deployment-role/`, no `modules/security-group/`, no `shared/` directory. `test/`, `stage/`, `prod/` do not exist and are not scaffolded. This is deliberately the **smallest tree that gives every distinct concern (networking, workstation identity, compute) its own reusable, independently testable module**, without introducing a module for something that has no plausible reuse case (§3).

---

## 3. Module Evaluation — Which Modules Deserve to Exist

The task explicitly warns against assuming every proposed module is justified. Each module below is evaluated on its own merits, not simply carried over from the design documents by default.

### 3.1 The proposed structure, evaluated

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

**Adopted as-is.** This matches `Terraform_Bootstrap_Implementation_Plan.md` §2's already-approved future structure exactly, and each of the three modules independently justifies its own existence (below) rather than merely being carried forward by inertia.

- **`modules/vpc` — justified.** Networking is a distinct concern from IAM and compute, has its own well-defined inputs (CIDR ranges, AZ) and outputs (`vpc_id`, `public_subnet_id`), and is the one module in this set with a genuine, near-term reuse case: `test`/`stage`/`prod`, whenever each is actually implemented, will each need their own VPC, instantiated from the same module with different CIDR/environment inputs rather than copy-pasted networking code. Reserved-but-undeployed private-subnet CIDR space (`Terraform_Bootstrap_Design.md` §24) also belongs conceptually with networking, not compute or IAM.
- **`modules/iam-workstation-role` — justified, kept separate from `ec2-workstation`.** IAM role/trust/policy/instance-profile definition is a distinct concern from the EC2 resource itself: it has its own least-privilege review surface (§37–38), and — like the VPC — is a plausible reuse case if a second workstation-style instance is ever needed (e.g., a temporary heavier-duty instance, or a future CI runner with a similarly-scoped role). Folding it into `ec2-workstation` would mix an identity-and-permissions concern with a compute-provisioning concern inside one module, which is exactly the kind of monolithic-module anti-pattern `Standards.md`'s "Modules" requirement and `Terraform_Bootstrap_Design.md` §16 both caution against.
- **`modules/ec2-workstation` — justified.** The instance itself, its security group, and its metadata/monitoring/volume configuration are a cohesive unit that only ever gets instantiated once per environment that has a workstation (currently just `dev`) — but "used once today" does not make a module unjustified; it makes it a **well-scoped unit of resources with a clear interface** (inputs: subnet, instance profile, AMI ID, security-group's VPC; outputs: instance ID, security group ID), independently testable/reviewable and consistent with the same reasoning that already removed `modules/state-backend`/`modules/iam-deployment-role` from `bootstrap/` — the deciding factor there was that bootstrap's resources were **small enough to read as one file with no real interface boundary worth drawing**, not that "used once" alone disqualifies a module. `ec2-workstation`'s resource count and internal logic (security group, instance, metadata options) is large enough that inlining it into `environments/dev/main.tf` directly would make that root module's own logic (module composition, wiring) harder to read against a mass of instance-configuration detail. **Revised 2026-07-26: the AMI data source no longer lives in this module** — see the AMI sub-decision below; the module now simply receives `ami_id` as a required input.

### 3.2 The six explicit sub-decisions

**All six confirmed/approved in this revision (2026-07-26), per explicit review instruction — not merely proposed:**

- **Do route tables belong in `vpc`? APPROVED — Yes.** A route table with no owning subnet/IGW association is meaningless on its own; it is tightly coupled to the VPC/subnet/IGW resources already inside `modules/vpc`, and splitting it into a separate module would create an artificial dependency edge (a route-table module needing the VPC module's `vpc_id`/`subnet_id`/`igw_id` outputs) for no benefit. `Terraform_Bootstrap_Design.md` §16 already described `modules/vpc` as owning "the dedicated VPC, public subnet, Internet Gateway, route table" together — this plan follows that.
- **Does the workstation security group belong in `ec2-workstation`? APPROVED — Yes**, already decided in `Terraform_Bootstrap_Implementation_Plan.md` §2 ("the workstation security group belongs inside `modules/ec2-workstation/` from the start... the prior draft's 'borderline, kept separate for future reuse' reasoning is superseded"). This plan does not reopen that decision — no standalone `modules/security-group` is created. The security group's only consumer is the workstation instance in the same module; a security group with zero inbound rules and one narrow outbound rule has no independent reuse case yet that would justify externalizing it.
- **Does the instance profile belong in `iam-workstation-role` or `ec2-workstation`? APPROVED — `iam-workstation-role`.** An instance profile is, functionally, a thin AWS wrapper that lets an EC2 instance assume an IAM role — it has a strict 1:1 relationship with the role it wraps, is created and destroyed alongside the role's own lifecycle, and its only meaningful input is the role name (which `iam-workstation-role` already owns). `Terraform_Bootstrap_Design.md` §30 already groups these together in its proposed-resources list ("`aws_iam_role` + `aws_iam_instance_profile` — workstation role"). Keeping the instance profile with the role means `ec2-workstation` only ever receives a ready-to-use `instance_profile_name` as an input variable — it never needs to reason about IAM trust policies or role permissions at all, which is a cleaner separation of concerns than the alternative.
- **Should the user-data/bootstrap script live under `scripts/`? APPROVED — Yes, but at a revised path.** Per `EC2_Development_Workstation.md` §21's own recommendation ("Store the script in this GitHub repository (e.g., `scripts/bootstrap_workstation.sh`...), not on the instance only"). **Revised 2026-07-26:** the exact path is now `infrastructure/terraform/scripts/bootstrap_workstation.sh` — inside `infrastructure/terraform/`, not a top-level repository directory as the original draft proposed — per explicit instruction. The script's content is still read once, at the **root module** (`environments/dev/main.tf`, via `file()` or `templatefile()`, using a path two levels up from `path.root`: `environments/dev` → `environments` → `terraform`, i.e. `file("${path.root}/../../scripts/bootstrap_workstation.sh")`), and passed into `modules/ec2-workstation` as a plain `user_data` string variable — the module itself never assumes anything about repository layout above its own directory, keeping it portable and independently testable.
- **Does AMI lookup belong in the dev root or `ec2-workstation`? REVISED 2026-07-26 — moved to the dev root (`environments/dev`).** The original draft placed the AMI data source inside `modules/ec2-workstation`; this revision moves it to `environments/dev/main.tf` instead, per explicit instruction. Rationale: AMI selection (Amazon Linux 2023, x86_64, HVM, EBS-backed) is **region- and environment-specific** — the resolved AMI ID can differ across regions and over time as AWS publishes new AL2023 builds — and a decision with that kind of variability should be **visible directly in the root module's own `plan` output**, not buried inside a module a reviewer has to open separately to see what AMI will actually be used. `modules/ec2-workstation` now receives `ami_id` as a **required** input variable (no default, no internal fallback data source) — the module itself no longer reasons about AMI selection at all, only about what to do with whatever AMI ID it's given. The root's own `variables.tf` gains an optional `ami_id_override` (default `null`) so a specific AMI can still be pinned deliberately without editing any module; when `null`, the root's own `data "aws_ami"` block resolves the current AL2023 AMI and passes that resolved ID into the module.
- **Is a separate `shared/` directory still unnecessary? APPROVED — Still unnecessary**, unchanged from `Terraform_Bootstrap_Implementation_Plan.md` §7's conclusion. With only two independent root modules in existence (`bootstrap/`, and now `environments/dev/`), each with its own small `locals.tf` computing its own tag map, the indirection of a shared tags/locals module would add a cross-root-module dependency for a handful of key-value pairs that are trivial to state twice. Revisit only if a third or fourth root module (`test`/`stage`/`prod`, once actually implemented) makes the duplication genuinely costly to maintain — not before.

---

## 4. Reusable Modules Needed Immediately

Exactly three, all newly created by the eventual code-creation task: `modules/vpc`, `modules/iam-workstation-role`, `modules/ec2-workstation` (§3). No existing module is reused, since none exists yet — `bootstrap/` deliberately has no modules of its own (§3.1).

## 5. Resources That Should Remain Directly in `environments/dev`

**None of the actual infrastructure resources.** `environments/dev/main.tf` contains only `module` blocks (three) plus the small amount of root-level wiring: reading the bootstrap script's content (`file()`/`templatefile()`), computing the common tag map (`locals.tf`), and passing each module's outputs into the next module's inputs where a dependency exists (§8). This mirrors `Terraform_Bootstrap_Design.md` §17's description of `environments/dev/` as a **composing** root module, not a resource-defining one — unlike `bootstrap/`, whose small, one-off resource set justified inlining everything directly (§3.1's `modules/state-backend`/`modules/iam-deployment-role` reasoning, in reverse).

## 6. Modules and Resources That Must Be Deferred

- **Private application/private-data subnets** — CIDR space is reserved in the VPC's addressing scheme (§21) but no `aws_subnet` resource for either tier is created. Deferred until a concrete Phase 0+ workload genuinely needs them (`Terraform_Bootstrap_Design.md` §24).
- **NAT Gateway / VPC endpoint egress** — not created; the no-NAT trade-off (§19) is accepted for this phase.
- **Automatic-shutdown module** (EventBridge Scheduler + Lambda) — `EC2_Development_Workstation.md` §22's "Phase 2 (later)" item; manual shutdown only for this implementation (§33).
- **Monitoring/alarm module** (disk-space alarm, idle-runtime alarm) — `EC2_Development_Workstation.md` §23 describes these as desirable but does not block workstation acceptance; deferred to a follow-up, separately authorized task.
- **Budget-as-code** (`aws_budgets_budget`) — the existing, manually-created AWS Budget stays manually managed, unchanged from the bootstrap decision (`Terraform_Bootstrap_Design.md` §26).
- **CI/CD module or role** — out of scope until Phase 8, unchanged project-wide policy.
- **`test`/`stage`/`prod` root modules** — not created; only `dev` is scaffolded (`Terraform_Bootstrap_Design.md` §13–14).
- **A second, standalone `iam-deployment-role` module inside `environments/dev`** — the deployment role is, and remains, a `bootstrap/`-owned resource (§11); `environments/dev` only ever consumes its ARN as an input, never redefines or duplicates it.

---

## 7. Exact File List and Responsibility for Every Proposed File

### `modules/vpc/`

| File | Responsibility |
|---|---|
| `versions.tf` | **REVISED 2026-07-26 (TFLint finding, first local validation gate):** now declares both `required_version = ">= 1.10.0"` and `required_providers { aws = { source = "hashicorp/aws", version = ">= 6.0.0, < 7.0.0" } }`, matching `environments/dev/versions.tf`'s constraint exactly. TFLint's default ruleset expects every module — not only the calling root — to declare its own compatible version range. Still configures no provider block of its own. |
| `variables.tf` | `project_name`, `environment`, `vpc_cidr`, `public_subnet_cidr`, `tags` (map). No account-specific values, no defaults for CIDR ranges (supplied by the caller, §21). |
| `main.tf` | `aws_vpc`, one `data "aws_availability_zones"` lookup (§20), `aws_subnet` (public), `aws_internet_gateway`, `aws_route_table`, `aws_route` (default route `0.0.0.0/0` → IGW), `aws_route_table_association`. |
| `outputs.tf` | `vpc_id`, `public_subnet_id`, `availability_zone` (the AZ actually selected, §20), `internet_gateway_id`, `public_route_table_id`. |

### `modules/iam-workstation-role/`

| File | Responsibility |
|---|---|
| `versions.tf` | Same pattern as `modules/vpc/versions.tf` — **REVISED 2026-07-26**, same version constraints added. |
| `variables.tf` | **REVISED 2026-07-26 (TFLint finding, first local validation gate): `project_name` removed** — this module never actually used it (every resource inside is named entirely from the caller-supplied `var.role_name`, which the root module already composes as `"${var.project_name}-${var.environment}-workstation-role"`; tags come entirely from `var.tags`, itself already computed by the caller). Retaining an input a module never reads would have meant inventing a usage merely to silence the linter, which is not an approved fix. Current inputs: `environment`, `deployment_role_arn` (the exact ARN the workstation role is permitted to assume, no default — supplied by the caller from the bootstrap output, §12), `tags`. |
| `main.tf` | `data "aws_iam_policy_document"` for the role's own trust policy (principal: `ec2.amazonaws.com` service principal only), `aws_iam_role` (the workstation role), `aws_iam_role_policy_attachment` (AWS-managed `AmazonSSMManagedInstanceCore`), `data "aws_iam_policy_document"` + `aws_iam_role_policy` (inline statement: `sts:AssumeRole` on `var.deployment_role_arn` only, no wildcard), `aws_iam_instance_profile` (§3.2's instance-profile-co-location decision). |
| `outputs.tf` | `role_name`, `role_arn`, `instance_profile_name`, `instance_profile_arn`. |

### `modules/ec2-workstation/`

| File | Responsibility |
|---|---|
| `versions.tf` | Same pattern as above — **REVISED 2026-07-26**, same version constraints added. |
| `variables.tf` | `project_name`, `environment`, `vpc_id`, `subnet_id`, `instance_profile_name`, `instance_type` (default `"t3.medium"`, validated against an allow-list, §24–25), `ami_id` (**REVISED 2026-07-26: required, no default** — resolved by the root module and passed in, §22, §3.2), `root_volume_size` (default `30`), `user_data` (string, the bootstrap script's rendered content, §29), `tags`. |
| `main.tf` | **REVISED 2026-07-26: no `data "aws_ami"` block in this file** — AMI resolution now lives in `environments/dev/main.tf` (§22, §3.2). `aws_security_group` (zero inbound, one scoped HTTPS-outbound rule, §16), `aws_instance` (the workstation: uses `var.ami_id` directly, IMDSv2-enforced `metadata_options`, `monitoring = false`, `root_block_device` gp3/encrypted/30 GiB, `associate_public_ip_address = true`, `subnet_id`, `vpc_security_group_ids`, `iam_instance_profile`, `user_data`, tags including the `Name` tag per `Naming_Convention.md`). |
| `outputs.tf` | `instance_id`, `public_ip`, `security_group_id`. |

### `environments/dev/`

| File | Responsibility |
|---|---|
| `versions.tf` | `required_version = ">= 1.10.0, < 2.0.0"` (matching bootstrap, §39) and the exact, verified-at-implementation-time AWS provider constraint. |
| `providers.tf` | Configures the `aws` provider with `region = var.region`, `allowed_account_ids = [var.aws_account_id]` (same wrong-account safety pattern as `bootstrap/providers.tf`), and its own `assume_role { role_arn = var.deployment_role_arn, session_name = "terraform-dev-provider" }` block (§9, §12's MFA caveat noted there) — deliberately named distinctly from the backend's `session_name` (§9) so the two separate `AssumeRole` calls are distinguishable in CloudTrail. |
| `backend.tf` | Declares an **active** (not two-phase/commented) `backend "s3" {}` block — unlike `bootstrap/`, `environments/dev` is remote-state-from-its-first-apply, since the S3 backend already exists (§9, `Terraform_Bootstrap_Design.md` §5's closing line). |
| `variables.tf` | `project_name`, `region`, `aws_account_id` (no default), `environment` fixed to `"dev"` via validation, `deployment_role_arn` (no default, §12), `vpc_cidr`, `public_subnet_cidr` (§21), `instance_type` (default `"t3.medium"`, allow-list validated, §24), `ami_id_override` (**new, 2026-07-26**, optional, default `null`, §3.2, §22), `additional_tags`. |
| `locals.tf` | Common tags map: `{ Project = var.project_name, Environment = "dev", ManagedBy = "terraform", Owner = "DataEngAA", CostCenter = "personal-learning" }`, merged with `var.additional_tags` using the same override-safe merge order bootstrap's `locals.tf` already uses (required tags win). |
| `main.tf` | `data "aws_ami" "al2023"` (**moved here, 2026-07-26**, used only when `var.ami_id_override` is `null`, §22, §3.2), `module "vpc"`, `module "workstation_role"`, `module "ec2_workstation"` blocks (the latter receiving `ami_id = var.ami_id_override != null ? var.ami_id_override : data.aws_ami.al2023.id`), wiring outputs to inputs per the dependency graph (§8); one `file()`/`templatefile()` call reading `infrastructure/terraform/scripts/bootstrap_workstation.sh` into a local, passed as `user_data` (§29). |
| `outputs.tf` | `vpc_id`, `public_subnet_id`, `workstation_role_arn`, `workstation_instance_profile_name`, `instance_id`, `instance_public_ip` — `workstation_role_arn` specifically exists to support §12's future trust-policy-update apply, copied from real output, never retyped. |
| `terraform.tfvars.example` | Committed placeholder template — no real account ID, ARN, or CIDR asserted as final (§41). |
| `backend.hcl.example` | Committed placeholder template, now including a nested `assume_role = { role_arn = ..., session_name = ... }` block (**corrected syntax, 2026-07-26** — not a standalone `role_arn` field; absent from bootstrap's, since bootstrap never assumes a role for its own backend access) (§9, §41). |
| `README.md` | Purpose, prerequisites, required inputs, the dependency-order/stage sequence (§8, stage table, three-stage IAM sequencing before §11), verification commands (§45), break-glass/`prevent_destroy` notes carried from bootstrap's pattern, and an explicit "no commands were run" statement — mirroring `bootstrap/README.md`'s structure. |

`infrastructure/terraform/scripts/bootstrap_workstation.sh` (**revised path, 2026-07-26**) is **not** part of the file list this plan authorizes creating alongside the Terraform code — see §29 for why it is treated as a separate, small authoring-and-testing task.

---

## 8. Dependency Order

Within `environments/dev`'s three modules, the actual resource dependency graph is:

```text
      data.aws_ami.al2023 (root)          module "vpc"                    module "workstation_role"
   (resolved in environments/dev/  (VPC, public subnet, IGW,                 (IAM role, trust policy,
    main.tf, independent of         route table, AZ lookup)                   SSM attachment, AssumeRole
    everything else, §22, §3.2)              │                                  policy, instance profile)
            │                                │  vpc_id, subnet_id                        │
            │  ami_id                        │                            instance_profile_name
            └───────────────┬────────────────┴───────────────┬───────────────────────────┘
                             ▼                                ▼
                                  module "ec2_workstation"
                    (security group [needs vpc_id],
         EC2 instance [needs ami_id + subnet_id + instance_profile_name])
```

`module "vpc"`, `module "workstation_role"`, and the root's own `data "aws_ami"` lookup have **no dependency on each other** and can, in principle, be resolved/applied in any order or concurrently within the same `terraform apply` (Terraform's own graph-based scheduler handles this automatically — this plan does not need to force an artificial order between them). `module "ec2_workstation"` depends on **all three**: its internal security group needs `vpc_id` from `modules/vpc`; its `aws_instance` needs `subnet_id` (from `modules/vpc`), `instance_profile_name` (from `modules/iam-workstation-role`), and `ami_id` (from the root's own `data "aws_ami"` lookup, or `var.ami_id_override` if set — **moved to the root module in this revision, 2026-07-26, §3.2, §22**; the module no longer performs any AMI lookup of its own).

This is a single `terraform apply` for all of `environments/dev` — not three separate applies — consistent with the single `dev/terraform.tfstate` key (§10) and the "one composing root module" design (§17 of `Terraform_Bootstrap_Design.md`, §5).

---

## Stage Separation (A–I)

The task requires this plan to separate work into nine explicit stages. **These are work-stream categories, not a strict A-then-B-then-C execution order** — in particular, Stage B cannot happen before Stage E (the workstation role must exist before its ARN can be added to a trust policy), which is called out explicitly below rather than left to be misread as literal sequence. **A higher-level, three-stage grouping of this same table — the one that actually matters for the IAM chicken-and-egg dependency — is given in "IAM Sequencing: Three Ordered Stages," immediately before §11: Stage A below = that section's Stage 1; Stages C+D+E below = that section's Stage 2; Stage B below = that section's Stage 3.**

| Stage | What it covers | Where the change lives | When it actually happens, relative to the others |
|---|---|---|---|
| **A. Deployment-role permission update** | Attach a permissions policy to the existing `aws_iam_role.deployment` (currently zero permissions, per `README.md` "Unresolved Permission Scope") scoped to: the `dev/terraform.tfstate` object + its `.tflock` lock object; EC2/VPC create-manage permissions for the resources in §C/§E; IAM permissions narrowly scoped to create/manage exactly the workstation role, its policy, and its instance profile (§11, §37). | `bootstrap/variables.tf`, `bootstrap/main.tf`, `bootstrap/README.md` — **existing files, modified**, not new files. | **First**, before Stage C/D/E can be planned or applied at all — `environments/dev`'s provider and backend both assume the deployment role (§9, §12), so that role needs real permissions before any dev-side `plan` can succeed. |
| **B. Deployment-role trust update** | Add the (by-then-real) workstation role ARN as a second trusted principal on the deployment role's trust policy, alongside the human identity. | `bootstrap/variables.tf` (`trusted_principal_arns`), `bootstrap/main.tf` — **existing files, modified**, a small, separate, reviewed follow-up apply. | **Last**, strictly after Stage E has produced a real workstation-role ARN (copied from Terraform output, never retyped, §12). This is the one point, per `Terraform_Bootstrap_Design.md` §2 step 5, where the deployment role's trust relationship changes. |
| **C. Dev networking** | `modules/vpc` and its consumption in `environments/dev/main.tf`: VPC, public subnet, IGW, route table (§16–21). | New files under `modules/vpc/`, wired from `environments/dev/main.tf`. | After Stage A (needs deployment-role EC2/VPC permissions); can proceed in parallel with Stage D. |
| **D. Workstation IAM role** | `modules/iam-workstation-role` and its consumption: the role, SSM attachment, `AssumeRole` policy, instance profile (§13–14). | New files under `modules/iam-workstation-role/`, wired from `environments/dev/main.tf`. | After Stage A (needs deployment-role IAM permissions); can proceed in parallel with Stage C. |
| **E. EC2 workstation** | `modules/ec2-workstation` and its consumption: security group, the instance itself (§16, §23–28). **AMI resolution (§22) now happens in the root module (`environments/dev/main.tf`), not inside this module — revised 2026-07-26, §3.2.** | New files under `modules/ec2-workstation/`; the AMI `data` block itself lives in `environments/dev/main.tf`. | After both C and D complete (needs `subnet_id` from C, `instance_profile_name` from D, and `ami_id` from the root's own AMI lookup, which has no dependency on C or D and can resolve independently, §8). |
| **F. Validation** | `terraform fmt -check -recursive`, `terraform init`, `terraform validate`, `tflint`, a Trivy/`tfsec` scan (§42). | No file changes — command execution only, once C/D/E's files exist. | After C/D/E's files are written, before any `plan`. |
| **G. Plan** | `terraform plan`, manually reviewed against this document's proposed resource list and tags (§43). | No file changes. | After F passes cleanly (or with only reviewed, accepted findings, same discipline as bootstrap's Trivy exceptions). |
| **H. Apply** | `terraform apply` against the reviewed, saved plan (§44). | Creates real AWS resources for the first time under `environments/dev`. | After G is reviewed and a separate, explicit apply authorization is given — never automatic on a clean plan. |
| **I. AWS verification** | Real `aws` CLI output confirming the created VPC/subnet/IGW/route-table/security-group/role/instance-profile/instance match the design, plus a Session Manager connectivity test (§45–48). | No file changes — verification only. | After H succeeds; not implied by `Apply complete!` alone, same discipline as the bootstrap apply's AWS-side verification. |

Stage A is a **prerequisite, not part of `environments/dev` itself** — it is a change to the existing `bootstrap/` root module's own files, applied via its own separate `plan`/`apply` (bootstrap's own state, `bootstrap/terraform.tfstate`, not `dev/terraform.tfstate`). Stage B is the mirror image at the end of the sequence. Neither is created or run by this plan or by the eventual `environments/dev` code-creation task — both are explicitly out of scope for this document (Constraints) and are recorded here only so the full dependency chain is visible in one place.

---

## 9. Backend Configuration for `environments/dev`

- **Backend type:** `s3`, same bucket as `bootstrap/` (the existing, already-hardened, already-verified state bucket — no second bucket is created).
- **Active from the first apply** — unlike `bootstrap/`'s two-phase (local-then-migrate) `backend.tf`, `environments/dev/backend.tf` declares an active, empty `backend "s3" {}` block from the moment the file is created, because the S3 backend this configuration depends on already exists and is already verified (Terraform Bootstrap phase, `PROJECT_EXECUTION_JOURNAL.md` Section 27g). This matches `Terraform_Bootstrap_Design.md` §5's closing statement: "everything other than the bootstrap config itself... is remote-state-only from its very first apply."
- **Partial configuration**, same mechanism as bootstrap: real values supplied only via `-backend-config=backend.hcl` at `terraform init` time, never hardcoded in `backend.tf` itself (`Terraform_Bootstrap_Design.md` §19).
- **The backend must assume the deployment role — CORRECTED SYNTAX, 2026-07-26.** The prior draft of this plan incorrectly described a standalone top-level `role_arn` field in `backend.hcl`; no such field exists in Terraform's S3 backend schema. The correct shape, confirmed against the real S3 backend's `assume_role` support, is a **nested `assume_role` block**:

  ```hcl
  bucket       = "<STATE_BUCKET_NAME>"
  key          = "dev/terraform.tfstate"
  region       = "ap-south-1"
  encrypt      = true
  use_lockfile = true
  assume_role = {
    role_arn     = "<DEPLOYMENT_ROLE_ARN>"
    session_name = "terraform-dev-backend"
  }
  ```

  This is the exact, complete proposed shape of `environments/dev/backend.hcl.example` (§41). No credential, profile name, or real ARN is included — `<DEPLOYMENT_ROLE_ARN>` is a placeholder, filled in only in the real, gitignored `backend.hcl`, exactly as `<STATE_BUCKET_NAME>` already is in bootstrap's own `backend.hcl.example`. Terraform's own state read/write calls against S3 are made as the deployment role once this is in place, not as whatever identity invoked `terraform init`. This is a genuine difference from `bootstrap/backend.hcl.example`, which has no `assume_role` block at all, since bootstrap's backend is accessed directly as the human identity (no role assumption for bootstrap's own state, ever, by design — `README.md` "Unresolved Permission Scope").
- **Backend configuration and provider configuration remain separate — restated explicitly.** The `assume_role` block above configures only how Terraform's *state storage* calls (reading/writing `dev/terraform.tfstate`, acquiring/releasing its native lock) authenticate — it has no effect on how Terraform authenticates the *resource-management* API calls it makes during `plan`/`apply`. Those are governed entirely by `environments/dev/providers.tf`'s own, independent `assume_role` block (§7, §12's implementation-time constraint) — a second, distinct `AssumeRole` call using the AWS provider's own `assume_role { role_arn = var.deployment_role_arn, session_name = "terraform-dev-provider" }` syntax, with its own distinct `session_name` so the two calls are individually visible in CloudTrail. The backend's `assume_role.role_arn` and the provider's `assume_role.role_arn` point at the **same** deployment role, but they are two functionally separate assumptions (state access vs. resource management), configured in two separate files (`backend.hcl`, not committed, vs. `providers.tf`, committed) using two separate mechanisms (S3 backend config vs. AWS provider config) — this mirrors how `bootstrap/`'s human identity has always made two conceptually separate kinds of calls (direct S3 calls for its own state, direct IAM/S3 calls for its own bootstrap resources) even though bootstrap itself never needed a role assumption for either.
- **Native S3 locking**, `use_lockfile = true`, unchanged from bootstrap — no DynamoDB table, consistent project-wide.
- **`bootstrap/` continues using the human IAM identity directly**, never the deployment role, for its own state — this is not renegotiated by this plan. `environments/dev` is the first configuration in this project to actually exercise deployment-role-mediated backend/provider access, which is precisely why Stage A of the IAM Sequencing section (before §11) must happen first: the role currently has no permissions to do either.
- **Bootstrap and dev state keys are never mixed** — see §10.

## 10. Approved Dev State Key

```text
dev/terraform.tfstate
```

A single key for the entire `environments/dev` root module (VPC + workstation role + EC2 instance together), **not** the finer-grained `dev/networking/terraform.tfstate` / `dev/iam/terraform.tfstate` / `dev/ec2-workstation/terraform.tfstate` split illustrated in `Terraform_Bootstrap_Design.md` §8. This is a deliberate, explicit choice — see the **Documentation Conflicts Flagged** note in §56 for why this plan follows the single-key model instead, and why that is not a silent deviation.

`dev/terraform.tfstate` lives inside the **same** state bucket bootstrap already created and hardened — no new bucket, no new backend infrastructure. Its lock object (native S3 locking) is `dev/terraform.tfstate.tflock`, following the same pattern as bootstrap's own `bootstrap/terraform.tfstate.tflock` (never manually created, deleted, or manipulated — the same rule carried from `README.md` "State Safety").

---

## IAM Sequencing: Three Ordered Stages and the Chicken-and-Egg Dependency

**New section, added in this revision (2026-07-26), per explicit instruction.** The Stage Separation (A–I) table above is a work-stream breakdown; this section is the higher-level grouping that actually resolves the IAM chicken-and-egg dependency at the center of this plan — three **strictly ordered** stages, each gated on the previous one succeeding and being AWS-verified before the next begins.

**The chicken-and-egg dependency, stated plainly:** `environments/dev`'s backend and provider must both assume the deployment role (§9) — but the deployment role, as bootstrap left it, has no permissions policy attached at all and trusts only the human identity, not any workstation role. The workstation role that will eventually be trusted doesn't exist until `environments/dev`'s own apply creates it. So: the deployment role needs permissions before it can do anything in `environments/dev`; the workstation role needs to exist before it can be trusted; and `environments/dev` needs the deployment role to already be usable before it can create that workstation role. None of these can happen simultaneously in one apply. The three stages below resolve this the same way bootstrap resolved its own local-state-then-migrate chicken-and-egg problem (`Terraform_Bootstrap_Design.md` §1) — by producing exactly the missing input each next stage needs, in order, rather than attempting a circular reference in a single step.

**Stage A — Bootstrap update 1** (run through the human-administered `bootstrap/` root only; = Stage Separation table's Stage A):
- Add a reviewed permissions policy to `aws_iam_role.deployment` (§11) — exact `dev/terraform.tfstate` state-object and `dev/terraform.tfstate.tflock` lock-object access, plus the EC2/VPC/IAM permissions Stage B will need.
- The existing human IAM-user MFA trust path is retained **unchanged** — this stage does not touch the trust policy at all.
- **The workstation-role trust statement is explicitly NOT added yet** — it cannot be, since the workstation role does not exist until Stage B creates it.
- Applied against `bootstrap/terraform.tfstate` only, via its own separate, reviewed `plan`/`apply` — never against `dev/terraform.tfstate`.
- **Gate:** must succeed and be AWS-verified (the role's new permissions actually usable) before Stage B is attempted.

**Stage B — `environments/dev` apply** (run through the deployment role; = Stage Separation table's Stages C, D, and E combined):
- Create networking: VPC, public subnet, IGW, route table (Stage C).
- Create the workstation IAM role and instance profile (Stage D).
- Create the workstation security group and the EC2 instance itself (Stage E).
- The deployment role is assumed, for this stage, **by the human identity** via its MFA-conditioned trust statement (§12's implementation-time constraint) — not by the workstation role, which does not exist until this stage finishes creating it.
- Applied against `dev/terraform.tfstate` only, using exactly the permissions Stage A granted — nothing more.
- **Gate:** must succeed and be AWS-verified, producing a real, usable workstation-role ARN (copied from Terraform output, never retyped), before Stage C is attempted.

**Stage C — Bootstrap update 2** (run through the human-administered `bootstrap/` root again, after Stage B; = Stage Separation table's Stage B):
- Add the workstation role's real ARN (from Stage B's `workstation_role_arn` output) as an **additional** trusted principal on `aws_iam_role.deployment`'s trust policy (§12).
- The human IAM-user MFA trust path is **kept, unchanged**, alongside the new statement — both trust paths coexist from this point forward.
- **Both trust paths are validated** after this apply: the human identity must still be able to assume the deployment role with MFA (a regression check against Stage A/B's own working access), and the workstation role must now be able to assume it without MFA (a new-capability check, exercised for real once the workstation is reachable via Session Manager, §46).
- Applied against `bootstrap/terraform.tfstate` only — **`environments/dev` never manages the deployment role itself, in either direction.** The deployment role remains exclusively `bootstrap/`-owned (§11, §37 item 3) both before and after this stage.

From Stage C onward, **routine `environments/dev` Terraform runs are expected to happen from the EC2 workstation itself**, assuming the deployment role via the workstation role's own (non-MFA) trust statement — the human identity's direct use of the deployment role, required for Stages A and B, becomes the exception going forward, not the routine path (`Terraform_Bootstrap_Design.md` §2 step 6, restated in §12 below).

---

## 11. How the Bootstrap Deployment Role Will Receive Dev-State and Infrastructure Permissions (Stage A / IAM Sequencing Stage A)

**Current state (as of the formally-complete bootstrap phase): `aws_iam_role.deployment` has NO permissions policy attached at all** — only its trust policy exists (`README.md` "Unresolved Permission Scope"). This was a deliberate decision (`PROJECT_EXECUTION_JOURNAL.md` Section 14): the role's trust relationship needed to exist for `environments/dev` to reference its ARN as a forward input, but granting it access to `bootstrap/terraform.tfstate` itself was rejected as an unnecessary, self-referential expansion of blast radius.

**FINALIZED, exact proposal (2026-07-26).** This section previously described the permission grant only by category; it now specifies the complete, literal policy — an exact IAM policy JSON document, ready for code-creation-time use (still not applied, per this plan's own constraints). This is a modification to existing `bootstrap/` files (`main.tf`, likely as a single `aws_iam_role_policy` or an `aws_iam_policy` + `aws_iam_role_policy_attachment` pair — exact Terraform resource shape chosen at code-creation time, the JSON content below does not change either way), not a new file, and remains a **separate, small, reviewed `bootstrap/` apply** (its own `plan`, its own review, its own explicit authorization) — not bundled into the same apply as `environments/dev`'s own resources. It must complete successfully, with its own AWS-side verification (that the policy attached and the role can now be assumed and actually used), **before** Stage B's `plan` can be expected to succeed.

### 11.1 Action / Resource / Condition Matrix

**Rows 5-8 CORRECTED 2026-07-26 (IAM policy bypass fix, first-real-validation-gate follow-up task).** The original single "Networking — create/manage" row (covering all 20 create+manage actions under one condition set, with a second, overlapping row re-granting 5 of those same actions with a tag condition) had a real IAM bypass: because IAM `Allow` statements are additive/OR'd, the broader, untagged grant made the narrower, tagged grant's condition meaningless for the 5 actions both covered. Rows 5 and 5b below replace that pair, split so each action appears in exactly one row/statement — see §11.3 and §11.6 for the full explanation.

**Row 5 SUPERSEDED 2026-07-26 (second real partial `environments/dev` apply failure).** The single combined `DevNetworkingCreateTaggedOnly` statement (row 5 below) was itself a real, deployed defect: a real apply against it created a replacement VPC and an Internet Gateway successfully, then failed with `AccessDenied` on `ec2:CreateSubnet`/`ec2:CreateRouteTable`/`ec2:CreateSecurityGroup`, each against the **parent VPC's ARN**. Root cause: `CreateSubnet`, `CreateRouteTable`, and `CreateSecurityGroup` are each multi-resource-type actions that authorize against TWO resources in the same call — the new resource being created, AND the existing parent VPC it is created inside. `aws:RequestTag` only has a value for a resource actually being tagged as part of the current call; the existing parent VPC is not being tagged (it already has tags), so the single statement's `aws:RequestTag` condition had nothing to match against that resource, producing an implicit deny for it. Confirmed via a real 2026-07-26 fetch of AWS's own EC2 Service Authorization Reference: `CreateVpc`'s only resource type is `vpc` (no parent); `CreateInternetGateway`'s only resource type is `internet-gateway` (not attached to a VPC until a separate `AttachInternetGateway` call) — both of these already succeeded in the second partial apply. `CreateSubnet`/`CreateRouteTable`/`CreateSecurityGroup` were each confirmed (same fetch) to require BOTH their own new resource type (`subnet*`/`route-table*`/`security-group*`, supporting `aws:RequestTag/${TagKey}`) AND the existing `vpc` resource type (supporting `aws:ResourceTag/${TagKey}`, not `aws:RequestTag`). Row 5 is replaced by rows 5c-5j below — one statement each for `CreateVpc` and `CreateInternetGateway` (single resource type, `aws:RequestTag` only), and a NEW-resource/EXISTING-parent-VPC pair for each of `CreateSubnet`, `CreateRouteTable`, and `CreateSecurityGroup`. Tag enforcement is preserved throughout — no untagged path exists for any of these 5 actions anywhere in the policy. Row 5b (`DevNetworkingManageTaggedResourceOnly`) is unaffected by this correction and remains unchanged.

**Row 9 CORRECTED AGAIN 2026-07-26 (deployed-v1-policy review).** The original single `RunInstances` row applied `ec2:Owner = amazon` across a `Resource` list mixing the AMI resource type with five non-AMI resource types (`instance/*`, `volume/*`, `network-interface/*`, `subnet/*`, `security-group/*`) — broader than that condition key is meant to apply to, since `ec2:Owner` reflects ownership of the AMI being launched from and is not a meaningful context key for the non-AMI resources `RunInstances` also references in the same call. Rows 9a-9c below replace it: 9a scopes `ec2:Owner` to the AMI resource only, 9b covers the five non-AMI resource types with no `ec2:Owner` condition, and 9c documents the pre-existing, unchanged, separate tag-on-create statement that the original single row had folded into its own condition column (a documentation imprecision corrected here, not a policy change — `DevRunInstancesTagOnCreate`'s `ec2:CreateTags` statement was never conditioned on `ec2:Owner` and is untouched by this correction).

| # | Category | Actions | Resource | Key conditions |
|---|---|---|---|---|
| 1 | Dev state — list | `s3:ListBucket` | state bucket | `s3:prefix` StringLike `dev/terraform.tfstate`, `dev/terraform.tfstate.tflock` |
| 2 | Dev state — bucket metadata | `s3:GetBucketLocation`, `s3:GetBucketVersioning` | state bucket | none |
| 3 | Dev state — state object | `s3:GetObject`, `s3:PutObject` | `.../dev/terraform.tfstate` (exact object) | none — **no `s3:DeleteObject`** |
| 4 | Dev state — lock object | `s3:GetObject`, `s3:PutObject`, `s3:DeleteObject` | `.../dev/terraform.tfstate.tflock` (exact object) | none — delete needed to release the lock |
| 5 | ~~Networking — create only (`DevNetworkingCreateTaggedOnly`)~~ **SUPERSEDED 2026-07-26 — see the note above and rows 5c-5j below** | ~~`ec2:CreateVpc`, `CreateSubnet`, `CreateInternetGateway`, `CreateRouteTable`, `CreateSecurityGroup`~~ | ~~`Resource = "*"`~~ | ~~`aws:RequestedRegion` AND `aws:RequestTag/Project`/`aws:RequestTag/Environment`~~ — real `AccessDenied` on the parent-VPC side of `CreateSubnet`/`CreateRouteTable`/`CreateSecurityGroup` |
| 5b | Networking — manage existing (`DevNetworkingManageTaggedResourceOnly`) | `ec2:ModifyVpcAttribute`, `DeleteVpc`, `ModifySubnetAttribute`, `DeleteSubnet`, `AttachInternetGateway`, `DetachInternetGateway`, `DeleteInternetGateway`, `CreateRoute`, `ReplaceRoute`, `DeleteRoute`, `AssociateRouteTable`, `DisassociateRouteTable`, `ReplaceRouteTableAssociation`, `DeleteRouteTable`, `DeleteSecurityGroup` | `Resource = "*"` (not narrowed to a specific ARN pattern by this correction — see §11.3) | `aws:RequestedRegion = ap-south-1` AND `aws:ResourceTag/Project = enterprise-data-platform` AND `aws:ResourceTag/Environment = dev` — the **target** resource must already carry these tags (only true for resources created via rows 5c-5j below) — **unaffected by the 2026-07-26 restructuring** |
| 5c | `CreateVpc` (`DevCreateVpcTaggedOnly`) | `ec2:CreateVpc` | `arn:aws:ec2:ap-south-1:<AWS_ACCOUNT_ID>:vpc/*` — **CONFIRMED 2026-07-26** (real AWS reference fetch): `CreateVpc`'s only resource type is `vpc`, no parent | `aws:RequestedRegion = ap-south-1` AND `aws:RequestTag/Project`/`aws:RequestTag/Environment` — **not part of the second partial-apply failure; already succeeded** |
| 5d | `CreateInternetGateway` (`DevCreateInternetGatewayTaggedOnly`) | `ec2:CreateInternetGateway` | `arn:aws:ec2:ap-south-1:<AWS_ACCOUNT_ID>:internet-gateway/*` — **CONFIRMED 2026-07-26**: only resource type is `internet-gateway`, not attached to a VPC until a separate `AttachInternetGateway` call | `aws:RequestedRegion = ap-south-1` AND `aws:RequestTag/Project`/`aws:RequestTag/Environment` — **not part of the second partial-apply failure; already succeeded** |
| 5e | `CreateSubnet` — new subnet (`DevCreateSubnetNewResourceTaggedOnly`) | `ec2:CreateSubnet` | `arn:aws:ec2:ap-south-1:<AWS_ACCOUNT_ID>:subnet/*` | `aws:RequestedRegion = ap-south-1` AND `aws:RequestTag/Project`/`aws:RequestTag/Environment` |
| 5f | `CreateSubnet` — existing parent VPC (`DevCreateSubnetExistingVpcTaggedOnly`) | `ec2:CreateSubnet` | `arn:aws:ec2:ap-south-1:<AWS_ACCOUNT_ID>:vpc/*` | `aws:RequestedRegion = ap-south-1` AND `aws:ResourceTag/Project`/`aws:ResourceTag/Environment` — the VPC must already carry these tags (true for a VPC created via row 5c) |
| 5g | `CreateRouteTable` — new route table (`DevCreateRouteTableNewResourceTaggedOnly`) | `ec2:CreateRouteTable` | `arn:aws:ec2:ap-south-1:<AWS_ACCOUNT_ID>:route-table/*` | `aws:RequestedRegion = ap-south-1` AND `aws:RequestTag/Project`/`aws:RequestTag/Environment` |
| 5h | `CreateRouteTable` — existing parent VPC (`DevCreateRouteTableExistingVpcTaggedOnly`) | `ec2:CreateRouteTable` | `arn:aws:ec2:ap-south-1:<AWS_ACCOUNT_ID>:vpc/*` | `aws:RequestedRegion = ap-south-1` AND `aws:ResourceTag/Project`/`aws:ResourceTag/Environment` |
| 5i | `CreateSecurityGroup` — new security group (`DevCreateSecurityGroupNewResourceTaggedOnly`) | `ec2:CreateSecurityGroup` | `arn:aws:ec2:ap-south-1:<AWS_ACCOUNT_ID>:security-group/*` | `aws:RequestedRegion = ap-south-1` AND `aws:RequestTag/Project`/`aws:RequestTag/Environment` |
| 5j | `CreateSecurityGroup` — existing parent VPC (`DevCreateSecurityGroupExistingVpcTaggedOnly`) | `ec2:CreateSecurityGroup` | `arn:aws:ec2:ap-south-1:<AWS_ACCOUNT_ID>:vpc/*` | `aws:RequestedRegion = ap-south-1` AND `aws:ResourceTag/Project`/`aws:ResourceTag/Environment` |
| 6 | Security-group rules — egress only | `ec2:AuthorizeSecurityGroupEgress`, `RevokeSecurityGroupEgress` | `arn:aws:ec2:ap-south-1:<AWS_ACCOUNT_ID>:security-group/*` | `aws:RequestedRegion = ap-south-1` AND `aws:ResourceTag/Project`/`aws:ResourceTag/Environment` (added 2026-07-26, same rationale as row 5b) — **no `AuthorizeSecurityGroupIngress`/`RevokeSecurityGroupIngress` granted at all** (§11.7) |
| 7 | ~~Tagging (`DevTagging`)~~ **SUPERSEDED 2026-07-26 — see rows 7a-7b below** | ~~`ec2:CreateTags`, `DeleteTags`~~ | ~~`Resource = "*"`~~ | ~~`aws:RequestedRegion` only, no tag condition~~ — broader than necessary once AWS's own implicit create-time `CreateTags` authorization and Terraform's separate post-creation reconciliation calls are distinguished |
| 7a | Tagging — create-time only (`DevTaggingOnApprovedCreateActions`) | `ec2:CreateTags` | `Resource = "*"` (§11.4 item 1) | `aws:RequestedRegion = ap-south-1` AND `ec2:CreateAction` IN [`CreateVpc`,`CreateSubnet`,`CreateInternetGateway`,`CreateRouteTable`,`CreateSecurityGroup`] AND `aws:RequestTag/Project`/`aws:RequestTag/Environment` — same officially-documented tag-on-create pattern this policy already used, unmodified, for `RunInstances` (row 9c/`DevRunInstancesTagOnCreate`, not duplicated here) — **`ec2:CreateAction` support for these 5 actions is pattern-inferred, not independently reference-confirmed in this pass; see §11.6** |
| 7b | Tagging — post-creation management (`DevTaggingManageTaggedResourceOnly`) | `ec2:CreateTags`, `DeleteTags` | `Resource = "*"` (§11.4 item 1) | `aws:RequestedRegion = ap-south-1` AND `aws:ResourceTag/Project`/`aws:ResourceTag/Environment` — the target must already carry these tags; Project/Environment are fixed values so this does not block legitimate tag reconciliation |
| 8 | Read-only / describe | `ec2:DescribeVpcs`, `DescribeVpcAttribute` **(added 2026-07-26 — see note below)**, `DescribeSubnets`, `DescribeInternetGateways`, `DescribeRouteTables`, `DescribeSecurityGroups`, `DescribeSecurityGroupRules`, `DescribeInstances`, `DescribeInstanceAttribute`, `DescribeInstanceTypes`, `DescribeInstanceCreditSpecifications`, `DescribeImages`, `DescribeAvailabilityZones`, `DescribeTags`, `DescribeVolumes`, `DescribeAccountAttributes` | `Resource = "*"` (unavoidable, §11.4 item 2) | `aws:RequestedRegion = ap-south-1` **added 2026-07-26** — a universal AWS global condition key, available regardless of an action's resource-level restriction capability; no resource-tag condition added, since `Describe*` actions do not evaluate resource/request tags at all |

**Row 8 CORRECTED AGAIN 2026-07-26 (real partial-apply failure, first `environments/dev` apply attempt).** The first real `terraform apply` against `environments/dev` created the workstation IAM role, its `AmazonSSMManagedInstanceCore` attachment, its inline `AssumeRole` policy, and its instance profile, then began creating the VPC and returned a real VPC ID — then stopped with a real AWS `AccessDenied`-class error on `ec2:DescribeVpcAttribute`, an action the AWS provider calls internally while waiting for `aws_vpc`'s `enable_dns_hostnames`/`enable_dns_support` attributes (`modules/vpc/main.tf`) to finish propagating after creation. This action was missing from `DevReadOnlyDescribe`. **Corrected** by adding `ec2:DescribeVpcAttribute` to `DevReadOnlyDescribe`'s existing action list — same `Resource = "*"`, same `aws:RequestedRegion` condition, no new write permission, no other statement broadened. This was a partial, failed, real deployment (Tier 6-adjacent evidence, not a design-review finding) — see `PROJECT_EXECUTION_JOURNAL.md` for the full incident record and the required recovery sequence before any further `environments/dev` apply is attempted.
| 9a | `RunInstances` — AMI (`DevRunInstancesAmi`) | `ec2:RunInstances` | `arn:aws:ec2:ap-south-1::image/*` (AWS-owned AMI only) | `aws:RequestedRegion = ap-south-1` AND `ec2:Owner = amazon` AND `ec2:InstanceType` StringEquals `t3.medium`\|`t3.large`\|`t3.xlarge` — **`ec2:Owner` lives on this statement only** (§11.6, corrected 2026-07-26 — see below) |
| 9b | `RunInstances` — supporting resources (`DevRunInstancesSupportingResources`) | `ec2:RunInstances` | `instance/*`, `volume/*`, `network-interface/*`, `subnet/*`, `security-group/*` (account/region-scoped) | `aws:RequestedRegion = ap-south-1` AND `ec2:InstanceType` StringEquals `t3.medium`\|`t3.large`\|`t3.xlarge` — **no `ec2:Owner` condition** (that key is AMI-specific, not meaningful for these five non-AMI resource types) |
| 9c | `RunInstances` tag-on-create (`DevRunInstancesTagOnCreate`) | `ec2:CreateTags` (not `ec2:RunInstances` itself — a separate statement, unaffected by the 9a/9b split) | `arn:aws:ec2:ap-south-1:<AWS_ACCOUNT_ID>:instance/*` | `ec2:CreateAction = RunInstances` AND `aws:RequestTag/Project = enterprise-data-platform` AND `aws:RequestTag/Environment = dev` — preserved unchanged by this correction |
| 10 | Instance lifecycle | `ec2:StartInstances`, `StopInstances`, `RebootInstances`, `TerminateInstances` | `arn:aws:ec2:ap-south-1:<AWS_ACCOUNT_ID>:instance/*` | `aws:ResourceTag/Project = enterprise-data-platform`, `aws:ResourceTag/Environment = dev` (**standardized 2026-07-26** from `ec2:ResourceTag` to the global `aws:ResourceTag` form, for consistency with rows 5b/6 — both keys are equally supported per AWS's EC2 Service Authorization Reference; non-functional change) |
| 11 | Instance metadata options | `ec2:ModifyInstanceMetadataOptions` | `arn:aws:ec2:ap-south-1:<AWS_ACCOUNT_ID>:instance/*` | `aws:ResourceTag/Project`, `aws:ResourceTag/Environment` (same as row 10, same standardization) |
| 12 | Workstation IAM role | `iam:CreateRole`, `GetRole`, `UpdateRole`, `UpdateAssumeRolePolicy`, `DeleteRole`, `TagRole`, `UntagRole`, `PutRolePolicy`, `GetRolePolicy`, `DeleteRolePolicy`, `ListRolePolicies`, `AttachRolePolicy`, `DetachRolePolicy`, `ListAttachedRolePolicies` | `arn:aws:iam::<AWS_ACCOUNT_ID>:role/enterprise-data-platform-dev-workstation-role` (exact ARN — IAM supports real resource-level restriction here) | `AttachRolePolicy`/`DetachRolePolicy` additionally conditioned on `iam:PolicyARN = arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore` |
| 13 | Workstation instance profile | `iam:CreateInstanceProfile`, `GetInstanceProfile`, `DeleteInstanceProfile`, `AddRoleToInstanceProfile`, `RemoveRoleFromInstanceProfile`, `TagInstanceProfile`, `UntagInstanceProfile` | `arn:aws:iam::<AWS_ACCOUNT_ID>:instance-profile/enterprise-data-platform-dev-workstation-role` (exact ARN) | none |
| 14 | `PassRole` | `iam:PassRole` | `arn:aws:iam::<AWS_ACCOUNT_ID>:role/enterprise-data-platform-dev-workstation-role` (exact ARN) | `iam:PassedToService = ec2.amazonaws.com` |

### 11.2 Proposed Complete IAM Policy JSON

**CORRECTED 2026-07-26, CORRECTED AGAIN 2026-07-26, then CORRECTED A THIRD TIME 2026-07-26** — this JSON now matches `bootstrap/main.tf`'s actual, corrected HCL exactly (`DevNetworkingCreateManage`/`DevNetworkingCreateManageTaggedOnCreate` replaced by `DevNetworkingCreateTaggedOnly`/`DevNetworkingManageTaggedResourceOnly`; `DevSecurityGroupEgressRulesOnly` gained resource-tag conditions; `DevInstanceLifecycleTaggedOnly`/`DevInstanceMetadataOptionsTaggedOnly` standardized from `ec2:ResourceTag` to `aws:ResourceTag`; `DevRunInstances` replaced by `DevRunInstancesAmi`/`DevRunInstancesSupportingResources`, moving `ec2:Owner` onto the AMI-only statement; `ec2:DescribeVpcAttribute` added to `DevReadOnlyDescribe`; **`DevNetworkingCreateTaggedOnly` replaced by 8 statements (`DevCreateVpcTaggedOnly`, `DevCreateInternetGatewayTaggedOnly`, and a new-resource/existing-parent-VPC pair each for `CreateSubnet`/`CreateRouteTable`/`CreateSecurityGroup`) and `DevTagging` replaced by 2 statements (`DevTaggingOnApprovedCreateActions`, `DevTaggingManageTaggedResourceOnly`), fixing a real second partial `environments/dev` apply failure**) — see §11.1's row 5/5b/5c-5j/7a-7b and row 9a-9c notes and §11.3/§11.6 for the full rationale. No real account ID, bucket name, or ARN appears below — every account-specific value is a placeholder (`<AWS_ACCOUNT_ID>`, `<STATE_BUCKET_NAME>`), consistent with every other placeholder already used throughout this plan and in `bootstrap/`'s own committed `.example` files. **Statement count is now 26, not 18.**

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DevStateListBucket",
      "Effect": "Allow",
      "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::<STATE_BUCKET_NAME>",
      "Condition": {
        "StringLike": {
          "s3:prefix": [
            "dev/terraform.tfstate",
            "dev/terraform.tfstate.tflock"
          ]
        }
      }
    },
    {
      "Sid": "DevStateBucketMetadataRead",
      "Effect": "Allow",
      "Action": [
        "s3:GetBucketLocation",
        "s3:GetBucketVersioning"
      ],
      "Resource": "arn:aws:s3:::<STATE_BUCKET_NAME>"
    },
    {
      "Sid": "DevStateObjectReadWrite",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject"
      ],
      "Resource": "arn:aws:s3:::<STATE_BUCKET_NAME>/dev/terraform.tfstate"
    },
    {
      "Sid": "DevStateLockObjectManage",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject"
      ],
      "Resource": "arn:aws:s3:::<STATE_BUCKET_NAME>/dev/terraform.tfstate.tflock"
    },
    {
      "Sid": "DevCreateVpcTaggedOnly",
      "Effect": "Allow",
      "Action": "ec2:CreateVpc",
      "Resource": "arn:aws:ec2:ap-south-1:<AWS_ACCOUNT_ID>:vpc/*",
      "Condition": {
        "StringEquals": {
          "aws:RequestedRegion": "ap-south-1",
          "aws:RequestTag/Project": "enterprise-data-platform",
          "aws:RequestTag/Environment": "dev"
        }
      }
    },
    {
      "Sid": "DevCreateInternetGatewayTaggedOnly",
      "Effect": "Allow",
      "Action": "ec2:CreateInternetGateway",
      "Resource": "arn:aws:ec2:ap-south-1:<AWS_ACCOUNT_ID>:internet-gateway/*",
      "Condition": {
        "StringEquals": {
          "aws:RequestedRegion": "ap-south-1",
          "aws:RequestTag/Project": "enterprise-data-platform",
          "aws:RequestTag/Environment": "dev"
        }
      }
    },
    {
      "Sid": "DevCreateSubnetNewResourceTaggedOnly",
      "Effect": "Allow",
      "Action": "ec2:CreateSubnet",
      "Resource": "arn:aws:ec2:ap-south-1:<AWS_ACCOUNT_ID>:subnet/*",
      "Condition": {
        "StringEquals": {
          "aws:RequestedRegion": "ap-south-1",
          "aws:RequestTag/Project": "enterprise-data-platform",
          "aws:RequestTag/Environment": "dev"
        }
      }
    },
    {
      "Sid": "DevCreateSubnetExistingVpcTaggedOnly",
      "Effect": "Allow",
      "Action": "ec2:CreateSubnet",
      "Resource": "arn:aws:ec2:ap-south-1:<AWS_ACCOUNT_ID>:vpc/*",
      "Condition": {
        "StringEquals": {
          "aws:RequestedRegion": "ap-south-1",
          "aws:ResourceTag/Project": "enterprise-data-platform",
          "aws:ResourceTag/Environment": "dev"
        }
      }
    },
    {
      "Sid": "DevCreateRouteTableNewResourceTaggedOnly",
      "Effect": "Allow",
      "Action": "ec2:CreateRouteTable",
      "Resource": "arn:aws:ec2:ap-south-1:<AWS_ACCOUNT_ID>:route-table/*",
      "Condition": {
        "StringEquals": {
          "aws:RequestedRegion": "ap-south-1",
          "aws:RequestTag/Project": "enterprise-data-platform",
          "aws:RequestTag/Environment": "dev"
        }
      }
    },
    {
      "Sid": "DevCreateRouteTableExistingVpcTaggedOnly",
      "Effect": "Allow",
      "Action": "ec2:CreateRouteTable",
      "Resource": "arn:aws:ec2:ap-south-1:<AWS_ACCOUNT_ID>:vpc/*",
      "Condition": {
        "StringEquals": {
          "aws:RequestedRegion": "ap-south-1",
          "aws:ResourceTag/Project": "enterprise-data-platform",
          "aws:ResourceTag/Environment": "dev"
        }
      }
    },
    {
      "Sid": "DevCreateSecurityGroupNewResourceTaggedOnly",
      "Effect": "Allow",
      "Action": "ec2:CreateSecurityGroup",
      "Resource": "arn:aws:ec2:ap-south-1:<AWS_ACCOUNT_ID>:security-group/*",
      "Condition": {
        "StringEquals": {
          "aws:RequestedRegion": "ap-south-1",
          "aws:RequestTag/Project": "enterprise-data-platform",
          "aws:RequestTag/Environment": "dev"
        }
      }
    },
    {
      "Sid": "DevCreateSecurityGroupExistingVpcTaggedOnly",
      "Effect": "Allow",
      "Action": "ec2:CreateSecurityGroup",
      "Resource": "arn:aws:ec2:ap-south-1:<AWS_ACCOUNT_ID>:vpc/*",
      "Condition": {
        "StringEquals": {
          "aws:RequestedRegion": "ap-south-1",
          "aws:ResourceTag/Project": "enterprise-data-platform",
          "aws:ResourceTag/Environment": "dev"
        }
      }
    },
    {
      "Sid": "DevNetworkingManageTaggedResourceOnly",
      "Effect": "Allow",
      "Action": [
        "ec2:ModifyVpcAttribute",
        "ec2:DeleteVpc",
        "ec2:ModifySubnetAttribute",
        "ec2:DeleteSubnet",
        "ec2:AttachInternetGateway",
        "ec2:DetachInternetGateway",
        "ec2:DeleteInternetGateway",
        "ec2:CreateRoute",
        "ec2:ReplaceRoute",
        "ec2:DeleteRoute",
        "ec2:AssociateRouteTable",
        "ec2:DisassociateRouteTable",
        "ec2:ReplaceRouteTableAssociation",
        "ec2:DeleteRouteTable",
        "ec2:DeleteSecurityGroup"
      ],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "aws:RequestedRegion": "ap-south-1",
          "aws:ResourceTag/Project": "enterprise-data-platform",
          "aws:ResourceTag/Environment": "dev"
        }
      }
    },
    {
      "Sid": "DevSecurityGroupEgressRulesOnly",
      "Effect": "Allow",
      "Action": [
        "ec2:AuthorizeSecurityGroupEgress",
        "ec2:RevokeSecurityGroupEgress"
      ],
      "Resource": "arn:aws:ec2:ap-south-1:<AWS_ACCOUNT_ID>:security-group/*",
      "Condition": {
        "StringEquals": {
          "aws:RequestedRegion": "ap-south-1",
          "aws:ResourceTag/Project": "enterprise-data-platform",
          "aws:ResourceTag/Environment": "dev"
        }
      }
    },
    {
      "Sid": "DevTaggingOnApprovedCreateActions",
      "Effect": "Allow",
      "Action": "ec2:CreateTags",
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "ec2:CreateAction": [
            "CreateVpc",
            "CreateSubnet",
            "CreateInternetGateway",
            "CreateRouteTable",
            "CreateSecurityGroup"
          ],
          "aws:RequestedRegion": "ap-south-1",
          "aws:RequestTag/Project": "enterprise-data-platform",
          "aws:RequestTag/Environment": "dev"
        }
      }
    },
    {
      "Sid": "DevTaggingManageTaggedResourceOnly",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateTags",
        "ec2:DeleteTags"
      ],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "aws:RequestedRegion": "ap-south-1",
          "aws:ResourceTag/Project": "enterprise-data-platform",
          "aws:ResourceTag/Environment": "dev"
        }
      }
    },
    {
      "Sid": "DevReadOnlyDescribe",
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeVpcs",
        "ec2:DescribeVpcAttribute",
        "ec2:DescribeSubnets",
        "ec2:DescribeInternetGateways",
        "ec2:DescribeRouteTables",
        "ec2:DescribeSecurityGroups",
        "ec2:DescribeSecurityGroupRules",
        "ec2:DescribeInstances",
        "ec2:DescribeInstanceAttribute",
        "ec2:DescribeInstanceTypes",
        "ec2:DescribeInstanceCreditSpecifications",
        "ec2:DescribeImages",
        "ec2:DescribeAvailabilityZones",
        "ec2:DescribeTags",
        "ec2:DescribeVolumes",
        "ec2:DescribeAccountAttributes"
      ],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "aws:RequestedRegion": "ap-south-1"
        }
      }
    },
    {
      "Sid": "DevRunInstancesAmi",
      "Effect": "Allow",
      "Action": "ec2:RunInstances",
      "Resource": "arn:aws:ec2:ap-south-1::image/*",
      "Condition": {
        "StringEquals": {
          "aws:RequestedRegion": "ap-south-1",
          "ec2:Owner": "amazon",
          "ec2:InstanceType": [
            "t3.medium",
            "t3.large",
            "t3.xlarge"
          ]
        }
      }
    },
    {
      "Sid": "DevRunInstancesSupportingResources",
      "Effect": "Allow",
      "Action": "ec2:RunInstances",
      "Resource": [
        "arn:aws:ec2:ap-south-1:<AWS_ACCOUNT_ID>:instance/*",
        "arn:aws:ec2:ap-south-1:<AWS_ACCOUNT_ID>:volume/*",
        "arn:aws:ec2:ap-south-1:<AWS_ACCOUNT_ID>:network-interface/*",
        "arn:aws:ec2:ap-south-1:<AWS_ACCOUNT_ID>:subnet/*",
        "arn:aws:ec2:ap-south-1:<AWS_ACCOUNT_ID>:security-group/*"
      ],
      "Condition": {
        "StringEquals": {
          "aws:RequestedRegion": "ap-south-1",
          "ec2:InstanceType": [
            "t3.medium",
            "t3.large",
            "t3.xlarge"
          ]
        }
      }
    },
    {
      "Sid": "DevRunInstancesTagOnCreate",
      "Effect": "Allow",
      "Action": "ec2:CreateTags",
      "Resource": "arn:aws:ec2:ap-south-1:<AWS_ACCOUNT_ID>:instance/*",
      "Condition": {
        "StringEquals": {
          "ec2:CreateAction": "RunInstances",
          "aws:RequestTag/Project": "enterprise-data-platform",
          "aws:RequestTag/Environment": "dev"
        }
      }
    },
    {
      "Sid": "DevInstanceLifecycleTaggedOnly",
      "Effect": "Allow",
      "Action": [
        "ec2:StartInstances",
        "ec2:StopInstances",
        "ec2:RebootInstances",
        "ec2:TerminateInstances"
      ],
      "Resource": "arn:aws:ec2:ap-south-1:<AWS_ACCOUNT_ID>:instance/*",
      "Condition": {
        "StringEquals": {
          "aws:ResourceTag/Project": "enterprise-data-platform",
          "aws:ResourceTag/Environment": "dev"
        }
      }
    },
    {
      "Sid": "DevInstanceMetadataOptionsTaggedOnly",
      "Effect": "Allow",
      "Action": "ec2:ModifyInstanceMetadataOptions",
      "Resource": "arn:aws:ec2:ap-south-1:<AWS_ACCOUNT_ID>:instance/*",
      "Condition": {
        "StringEquals": {
          "aws:ResourceTag/Project": "enterprise-data-platform",
          "aws:ResourceTag/Environment": "dev"
        }
      }
    },
    {
      "Sid": "DevWorkstationRoleManage",
      "Effect": "Allow",
      "Action": [
        "iam:CreateRole",
        "iam:GetRole",
        "iam:UpdateRole",
        "iam:UpdateAssumeRolePolicy",
        "iam:DeleteRole",
        "iam:TagRole",
        "iam:UntagRole",
        "iam:PutRolePolicy",
        "iam:GetRolePolicy",
        "iam:DeleteRolePolicy",
        "iam:ListRolePolicies",
        "iam:ListAttachedRolePolicies"
      ],
      "Resource": "arn:aws:iam::<AWS_ACCOUNT_ID>:role/enterprise-data-platform-dev-workstation-role"
    },
    {
      "Sid": "DevWorkstationRolePolicyAttachApprovedOnly",
      "Effect": "Allow",
      "Action": [
        "iam:AttachRolePolicy",
        "iam:DetachRolePolicy"
      ],
      "Resource": "arn:aws:iam::<AWS_ACCOUNT_ID>:role/enterprise-data-platform-dev-workstation-role",
      "Condition": {
        "StringEquals": {
          "iam:PolicyARN": "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
        }
      }
    },
    {
      "Sid": "DevWorkstationInstanceProfileManage",
      "Effect": "Allow",
      "Action": [
        "iam:CreateInstanceProfile",
        "iam:GetInstanceProfile",
        "iam:DeleteInstanceProfile",
        "iam:AddRoleToInstanceProfile",
        "iam:RemoveRoleFromInstanceProfile",
        "iam:TagInstanceProfile",
        "iam:UntagInstanceProfile"
      ],
      "Resource": "arn:aws:iam::<AWS_ACCOUNT_ID>:instance-profile/enterprise-data-platform-dev-workstation-role"
    },
    {
      "Sid": "DevPassWorkstationRoleToEC2Only",
      "Effect": "Allow",
      "Action": "iam:PassRole",
      "Resource": "arn:aws:iam::<AWS_ACCOUNT_ID>:role/enterprise-data-platform-dev-workstation-role",
      "Condition": {
        "StringEquals": {
          "iam:PassedToService": "ec2.amazonaws.com"
        }
      }
    }
  ]
}
```

### 11.3 Explanation of Every `Resource = "*"` Entry

**Revised 2026-07-26** to reflect the corrected row 5/5b split. Two categories of statement above use `Resource = "*"`, for two materially different reasons — one a genuine AWS platform limit, the other a deliberate scoping choice this correction made rather than attempting an unverified specific-ARN pattern:

1. **`DevNetworkingCreateTaggedOnly` (row 5) — genuinely unavoidable.** The 5 pure EC2 **creation** actions (`CreateVpc`, `CreateSubnet`, `CreateInternetGateway`, `CreateRouteTable`, `CreateSecurityGroup`) **cannot** support resource-level ARN restriction in AWS IAM, full stop — the resource doesn't exist yet at the moment permission is evaluated, so there is no ARN to restrict `Resource` to. The mitigation actually available is used: `aws:RequestedRegion = ap-south-1` (confines blast radius to one region) plus `aws:RequestTag/Project`/`aws:RequestTag/Environment` (confirmed-supported for all 5 actions against AWS's own EC2 Service Authorization Reference, fetched during the 2026-07-26 correction) — and, critically, **these 5 actions now appear in no other statement in this policy**, so the tag condition cannot be bypassed via an overlapping, untagged grant elsewhere (the bypass this correction fixed).
2. **`DevNetworkingManageTaggedResourceOnly` (row 5b) and `DevReadOnlyDescribe` (row 8) — `Resource = "*"` retained, but for different reasons.** Row 5b's 15 modify/delete/attach/associate actions operate on an **already-existing** vpc/subnet/internet-gateway/route-table/security-group resource — per the AWS reference checked during the 2026-07-26 correction, several of these genuinely do support resource-level ARN restriction in principle (they act on a specific, already-existing resource whose ARN is knowable). This correction did **not** attempt to narrow `Resource` to a specific ARN pattern for row 5b, since the exact ARN syntax per resource type was not independently verified as part of this task and getting it wrong risks either a rejected policy or a silently-ineffective one — narrowing this further, with proper per-action ARN verification, remains a legitimate future tightening opportunity (§11.6), not something this correction claims to have already done. Instead, row 5b relies on `aws:ResourceTag/Project`/`aws:ResourceTag/Environment` — confirmed supported for `CreateRoute`, `DeleteSubnet`, `DeleteInternetGateway`, `DeleteRoute`, `DeleteRouteTable`, `AssociateRouteTable`, `AttachInternetGateway` directly against the AWS reference, and for `DisassociateRouteTable` via a secondary source citing that same reference; the remaining 7 actions (`DeleteVpc`, `ModifyVpcAttribute`, `ModifySubnetAttribute`, `DetachInternetGateway`, `ReplaceRoute`, `ReplaceRouteTableAssociation`, `DeleteSecurityGroup`) were not individually confirmed in this pass (the reference page is far larger than could be fetched in one pass) and are included on the strength of an exact-resource-type sibling pattern with zero observed exceptions — flagged here, not silently asserted, and pending independent re-confirmation before this policy is applied for real. `DevReadOnlyDescribe`'s wildcard remains the genuine, unconditional AWS platform limit already documented (Describe* actions never support resource-level restriction, full stop) — unchanged by this correction except for the newly-added `aws:RequestedRegion` condition, a universal global condition key unrelated to resource-level restriction capability.

Every other statement in this policy (rows 3, 4, 6, 9's resource-typed subset, 10-14 of the matrix) uses a real, specific resource ARN or ARN pattern — the wildcards above are the genuine, documented limit of AWS IAM's own capability for this action set (row 5) or a deliberate, explained scoping choice (row 5b/8), not a default fallen back to for convenience.

### 11.4 Permissions That Remain Human-Only

The following are **never** granted to the deployment role, by design, regardless of what `environments/dev` needs to create:

- **`ssm:StartSession` and any other Session Manager session-user permission.** Creating the workstation instance and its instance profile (which is what the deployment role does) is a distinct concern from *who is allowed to open an interactive session against it once it exists* (§11.5 below) — the latter is an operator-facing permission granted separately, to human IAM identities, and is never part of the deployment role's own policy.
- **Any action against `bootstrap/terraform.tfstate`, the state bucket's own hardening configuration (versioning, encryption, public-access-block, bucket policy), or the deployment role's own trust/permissions.** The deployment role's job is managing `environments/dev`; it has no legitimate reason to read, write, or reconfigure the bootstrap resources that define its own existence — granting that would be exactly the self-referential blast-radius expansion this project's bootstrap-management-model decision (`PROJECT_EXECUTION_JOURNAL.md` Section 14) already rejected once.
- **Creating or managing a real `backend.hcl`/`terraform.tfvars` file** — an operational, human action (placing real values into a gitignored file on a machine), not an IAM permission at all, but worth naming here since it's a genuinely human-only step in the overall workflow.

### 11.5 Permissions Added Only in Bootstrap Update 2

**Exactly one change happens in Bootstrap Update 2 (Stage C, §12), and it is not a new *permission* at all — it is a *trust-policy* addition.** The deployment role's **permissions** policy (§11.2 above) is not modified by Update 2 in any way; only its **trust** policy changes, gaining a second statement that allows the (by-then-real) workstation role to assume it (§12). This distinction matters: someone reviewing "what new access does Update 2 grant" should understand that it grants no new *capability* to whoever holds the role — it only changes *who* (human identity vs. workstation role) is allowed to hold it. If a future genuine need arises to expand the deployment role's actual permissions (e.g., §13's deferred CloudWatch Logs/artifact-bucket access once a concrete target exists), that would be a separate, third, explicitly reviewed change — not something bundled into Update 2.

### 11.6 Residual Risks and Future Tightening Opportunities

**RESOLVED 2026-07-26 (previously the top item in this section):** *"A compromised deployment-role session could still create/tag arbitrary EC2 networking resources... the tag-on-create conditions constrain what gets tagged... but don't prevent creating an untagged VPC/subnet/etc."* — this was true because `DevNetworkingCreateManage` granted the same 5 create actions **without** any tag condition, alongside `DevNetworkingCreateManageTaggedOnCreate`'s tagged grant of the same actions; since IAM `Allow` statements are additive, the untagged grant made the tagged one's condition unenforceable, so an untagged `CreateVpc`/`CreateSubnet`/etc. really could succeed. This was found during the first real local validation gate's manual IAM review and corrected the same day: the 5 create actions now appear in exactly one statement, `DevNetworkingCreateTaggedOnly`, with no untagged alternative anywhere in the policy — the tag condition can no longer be bypassed for these actions. See §11.1 row 5/5b and §11.3 for the corrected design.

- **`RunInstances`' resource list still includes `instance/*`** (and several other `/*` entries) because AWS cannot scope a creation call to a not-yet-existing resource ID — mitigated by the `ec2:InstanceType` condition (§11.1 row 9b, present on `DevRunInstancesSupportingResources` only as of the 2026-08-04 correction below) and `ec2:Owner` (§11.1 row 9a, present only on the AMI statement), which are real, enforced restrictions even though the resource ARNs themselves remain wildcarded within account/region.
- **RESOLVED 2026-07-26 (deployed-v1-policy review):** *the single `DevRunInstances` statement applied `ec2:Owner = amazon` across a `Resource` list that mixed the AMI resource type with five non-AMI resource types* — this was a real condition-scoping defect: `ec2:Owner` is meaningful only for the AMI being launched from, not for the instance/volume/network-interface/subnet/security-group resources the same `RunInstances` call also references, so applying it across all six resource types in one statement scoped the condition more broadly than the key is meant to apply to. Found during a review of the deployed-but-not-yet-applied v1 policy and corrected by splitting into `DevRunInstancesAmi` (AMI only, carries `ec2:Owner`) and `DevRunInstancesSupportingResources` (the five non-AMI types, no `ec2:Owner`) — see §11.1 rows 9a-9c. This is a source correction only; the corrected policy has not yet been planned or applied.
- **RESOLVED 2026-08-04 (real `--dry-run` denial, confirmed deployed defect — corrects two prior claims in this project's own record):** a real `ec2:RunInstances --dry-run` request under the confirmed deployment-role session was denied with `UnauthorizedOperation` on the AMI resource (`--dry-run` created no resource). Root cause: `DevRunInstancesAmi` carried a `StringEquals` condition on `ec2:InstanceType` — an instance-resource condition key, not populated during AMI-side authorization — so the entire statement failed to match. This corrects two things this document and `PROJECT_EXECUTION_JOURNAL.md` had previously stated: that the `DevRunInstancesAmi` diagnostic-condition restoration (§9 of this document's status block, historical) had closed the investigation, and that `ec2:InstanceType` on the AMI statement was a harmless, conservative inclusion — neither was accurate. **Corrected** in `bootstrap/main.tf`: the `ec2:InstanceType` condition removed from `DevRunInstancesAmi` entirely; `ec2:Owner`/`aws:RequestedRegion` unchanged on that statement; `ec2:InstanceType` remains fully enforced, unchanged, on `DevRunInstancesSupportingResources` — the cleaner least-privilege design of placing a condition key only on the resource type it actually applies to, rather than attaching it everywhere and relying on AWS silently ignoring it where unsupported. Source correction only, structurally verified (hcl2 parse, brace count 188/188, statement count unchanged at 30, condition count 59 from 60) — not yet planned or applied at the time this entry was first written. **RESOLVED 2026-08-04: a fresh `aws ec2 run-instances --dry-run` under the confirmed deployment-role session against the approved launch path returned `DryRunOperation: Request would have succeeded, but DryRun flag is set.`** — no EC2 resource created, confirming the fix. This was the last open IAM-related validation item in this project; it is now closed. Full record: `PROJECT_EXECUTION_JOURNAL.md` Sections 27aj/27ak.
- **The five `Create*` networking actions and `CreateTags`/`DeleteTags` remain account-region-wide** (`Resource = "*"`, region-scoped only) because AWS IAM offers no finer control for them (§11.3). If AWS ever extends resource-level support to these actions in the future, tightening this policy to match would be a natural, low-risk follow-up — worth revisiting periodically, not assumed permanent.
- **`DevTagging` (`ec2:CreateTags`/`DeleteTags`) remains deliberately untagged-condition** (region-scoped only), reviewed and kept broad on 2026-07-26 specifically because narrowing it risks breaking Terraform's own legitimate tag-reconciliation calls against a resource whose tags are mid-correction — a genuine, accepted trade-off, not an oversight.
- **`DevNetworkingManageTaggedResourceOnly`'s `Resource = "*"` was not narrowed to per-action-type ARNs** even though several of its 15 actions likely support that narrowing per AWS's own reference — this correction relied on `aws:ResourceTag` conditions instead of also attempting resource-level ARN restriction, since the exact ARN syntax per EC2 resource type was not independently verified as part of this pass. A future tightening pass could add resource-typed ARNs (e.g., `arn:aws:ec2:ap-south-1:<AWS_ACCOUNT_ID>:vpc/*`, `:subnet/*`, `:route-table/*`) alongside the existing tag conditions, once each action's exact resource-type support is confirmed — not adopted now, to avoid introducing an unverified restriction that could silently break legitimate reconcile/delete operations.
- **RESOLVED 2026-07-26 (second review pass):** all 15 of `DevNetworkingManageTaggedResourceOnly`'s actions' `aws:ResourceTag` support are now confirmed against AWS's official EC2 Service Authorization Reference. The 8 directly confirmed during the first correction pass — `CreateRoute`, `DeleteSubnet`, `DeleteInternetGateway`, `DeleteRoute`, `DeleteRouteTable`, `AssociateRouteTable`, `AttachInternetGateway`, `DisassociateRouteTable` — are unchanged. The remaining 7, previously flagged as pattern-inferred only — `DeleteVpc`, `ModifyVpcAttribute`, `ModifySubnetAttribute`, `DetachInternetGateway`, `ReplaceRoute`, `ReplaceRouteTableAssociation`, `DeleteSecurityGroup` — were reported confirmed by the user's own direct review of the current official AWS reference. **Attribution note:** this project's own sandbox fetch tool still could not independently re-retrieve these 7 entries when re-attempted during this same review pass (the reference page's size exceeds the tool's return limit and truncates before reaching them alphabetically) — this confirmation is recorded as user-reported reference evidence, not as an independently-repeated Claude fetch, consistent with this project's evidence-attribution discipline. No action in this statement remains on inference alone. **Also reviewed in the same pass:** whether the statement's `Resource = "*"` element represents every required ARN type for all 15 actions (`vpc*`, `subnet*`, `internet-gateway*`, `route-table*`, `security-group*`, including the dual-resource-type actions `AttachInternetGateway`/`DetachInternetGateway` and `AssociateRouteTable`/`DisassociateRouteTable`/`ReplaceRouteTableAssociation`) — a bare `"*"` wildcard trivially represents every type, so no missing-ARN-type gap exists and no source change was made to the `resources` element. Itemizing `resources` into per-type ARN patterns instead of `"*"` remains a distinct, NOT-yet-adopted future tightening option, unchanged from the bullet above.
- **`Describe*` actions are unconditionally account-wide** — acceptable because they are read-only, but worth remembering this role can enumerate *all* of the account's EC2/VPC resources (not just `environments/dev`'s own), even though it can only mutate the tagged, region-scoped subset described above. This is a visibility risk, not a mutation risk, and is consistent with how Terraform's own refresh cycle needs to work (it can't distinguish "resources it manages" from "resources that exist" without first describing broadly).
- **RESOLVED 2026-07-26 (second real partial-apply failure):** the single combined `DevNetworkingCreateTaggedOnly` statement applied `aws:RequestTag` conditions across `Resource = "*"` for `CreateVpc`/`CreateSubnet`/`CreateInternetGateway`/`CreateRouteTable`/`CreateSecurityGroup` — but `CreateSubnet`/`CreateRouteTable`/`CreateSecurityGroup` each authorize against TWO resources per call (the new resource, and the existing parent VPC), and `aws:RequestTag` has no value for the existing-parent-VPC side. A real `environments/dev` apply confirmed this: it created a replacement VPC and Internet Gateway successfully, then failed with `AccessDenied` on all three multi-resource-type actions against the parent VPC ARN. Corrected by splitting into 8 statements (§11.1 rows 5c-5j) — a single statement each for `CreateVpc`/`CreateInternetGateway` (no parent resource involved, confirmed via a real 2026-07-26 AWS reference fetch), and a new-resource (`aws:RequestTag`) / existing-parent-VPC (`aws:ResourceTag`) pair each for `CreateSubnet`/`CreateRouteTable`/`CreateSecurityGroup`. The same task also replaced the broad, untagged `DevTagging` statement with two narrower statements (§11.1 rows 7a-7b): create-time tagging restricted via `ec2:CreateAction` to the 5 approved non-`RunInstances` create actions (pattern-inferred against AWS's officially documented tag-on-create pattern and this policy's own already-working `RunInstances` precedent — **not independently reference-confirmed for these 5 actions specifically; the real AWS reference fetch attempted for this task reached `CreateTags`' resource-type table but did not show `ec2:CreateAction` listed against the vpc/subnet/internet-gateway/route-table/security-group rows, a result recorded as an inconclusive fetch given this project's already-documented reference-page truncation issue, not a confirmed absence**), and post-creation tag management restricted via `aws:ResourceTag`. Tag enforcement is preserved throughout both corrections — no untagged path exists anywhere in the policy for any of these actions.
- **NEW RISK, flagged 2026-07-26, NOT yet checked against real AWS:** this restructuring added 10 net new statements to `deployment_dev_permissions` (18 → 26). AWS customer-managed IAM policies have a default size quota (commonly 6,144 non-whitespace characters per policy version, adjustable via a service-quota increase). This project's own sandbox cannot compile real Terraform-rendered JSON or call the AWS API to measure the actual compiled policy size, and an approximate, non-authoritative Python-based estimate produced during this task was inconsistent with the fact that the prior 18-statement version was already applied successfully in real AWS — that estimate is therefore not reported as reliable evidence and is not treated as a confirmed problem. This must be checked for real as part of the recovery sequence's plan review (creating and reviewing the new Bootstrap Update 1 plan) and, if the policy does turn out to be oversized, resolved via a follow-up, separately reviewed change (e.g., splitting `deployment_dev_permissions` into multiple managed policies attached to the same role, which IAM supports) — not by silently reducing tag enforcement or condition granularity to save space.
- **RESOLVED 2026-07-26 (first real partial-apply failure):** `DevReadOnlyDescribe` was originally missing `ec2:DescribeVpcAttribute` — a read-only action the AWS provider calls internally while waiting for `aws_vpc`'s `enable_dns_hostnames`/`enable_dns_support` attributes to finish propagating. This was not caught by design review or static analysis, since it only surfaces as a real `AccessDenied` during an actual `apply`'s post-create wait step — the first real `environments/dev` apply hit exactly this, partway through, after already creating the workstation IAM role/attachment/instance profile and starting VPC creation. Corrected by adding the action to `DevReadOnlyDescribe`'s existing list (§11.1 row 8) — same `Resource = "*"`, same `aws:RequestedRegion` condition, no other statement touched. **Lesson for future permission-scoping work on this project:** provider-internal calls made while waiting for a resource attribute to propagate are easy to miss in a matrix built from the resource's own explicit `CRUD` actions alone — they only surface via a real `apply`, not via static review or `plan`.
- Future tightening could still explore AWS Organizations SCPs or a permissions boundary policy on the role itself as an additional layer — not adopted now, since this project has no AWS Organization in scope (`Terraform_Bootstrap_Design.md`).

## 12. How the Future Workstation Role Will Be Added to the Deployment-Role Trust Policy (Stage B / IAM Sequencing Stage C)

**Current state:** the deployment role's trust policy trusts **only** the human identity (with an MFA condition), per the bootstrap-management-model decision — the workstation role does not exist yet, so it cannot be trusted yet (`Terraform_Bootstrap_Design.md` §2 step 5, §22).

**Proposed change (Stage B, after Stage E produces a real workstation role):** a second, small, separate, reviewed `bootstrap/` apply adds the workstation role's real ARN (copied from `environments/dev`'s `workstation_role_arn` output, §7 — never retyped or guessed) as an **additional** trusted principal on the deployment role's trust policy, alongside the human identity. Concretely, in `bootstrap/variables.tf`, the (currently single-value, human-identity-only) trust input becomes a list (`trusted_principal_arns`), and `bootstrap/main.tf`'s trust-policy document gains a second statement:

- **The human-identity trust statement keeps its `aws:MultiFactorAuthPresent: true` condition** — unchanged, since a human interactive session can and should present MFA.
- **The workstation-role trust statement has no MFA condition** — an EC2 instance role obtained via instance metadata has no interactive MFA context to present; requiring one would make the workstation permanently unable to assume the role. The compensating controls are the workstation role's own narrow scope (§13), the deployment role's short max session duration (3600 seconds, unchanged from bootstrap), and CloudTrail-audited `AssumeRole` events (`Terraform_Bootstrap_Design.md` §23) — this was already the approved design, now simply implemented for real.

From this point forward, **routine `environments/dev` Terraform runs are expected to happen from the EC2 workstation itself** (once it exists and this trust update has landed), assuming the deployment role via `sts:AssumeRole` using its own instance-profile credentials — no MFA needed for that path, since it's the workstation role's statement being exercised, not the human identity's. The human identity's direct use of the deployment role (as required for Stages A–E, before the workstation exists) becomes the exception going forward, not the routine path — consistent with `Terraform_Bootstrap_Design.md` §2 step 6.

**A genuine implementation-time constraint worth flagging now, not glossed over:** Terraform's `assume_role` provider block does not itself prompt for an MFA token code. For Stages A–E (run by the human identity, whose trust statement *does* require MFA), the practical mechanism is **not** an `assume_role` block in `bootstrap/`'s own provider (bootstrap never assumes anything, §9) — it applies to `environments/dev`'s provider, which assumes the deployment role. Since the human identity must present MFA to assume that role, the realistic approach during this human-administered interim period is either (a) the human pre-authenticates via `aws sts assume-role --serial-number <mfa-arn> --token-code <code>` and exports the resulting temporary credentials as environment variables before invoking Terraform (so Terraform's own `assume_role` block in `providers.tf` is technically redundant during this phase and could be temporarily bypassed by already-assumed credentials), or (b) a named AWS CLI profile is configured locally with `role_arn`/`source_profile`/`mfa_serial`, letting the AWS SDK's credential chain handle the MFA prompt transparently when Terraform (via `AWS_PROFILE`) needs credentials. Neither approach requires any change to the committed Terraform code itself — `providers.tf`'s `assume_role` block is written once and works correctly for both the human-administered interim period and the eventual EC2-workstation-administered routine period, since MFA is a property of *how the identity is authenticated before Terraform runs*, not of the `assume_role` block's own configuration.

---

## 13. Workstation IAM Role Permissions

Per `modules/iam-workstation-role` (§7), the workstation role's permissions for this **first** implementation are deliberately narrower than the full scope described in `EC2_Development_Workstation.md` §13.1 — see §37–38 for the explicit, reasoned narrowing:

- **SSM core connectivity** — `AmazonSSMManagedInstanceCore` AWS-managed policy attachment. Required for Session Manager (§15) to function at all.
- **`sts:AssumeRole`, scoped to exactly `var.deployment_role_arn`** — no wildcard, no second role. This is the workstation role's only path to any infrastructure-management capability, per the two-role split (`IAM_and_Access.md`, `Terraform_Bootstrap_Design.md` §21).
- **Explicitly NOT included in this first implementation:** "minimal CloudWatch Logs write" and "narrowly scoped artifact access" — both listed as in-scope in `EC2_Development_Workstation.md` §13.1, but **deferred here** because neither has a concrete target yet (no CloudWatch Log Group exists to write to; no dev-artifact S3 bucket/prefix exists to scope access against). Granting either now would mean writing a permission against a resource that doesn't exist, or granting broader-than-necessary access (e.g., `logs:*` account-wide) just to have *something* — both of which violate the least-privilege principle this project applies consistently elsewhere. **Add both only when their concrete target exists**, as a small, separate, reviewed policy update to `modules/iam-workstation-role`, not now.
- **Explicitly excluded, unchanged from the design:** no direct EC2/VPC/IAM/Glue create-modify-delete permission on the workstation role itself; no `iam:CreateRole`/`iam:CreateUser`/`iam:CreateAccessKey` (no self-escalation path).

## 14. EC2 Instance Profile Design

One `aws_iam_instance_profile`, created inside `modules/iam-workstation-role` (§3.2), wrapping exactly the workstation role defined in the same module (1:1 relationship, no shared/multi-role instance profile). `modules/ec2-workstation` receives only the resulting `instance_profile_name` as an input variable and attaches it to the `aws_instance` via `iam_instance_profile` — it never constructs or reasons about the profile itself.

## 15. Session Manager Prerequisites

Per `EC2_Development_Workstation.md` §12, unchanged, now made concrete for this implementation:

- SSM Agent running on the instance — preinstalled on Amazon Linux 2023, no separate installation step needed.
- Outbound reachability to the `ssm`, `ssmmessages`, `ec2messages` endpoints — satisfied by the public subnet + IGW design (§17–18); no VPC interface endpoints are created for this phase (consistent with the no-NAT/no-endpoints decision, §19).
- IAM-controlled access — governed by who can call `ssm:StartSession` against this instance (a human-identity/IAM concern outside this Terraform configuration's own resources — not created here, since it depends on which human identities should have that permission, an operational decision, not an infrastructure one).
- The workstation role itself needs no additional SSM-specific permission beyond the `AmazonSSMManagedInstanceCore` attachment already included (§13) — that managed policy covers what the *instance* needs to register with and respond to Session Manager; who is *allowed to start a session* is a separate IAM concern on the human/caller side.

## 16. Zero-Inbound Security-Group Design — FINALIZED (2026-07-26)

Per `EC2_Development_Workstation.md` §11, implemented inside `modules/ec2-workstation` (§3.2):

- **Zero inbound rules** — no `ingress` block of any kind. No rule for port 22, no rule for any development port, to any CIDR, including the operator's own IP. This holds regardless of the subnet being public (§17). This is unaffected by, and independent of, the outbound decision below — inbound and outbound are governed by entirely separate rule sets.
- **Unrestricted outbound access initially — REVISED 2026-07-26.** The prior draft proposed a single scoped HTTPS-only (443) egress rule; this is now revised to a single `egress` rule allowing all protocols and ports to `0.0.0.0/0` (`from_port = 0`, `to_port = 0`, `protocol = "-1"`), per explicit instruction. **Trade-off, documented rather than silently adopted:** unrestricted outbound means the instance can reach any destination on the internet on any port, which is a broader network-egress posture than the previously scoped 443-only rule — if the instance were ever compromised, unrestricted egress gives an attacker more exfiltration/command-and-control flexibility than a 443-only rule would. This is accepted for the current phase because (1) the workstation's actual toolchain needs vary (package managers, Git over SSH-alternative HTTPS, various API endpoints, potentially non-443 ports for specific tooling) and enumerating every port a developer might need in advance is impractical and would just get widened reactively anyway; (2) the primary security control this design relies on is the **zero-inbound** rule set, not a tightly scoped egress rule — nothing can *initiate* a connection to the instance regardless of what it's allowed to *initiate* outward; (3) tightening egress to a specific allow-list remains a documented, available future hardening step once the workstation's actual outbound traffic patterns are observed and a concrete allow-list can be derived from real usage rather than guessed in advance. This trade-off is also recorded in the **Decision Rationale** section (after §57).
- **No rule ever opens a database, Docker daemon, or Jupyter port to `0.0.0.0/0` for *inbound* traffic** — carried as a hard constraint from `08_Security/Security.md`, restated here since this is the first Terraform code that will actually implement it. This constraint is about inbound exposure specifically and is unaffected by the outbound-access revision above.

## 17. Public Subnet and Public IPv4 Design

One public subnet (`modules/vpc`), in a single Availability Zone selected dynamically (§20), with `map_public_ip_on_launch` **not** relied upon at the subnet level — instead, the instance itself sets `associate_public_ip_address = true` explicitly (`modules/ec2-workstation`), so the behavior is visible at the resource that actually needs it rather than implied by a subnet-wide default that could silently affect a future second instance in the same subnet. Per `EC2_Development_Workstation.md` §9–10: a public IP does **not** by itself create inbound accessibility — that is governed entirely by the security group (§16), which has zero inbound rules regardless of the instance's public-IP status.

## 18. Internet Gateway and Route-Table Design

One `aws_internet_gateway`, attached to the VPC; one public `aws_route_table` with a single `aws_route` (`0.0.0.0/0` → the IGW) and one `aws_route_table_association` binding the public subnet to that route table (`modules/vpc`, §7). No private route table is created in this phase, since no private subnet exists yet (§6).

## 19. No-NAT Trade-off

**Accepted, unchanged from `EC2_Development_Workstation.md` §9 and `AWS_Account_Preparation.md`.** The public-subnet/IGW model gives outbound reachability for package installation, GitHub, and container registries without provisioning a NAT Gateway (a genuine, non-trivial recurring cost) before any private-subnet workload actually needs one. The explicit costs of this trade-off, restated for this plan: (1) the workstation carries a public IPv4 address, which AWS bills hourly and which is a larger network-exposure surface *in principle* than a fully private instance — mitigated entirely by the zero-inbound security group (§16), not by network topology; (2) moving to the future private-subnet/NAT-or-endpoint hardened alternative (documented, not built) will itself cost NAT Gateway or VPC-endpoint charges instead — this is a trade of one cost/exposure profile for another, not a free upgrade, and is explicitly **not** part of this implementation.

## 20. Availability Zone Selection Strategy — FINALIZED

`data "aws_availability_zones" "available"` filtered to `state = "available"`, and the **first** AZ in the returned, provider-ordered list is selected for the single public subnet (`element(data.aws_availability_zones.available.names, 0)`), rather than hardcoding a literal AZ name (e.g., `"ap-south-1a"`). **Do not hardcode `ap-south-1a` or any other literal AZ name anywhere in this configuration** — this is standard Terraform practice, restated here as a hard requirement, not just a preference: AZ **names** (the `1a`/`1b`/`1c` suffixes) have **account-specific mappings** — the same suffix can correspond to a different physical AZ in a different AWS account, since AWS deliberately randomizes this mapping per account to spread load evenly across its infrastructure. Only AZ **IDs** (e.g., `aps1-az1`) are consistent across accounts, and even those aren't needed here since this design doesn't require pinning a *specific* AZ, only a *deterministic* one. Querying dynamically and picking a fixed index (always index 0 of a stable, alphabetically-ish ordered API response) avoids silently depending on an account-specific assumption that might not hold. **The selected AZ is exposed as a module output** (`availability_zone` in `modules/vpc/outputs.tf`, §7) specifically so the actual AZ in use is visible to anyone reviewing a `plan`/`apply`/`output`, rather than being an invisible internal detail of the module. A second AZ is not selected or reserved as a variable in this first implementation, since only one subnet is being created (§6); the module's `variables.tf` can accept an optional `availability_zone_override` for future flexibility, defaulting to `null` (use the dynamic lookup).

## 21. VPC and Subnet CIDR — FINALIZED (2026-07-26)

**FINALIZED in this revision (2026-07-26) — previously a blocking, unapproved proposal (§56.1); now resolved and moved to §56.2.** This is exactly the kind of "exact CIDR range" decision `Terraform_Bootstrap_Design.md` §30 explicitly deferred to this implementation plan; the specific values below are now settled:

```text
VPC CIDR:                         10.20.0.0/16   (65,536 addresses total)
Public subnet (AZ index 0):       10.20.1.0/24   (256 addresses)  -- created now
Reserved, NOT created:
  Private-application tier:       10.20.11.0/24  (256 addresses)
  Private-data tier:               10.20.21.0/24  (256 addresses)
```

**REVISED 2026-07-26 (TFLint finding, first local validation gate):** the reserved private-application and private-data ranges were originally modeled as two Terraform variables — `private_application_subnet_cidr_reserved` and `private_data_subnet_cidr_reserved` — in `environments/dev/variables.tf` (this section previously, inaccurately, described them as living in `modules/vpc/variables.tf`; they never did — flagged and corrected here per `CLAUDE.md` §4's rule against silently resolving documentation conflicts). TFLint correctly flagged both as unused: no `aws_subnet` resource, module call, local, or output ever consumed them, so they existed only as inert documentation dressed up as Terraform inputs. Both variables have been **removed from Terraform entirely** — no `aws_subnet` resource is created for either range, per `Terraform_Bootstrap_Design.md` §24 point 4, and the two CIDR values now live **only as prose/comments**, here and in `terraform.tfvars.example`'s comment block, not as any kind of Terraform-evaluated construct. See the **Decision Rationale** section (after §57) for the full reasoning behind the `/16` sizing, the `.1.0/24` public-subnet placement, and the `.11.0/24`/`.21.0/24` reserved-tier numbering — summarized here: the `/16` VPC leaves ample room for future growth without re-addressing anything already deployed; a dedicated custom CIDR (rather than reusing default-VPC-style ranges) avoids any collision with the account's default VPC; the octet-per-tier numbering (`.1` public, `.11` private-application, `.21` private-data) makes subnet segmentation immediately readable from the address alone; and `10.20.0.0/16` was chosen specifically because it falls outside the address ranges most home/office routers use by default (which cluster around `192.168.0.0/16` and, to a lesser extent, `10.0.0.0/24`–`10.0.255.0/24` and `172.16.0.0/12`), reducing the chance of a routing conflict for anyone connecting from a typical home network via Session Manager port-forwarding.

## 22. Amazon Linux 2023 AMI Lookup Strategy

**REVISED 2026-07-26 — moved from `modules/ec2-workstation` to `environments/dev` (the root module), per explicit instruction (§3.2).** Inside `environments/dev/main.tf`, a `data "aws_ami" "al2023"` block with `most_recent = true`, `owners = ["amazon"]`, and filters on `name` (`al2023-ami-2023.*-x86_64`), `architecture` (`x86_64`), `virtualization-type` (`hvm`), and `root-device-type` (`ebs`) — evaluated only when `var.ami_id_override` is `null` (the default). The resolved AMI ID is then passed into `modules/ec2-workstation` as its now-**required** `ami_id` input variable (no default, no internal fallback lookup inside the module itself).

**Why the root, not the module:** AMI selection is **region- and environment-specific** — the exact AMI ID that resolves from this filter set can differ across AWS regions and changes over time as AWS publishes new AL2023 builds, so it is not a static, "set once and forget" value the way most of the module's other inputs are. A decision with that kind of variability should be **visible directly in the root module's own `terraform plan` output** — a reviewer looking at `environments/dev`'s plan should be able to see exactly which AMI ID is about to be used without having to open `modules/ec2-workstation` separately to find where that decision is made. Keeping the lookup in the root also means the root, not the module, is the single place responsible for deciding "current AMI vs. pinned override" — the module's own interface stays simple: it always just uses whatever `ami_id` it's given.

This still means every `plan` picks up the current AL2023 AMI automatically (consistent with the disposable-workstation philosophy, §32), while still allowing a specific AMI ID to be pinned via `terraform.tfvars`'s `ami_id_override` if a known-good state ever needs to be reproduced deliberately — the override now lives at the root, matching where the lookup itself now lives.

## 23. x86_64 Enforcement

Enforced at two independent points, so a mismatch fails loudly rather than silently: (1) the AMI data source's `architecture = ["x86_64"]` filter (§22) ensures only an x86_64 AMI is ever selected; (2) `instance_type`'s allow-list validation (§24) is restricted to the `t3` family, which is inherently x86_64 (the ARM/Graviton equivalent is the separate `t4g` family — `t3` never refers to an ARM instance). No separate runtime assertion is needed beyond these two filters, since AWS itself would reject a mismatched AMI/instance-type pairing at `RunInstances` time regardless.

## 24. `t3.medium` Default Sizing

**FINALIZED in this revision (2026-07-26) — resolved, no longer an open decision.** `variable "instance_type" { type = string, default = "t3.medium" }`, with a `validation` block restricting the allowed set to exactly `["t3.medium", "t3.large", "t3.xlarge"]` (§25) — `t3.small` is deliberately **not** in the allow-list yet, per `EC2_Development_Workstation.md` §6's explicit "not adopted by default... not recommended as a starting point" — adding it later, if testing evidence supports it, is a small, separate, reviewed variable-validation change, not part of this implementation. This exact allow-list and default were explicitly requested and confirmed in this revision — no further review is required on this specific point before code creation (§56).

## 25. `t3.large` and `t3.xlarge` Temporary Override Strategy

**Not a separate Terraform mechanism** — a deliberate, temporary local edit to `terraform.tfvars` (`instance_type = "t3.large"` or `"t3.xlarge"`) for a specific known heavy session, applied, then reverted back to `"t3.medium"` in a follow-up `plan`/`apply` once the session is over (`EC2_Development_Workstation.md` §7's stop/modify/start discipline — Terraform's own `apply` handles the equivalent stop/change-type/start cycle when `instance_type` changes, since it's a value that forces replacement... actually forces an in-place update requiring a stop, not a replacement, for most instance families — confirmed at implementation time against the exact provider version, not asserted here). Because `terraform.tfvars` is gitignored (account-specific values), this override is a local, uncommitted, session-scoped choice, not a tracked code change — consistent with `t3.xlarge` being explicitly "not meant to run continuously" (§6 of the design doc).

## 26. 30 GiB Encrypted `gp3` Root Volume

`root_block_device { volume_type = "gp3", volume_size = 30, encrypted = true }` on the `aws_instance` resource (`modules/ec2-workstation`). Encryption uses the default AWS-managed `aws/ebs` KMS key (no customer-managed key, consistent with the project-wide SSE-S3/no-CMK cost-and-complexity posture already established for the state bucket, `Terraform_Bootstrap_Design.md` §9). Sizing and rationale unchanged from `EC2_Development_Workstation.md` §8.

## 27. IMDSv2 Enforcement — FINALIZED (2026-07-26)

```hcl
metadata_options {
  http_endpoint               = "enabled"
  http_tokens                 = "required"
  http_put_response_hop_limit = 1
  instance_metadata_tags      = "disabled"
}
```

on the `aws_instance` resource. **FINALIZED in this revision (2026-07-26)** — this was a new proposal in the original draft, not separately called out as already-approved in `EC2_Development_Workstation.md`; it is now confirmed as settled and removed from the pending-review list (§57). Enforcing IMDSv2 (token-required metadata requests) is a standard, low-cost AWS security hardening step that closes a known SSRF-to-credential-theft class of vulnerability, and this plan adopts it as the default for the workstation instance from day one, consistent with the project's general "least privilege, no unnecessary exposure" posture (`Standards.md`, `CLAUDE.md` §7). The `http_put_response_hop_limit = 1` setting is addressed separately in the **Decision Rationale** section (item 11, after §57) — in short, a hop limit of 1 keeps metadata responses local to the host itself (no proxy/container hop can retrieve them), which is sufficient for this workstation design since no containerized or proxied workload on the instance currently needs to reach the metadata service from more than one network hop away.

**`instance_metadata_tags = "disabled"` — finalized alongside the rest of this block.** This setting controls whether an instance's own tags are readable from inside the instance via the metadata service (`http://169.254.169.254/latest/meta-data/tags/instance`) — a convenience some tooling uses to self-configure based on its own tags, but also one more piece of information exposed to anything running on the instance that can reach the metadata endpoint. This project has no current tooling or bootstrap-script requirement (§29) that depends on reading instance tags from inside the instance itself — the bootstrap script's own configuration needs (project working directories, tool installation) don't vary by tag value. Consistent with this project's default-to-restrictive-unless-justified posture (already applied to the hop limit, §27, Decision Rationale item 11), this stays `disabled` unless a later, concrete requirement justifies enabling it — at which point enabling it is a one-line, reviewable change, not a default left open speculatively.

## 28. Detailed Monitoring Decision — FINALIZED

`monitoring = false` (basic 5-minute CloudWatch metrics, no additional cost) rather than `true` (detailed 1-minute metrics, small additional per-instance charge). Given the cost-conscious, single-developer framing already established (`EC2_Development_Workstation.md` §26, this account confirmed not Free-Tier-eligible), basic monitoring is finalized as the default for cost control; this can be revisited without any structural change (a one-line variable flip) if finer-grained metrics are genuinely needed later.

## 29. User Data / Bootstrap Script Strategy and Scope — FINALIZED (2026-07-26); UPDATED TO MATCH `bootstrap_workstation.sh` v1.1.0 (2026-08-04)

**Location, finalized: `infrastructure/terraform/scripts/bootstrap_workstation.sh`.** **The script itself is not created by this plan, and is not created by the same task that writes the Terraform code described elsewhere in this plan** — script authoring remains its own small, separate, later authoring-and-testing task (this document's own constraints explicitly exclude creating any script). What **is** finalized here, now, is the script's exact **scope** — what it may do, what it must never do, and its idempotency/logging/failure-handling/versioning requirements — so that when it is eventually authored, there is no ambiguity about its boundaries to re-litigate at that point.

**2026-08-04 update:** the script has since been authored (v1.0.0) and revised to v1.1.0, correcting three real problems found during review — hardcoded `ec2-user` assumptions that don't match this account's actual SSM Session Manager user (`ssm-user`), `uv` being installed in the wrong (root) user context, and a missing Terraform CLI installation. §29.1 and §29.1a below now reflect v1.1.0's actual, approved scope. No script content is repeated here beyond what's needed to keep this plan accurate — `bootstrap_workstation.sh` itself remains the authoritative source.

### 29.1 Permitted Scope — Workstation Prerequisites Only

The script may install and configure **only** the following categories, each a workstation *prerequisite*, never application logic or credentials:

- System package updates (e.g., `dnf update -y` or equivalent, applied non-interactively).
- `git`.
- GitHub CLI (`gh`) — installed only; **never authenticated** by the script (§29.2).
- `jq`.
- `unzip`.
- Common shell utilities reasonably needed for day-to-day development (`curl`, `tar`, `less`).
- Python tooling prerequisites (whatever `uv` itself needs present, if anything, on a fresh AL2023 image).
- `uv` (Python package/dependency manager, §31) — **installed for the resolved non-root workstation user, never for root** (§29.1a).
- Terraform CLI — **installed only, never invoked** (§29.1a); no Terraform command of any kind runs as part of the script (§29.2 item 7 remains unchanged and applies equally to this new step).
- Project working directories (e.g., creating an empty `~/projects` or equivalent directory structure, resolved under the workstation user's actual home directory, for the developer to later `git clone` into — **the script does not perform the clone itself**, §29.2).
- A bootstrap version marker and basic execution logging (§29.4).

### 29.1a Workstation-User Resolution and Terraform CLI Installation (added 2026-08-04, v1.1.0)

**Workstation-user resolution.** The script no longer assumes a hardcoded user or home directory (v1.0.0 incorrectly assumed `ec2-user`, which does not match this account's actual AL2023/SSM Session Manager environment). Instead:

- The target user is read from an environment variable, `WORKSTATION_USER`, defaulting to `ssm-user` when unset.
- The script verifies `WORKSTATION_USER` exists on the system (via the system user database) before doing anything else; it exits with an error and does not proceed if the user does not exist.
- The user's home directory and primary group are resolved from the system user database (not hardcoded, not guessed) and used for every subsequent user-scoped step (`uv` installation, the `~/projects` directory and its ownership).
- The script must be run with `sudo` (or as root); it exits immediately with an error if not, since user-database resolution and per-user installation both require root privileges.

**Terraform CLI installation.** A pinned version of the Terraform CLI is installed as a workstation prerequisite, on the same "tooling only, never invoked" basis as the GitHub CLI:

- Pinned version: **1.15.8** (no "latest" resolution, to keep installs reproducible).
- Source: the official HashiCorp release archive for that exact version (`terraform_1.15.8_linux_amd64.zip` from `releases.hashicorp.com`) — not a third-party mirror, not `curl | sh`.
- Integrity: the archive's SHA256 checksum is verified against HashiCorp's own published `SHA256SUMS` file for that release before the archive is used; installation aborts if the checksum does not match or cannot be found.
- Installation location: `/usr/local/bin/terraform`.
- Idempotency: if a `terraform` binary matching version 1.15.8 is already present, the download/verify/install steps are skipped on rerun (§29.3).
- Scope boundary unchanged: the script installs the `terraform` binary and stops there — it never runs `terraform init`, `plan`, `apply`, or any other Terraform subcommand (§29.2 item 7).

### 29.2 Explicit Prohibitions — What the Script Must Never Do

The script **must not**, under any circumstance:

1. **Contain any credential or token** — no API key, password, access key, or secret of any kind embedded in the script text.
2. **Perform GitHub authentication** — `gh auth login` remains a manual, interactive, per-developer step (§19 of the Decision Rationale, §14/§31 elsewhere) — the script installs `gh`, it never runs `gh auth login` or supplies any token to it.
3. **Clone a private repository** — cloning (of any repository, private or public) is a manual, post-boot developer action, not something `user_data` performs on the developer's behalf.
4. **Write AWS credentials anywhere** — no static access key, no credentials file, no environment variable containing a secret. The instance's only AWS identity is its instance-profile-derived, automatically-rotated credentials (§13, §14) — the script has no reason to ever touch AWS credentials directly.
5. **Assume the deployment role** — the deployment role is assumed only by Terraform's own provider/backend configuration (§9, §12), never by a shell script running as part of instance bootstrap. The bootstrap script's job is tool installation, not infrastructure management.
6. **Deploy application code** — no build step, no service start, no application-level configuration. This is a development-workstation bootstrap, not a deployment pipeline.
7. **Run `terraform apply`, or any Terraform command at all** — Terraform runs are a deliberate, human- (or later, workstation-role-)initiated action from an interactive shell (§9, IAM Sequencing), never something `user_data` triggers automatically at boot.
8. **Contain any account-specific ID or ARN** — no AWS account ID, no real role/bucket/resource ARN, no region-specific value beyond what's genuinely generic (the script should be reviewable and reusable without redaction, unlike this project's `.tf` files which reference real values only via variables).
9. **Depend on interactive input** — the script runs unattended as `user_data` at boot, with no human present to answer a prompt; every command must be fully non-interactive (`-y`/`--yes`/equivalent flags on every package-manager or installer invocation).
10. **Fail destructively when safely rerun** — see §29.3 (idempotency) for the concrete requirement this implies.

**Why these restrictions matter, stated once here rather than scattered:** `user_data` content is not a secret-storage location — it can appear in Terraform state and is retrievable from the instance's own metadata service by anything running on the instance (§19 of the Decision Rationale). A script that only ever installs generic, non-sensitive tooling has nothing in it worth protecting even if that visibility is exploited; a script that embedded a credential, performed authentication, or touched infrastructure would turn a routine visibility property into a real exposure. The prohibitions above exist to keep the script permanently in the "nothing sensitive here" category, not to be relaxed later without re-examining this reasoning.

### 29.3 Idempotency Requirement

The script must be **safe to re-run** on an already-configured instance without duplicating work, erroring, or leaving the instance in a worse state than before the rerun — this matters concretely because `user_data` can execute more than once in some recovery/replacement scenarios, and because a script that isn't safely rerunnable can't be manually re-invoked for debugging without first worrying about side effects. Concretely: package-manager installs (`dnf install -y ...`) are naturally idempotent and need no extra guard; any step that appends to a config file, creates a directory or user, or otherwise mutates state incrementally must explicitly check current state first (`grep -q ... || echo ... >>`, `[ -d "$DIR" ] || mkdir -p "$DIR"`, etc.) rather than assuming a fresh system on every run.

### 29.4 Logging Requirement

The script must log its own execution — at minimum, a timestamped start marker, a per-step success/failure indication, and a timestamped completion marker — written to a predictable, discoverable location (e.g., `/var/log/bootstrap_workstation.log` or the instance's own `cloud-init`/`user_data` output log, which AL2023 already captures by default). This is what makes §29.5's failure-handling requirement actually actionable: a script that fails silently, with no record of *which* step failed, defeats the purpose of having a version-controlled, reviewable script in the first place — the whole point is that failures should be diagnosable without guessing.

### 29.5 Failure-Handling Requirement

The script must fail loudly and stop, not silently continue past a broken step — concretely, this means running under `set -euo pipefail` (or the script's functional equivalent): exit immediately on any unhandled command failure (`-e`), treat unset variables as an error (`-u`), and propagate failure through piped commands rather than masking it (`-o pipefail`). A script that "successfully" reaches its completion marker having silently skipped a failed tool installation would be worse than one that stops and logs exactly where it failed — the former produces a workstation that looks bootstrapped but isn't, discoverable only much later when a missing tool causes a confusing downstream error.

### 29.6 Versioning Requirement

The script must write a **bootstrap version marker** as part of its execution (§29.1's last bullet) — a simple recorded value (e.g., a line in the log file, or a marker file such as `/etc/bootstrap_workstation_version`) identifying which version of the script actually ran on this instance. This matters for the disposable-workstation recovery model (§32): if the script is later revised, being able to tell, after the fact, exactly which version configured a given instance makes it possible to reason about what that instance actually has installed without re-deriving it from the script's current (possibly since-changed) content. The script itself is version-controlled in this repository (§2's directory tree) — the marker just makes that version traceable from the running instance itself, not only from the repository's own history.

### 29.7 Wiring Into `environments/dev` (Unchanged Mechanics)

Sequencing proposed: author and manually test the script against a throwaway instance (or a local container approximating AL2023) **before** Stage E's `apply`, then wire its content into `environments/dev/main.tf` via `file("${path.root}/../../scripts/bootstrap_workstation.sh")` (two levels up from `path.root` [`environments/dev` → `environments` → `terraform`], reflecting the script's finalized location inside `infrastructure/terraform/`; or `templatefile()` if any variable substitution is needed — though per §29.2 item 8, that substitution should never introduce an account-specific value into the script's own logic) as the `user_data` value passed into `modules/ec2-workstation`. Until the script exists, `environments/dev/main.tf` can pass an empty string or a minimal placeholder `user_data` (e.g., just enabling the SSM agent, which is already preinstalled and running by default on AL2023 regardless) — the instance is still fully usable via Session Manager and manual tool installation even before the full bootstrap script is wired in, so this is not a hard blocker for Stage E specifically, though it does block treating the workstation as fully accepted per `EC2_Development_Workstation.md`'s acceptance criteria (§56.1).

**2026-08-04 update: this acceptance-criteria gap is now closed.** `bootstrap_workstation.sh` v1.1.1 was run for real against the actual EC2 development workstation and completed successfully — AWS CLI, Git, GitHub CLI (install-only), Terraform v1.15.8 (checksum-verified), and `uv` (for `ssm-user`, not root) all confirmed present, the `/home/ssm-user/projects` directory created, and the version marker set to `1.1.1`. This is the first real-instance execution evidence for this script (prior evidence was source review and `bash -n` only). Full record: `PROJECT_EXECUTION_JOURNAL.md` Section 27ah.

## 30. Idempotent Bootstrap Requirements

**Superseded by §29.3, which states the same requirement with the full "why" attached — retained here only as a cross-reference for readers arriving via the original section index.** See §29.3 for the finalized, complete statement of this requirement, and §29.4–29.6 for the logging, failure-handling, and versioning requirements that accompany it.

## 31. GitHub CLI and `uv` Installation Strategy

Both installed by the bootstrap script (§29), not baked into a custom AMI (keeping the AMI lookup generic and always-current, §22): `gh` via its official package repository, `uv` via its official installer script. Neither tool's installation requires any credential to be embedded — GitHub authentication is deliberately **interactive**, per session (`gh auth login`, `EC2_Development_Workstation.md` §14), never baked into user data or the AMI; `uv` itself needs no authentication to install.

## 32. Disposable-Workstation Recovery Model

Unchanged from `EC2_Development_Workstation.md` §24: the instance is treated as replaceable, not precious. Because this Terraform configuration is the **source of truth for the instance's own definition**, the practical recovery path if the instance is lost/corrupted is: `terraform apply` again (idempotent — Terraform either finds the existing instance unchanged or, if it was actually terminated outside Terraform, creates a fresh one from the same AMI-lookup-and-bootstrap-script pattern), then re-clone the repository and re-authenticate `gh` (§31). No EBS-snapshot-based recovery is implemented as part of this Terraform configuration — snapshots remain a documented, optional convenience (§8 of the design doc), not something this plan's resources create or manage.

## 33. Shutdown and Cost-Control Procedure

**Manual only, for this implementation** — the user stops the instance via the AWS Console, AWS CLI, or Session Manager-adjacent tooling at the end of each session (`EC2_Development_Workstation.md` §22 "Phase 1"). No `aws_scheduler_schedule`/Lambda automatic-stop resource is created (§6, deferred). This Terraform configuration does not need to encode shutdown behavior at all — stopping an EC2 instance is an operational action, not a Terraform-managed resource state (Terraform does not need to run to stop or start an already-created instance).

## 34. Tagging and Naming

Applied exactly per `01_Architecture/Naming_Convention.md`, with `Environment = "dev"` (not `"shared"` — these are genuine dev-environment resources, unlike bootstrap's account-level resources):

| Resource | Name |
|---|---|
| VPC | `enterprise-data-platform-dev-vpc` |
| Public subnet | `enterprise-data-platform-dev-public-<az-suffix>` (suffix resolved from the selected AZ, §20) |
| Internet Gateway | `enterprise-data-platform-dev-igw` |
| Public route table | `enterprise-data-platform-dev-public-rt` |
| Security group | `enterprise-data-platform-dev-workstation-sg` |
| Workstation IAM role | `enterprise-data-platform-dev-workstation-role` |
| EC2 instance (`Name` tag) | `enterprise-data-platform-dev-workstation` |

All resources also carry the required tag set (`Project`, `Environment`, `ManagedBy = "terraform"`, `Owner = "DataEngAA"`, `CostCenter = "personal-learning"`, `DataClassification` — `"internal"` as the reasonable default for infrastructure resources, per `Naming_Convention.md`), applied via `locals.tf`'s common-tags map merged with any resource-specific tag (§7).

## 35. Variables and Outputs

Full per-file detail already given in §7's tables. Summarized conventions: all variable names `snake_case`; account-specific values (`aws_account_id`, `deployment_role_arn`, real CIDR values if ever made account-sensitive — they are not, §21) have **no default**, supplied only via gitignored `terraform.tfvars`; every output that a later, separate apply needs to reference (specifically `workstation_role_arn`, for Stage B, §12) is exposed explicitly and documented as to *why* it exists, not just *what* it is — matching bootstrap's own `outputs.tf` commenting style.

## 36. Data Sources

- `data "aws_availability_zones" "available"` (`modules/vpc`, §20).
- `data "aws_ami" "al2023"` (**REVISED 2026-07-26: now in `environments/dev/main.tf`, the root module — not `modules/ec2-workstation`**, §22, §3.2).
- `data "aws_iam_policy_document"` (×2, `modules/iam-workstation-role`: the role's own trust policy, and its `sts:AssumeRole` permission statement) — using policy-document data sources rather than inline JSON heredocs, consistent with Terraform best practice and with how `bootstrap/main.tf` already constructs its own trust policy.
- `data "aws_caller_identity" "current"` (`environments/dev/providers.tf` or `variables.tf`, mirroring bootstrap's own `allowed_account_ids` safety-check pattern) — used to help validate that `var.aws_account_id` matches the resolved caller identity, the same wrong-account guard bootstrap already has.

## 37. IAM Policy Boundaries

Three distinct IAM surfaces, each bounded independently, none allowed to expand the others' scope:

1. **The deployment role** (Stage A, §11) — bounded to exactly the dev state key, exactly the EC2/VPC/IAM actions this specific implementation needs, and explicitly excluded from any bootstrap-state access or self-escalation action.
2. **The workstation role** (§13) — bounded to SSM connectivity and a single-ARN `AssumeRole` statement; explicitly excluded from CloudWatch Logs and artifact-bucket access until a concrete target exists (§13's deferral).
3. **Neither role can create or modify the other's trust policy** — the deployment role's IAM permissions (§11 item 3) are scoped to *creating* the workstation role, not to *modifying the deployment role's own trust policy* (that update, Stage B, is a separate, reviewed, human-initiated apply against `bootstrap/`, never something the deployment role does to itself automatically).

## 38. Least-Privilege Decisions

Consolidating the least-privilege choices made throughout this plan, each stated with its specific reasoning rather than asserted generically:

- Deferring CloudWatch Logs and artifact-bucket permissions on the workstation role until a concrete target exists (§13) — granting access to a resource that doesn't exist yet would force either an overly broad grant or a meaningless empty-scoped one.
- Scoping the deployment role's new dev-state permissions to the exact `dev/` key prefix, not bucket-wide, and never to `bootstrap/*` (§11).
- Scoping the deployment role's new IAM permissions to the exact workstation-role ARN pattern, not IAM-wide (§11 item 3).
- IMDSv2 enforcement (§27) as a default-on hardening step, not an opt-in.
- Zero inbound security-group rules with no exception, including for the operator's own IP (§16) — the same "no exception, ever" rule already applied in `EC2_Development_Workstation.md` §11.
- No wildcard `sts:AssumeRole` on the workstation role — exactly one ARN (§13).

## 39. Terraform Version/Provider Compatibility

`environments/dev/versions.tf` declares `required_version = ">= 1.10.0, < 2.0.0"` — the **same** floor as `bootstrap/`, since `use_lockfile` (native S3 locking, §9) requires it here too, and there is no reason for the two root modules in this project to diverge on Terraform version support. The AWS provider constraint is re-verified against the Terraform Registry immediately before code creation (not fixed in this plan), consistent with how bootstrap's own provider constraint was corrected once during static review (`>= 5.0.0` → `>= 6.0.0`, `PROJECT_EXECUTION_JOURNAL.md` Section 13) — the exact currently-compatible constraint is checked fresh, not copied blindly from bootstrap's already-committed value, in case a newer major version has since become current.

## 40. `.terraform.lock.hcl` Handling

`environments/dev/` gets its **own** `.terraform.lock.hcl`, generated by its own `terraform init`, committed to version control, never hand-edited — independent of `bootstrap/`'s lock file, per `Terraform_Bootstrap_Design.md` §20's "each root module initializes its own providers and keeps its own lock file; they are not shared." Not created by this plan or by the file-creation task (only a real `terraform init` generates it, out of scope here, §57).

**REVISED 2026-07-26 (child-module lock-file policy, first local validation gate):** the first local validation gate's real `terraform init -backend=false` was run not only against `bootstrap/` and `environments/dev/` (the two executable roots) but also, independently, against each of the three reusable child modules (`modules/vpc/`, `modules/iam-workstation-role/`, `modules/ec2-workstation/`) as a standalone directory, in order to run `terraform validate` against each one in isolation. That standalone `init` generates its own `.terraform.lock.hcl` inside each module directory. **This is expected, temporary tooling behavior, not a design decision to give child modules their own committed lock file.** A reusable module is meant to be consumed via a `module` block from a root, never `init`'d and applied on its own — its dependency-locking responsibility belongs entirely to whichever root module calls it (`environments/dev/.terraform.lock.hcl` is the one that actually governs what gets deployed). Only `bootstrap/.terraform.lock.hcl` and `environments/dev/.terraform.lock.hcl` are committed; the three module-directory lock files are validation-only artifacts of running `terraform validate` standalone and **must not be committed**. `.gitignore` was updated (2026-07-26) with `infrastructure/terraform/modules/*/.terraform.lock.hcl` to make this unenforceable-by-convention rule enforceable-by-tooling. **The three module-directory lock files themselves were not deleted by this documentation task** (source/documentation edits only, no cleanup commands run) — deleting `infrastructure/terraform/modules/vpc/.terraform.lock.hcl`, `infrastructure/terraform/modules/iam-workstation-role/.terraform.lock.hcl`, and `infrastructure/terraform/modules/ec2-workstation/.terraform.lock.hcl` (and, for tidiness, each module's `.terraform/` directory) is recorded as the required next local action, to be run by hand on the machine that generated them.

## 41. `backend.hcl.example` and `terraform.tfvars.example` Strategy

Both committed, both placeholders only, exactly mirroring bootstrap's already-established pattern:

- **`backend.hcl.example`** (**syntax corrected 2026-07-26, §9**): `bucket = "<STATE_BUCKET_NAME>"`, `key = "dev/terraform.tfstate"` (this one **is** a literal, real, non-sensitive value — the key name itself is not account-specific, unlike the bucket name), `region = "ap-south-1"`, `encrypt = true`, `use_lockfile = true`, and a nested `assume_role = { role_arn = "<DEPLOYMENT_ROLE_ARN>", session_name = "terraform-dev-backend" }` block — **not** a standalone `role_arn` field (the prior draft's error, now corrected, §9). No credential, profile name, or real ARN is included in the committed `.example` file — only the placeholder tokens shown.
- **`terraform.tfvars.example`**: `aws_account_id = "<AWS_ACCOUNT_ID>"`, `deployment_role_arn = "<DEPLOYMENT_ROLE_ARN>"` (consumed by `providers.tf`'s separate `assume_role` block, §9), `ami_id_override = null` (new, 2026-07-26, §3.2, §22, shown commented-out by default since `null` is already `variables.tf`'s own default), `vpc_cidr`/`public_subnet_cidr` — **since §21's CIDR scheme is now finalized (2026-07-26)**, `10.20.0.0/16` and `10.20.1.0/24` can be set as real, literal defaults directly in `environments/dev/variables.tf` itself, rather than left as placeholders in the `.example` file — CIDR ranges are not account-sensitive, unlike `aws_account_id` and `deployment_role_arn`, which remain gitignored-only with no default.
- Real `backend.hcl` and `terraform.tfvars` (with actual account values) are **not** created by this plan or the file-creation task — gitignored, created only at actual `init`/`plan` time (§57), following the exact same `.gitignore` entries already covering bootstrap's equivalents (no new `.gitignore` change needed, since `backend.hcl`/`terraform.tfvars` are already excluded generically, not per-root-module).

## 42. Validation, Lint, and Security-Scan Commands (Stage F)

Same tool set as bootstrap, run from `infrastructure/terraform/environments/dev/`:

```text
terraform fmt -check -recursive
terraform init
terraform validate
tflint --init   # if not already initialized for this directory
tflint
trivy config --misconfig-scanners=terraform .
trivy config --misconfig-scanners=terraform --tf-vars terraform.tfvars .   # once a real tfvars exists
```

Any finding is triaged the same way bootstrap's two Trivy findings were: fixed if it's a real defect, or explicitly reviewed and accepted as a documented design exception if it reflects an already-approved trade-off (e.g., a scanner flagging the absence of a customer-managed KMS key on the root volume, consistent with the project-wide SSE-S3-equivalent posture) — never silently suppressed via `.trivyignore` or an inline ignore annotation without a recorded reason, unchanged project-wide discipline.

### 42a. First Real Local Validation Gate — Results (2026-07-26)

**Run on the user's own Windows machine (not the Cowork sandbox, which has no usable Terraform/TFLint/Trivy toolchain — see the prior, sandbox-blocked attempt recorded elsewhere in this project's tracking docs).** Confirmed, real toolchain evidence, superseding that earlier sandbox-blocked attempt:

- `terraform fmt -check -recursive` — **passed**, no file needed reformatting.
- `terraform validate` — **passed** in all five directories: `bootstrap/`, `environments/dev/`, `modules/vpc/`, `modules/iam-workstation-role/`, `modules/ec2-workstation/`.
- `tflint` — **nine warnings**, all now addressed by source changes in this revision:
  1–2. Two unused variables in `environments/dev/variables.tf` (`private_application_subnet_cidr_reserved`, `private_data_subnet_cidr_reserved`) — **removed** (§21).
  3. One unused variable in `modules/iam-workstation-role/variables.tf` (`project_name`) — **removed**, and the corresponding argument removed from the `module "workstation_role"` call in `environments/dev/main.tf` (§7).
  4–9. Six missing-version-constraint findings (`terraform_required_version` and/or `terraform_required_providers`) across the three child modules' `versions.tf` files (two findings per module) — **fixed** by adding `required_version = ">= 1.10.0"` and `aws = { version = ">= 6.0.0, < 7.0.0" }` to each of `modules/vpc/versions.tf`, `modules/iam-workstation-role/versions.tf`, and `modules/ec2-workstation/versions.tf`, matching `environments/dev/versions.tf`'s own constraint (§7).
- `trivy config` — **not yet run.** This gate stopped at TFLint; a Trivy pass is the next tool to run, after the fixes below are re-validated.

**These nine fixes have been made in source but have NOT yet been re-validated** — `terraform fmt -check -recursive`, `terraform validate` (all five directories), and `tflint` (all five directories) all need to be re-run for real, on the same Windows machine, to confirm the fixes are both syntactically correct and actually clear all nine warnings with zero new ones introduced. Until that re-run happens, these are **code-evidence fixes (Tier 2), not re-confirmed validation evidence (Tier 4)** — the exact same evidence-tier distinction this project applies everywhere else. Also unresolved: the three child-module `.terraform.lock.hcl` files generated by the standalone module-level `terraform init`/`validate` runs are validation-only artifacts and must be deleted by hand before the next commit (§40).

### 42b. Second Real Local Validation Gate — TFLint Clean, Trivy Run, IAM Bypass Found and Corrected (2026-07-26)

**Run on the user's own Windows machine, re-confirming §42a's nine fixes and adding the Trivy pass that §42a had not yet reached.** Toolchain versions confirmed for the record: Terraform v1.15.8, AWS provider v6.56.0, TFLint v0.64.0, Trivy v0.72.0.

- `terraform fmt -check -recursive` — **passed.**
- `terraform validate` — **passed** in all five directories: `bootstrap/`, `environments/dev/`, `modules/vpc/`, `modules/iam-workstation-role/`, `modules/ec2-workstation/`.
- `tflint --recursive` — **completed with zero findings** — confirms §42a's nine fixes (the two removed reserved-CIDR variables, the removed `project_name` variable, and the six added version constraints) are correct and complete; no new warning was introduced by them. This is the first real Tier 4 (Terraform validation, TFLint-clean) evidence for this code.
- `trivy config` — **run for the first time against this code.** Five findings reported; see the disposition table below. **Trivy explicitly warned that variable values were unavailable during these scans** (no `--tf-vars` was supplied) — these are **not** input-aware scans; see the variable-warning treatment note below the disposition table.

**Trivy findings and dispositions:**

| Finding | Severity | Scope | Disposition |
|---|---|---|---|
| AWS-0089 | LOW | `bootstrap/` — S3 bucket access logging disabled | **Accepted Phase 0 exception.** A separate logging-destination bucket and its own permissions/retention/cost review are not justified at this stage; the state bucket retains versioning, SSE-S3 encryption, full Block Public Access, `BucketOwnerEnforced` ownership, and a TLS-only bucket policy regardless. Revisit for production or a stronger audit requirement. Unchanged from bootstrap's original disposition of this same finding (§22 of this project's earlier bootstrap-phase record). |
| AWS-0132 | HIGH | `bootstrap/` — no customer-managed KMS key | **Accepted approved design decision.** SSE-S3 is the intentional, already-approved choice (`Terraform_Bootstrap_Design.md` §9) — no CMK administration, key-policy design, or KMS cost/dependency is taken on during bootstrap. Revisit if customer-managed key control, audit separation, or a compliance requirement makes CMK necessary. Unchanged from bootstrap's original disposition. |
| AWS-0342 | MEDIUM | `bootstrap/` — `iam:PassRole` present | **Necessary, reviewed permission — accepted only after re-confirming its scope.** Re-checked directly against `bootstrap/main.tf`'s `DevPassWorkstationRoleToEC2Only` statement: `Resource` is the exact workstation-role ARN (`arn:aws:iam::${var.aws_account_id}:role/${var.dev_workstation_role_name}`, never a wildcard role pattern), and the statement's sole condition is `iam:PassedToService = ec2.amazonaws.com` — confirmed exactly matching the required conditions before acceptance. No wildcard role-passing exists anywhere in this policy. This finding exists because `iam:PassRole` is inherently privilege-adjacent (it's how a role's permissions reach a launched instance) — the scanner is correct to flag it for review, and this review confirms the scoping is already as narrow as the task requires. |
| AWS-0104 | CRITICAL | `environments/dev`/`modules` — unrestricted security-group egress | **Temporary dev-phase exception, explicitly risk-accepted, not a defect.** The workstation needs outbound reachability to package repositories, GitHub, public APIs, and AWS service endpoints; no NAT Gateway, forward proxy, or VPC endpoints exist yet to narrow egress through (§19's accepted no-NAT trade-off). Zero inbound access remains fully enforced regardless (the actual primary control, §16) — this finding is about egress breadth, not inbound exposure. Future tightening options: scope egress to specific destination CIDRs/ports (HTTPS 443 to known package-repo/GitHub/AWS-endpoint ranges) once those ranges are enumerated; introduce VPC endpoints for AWS service traffic (S3, SSM) to remove that traffic from the public-internet egress path entirely; add a NAT Gateway plus a scoped egress-only security group if the workstation moves to a private subnet. Classified here as a **risk accepted for the initial dev phase**, not a permanently closed decision — reviewed again whenever the no-NAT/public-subnet trade-off itself is reconsidered (§19, §35). |
| AWS-0178 | MEDIUM | `environments/dev`/`modules` — VPC Flow Logs disabled | **Deferred control, not a defect.** This is a single, disposable development workstation (§32/§44 disposable-workstation philosophy) — enabling Flow Logs now would mean provisioning an additional CloudWatch Logs (or S3) destination, the IAM permissions to write to it, and accepting its ongoing ingestion/storage cost, for a network that has no production traffic and no compliance requirement driving audit-trail retention yet. Revisit and enable for a production environment, during incident investigation, or once stronger network-level auditing is a genuine requirement rather than a hypothetical one. |

**Duplicate scan paths consolidated, not treated as separate findings:** AWS-0104 and AWS-0178 were each reported twice in the raw Trivy output — once when Trivy scanned `environments/dev/` (which pulls in the module code via its `module` blocks) and again when Trivy scanned each of `modules/vpc/`/`modules/ec2-workstation/` directly as standalone directories. This is the same underlying HCL being evaluated through two different scan entry points, not two independent architectural findings — recorded here as one disposition per finding ID (above), not two, consistent with how this project already treats duplicate/near-duplicate material as a defect to flag and consolidate, not multiply (`CLAUDE.md` §3).

**No blanket ignore rule or global Trivy suppression was added anywhere** (no `.trivyignore` file created, no inline `#trivy:ignore` annotation added to any `.tf` file) — all five findings above remain visible to the next real scan; only this document's disposition table records the review decision. If an inline ignore comment is proposed in a future task, it requires: the exact finding ID, the exact resource it applies to, a written rationale, and an explicit expiry/review trigger — none of which has been added yet, since this task's scope was disposition documentation, not code suppression.

**Variable-warning treatment (Task C, first-real-Trivy-run follow-up):** Trivy warned, for both the `bootstrap/` scan and the `environments/dev`/module scans, that variable values required by the configuration (`aws_account_id`, `state_bucket_name`, `human_bootstrap_principal_arn`, `deployment_role_arn`, and others with no default) were unavailable, since no `--tf-vars` flag was supplied. **These scans are explicitly not claimed as fully input-aware** — some conditional logic or resource attributes that depend on those variable values may not have been fully evaluated. Trivy officially supports supplying real variable values via `trivy config --tf-vars <path-to-tfvars> .` (the same flag bootstrap's own prior input-aware rerun used, `PROJECT_EXECUTION_JOURNAL.md` Section 22/32) — a future scan should be run with the real, local, gitignored `terraform.tfvars` files for `bootstrap/` and (once one exists) `environments/dev/`, on the machine where those files already live. **No real `terraform.tfvars` value is created, exposed, or reproduced by this task** — this section documents only that the input-aware rerun is a pending next step, not its content.

**IAM policy correction status (Task A cross-reference):** the `DevNetworkingCreateManage`/`DevNetworkingCreateManageTaggedOnCreate` tag-enforcement bypass identified during manual review (§11.6) has been corrected in `bootstrap/main.tf` and in this document's §11.1/§11.2/§11.3/§11.6 (see those sections for the full before/after). **This correction has NOT yet been re-validated by a real `terraform fmt`/`validate`/`tflint`/Trivy run** — it was made after this section's `tflint --recursive`/Trivy results were obtained, so those clean/disposed results do not yet cover the corrected policy. A third validation pass, covering the IAM correction specifically, is required before this policy is trusted for a `terraform plan`.

## 43. Terraform Plan Review Criteria (Stage G)

A `terraform plan` for `environments/dev` is considered reviewed and acceptable when, at minimum:

- The resource count and resource types match exactly what §7's file tables describe — no unexpected VPC/EC2/IAM resource, no unexpected `test`/`stage`/`prod` resource, no NAT Gateway, no DynamoDB table, no customer-managed KMS key.
- Every resource carries the required tag set (§34), with `Environment = "dev"` specifically (not `"shared"` — a plan proposing `shared` on a dev resource would indicate a real bug, given `Naming_Convention.md`'s explicit reservation of that value).
- The security group shows **zero** proposed ingress rules (§16) — any proposed ingress rule, however narrow, is a hard stop pending explicit re-review, not a judgment call.
- `metadata_options.http_tokens = "required"` is present on the instance (§27).
- The root volume is `gp3`, `30` GiB, `encrypted = true` (§26).
- No resource is proposed for change, replacement, or destruction against anything outside `environments/dev`'s own resources — in particular, no diff touching `bootstrap/`'s resources should appear in this plan at all, since they are in a completely separate state file (§10).
- The deployment role's account-consistency safety check (`allowed_account_ids`, mirroring bootstrap's own, §36) resolves cleanly.

## 44. Apply Authorization Gate (Stage H)

**Identical discipline to bootstrap's own gate, restated for `environments/dev`:** a reviewed, saved plan (`terraform plan -out "dev.tfplan"`) requires its own separate, explicit authorization before `terraform apply "dev.tfplan"` is run — plan review passing does not itself authorize apply, exactly as bootstrap's plan-review gate and deployment gate were kept as two separate, separately-dated approvals (`PROJECT_EXECUTION_JOURNAL.md` Sections 27a–27b). Additionally, for `environments/dev` specifically: **Stage A must have already succeeded and been AWS-verified** (the deployment role actually has the permissions this apply needs) before this gate can be meaningfully granted — an apply attempted against an unpermitted role would simply fail partway through, which is itself the scenario the partial-apply recovery guidance (§50) exists for, but is best avoided by sequencing correctly in the first place.

## 45. AWS-Side Verification Commands (Stage I)

Run after a successful apply, with `--no-cli-pager` (the same tooling lesson already recorded from bootstrap's own verification, `PROJECT_EXECUTION_JOURNAL.md` mistake #15):

```text
aws ec2 describe-vpcs --vpc-ids <VPC_ID> --no-cli-pager
aws ec2 describe-subnets --subnet-ids <SUBNET_ID> --no-cli-pager
aws ec2 describe-internet-gateways --internet-gateway-ids <IGW_ID> --no-cli-pager
aws ec2 describe-route-tables --route-table-ids <ROUTE_TABLE_ID> --no-cli-pager
aws ec2 describe-security-groups --group-ids <SG_ID> --no-cli-pager   # confirm zero ingress rules
aws iam get-role --role-name enterprise-data-platform-dev-workstation-role --no-cli-pager
aws iam list-attached-role-policies --role-name enterprise-data-platform-dev-workstation-role --no-cli-pager
aws iam get-instance-profile --instance-profile-name enterprise-data-platform-dev-workstation-role --no-cli-pager
aws ec2 describe-instances --instance-ids <INSTANCE_ID> --no-cli-pager
aws ec2 describe-instances --instance-ids <INSTANCE_ID> --query "Reservations[].Instances[].MetadataOptions" --no-cli-pager   # confirm IMDSv2 required
```

None of these has been run — this is the documented, not-yet-executed verification command set, exactly as bootstrap's own `README.md` "Verification Commands" section was documented before it was actually exercised.

## 46. Session Manager Connection Test

Once the instance exists and is verified (§45): `aws ssm start-session --target <INSTANCE_ID>` from an authorized human identity's own machine. A successful connection (interactive shell prompt on the instance) is the acceptance signal — not merely that the instance shows `running` state, since Session Manager registration can lag slightly behind instance boot.

## 47. SSH-over-SSM Validation Approach for VS Code

Per `EC2_Development_Workstation.md` §15: `aws ssm start-session --target <INSTANCE_ID> --document-name AWS-StartPortForwardingSession --parameters '{"portNumber":["22"],"localPortNumber":["<LOCAL_PORT>"]}'` tunnels a local port to the instance's `sshd`, then VS Code's Remote-SSH extension is pointed at `localhost:<LOCAL_PORT>` via a manually-added SSH config entry. Validation is successful when VS Code's integrated terminal, file explorer, and extension host all function against the remote instance through that tunnel — with **no** security-group ingress rule for port 22 existing at any point (§16, reconfirmed via §45's `describe-security-groups` check immediately before this test, not assumed).

## 48. Known Session Manager Logging Limitations

Restated from `EC2_Development_Workstation.md` §23, since it is directly relevant evidence for what this implementation *can* and *cannot* audit: **command-content logging (recording actual keystrokes/output) is not available for SSH-over-SSM or port-forwarding sessions** — which is exactly the access pattern §47 uses. What remains available regardless of session type: **session start/stop events** and the relevant CloudTrail API activity (`StartSession`, `TerminateSession`, `AssumeRole`). This limitation is not a defect in this implementation — it is an inherent property of the chosen access pattern, documented here so it is not mistaken for a monitoring gap that this plan failed to close.

## 49. Native S3 Lock Contention Test Opportunity During This Phase

**This is the scheduled venue for the deliberate native-S3-locking contention test deferred during bootstrap phase closeout** (`PROJECT_EXECUTION_JOURNAL.md` Section 27e: "explicit contention verification is deferred to the `environments/dev` Terraform phase, where a genuinely longer-running operation provides a safer and more natural window"). Concrete opportunity: `environments/dev`'s `apply` (VPC + IAM role + EC2 instance, §H) takes meaningfully longer than bootstrap's near-instant S3/IAM-only apply did — plausibly tens of seconds to a few minutes, dominated by `RunInstances` and its associated waiters. **Proposed test procedure** (documented here, not run by this plan): while that `apply` is in progress and holding the `dev/terraform.tfstate.tflock` lock, deliberately start a second `terraform plan` (or `apply`) against the same `environments/dev` directory from a second terminal/session, and observe: (1) whether the second operation is correctly blocked or errors referencing the lock, rather than silently proceeding; (2) whether the lock is cleanly released once the first operation completes, allowing the second (retried) operation to succeed normally; (3) if a lock were ever left stuck, whether the documented recovery path (`Terraform_Bootstrap_Break_Glass_Procedure.md` diagnosis-before-`force-unlock`) works as written. This test is **not** part of the normal Stage G/H flow — it is a deliberately separate, additional exercise layered on top of one real apply, not a routine step every apply must repeat.

## 50. Partial-Apply Recovery

Identical discipline to `Terraform_Bootstrap_Design.md` §28.3 and `README.md` "Partial-Apply Recovery Guidance," restated for `environments/dev`'s specific resource set: inspect first (`terraform state list`, `terraform plan`, targeted `aws ec2 describe-*`/`aws iam get-*` checks) before any corrective action; `terraform import` for a resource AWS shows as created but Terraform's state doesn't yet know about; re-`apply` against the same, unmodified configuration for a resource that's only partially configured (each resource in this configuration is independently idempotent, no non-idempotent provisioners); never blind delete-and-recreate.

## 51. Import Guidance

Illustrative, not exhaustive (same caveat as bootstrap's own import guidance) — the exact resources needing import after a partial apply depend on what AWS actually shows as already created:

```text
terraform import module.vpc.aws_vpc.this <VPC_ID>
terraform import module.vpc.aws_subnet.public <SUBNET_ID>
terraform import module.vpc.aws_internet_gateway.this <IGW_ID>
terraform import module.vpc.aws_route_table.public <ROUTE_TABLE_ID>
terraform import module.workstation_role.aws_iam_role.this enterprise-data-platform-dev-workstation-role
terraform import module.workstation_role.aws_iam_instance_profile.this enterprise-data-platform-dev-workstation-role
terraform import module.ec2_workstation.aws_security_group.this <SG_ID>
terraform import module.ec2_workstation.aws_instance.this <INSTANCE_ID>
```

Always followed by `terraform plan` to confirm the imported resource matches this configuration with no unexpected diff, before any further `apply` — unchanged discipline from bootstrap.

## 52. Rollback and Cleanup Boundaries

`environments/dev`'s resources are **not** protected by `prevent_destroy` the way bootstrap's state bucket and deployment role are — a dev VPC/workstation is expected to be genuinely destroyable and recreatable as part of normal iteration (§32's disposable-workstation model), unlike bootstrap's resources, which everything else depends on. This is a deliberate, asymmetric decision worth stating plainly: **bootstrap protects itself from casual destruction; `environments/dev` deliberately does not**, because disposability is the entire point of the workstation design. `terraform destroy` against `environments/dev` is therefore a legitimate, expected operation during this project's lifetime (e.g., to stop paying for the public IP/instance between extended breaks) — not an incident. The one boundary that **does** still apply: destroying `environments/dev` must never be used as a shortcut to "fix" a bootstrap-level problem (state, the deployment role, its trust policy) — those remain governed entirely by `bootstrap/`'s own, separate, protected lifecycle.

## 53. Evidence to Capture

Same kind of evidence bootstrap already established a pattern for, captured only when each stage is actually executed (none of it exists yet): `terraform plan`/`apply` output for both the Stage A bootstrap-permission-update apply and the `environments/dev` apply itself; real `aws ec2`/`aws iam` CLI output for §45's checks; a recorded Session Manager connection result (§46); a recorded VS Code Remote-SSH-over-SSM result (§47); the native-lock contention test's actual observed behavior (§49) — recorded honestly whichever way it goes, including if something doesn't work as expected the first time; `tflint`/Trivy output for `environments/dev` (§42). All of it recorded in `Memory.md`/`Bootstrap_Checklist.md`(or a new dev-specific checklist)/`PROJECT_EXECUTION_JOURNAL.md`, following the exact evidence-tier discipline (`PROJECT_EXECUTION_JOURNAL.md` Section 2) already applied throughout the bootstrap phase — no claim of a stronger evidence tier than what was actually run and observed.

## 54. Interview-Guide Updates

Handled as a separate, parallel update to `17_Interview_Guide/Phase_0.md` (this plan does not itself contain interview Q&A content) — new questions covering: why `environments/dev` needed a permission update to the deployment role before it could do anything (§11); why the trust-policy update (§12) had to wait until *after* the workstation role exists, given the stage lettering otherwise implies A-then-B order; why the dev state key is a single `dev/terraform.tfstate` rather than the finer-grained split originally illustrated in `Terraform_Bootstrap_Design.md` §8 (§56); why `iam-workstation-role` remains a separate module from `ec2-workstation` while `security-group` does not (§3); and why the native-S3-locking contention test is deliberately scheduled for this phase rather than tested against bootstrap itself (§49). These questions are added to `Phase_0.md` directly, not duplicated here.

## 55. Risks and Mitigations

| Risk | Mitigation |
|---|---|
| Stage A's permission grant to the deployment role is scoped too broadly "just to get things working" | §11's category-by-category scoping (dev-state-only, EC2 actions needed for exactly these resources, IAM actions resource-ARN-restricted to the workstation role) is specified now, for review, before any policy JSON is written |
| The `dev/terraform.tfstate` single-key decision causes a future accidental cross-resource `plan`/`apply` (e.g., a VPC change unexpectedly proposing an EC2 replacement) | Accepted trade-off for this project's current size — see §56's flagged conflict; the mitigation is careful `plan` review (§43) before every apply, the same discipline already used successfully throughout bootstrap |
| MFA requirement on the human-identity trust statement complicates the human-run Stage A–E applies | §12 documents the practical workaround (pre-assumed session credentials or an MFA-aware named CLI profile) explicitly, rather than leaving it to be discovered as a surprise at `terraform init` time |
| The bootstrap script (§29) is wired into `user_data` before it has been tested, causing a workstation that boots but fails to configure itself with no easy first-boot diagnostic path | Explicit sequencing: author and test the script separately, first, before it is referenced in `environments/dev/main.tf` |
| `environments/dev` resources lack `prevent_destroy`, and a careless `terraform destroy` targets the wrong directory | `environments/dev` and `bootstrap/` are entirely separate state files/directories (§10, §52) — a `destroy` run from the wrong directory cannot touch the other's resources at the Terraform level, though operator discipline (checking `pwd`/`-chdir` before any destructive command) remains a real, human factor not eliminated by tooling alone |
| Finalized CIDR scheme (§21) collides with a VPC CIDR chosen for a future, unrelated need (e.g., a VPN or peering requirement not yet known) | `10.20.0.0/16` was deliberately chosen outside the ranges most home/office routers and common lab/VPN defaults use (`192.168.0.0/16`, `172.16.0.0/12`), reducing collision likelihood; if a genuine future conflict is discovered before any resource exists, re-addressing this unapplied plan costs nothing — the risk only becomes costly after `apply`, which has not happened |

## 56. Open Decisions

**REVISED 2026-07-26 — split into blocking and non-blocking, per explicit instruction.** Previously this section listed everything as "not blocking approval of this plan itself." That framing is corrected here: some of these genuinely must be resolved before code creation begins; others are now resolved outright by this revision; the rest remain genuinely non-blocking.

### 56.1 Blocking — Must Be Resolved Before Code Creation Begins

**None remain.** Both items formerly listed here are now resolved — see §56.2.

### 56.2 Resolved — No Longer Blocking

- **Exact IAM policy JSON/statement structure for Stage A's deployment-role permission grant (§11, IAM Sequencing Stage A).** **Resolved 2026-07-26** (this finalization pass) — the complete action/resource/condition matrix and the full proposed policy JSON are now drafted (§11.1–11.2), with every wildcard resource explained (§11.3), human-only permissions distinguished (§11.4), the Bootstrap-Update-2 scope clarified as trust-only (§11.5), and residual risks documented (§11.6). This still requires a **separate, explicit review/approval before Stage A's own apply** (a later gate, §44 — not this plan's approval), exactly as bootstrap's own permissions were reviewed before being applied, but no longer blocks **this plan's** approval, since the literal policy document now exists and is complete enough for code implementation.
- **The exact `infrastructure/terraform/scripts/bootstrap_workstation.sh` content (§29).** **Scope (not literal script content) resolved 2026-07-26** — §29 now fully specifies permitted scope, the ten explicit prohibitions, and the idempotency/logging/failure-handling/versioning requirements the script must satisfy. This is sufficient for code creation to begin (Stage B's apply already tolerates a placeholder `user_data` per §29.7); the literal shell-script text itself is still written during the code-creation task, not this planning task, consistent with every other `.tf`/script file in §7 — none of which are drafted in this planning document either. Not a blocker for plan approval.

- **Availability Zone selection strategy (§20).** Resolved: dynamic first-AZ lookup via `data "aws_availability_zones"`, index 0 of the returned list — a strategy, not a specific AZ name that needs pre-approval, since the actual AZ is computed at `plan`/`apply` time against whichever AWS account is in use. No further review needed on this point.
- **Detailed monitoring decision (§28).** Resolved: `monitoring = false` (basic 5-minute metrics), consistent with the project's cost-conscious framing. No further review needed; revisiting later is a one-line variable flip, not a design change.
- **Allowed EC2 instance types (§24–25).** Resolved and finalized in this revision: `t3.medium` (default), `t3.large`, `t3.xlarge`, `t3.small` deliberately excluded. Explicitly requested and confirmed — no further review needed on this point before code creation.
- **VPC CIDR and public-subnet CIDR (§21).** **Resolved 2026-07-26** (this rationale pass) — `10.20.0.0/16` / `10.20.1.0/24`, with `10.20.11.0/24` and `10.20.21.0/24` reserved for the private-application and private-data tiers, now finalized with rationale (§21, Decision Rationale items 1–3). No longer blocks Stage B's networking work.
- **IMDSv2 configuration, including the metadata hop limit (§27).** **Resolved 2026-07-26** (this rationale pass) — `http_tokens = "required"`, `http_put_response_hop_limit = 1`, now finalized with rationale (Decision Rationale items 10–11). No longer requires review before code creation.

### 56.3 Non-Blocking — May Be Resolved During or After Code Creation

- **Whether Terraform's `instance_type` change (§25) forces a stop/modify/start or a full replacement for `t3` family changes** — stated as "confirmed at implementation time against the exact provider version," not asserted here. Does not block code creation; affects only how a future instance-type change is executed operationally.
- **EBS snapshot cadence/retention, exact automatic-shutdown schedule, and whether `t3.small` is ever adopted** — all carried forward, still open, from `EC2_Development_Workstation.md` §28, unaffected by this plan.
- **Whether an ADR should be written for the ARM64→x86_64 reversal and/or the public-subnet-vs-private-subnet networking choice** — still flagged, still not written, per `CLAUDE.md` §9's guidance that this is a reversible-but-costly choice warranting one eventually. Does not block code creation.

### Documentation Conflicts Flagged (per `CLAUDE.md` §4) — ALL THREE RESOLVED (2026-07-26)

Per this project's standing rule to flag rather than silently resolve documentation disagreements, three were noted across the prior two revisions of this plan. This task's explicit instruction was to enumerate each with its full field set and, where the correct decision is already clear, **update the affected source document** rather than leave it flagged indefinitely. All three are resolved below; all three affected source documents have been edited (see "Files Modified" in the final report).

1. **Conflict: state-key granularity.**
   - **Documents involved:** `Terraform_Bootstrap_Design.md` §8 vs. this plan's §10.
   - **Conflicting statements:** §8 illustrates a finer-grained per-environment state-key layout (`<environment>/networking/terraform.tfstate`, `<environment>/iam/terraform.tfstate`, `<environment>/ec2-workstation/terraform.tfstate` — three keys per environment). This plan's §10 adopts a **single** `dev/terraform.tfstate` key for the whole `environments/dev` root module.
   - **Approved final decision:** single-key model. §17 of the same design document already describes `environments/dev/` as **one composing root module**, which logically implies one state key, not three — so §8's illustration and §17's description were already in tension with each other before this plan existed. This plan's single-key approach resolves that tension in favor of §17's model, consistent with this task's explicit instruction.
   - **Document updated:** `Terraform_Bootstrap_Design.md` §8 — a superseding clarifying note added directly after the original illustration (not a rewrite, preserving the original text as history, consistent with this project's ADR-style correction practice).
   - **Blocks code creation:** No — the single-key decision was already this plan's stated design; the document update brings the source-of-truth design doc into alignment, it does not change any Terraform value.

2. **Conflict: target-state networking principles vs. the approved dev-phase minimal design.**
   - **Documents involved:** `Networking.md` vs. this plan's §16–21.
   - **Conflicting statements:** `Networking.md` states general principles ("VPC across at least two Availability Zones," "VPC Flow Logs enabled," "VPC endpoints for S3/DynamoDB/ECR/... where justified") that this plan's first implementation does not meet (single AZ, no Flow Logs resource, no VPC endpoints).
   - **Approved final decision:** `Networking.md`'s principles describe the eventual production-grade target state for the platform's real data workloads (Phase 0 onward); this plan implements only the already-approved minimal subset needed for a single Pre-Phase dev workstation (`EC2_Development_Workstation.md`, `Terraform_Bootstrap_Design.md` §24). The two are not actually in conflict once scoped correctly — `Networking.md` was simply missing that scoping statement.
   - **Document updated:** `Networking.md` — a clarifying note added stating its principles apply from Phase 0's real-workload VPC onward and do not govern the Pre-Phase single-instance dev workstation, which is an explicitly approved, documented exception.
   - **Blocks code creation:** No — this plan's minimal design was already approved via `EC2_Development_Workstation.md` and the CIDR/AZ decisions in this task; the document update only makes the scoping explicit for future readers.

3. **Conflict: deployment-role naming example.**
   - **Documents involved:** `IAM_and_Access.md` vs. `Naming_Convention.md`.
   - **Conflicting statements:** `IAM_and_Access.md` showed `enterprise-data-platform-<environment>-deployment-role` as the naming pattern; `Naming_Convention.md` was already corrected (2026-07-25) to the single, project-wide `enterprise-data-platform-shared-deployment-role` (there is exactly one deployment role, shared across environments, not one per environment).
   - **Approved final decision:** `enterprise-data-platform-shared-deployment-role` — already the name used consistently throughout this plan (§11–12) and in `bootstrap/`'s actual deployed role.
   - **Document updated:** `IAM_and_Access.md` line 15 — corrected to match `Naming_Convention.md`.
   - **Blocks code creation:** No — the correct name was already in use everywhere it mattered (this plan, `bootstrap/main.tf`); only the stale doc example needed fixing.

## 57. Exit Criteria for Authorizing Code Creation

**FINALIZED 2026-07-26 — MET. This plan is REVIEWED AND APPROVED.** All four criteria below are satisfied as of this finalization pass:

1. **All blocking decisions in §56.1 are resolved** — §56.1 is now empty; the exact deployment-role permissions policy JSON for Stage A is fully drafted (§11.1–11.6), and the bootstrap-script scope (not yet its literal text, which is a code-creation-task activity like every other file in §7) is fully specified (§29). The VPC/public-subnet CIDR values and the IMDSv2 configuration were already finalized in the prior rationale pass (§56.2, §21, §27).
2. **The three flagged documentation conflicts** are enumerated with full fields (documents involved, conflicting statements, approved decision, document updated, blocking status) and resolved — see "Documentation Conflicts Flagged," all three marked RESOLVED, with `Terraform_Bootstrap_Design.md`, `Networking.md`, and `IAM_and_Access.md` each edited accordingly.
3. **This revised plan is reviewed and approved by the user as a whole** — incorporating the corrected backend syntax (§9), the three-stage IAM sequencing (before §11), the relocated AMI lookup (§22) and bootstrap script path (§2, §3.2, §29), the confirmed module boundaries (§3.2), the finalized CIDR scheme and IMDSv2 configuration (§21, §27), the complete deployment-role IAM policy (§11), and the Decision Rationale section (after this section).
4. **Explicit, separate authorization for the file-creation task itself** is still required before any `.tf`/script file is written — approval of this plan is not, by itself, that authorization. It is the **next task** (see closing footer), mirroring exactly how `Terraform_Bootstrap_Implementation_Plan.md`'s approval preceded, but was distinct from, the task that actually created `bootstrap/`'s ten files.

Even with this plan approved, **that does not authorize `terraform init`/`plan`/`apply`** — those remain their own separate, later, explicit gates (§44), following the identical two-step discipline (approve the plan → create the files; create the files → separately authorize running commands) that governed every stage of the now-complete Terraform Bootstrap phase. Approving this plan authorizes exactly one thing: proceeding to a follow-up task that creates the files listed in §7, with no Terraform command run and no AWS resource touched during that task either.

---

## Decision Rationale

**Added 2026-07-26.** This section exists to answer "why," not "what" — the numbered sections above already state each implementation choice precisely; this section connects each one explicitly to cost, security, portability, maintainability, or future-growth reasoning, so a reviewer (or a future interview answer, §54) doesn't have to reconstruct the reasoning from scattered cross-references. **No implementation value is changed by this section** — where a value is stated here, it matches the corresponding numbered section exactly, restated only for readability.

**1. VPC CIDR `10.20.0.0/16` (§21).** A `/16` gives 65,536 addresses of headroom — far more than a single dev workstation needs today, but enough that a second AZ, a `test`/`stage`/`prod` sibling design, or additional subnet tiers can all be added later without re-addressing anything already deployed (*future growth*). Using a deliberately chosen custom range, rather than accepting whatever a default VPC would have used, guarantees this VPC can never be confused with — or accidentally reference — the account's default VPC, which this project's design explicitly avoids using for any resource (`AWS_Account_Preparation.md`) (*maintainability, avoiding a known footgun*). `10.20.0.0/16` also falls outside the address space most home and small-office routers use out of the box (typically `192.168.0.0/16`, and to a lesser extent parts of `172.16.0.0/12`), which lowers the odds of an address collision when a developer connects to AWS resources from behind a typical home network (*portability across the developer's own network environments*).

**2. Public subnet `10.20.1.0/24` (§21).** 256 addresses is far more than one EC2 instance needs, but is the standard, readable subnet size used throughout this project's naming and addressing conventions — a `/24` is instantly recognizable as "one subnet's worth" without needing to compute it (*maintainability*). Starting the subnet numbering at `.1.0/24` rather than `.0.0/24` deliberately leaves the VPC's first `/24` block (`10.20.0.0/24`) unused and available as a clearly-reserved "block zero" for any future VPC-wide resource that might want an unambiguous, easy-to-remember first address range, rather than competing with the first subnet for that space (*future growth, predictable numbering*).

**3. Reserved future CIDRs `10.20.11.0/24` (private-application) and `10.20.21.0/24` (private-data) (§21, §6).** Reserving these ranges now — as comments/variables only, with no `aws_subnet` resource created — means that whenever a real private-application or private-data workload is designed, its subnet's address range is already decided and guaranteed not to overlap with the public subnet or with each other (*maintainability, prevents future overlap*). The numbering pattern (public tier in the `.1`–`.9` range, application tier starting at `.11`, data tier starting at `.21`) establishes a predictable, extensible convention — a third or fourth tier added later has an obvious next number to use, rather than requiring a fresh, potentially inconsistent choice each time (*predictable numbering, future growth*). Reserving without deploying costs nothing in AWS and creates no resource to secure, monitor, or pay for before it's actually needed (*cost*).

**4. First available AZ via `data.aws_availability_zones` (§20).** AZ *names* (the `1a`/`1b`/`1c` suffix) are account-specific labels, not physical identifiers — the same suffix can map to a different physical facility in a different AWS account. Hardcoding `"ap-south-1a"` would silently assume this account's mapping matches whatever the author had in mind, an assumption with no way to verify itself before `apply` (*portability* — this configuration, or a copy of it, works correctly in any account without a manual edit). Querying dynamically and always picking a deterministic index (0) keeps the selection reproducible without hardcoding a name (*maintainability*). Outputting the selected AZ (`availability_zone` in `modules/vpc`'s outputs, §7) makes the actual choice visible to anyone reviewing a `plan` or `apply`, rather than leaving it implicit inside the module (*visibility, supporting review*).

**5. Public subnet with a public IPv4 address (§17, §19).** The workstation genuinely needs outbound reachability — for `dnf`/package-manager installs, `git`/GitHub access, AWS API calls, and other developer tooling — and a public subnet with an Internet Gateway is the simplest way to provide that without first building private-subnet infrastructure (NAT Gateway or VPC endpoints) that isn't otherwise justified yet (*cost, simplicity*). Critically, having a public IPv4 address only affects *outbound* reachability and whether the instance is *addressable* from the internet — it does not, by itself, grant any *inbound* access; that is governed entirely, and separately, by the security group (§7, §16), which has zero inbound rules regardless of the subnet's public/private status. This separation of concerns (routing vs. access control) is what makes the public-subnet choice safe despite sounding permissive.

**6. No NAT Gateway initially (§19).** A NAT Gateway carries a genuine, non-trivial recurring cost: an hourly charge plus a per-GB data-processing charge, both of which accrue whether or not the instance is actively using much bandwidth (*cost*). For a single development workstation with no private-subnet workload yet, that ongoing cost isn't justified — the public-subnet model already provides the outbound reachability the workstation needs (§5 above) without it. This is deliberately framed as a **current-phase decision, not a permanent one**: moving to a private-subnet-plus-NAT-or-endpoints model remains a documented, available future hardening option (§19) once a concrete workload or compliance need actually justifies the added cost (*future growth, revisited when justified rather than paid for speculatively*).

**7. Zero inbound security-group rules (§16).** No rule opens port 22, port 3389 (RDP), or any application port to any CIDR — including the operator's own IP address, with no exception (*security*). This is possible specifically because Session Manager (§8 below) provides both interactive shell access and SSH-over-tunneling without needing any inbound security-group rule at all — the entire justification for historically opening SSH (remote interactive access) is met through a different mechanism that doesn't require exposing a port to the internet. The result is that the instance's internet-facing attack surface for unauthenticated network scanning and brute-force attempts is effectively zero, regardless of the instance having a public IP (*security, reduced attack surface*).

**8. Session Manager as the normal access path (§15, §46).** Access is governed entirely by IAM policy (who is allowed to call `ssm:StartSession` against this instance) rather than by possession of a distributed SSH private key (*security* — no key file to leak, copy, or lose track of). Revoking access is a matter of removing an IAM permission, which takes effect immediately and centrally, rather than needing to rotate a key across every machine that had it (*security, easier revocation*). Every session start/stop event and every `AssumeRole`/`StartSession` API call is recorded in CloudTrail automatically, giving a centralized audit trail that a distributed SSH key model doesn't provide on its own (*security, auditing*). No SSH key pair needs to be generated, distributed, or stored anywhere for this access path to work at all (*maintainability — nothing to distribute*).

**9. SSH only through SSM tunneling, never a direct network path (§47).** VS Code's Remote-SSH extension needs a real SSH connection to function, but this design provides that connection through `aws ssm start-session --document-name AWS-StartPortForwardingSession` — a locally-tunneled port — rather than through any security-group rule opening port 22 on the instance itself (*security* — the network-level SSH port stays closed at all times, satisfying item 7 above, while still supporting the developer tooling that expects SSH). This means the convenience of a familiar SSH-based workflow (VS Code Remote-SSH, `scp`-style file transfer if ever needed) is available without trading away the zero-inbound-rules security posture.

**10. IMDSv2 required (§27).** Requiring a session token for every instance-metadata request (rather than allowing the older, tokenless IMDSv1 requests) closes a well-known class of vulnerability where a server-side request forgery (SSRF) bug in *any* software running on the instance could otherwise be tricked into fetching the instance's own IAM credentials from the metadata service with a single unauthenticated HTTP request (*security*). This is a standard, widely-recommended AWS hardening step with no meaningful downside for a workstation that has no legacy tooling depending on IMDSv1 — a genuinely low-cost way to close a real credential-theft path (*security, low cost to adopt*).

**11. Metadata hop limit `1` (§27).** The hop limit controls how many network hops (e.g., through a container bridge or a local proxy) a metadata request can traverse before AWS refuses to answer it. Setting it to `1` means only a process running directly on the host — not inside an extra network layer such as a Docker container using a bridge network — can reach the metadata service (*security, reduces the surface an extra network hop could expose*). This is sufficient for the current workstation design, since nothing in this plan's scope runs a containerized workload that legitimately needs to reach instance metadata from more than one hop away; if that need arises later, raising the hop limit is a small, deliberate, reviewable change, not a default left open "just in case" (*maintainability, deliberate-by-default rather than permissive-by-default*).

**12. Detailed monitoring disabled initially (§28).** Basic monitoring (5-minute CloudWatch metric intervals) is free; detailed monitoring (1-minute intervals) carries a small additional per-instance charge. For a single development workstation where nothing depends on minute-level metric granularity, that additional cost isn't justified yet (*cost*). Five-minute intervals are still enough to notice sustained CPU pressure, unexpected network activity, or a stuck process during normal use (*sufficient for current needs*). Enabling detailed monitoring later, if a genuine need for finer-grained metrics emerges, is a one-line variable change — not a structural redesign (*maintainability, cheap to revisit*).

**13. `t3.medium` default sizing (§24).** `t3.medium` (2 vCPU, 4 GiB RAM, burstable) is sized to comfortably run Terraform, the AWS CLI, Git, a Python toolchain (`uv`), and a moderate development session — the actual workload this workstation exists for — without over-provisioning for headroom that's rarely used (*cost, right-sizing*). Its burstable-CPU-credit model fits development usage well: development work is naturally bursty (short compile/plan/apply spikes, then idle time reading or writing code), and burstable instances are specifically priced for that pattern rather than sustained, continuous load (*cost, workload fit*). Choosing `t3.medium` as the *default*, with larger sizes available as an explicit override (item 14), keeps the everyday, most-common cost as low as the workload allows without permanently blocking heavier sessions when they're genuinely needed.

**14. `t3.large`/`t3.xlarge` as temporary overrides, not new defaults (§25).** Making these available only via a deliberate, local, uncommitted `terraform.tfvars` edit — not as an alternate default — means heavier compute is available exactly when a specific session genuinely needs it (a larger Spark/EMR-adjacent local test, a heavier build) without permanently paying for that capacity the rest of the time (*cost control, avoids an oversized default*). Requiring a deliberate, visible action (editing `terraform.tfvars`, then reverting it) rather than a silent, automatic scale-up also means every period of higher spend traces back to an explicit, intentional choice, not an accidental default (*cost accountability*).

**15. 30 GiB encrypted `gp3` root volume (§26).** 30 GiB is sized to comfortably hold the OS, development tools, a cloned repository, Python/Terraform environments, and reasonable temporary data, without being so large that it carries meaningfully more cost than needed (*cost, right-sizing*). `gp3` provides predictable baseline IOPS and throughput independent of volume size (unlike `gp2`, where performance scales with size), which matters for a workstation doing frequent, bursty I/O (package installs, `terraform init`, compiling) rather than sustained throughput (*predictable performance*). Encryption at rest (AWS-managed key, no customer-managed KMS complexity, consistent with the state bucket's own SSE-S3 posture, §26) protects any data written to the volume, including transient build artifacts and cached credentials, without adding KMS key-management overhead (*security, consistent with the project's existing encryption posture*). All of this supports the disposable-workstation model (§32): a right-sized, encrypted, replaceable volume that's cheap enough to recreate rather than something precious to preserve.

**16. `delete_on_termination = true` for the root volume (§26, §32).** Because the workstation is explicitly designed to be disposable — durable state lives in GitHub (source code) and S3 (artifacts), never on the instance's own disk (§32) — there is no reason for the root EBS volume to outlive the instance it's attached to. Leaving `delete_on_termination` at its default `true` value means terminating or replacing the instance never leaves an orphaned, still-billing EBS volume behind that has to be separately noticed and cleaned up (*cost, avoids orphaned-resource billing*). This is consistent with, not a change to, the disposable-workstation philosophy already documented — recorded explicitly here because it's easy to overlook as "just a default" rather than a deliberate choice that reinforces the rest of the design.

**17. Three-module boundary — `vpc`, `iam-workstation-role`, `ec2-workstation` (§3).** Each module owns a distinct category of responsibility, not an arbitrary folder split: `modules/vpc` owns every networking resource (VPC, subnet, IGW, route table); `modules/iam-workstation-role` owns the workstation's identity — its role, its policies, and its instance profile (co-located because an instance profile has a strict 1:1 lifecycle relationship with the role it wraps, §3.2); `modules/ec2-workstation` owns the compute-adjacent resources — the security group, the instance itself, its root volume, its metadata configuration, and the `user_data` it receives. This boundary is drawn by **responsibility, independent reviewability, and lifecycle**, not by an arbitrary count of folders or files (*maintainability* — each module can be read, reviewed, and reasoned about on its own; a security review of IAM permissions never has to wade through EC2 instance configuration to find what it's looking for, and vice versa). It also supports **future reuse**: `modules/vpc` is the module most likely to be instantiated again for a `test`/`stage`/`prod` sibling later, and keeping it clean of workstation-specific EC2/IAM detail makes that reuse straightforward when the time comes (*future growth*).

**18. Deployment-role sequencing — human permission update, then dev apply, then human trust update (§11–12, IAM Sequencing before §11).** This exact order exists to avoid a genuine chicken-and-egg dependency, not as an arbitrary process step: the deployment role needs permissions before `environments/dev` can do anything with it; the workstation role needs to actually exist before the deployment role can trust it; and `environments/dev` needs the deployment role to already be usable before it can create that workstation role. Sequencing it as (1) human grants permissions → (2) human, using those permissions, runs the `environments/dev` apply that creates the workstation role → (3) human adds the now-real workstation role's ARN to the deployment role's trust policy resolves the dependency without ever requiring a step to reference something that doesn't exist yet (*maintainability, avoids a circular design that can't actually be built in one step*). Keeping every deployment-role change human-initiated, through `bootstrap/`'s own state, also means the deployment role's own definition is never something `environments/dev` — the thing the role exists to manage — can modify about itself (*security, no self-escalation path*).

**19. Bootstrap script restrictions — installs tools only, no credentials, no interactive auth (§29–31).** The script installs and configures development tooling (Git, Python/`uv`, GitHub CLI, etc.) and nothing else — it deliberately does not embed any credential, perform any GitHub authentication, assume any IAM role, clone any private repository, or deploy any application (§14, §31: `gh auth login` stays interactive, per developer, never baked into `user_data`). This matters because **EC2 `user_data` is not a secret-storage location** — its content can be visible in Terraform state and is retrievable from the instance's own metadata service by anything running on it, so anything embedded there should be treated as though it could be read by any process on the box (*security*). The script must also be idempotent (safe to re-run without duplicating work, §30) and non-interactive (it runs unattended at boot, with no human present to answer a prompt) — both are hard requirements for a `user_data` script specifically, since a script that hangs waiting for input, or that fails destructively on a second run, would break the disposable-workstation recovery model (§32) that depends on being able to re-apply and re-boot cleanly.

**20. Human-administered bootstrap root, never managed by `environments/dev` (§11, §37 item 3, IAM Sequencing Stage C).** `bootstrap/` — the state bucket and the deployment role — remains governed exclusively by its own, separately-run root module, accessed directly by the human identity, never by anything `environments/dev` creates or manages. The reasoning is a straightforward ownership-boundary argument: the deployment role's entire purpose is to manage `environments/dev`'s infrastructure, so letting `environments/dev` (or anything running as the deployment role) modify the deployment role's own trust policy or permissions would be a self-referential, self-escalating capability with no legitimate use case and a real risk if ever misused (*security*). Keeping this boundary strict and unambiguous — bootstrap resources are edited only through `bootstrap/`'s own state, `environments/dev` resources only through `dev/terraform.tfstate`, never crossed in either direction — also makes it straightforward to reason about which state file is authoritative for which resource at a glance, without needing to trace a resource's history across two root modules (*maintainability*).

---

*This plan is derived from and cross-references `02_Infrastructure/Terraform_Bootstrap_Design.md`, `02_Infrastructure/EC2_Development_Workstation.md`, `02_Infrastructure/AWS_Account_Preparation.md`, `02_Infrastructure/IAM_and_Access.md`, `02_Infrastructure/Networking.md`, `01_Architecture/Naming_Convention.md`, `01_Architecture/Standards.md`, `16_Implementation_Notes/Terraform_Bootstrap_Implementation_Plan.md`, `16_Implementation_Notes/PROJECT_EXECUTION_JOURNAL.md`, `infrastructure/terraform/bootstrap/README.md`, `infrastructure/terraform/bootstrap/outputs.tf`, and (for this revision) `infrastructure/terraform/bootstrap/main.tf` and `infrastructure/terraform/bootstrap/backend.hcl.example`. No file, directory, Terraform command, AWS CLI command, or AWS resource described in this document has been created, run, or modified. No account ID, ARN, bucket name, or other account-specific identifier is invented anywhere in this plan.*

Last updated: 2026-07-26 (finalization pass — deployment-role IAM policy drafted in full, egress/AZ/IMDSv2/bootstrap-script scope finalized, all three documentation conflicts resolved and source documents updated, plan status changed to REVIEWED AND APPROVED — see "Revision History" at top)
