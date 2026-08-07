# CI/CD Foundation — Design

Status: **Design approved. Implementation slice 1 (AWS OIDC trust only, `infrastructure/terraform/bootstrap/` source) written 2026-08-07 — NOT applied to real AWS. Implementation slice 2A (PR validation workflow, `.github/workflows/terraform-ci.yml`) written to source 2026-08-07 — untrusted, credential-free, no AWS access, not yet exercised by a real pull request.** No apply-capable or OIDC-authenticated GitHub Actions workflow exists yet. This document is the architecture for Phase 0's CI/CD Foundation workstream (`PROJECT_BLUEPRINT.md` §11 Step 9: "GitHub Actions validation, Terraform fmt, Terraform validate, security scan, plan generation, manual approval design for later production deployment"). It follows this project's design-then-implement pattern (`10_Cost_and_FinOps/Cost_Controls.md`, `02_Infrastructure/KMS_and_Secrets.md`). Companion ADR: `01_Architecture/ADRs/ADR-0006-cicd-foundation.md` (status remains **Proposed** until slice 1 is applied and validated on real AWS).

**Exact GitHub repository this design is scoped to, per explicit authorization: `DataEngAA/Enterprise_Data_Platform`.** This resolves unresolved decision #1 from the original version of this document (Section 15).

**Slice 1 — AWS OIDC trust only (Section 2's Hop 1 and the deployment-role trust addition in Section 4) — implemented in source, not yet applied:**

- `aws_iam_openid_connect_provider.github_actions` — the OIDC identity provider for `token.actions.githubusercontent.com`, audience `sts.amazonaws.com`. `thumbprint_list` is deliberately omitted, not populated: confirmed against current Terraform Registry documentation that `thumbprint_list` has been **optional** on `aws_iam_openid_connect_provider` since the AWS provider's v5.81.0 release (December 2024, PR #37255) — well within this configuration's `>= 6.0.0` floor. AWS IAM validates the OIDC provider's certificate against its own trusted root CA library for providers like GitHub's rather than requiring a caller-supplied thumbprint, and derives one itself when none is given. An earlier draft of this slice added a `data.tls_certificate` lookup (and a `hashicorp/tls` provider dependency) specifically to populate this argument, on the incorrect assumption it was still schema-required — removed once the current documentation was checked, before any real Terraform validation was run. This configuration has no dependency on any provider other than `hashicorp/aws`.
- `data.aws_iam_policy_document.github_actions_trust` and `aws_iam_role.github_actions` — the dedicated `enterprise-data-platform-shared-github-actions-role`, trusted only via `sts:AssumeRoleWithWebIdentity`, gated by exact-match (`StringEquals`, no `StringLike`) `aud`/`sub` conditions restricted to `DataEngAA/Enterprise_Data_Platform`'s `ref:refs/heads/main` and `environment:aws-dev` claims only.
- `data.aws_iam_policy_document.github_actions_permissions`, `aws_iam_policy.github_actions_permissions`, and its attachment — the role's only permission: `sts:AssumeRole` on the exact deployment-role ARN.
- One new, additive statement (`AllowGitHubActionsRoleAssumeRoleNoMfa`) on the existing `data.aws_iam_policy_document.deployment_role_trust` — the human-MFA statement and the workstation-role statement are both unchanged.
- New outputs: `github_oidc_provider_arn`, `github_actions_role_arn`, `github_actions_role_name`, `github_actions_permissions_policy_arn`.

**Explicitly not part of slice 1** (unchanged from this document's original scope, still future work): any GitHub Actions workflow YAML; any change to `kms-secrets/`, `cost-controls/`, or `environments/dev`; any change to `bootstrap/`'s or `logging/`'s own human-direct authentication; a real `terraform apply`. Bootstrap-operator permissions were reviewed (Section 15, item 1, now resolved) — no new grant was identified as necessary; OIDC-provider/role/trust-policy creation is the same category of IAM action already required to create the deployment role itself, already covered by the human bootstrap identity's own, Terraform-external permission setup (`bootstrap/README.md` "Prerequisites").

Governing constraints for slice 1, as authorized: no `terraform apply` run; no `.github/workflows/*.yml` written; no application/data stack modified; no change to `bootstrap`'s/`logging`'s authentication behavior.

---

## 1. Why This Workstream, and What It Must Not Break

Phase 0's four completed workstreams (IAM foundation, Logging and Audit, Networking Hardening, KMS and Secrets) plus Cost Controls established a specific, deliberate authorization model that this design must extend, not bypass:

- **One shared, human-MFA-authenticated deployment role** (`enterprise-data-platform-shared-deployment-role`) is the sole identity that ever mutates most Terraform-managed infrastructure (`dev/*`, `kms-secrets/*`, `cost-controls/*`), trusted today by exactly two principals: the human bootstrap IAM user (MFA-required) and the EC2 workstation role (no MFA, since an instance profile cannot supply one) — see `bootstrap/main.tf`'s `deployment_role_trust` document.
- **`bootstrap/` and `logging/` deliberately authenticate human-direct**, not through the deployment role — `bootstrap/` because it is the self-referential root of trust (the deployment role's own definition lives here), and `logging/` because routing it through the deployment role would have required expanding that role's permissions for `cloudtrail:*`/`logs:*`/`sns:*` and new non-runtime IAM-role creation, which was explicitly out of scope when that workstream was implemented (`infrastructure/terraform/logging/README.md`, "Why this stack authenticates human-direct").
- **Every new domain gets its own dedicated managed IAM policy** once a shared policy approaches AWS's 6,144-byte managed-policy quota, never a compressed/merged statement (established repeatedly: networking, KMS/Secrets, Cost Controls state-access — `PROJECT_EXECUTION_JOURNAL.md` Sections 27ap/27aq).
- **Every IAM grant is scoped to the exact action and exact resource ARN the real, evidenced need requires** — no wildcard action, no untagged/unscoped resource grant, condition-scoped where AWS's API supports it.

A CI/CD design that let GitHub Actions assume the deployment role directly, or that gave a GitHub-facing role any permission beyond what's needed to reach the deployment role, would quietly widen every one of those boundaries at once — an external, semi-automated caller would gain the same reach as the human-MFA/workstation-only trust boundary this project has spent five workstreams narrowing. The design below is built around not doing that.

---

## 2. Proposed Architecture — Trust Flow

```text
GitHub Actions (workflow run, this repo only)
    |
    | (1) OIDC token exchange -- short-lived, per-run, no stored secret
    v
AWS IAM OIDC Identity Provider (token.actions.githubusercontent.com)
    |
    | (2) sts:AssumeRoleWithWebIdentity, trust conditioned on repo + branch/environment
    v
enterprise-data-platform-shared-github-actions-role   <-- NEW, this workstream
    |
    | (3) sts:AssumeRole, a SEPARATE, explicit hop -- not implicit,
    |     not inherited, the GitHub role's own credentials are never
    |     used to touch a Terraform-managed resource directly
    v
enterprise-data-platform-shared-deployment-role   <-- EXISTING, unchanged trust
    |
    | (4) the deployment role's own existing, already-scoped permissions --
    |     nothing new granted to it by this workstream
    v
Terraform-managed AWS resources (dev/*, kms-secrets/*, cost-controls/*, ...)
```

Two hops, not one, is the load-bearing design decision here (requirement 2). The GitHub Actions role is deliberately a thin, near-empty identity whose only job is to pass the OIDC-established "this really is a workflow run from this exact GitHub repository" fact into a second, conditioned `sts:AssumeRole` call — it does not itself accumulate `s3:*`/`ec2:*`/service-specific permissions. This mirrors the shape this project already uses for the EC2 workstation (`bootstrap/main.tf`'s `AllowDevWorkstationRoleAssumeRoleNoMfa` statement): a narrow, purpose-built identity trusted to reach the deployment role, not a second copy of the deployment role's own permission set.

`logging/` and `bootstrap/` are explicitly excluded from this trust chain (Sections 4 and 5, below) — CI never gains a path to either through the GitHub Actions role, at any hop.

---

## 3. OIDC Trust Policy Shape (proposed, not implemented)

The OIDC identity provider (`token.actions.githubusercontent.com`, thumbprint managed by AWS's own OIDC provider validation, standard `sts.amazonaws.com` audience) is a one-time, account-level, shared resource — analogous in scope to the existing deployment role, not owned by any single stack. Its creation would be a `bootstrap/`-level or dedicated `cicd/`-level resource (Section 12).

`enterprise-data-platform-shared-github-actions-role`'s trust policy, in shape (no real values, matching this project's standing rule against inventing account IDs/ARNs):

```text
Principal: Federated <OIDC provider ARN for token.actions.githubusercontent.com>
Action: sts:AssumeRoleWithWebIdentity
Condition:
  StringEquals:
    token.actions.githubusercontent.com:aud = "sts.amazonaws.com"
    token.actions.githubusercontent.com:sub = [
      "repo:DataEngAA/Enterprise_Data_Platform:ref:refs/heads/main",
      "repo:DataEngAA/Enterprise_Data_Platform:environment:aws-dev"
    ]
```

**Implemented exactly as shown, in `infrastructure/terraform/bootstrap/main.tf` (`data.aws_iam_policy_document.github_actions_trust`)** — both `sub` values use `StringEquals` against a list (an exact-match OR across the two approved values, not `StringLike`, and not a single combined pattern), per the explicit instruction not to trust any wildcard, `pull_request_target`, tag ref, or other GitHub Environment.

Two load-bearing restrictions, both required by requirement 1:

- **`aud` pinned to `sts.amazonaws.com`** — the standard, AWS-documented audience restriction; without it, a token minted for an unrelated audience could theoretically be replayed.
- **`sub` restricted to the exact repository, and further restricted by ref/environment** — GitHub's OIDC token `sub` claim encodes repository, ref, and (when a GitHub Environment gates the job) environment name. Scoping this condition to `repo:<org>/<repo>:...` and nothing broader means no other repository in the org (or elsewhere) can ever assume this role, even if it discovers the role ARN. Two `sub` patterns are proposed, not one, corresponding to two different classes of workflow (Section 7): a `ref:refs/heads/main` pattern for jobs that only need read/plan-level access gated by branch, and an `environment:aws-dev` pattern for jobs that require the protected GitHub Environment's own manual-approval gate (Section 8) — **the environment-scoped condition is the only one ever combined with permission to reach the deployment role for a mutating action.** Pull-request-triggered jobs (Section 7) use neither pattern for anything beyond read-only/plan access, and are further restricted by requirement 14's forked-PR mitigation below.

The exact `<org>/<repo>` value is an unresolved decision (Section 14) — this project's real GitHub repository identity was not found in the reviewed documentation and must not be guessed.

---

## 4. Role Assumption Chain — Detail

**Hop 1 — `enterprise-data-platform-shared-github-actions-role`.** Trusted only by the OIDC provider, only for this repository, only for the specific `sub` patterns above. Its own permission set (attached policy, not assumed) is deliberately minimal — the minimum required to (a) call `sts:AssumeRole` on the deployment role's ARN and nothing else, and (b) whatever narrow, pre-assumption AWS read access a workflow genuinely needs before it can assume anything (Section 6 — expected to be empty or near-empty in practice). No service-specific data-plane permission (`s3:*`, `ec2:*`, `kms:*`, etc.) is ever attached directly to this role.

**Hop 2 — `enterprise-data-platform-shared-deployment-role`.** Its trust policy gains exactly one new statement, additive only: a principal statement trusting `enterprise-data-platform-shared-github-actions-role`'s ARN, structurally parallel to the existing `AllowDevWorkstationRoleAssumeRoleNoMfa` statement (no MFA condition, since an OIDC-derived federated identity cannot supply one, exactly the same reasoning already accepted for the EC2 workstation role). The existing `AllowHumanBootstrapPrincipalAssumeRoleWithMFA` statement is untouched. **No existing permission attached to the deployment role changes as a result of this workstream** — GitHub Actions, once it reaches this role, is bound by exactly the same, already-reviewed, already-scoped permission boundary every other caller of this role is bound by (requirement 3). This is the single design fact that satisfies "do not allow GitHub to bypass the existing shared deployment-role authorization boundary" — there is no separate, wider grant lurking anywhere in the chain; the deployment role's permission set is the ceiling for every path that reaches it, GitHub included.

---

## 5. Bootstrap — CI Validates It, Never Applies It

`bootstrap/` is self-referential: it defines the deployment role and its own state-access permissions, authenticated human-direct (never through the deployment role, by design — the deployment role cannot be the thing that grants itself permissions). Extending automatic CI apply to `bootstrap/` would mean a GitHub-triggered workflow could, in principle, rewrite the very trust boundary this whole design depends on — a privilege-escalation path this document explicitly refuses to open (requirement 4, requirement 14).

Proposed treatment: `bootstrap/` participates in the **PR validation workflow** (`fmt -check`, `init -backend=false`, `validate`, security scan — Section 7) like every other stack, using no AWS credentials at all for those steps (all four run against local source only, no state read, no plan). `bootstrap/` is explicitly **excluded from the plan-generation and apply-eligible stack list** (Section 9's eligibility matrix) — no workflow ever runs `terraform plan` or `terraform apply` against `bootstrap/` using the GitHub Actions role or the deployment role. Any real `bootstrap/` change continues to require the existing human-direct, MFA-authenticated `login.ps1` workflow this project already uses, on the user's own machine, exactly as every bootstrap change to date has been applied. This is a deliberate, permanent asymmetry, not a placeholder to close later without a separately reasoned decision.

---

## 6. Logging and Audit — Preserved As Human-Direct

`logging/`'s human-direct authentication was a considered design decision (Section 1, above; `ADR-0002` Option 3; `infrastructure/terraform/logging/README.md`), not an oversight — CloudTrail, the audit bucket, the CloudTrail-to-CloudWatch role, the SNS topic, and the security alarms are treated as account-level trust-and-audit infrastructure analogous to bootstrap's own resources, deliberately kept outside the deployment role's reach. Routing `logging/` through CI (which would require either expanding the deployment role's permissions to cover `cloudtrail:*`/`logs:*`/`sns:*`, or granting the GitHub Actions role its own separate path to `logging/`'s state) would silently reopen a boundary this project already closed once, without a new ADR reconsidering it.

Proposed treatment: identical to `bootstrap/` — `logging/` participates in `fmt`/`init -backend=false`/`validate`/security-scan on every PR, using no AWS credentials, but is **excluded from CI plan generation and apply**. If `logging/` needs a Terraform change in the future, it continues to be applied human-direct exactly as it is today. Preserving this is an explicit requirement (requirement 5) and is treated here as durable unless a future, separately justified ADR reopens it — this document does not reopen it.

---

**Implementation slice 2A — PR validation workflow only, implemented in source (2026-08-07): `.github/workflows/terraform-ci.yml` exists.** This is steps 1–4 of Section 7 below (`fmt`, `init -backend=false`, `validate`, Checkov), for all five stacks currently in scope. It deliberately does **not** implement step 5 (the OIDC-authenticated plan-on-PR step) — that remains a separate, later implementation slice, tracked as still-future in Section 7 below. Slice 2A requests no `id-token` permission, uses no `aws-actions/configure-aws-credentials` or any other AWS-authenticating action, and cannot reach AWS by construction — safe to run, unreviewed, against a forked pull request. See this slice's own implementation report for the exact Terraform/Checkov version pins used. **Correction (2026-08-07, before the first real GitHub PR test):** the trigger's `paths` filter was removed entirely — this workflow is intended to become a required PR check, and a path-filtered required check produces no result at all for a PR touching none of the matched paths, which could block that PR from merging. The workflow now runs on every pull request targeting `main`, unconditionally; this also resolves the "path-filtered triggers vs. required status checks" risk previously flagged in Section 14, below.

## 7. PR Workflow (proposed)

Triggered on every pull request, unconditional (requirement 7 — never gated behind an environment approval, since nothing here mutates anything):

1. **`terraform fmt -check -recursive`** — every stack, no AWS credentials. **Implemented (slice 2A) — `.github/workflows/terraform-ci.yml`, `terraform-validate` job, per-stack matrix.**
2. **`terraform init -backend=false`** — every stack that has a `backend.tf` (all of them); local-only initialization, never touches the real state bucket, never needs AWS credentials. **Implemented (slice 2A).** Provider resolution prefers each stack's own checked-in `.terraform.lock.hcl` (present for all five in-scope stacks) — `terraform init`'s own default behavior when a lock file already exists, no extra flag needed.
3. **`terraform validate`** — every stack, no AWS credentials. **Implemented (slice 2A).**
4. **IaC security scanning** — Checkov (Section 12), every stack, no AWS credentials, source-only. **Implemented (slice 2A)** — a separate `checkov` job, pinned version, scans `infrastructure/terraform/` in one pass rather than per-stack (Checkov itself handles a multi-module tree natively; no per-stack repetition needed for a static source scan the way `validate` needs it for schema/provider-specific checking).
5. **`terraform plan`** — **only for eligible stacks** (Section 9's matrix), using a **read/plan-scoped path through the same two-hop OIDC chain**, gated by the `ref:refs/heads/main`-class `sub` condition (not the `environment:aws-dev` condition — plan-on-PR does not require the protected-environment gate, since it never mutates anything, but it does still require the exact-repository OIDC restriction). Plan output is never applied automatically from a PR context (requirement 7 — "absolutely no apply"). **NOT implemented by slice 2A — explicitly deferred to a later, separate implementation slice.** `.github/workflows/terraform-ci.yml` requests no `id-token` permission and cannot perform this step; a future slice will add a second workflow (or a second job in a workflow restricted to non-forked PRs) for it.

**No step in this workflow ever runs against a forked-repository pull request with write-level or credentialed access** — see requirement 14's `pull_request_target` discussion (Section 14). Steps 1–4 can safely run under the ordinary `pull_request` trigger (read-only checkout, no secrets, no OIDC token available or needed). Step 5, which does require an OIDC token, is proposed to run **only for pull requests originating from a branch within this repository itself** — not from forks — until a specific, reviewed need for forked-PR plans is identified (Section 14 flags this as an explicit residual risk if ever revisited).

---

## 8. Main/Apply Workflow (proposed)

Triggered on push/merge to `main`, for eligible stacks only (Section 9):

1. **Re-validate** — `fmt -check`, `validate`, security scan re-run against the merged `main` state (not trusted from the PR run — a merge can combine two individually-valid PRs into a combination neither was checked against).
2. **Regenerate the plan** — a fresh `terraform plan` is generated at deployment time, against current remote state, through the same two-hop OIDC chain. **The PR-time plan from Section 7 is never reused for apply** — this satisfies both requirement 8 ("regenerate/validate the plan at deployment time rather than trusting a stale PR plan") and requirement 9's operational rule (a saved plan must never be reused after any state-changing or state-refreshing gap, and the gap between PR-open and merge-to-main is exactly such a gap: other merges, manual applies, or drift could have occurred in between).
3. **Manual approval gate** — the apply job runs inside a **protected GitHub Environment** (proposed name: `aws-dev`, matching the naming the user specified; one environment per target, e.g. a future `aws-prod` when multi-environment work begins). GitHub Environments support required reviewers, meaning the job pauses and waits for an explicit human approval click before the environment's secrets/OIDC-claims become available to the job at all — this is what the `sub: repo:<org>/<repo>:environment:aws-dev` trust-policy condition (Section 3) exists to gate: **only a workflow job running inside the approved, reviewer-gated environment can ever present a token the deployment-role-reaching trust policy accepts for a mutating action.** No automatic, unattended apply path exists anywhere in this design (requirement 8, "no blind automatic apply").
4. **Apply** — only after approval, only the freshly regenerated plan from step 2, only for the one eligible stack the workflow run targets.

**Failure behavior:** any failure in steps 1–2 halts before reaching the approval gate — a human is never asked to approve a deployment behind a plan that didn't validate. A failure during apply (a real, partial-apply scenario, which this project has hit repeatedly during manual work — `PROJECT_EXECUTION_JOURNAL.md` Sections 58–63, 27aq) does not trigger any automatic retry or rollback; the workflow reports failure and stops, and recovery follows this project's existing, established manual pattern: fresh `terraform plan` against current state, reviewed by a human, before any further apply — never a re-run of the same saved plan.

---

## 9. Stack Eligibility Matrix (proposed)

| Stack | `fmt`/`validate`/scan (PR) | `plan` (PR, via OIDC) | `plan`+`apply` (main, via OIDC, manual approval) | Authentication path |
|---|---|---|---|---|
| `bootstrap/` | Yes | **No** | **No — permanently excluded (Section 5)** | Human-direct only, unchanged |
| `logging/` | Yes | **No** | **No — excluded pending a future, separate ADR (Section 6)** | Human-direct only, unchanged |
| `kms-secrets/` | Yes | Yes | Yes | Two-hop OIDC -> deployment role (existing `assume_role` pattern, unchanged) |
| `cost-controls/` | Yes | Yes | Yes | Two-hop OIDC -> deployment role (existing `assume_role` pattern, unchanged) |
| `environments/dev` | Yes | Yes | Yes | Two-hop OIDC -> deployment role (existing `assume_role` pattern, unchanged) |
| Future ingestion/processing stacks | Yes | Presumed yes, per-stack review at design time | Presumed yes, per-stack review at design time | Two-hop OIDC -> deployment role, unless a stack's own design calls for human-direct auth (same reasoning test as Section 6) |

No stack currently in this repository authenticates via a mechanism this design would need to change — `kms-secrets/`, `cost-controls/`, and `environments/dev` already assume the deployment role today (human-triggered); this workstream only adds a second, OIDC-authenticated caller capable of reaching that same role through the same trust boundary, it does not alter how any of the three already reach it.

---

## 10. Terraform Plan Artifact Handling (proposed)

A `.tfplan` binary can contain sensitive values (resource attributes, sometimes-unmasked variable values) and must be treated accordingly (requirement 9):

- **No raw `.tfplan` file is ever uploaded as a public or repo-wide-downloadable GitHub Actions artifact.** If a plan file needs to persist between a plan step and an apply step within the *same* workflow run (not across runs, not across PR-to-main), it uses `actions/upload-artifact`/`download-artifact` scoped to that run only, with the shortest viable retention (proposed: 1 day), never a permanently retained or publicly exposed artifact.
- **Human-readable output is a redacted plan summary, not the raw plan.** Proposed: `terraform show -no-color <plan>` piped through a redaction step (masking anything tagged `sensitive` in the Terraform configuration, which every secret-adjacent resource in this project's existing stacks already marks) before being posted as a PR comment or job summary — this gives reviewers the "what would change" signal requirement 9 asks for without exposing the full binary plan.
- **The PR-time plan is never carried into the apply job** (Section 8, step 2) — this is both a freshness requirement and a artifact-handling one: the shorter a plan artifact's lifetime, the smaller its exposure window.
- **The standing operational rule is restated as a hard workflow property, not just a documentation note**: if any step in a run detects a prior partial apply or an unexpected state (e.g., a `plan` step that would itself indicate drift inconsistent with the last known-good state), the workflow is designed to fail closed rather than proceed with a plan computed before that detection — consistent with this project's repeated real-incident lesson (`PROJECT_EXECUTION_JOURNAL.md`, "never reuse a saved Terraform plan after a partial apply or any state change").

---

## 11. Concurrency Strategy (proposed)

GitHub Actions' native `concurrency` key, applied per stack-and-environment, not globally:

```text
concurrency:
  group: terraform-<stack-name>-<environment>
  cancel-in-progress: false
```

`cancel-in-progress: false` is deliberate, not an oversight — cancelling an in-flight `apply` mid-run is a worse outcome than making a second run wait, since a cancelled apply can leave a stack in exactly the partial state this project has hit repeatedly through manual work. A second run targeting the same `<stack-name>-<environment>` group queues behind the first rather than racing it or interrupting it; a run targeting a *different* stack or a different environment is a different concurrency group entirely and proceeds independently. This directly satisfies requirement 10 ("two Terraform mutations against the same environment/stack cannot race") using GitHub Actions' own built-in primitive rather than a custom lock mechanism — Terraform's own S3-native state locking (already in use by every stack in this project) remains the second, independent layer of protection underneath this one, exactly as it already protects the existing human-triggered workflow today.

---

## 12. Security Scanning (proposed)

**Checkov, proposed as the sole primary Terraform IaC scanner** (requirement 11) — a mature, actively maintained, Terraform-native policy scanner with broad AWS coverage, comparable in role to Trivy's config-scanning mode (already used by this project for the manual validation gates recorded in `Bootstrap_Checklist.md`) but purpose-built for IaC rather than being a general vulnerability/config/secret scanner repurposed for it. No second scanner is proposed alongside it — this project's own standing practice (Trivy alone for manual gates) already established that one well-chosen scanner, reviewed and dispositioned deliberately, is preferred over stacking multiple tools without a concrete, stack-specific reason neither this document nor prior workstreams have identified. If a future stack surfaces a real gap Checkov's ruleset doesn't cover (e.g., a scanner specialized in a service this project doesn't use yet), that would be a new, separately reasoned decision, not a default.

Findings handling mirrors this project's existing Trivy disposition pattern (`Bootstrap_Checklist.md`'s Trivy entry): every finding is reviewed and explicitly dispositioned (accepted-with-reason, fixed, or flagged as a known residual risk) — a CI scan failing the PR check by default on any new HIGH/CRITICAL finding, with an explicit, reviewed, in-repository suppression (not a silent `.checkov.yaml skip-check` added without a recorded reason) required to pass a finding through. No blanket suppression file is proposed as part of this design.

---

## 13. Files That Would Eventually Be Created or Changed (not created now)

Grouped by what this document's *approval* would authorize designing in detail next, not what exists today:

- `.github/workflows/pr-validate.yml` — Section 7's PR workflow (fmt/validate/scan/plan-for-eligible-stacks).
- `.github/workflows/apply-<stack>.yml` (one per eligible stack, or one parameterized workflow reused across stacks — an open design choice, Section 14) — Section 8's main/apply workflow.
- `.github/PULL_REQUEST_TEMPLATE.md` — already anticipated, not yet created, by `03_Development/Git_Workflow.md` Section 2.
- `infrastructure/terraform/bootstrap/main.tf` — the one new, additive trust-policy statement on `deployment_role_trust` (Section 4); likely also where the OIDC identity provider resource itself is defined, as an account-level, `bootstrap`-adjacent, human-applied resource (or a new dedicated `cicd/` stack — Section 14, unresolved).
- A new `infrastructure/terraform/cicd/` root stack (if the OIDC-provider-plus-GitHub-Actions-role resources are not folded into `bootstrap/`) — its own `providers.tf`/`backend.tf`/`main.tf`/`variables.tf`/`outputs.tf`/`README.md`, human-direct authenticated (matching `bootstrap/`'s and `logging/`'s pattern, since this stack is itself part of the trust root, not a consumer of it).
- `02_Infrastructure/CI_CD.md` (this document) and `01_Architecture/ADRs/ADR-0006-cicd-foundation.md` — updated from "design" to "implemented and validated" status once real work begins, following this project's established pattern.
- `01_Architecture/Naming_Convention.md` — a new entry for the GitHub Actions role name and any new resource-naming pattern this workstream introduces (e.g., the OIDC provider resource, workflow file naming).
- `00_Project_Management/Memory.md`, `16_Implementation_Notes/PROJECT_EXECUTION_JOURNAL.md`, `16_Implementation_Notes/Bootstrap_Checklist.md`, `17_Interview_Guide/Phase_0.md` — updated at implementation-closure time, matching every prior Phase 0 workstream's documentation pattern.

**None of the above is created or modified by this task.**

---

## 14. Risks and Mitigations

**Public repository / forked pull-request execution.** If this repository is public (or becomes public), any external contributor can open a pull request. GitHub's default `pull_request` trigger runs against the PR's own merge commit but — critically — does **not** expose repository secrets or an OIDC token capable of reaching this design's role chain to workflows triggered by a forked PR, which is exactly why Section 7 restricts plan-on-PR (the only PR-time step needing AWS access) to PRs opened from a branch within this repository, not from forks. *Mitigation:* keep the forked-PR restriction explicit in the workflow's own trigger conditions (not just an assumption about GitHub's defaults, which can be misconfigured); never add `pull_request_target` to any step that reads a fork's own code (see next risk).

**`pull_request_target` dangers.** `pull_request_target` runs with the *base* repository's permissions and secrets, but can be configured to check out the *fork's* code — a well-documented, real-world source of secret-exfiltration and repo-compromise incidents when combined carelessly. *Mitigation:* this design does not use `pull_request_target` anywhere. If a future need arises (e.g., posting a PR comment with results that requires write permission the default `pull_request` trigger doesn't have), the safe pattern is a **two-workflow split** — an untrusted `pull_request`-triggered workflow that runs the actual validation/plan with no secrets, uploads its results as an artifact, and a separate, trusted `workflow_run`-triggered workflow (which does not check out the fork's code at all) that only reads that artifact and posts the comment. This split is flagged here as the correct pattern to reach for, not implemented now, since no PR-comment-posting requirement exists yet in this design.

**OIDC trust becoming too broad over time.** The single greatest way this design could quietly degrade is the `sub` condition (Section 3) drifting from an exact repository/ref/environment match toward a broader `StringLike` wildcard (e.g., matching any ref, or any repository in an org) added for convenience during some future debugging session. *Mitigation:* treat the `sub` condition's exactness as a standing invariant, reviewed every time the trust policy is touched, the same discipline already applied to every exact-ARN IAM statement elsewhere in this project; any proposed widening requires a new ADR, not an inline edit.

**Privilege escalation through bootstrap.** Covered in depth in Section 5 — the mitigation is structural (bootstrap is permanently excluded from CI's plan/apply eligibility, not just discouraged by convention) rather than relying on a reviewer noticing a bad PR.

**Stale Terraform plans.** Covered in Sections 8 and 10 — the mitigation is that no apply step is designed to ever consume a plan artifact from a different job run than its own regenerate-then-apply pair, and artifact retention is deliberately short.

**Secrets in Actions logs/artifacts.** No long-lived AWS credential ever exists in this design (the entire point of OIDC) — the residual risk is a Terraform *output* or *plan diff* itself containing sensitive data (e.g., a Secrets Manager ARN's context, though not the actual secret value, since this project's existing `kms-secrets` design already keeps real secret values out of Terraform state entirely). *Mitigation:* Section 10's redacted-plan-summary approach, plus GitHub Actions' own log-masking for any value explicitly marked `sensitive` in Terraform output blocks — an existing Terraform-native mechanism this design relies on rather than reinvents.

**Concurrent Terraform operations.** Covered in Section 11 — GitHub Actions `concurrency` groups per stack-and-environment, backed by Terraform's own existing S3-native state locking as a second, independent layer.

**Path-filtered triggers vs. required status checks — RESOLVED (2026-08-07, before the first real GitHub PR test).** `.github/workflows/terraform-ci.yml`'s `pull_request` trigger originally carried a `paths` filter (`infrastructure/terraform/**`, the workflow file itself), on the reasoning that it should only run when a file it could say something useful about had changed. This was corrected before this workflow was ever exercised against a real PR: GitHub's own documented behavior is that a path-filtered workflow does not run at all — and therefore never reports any check result, pass or fail — for a pull request that touches none of the matched paths, which would have permanently blocked such a PR from merging once this workflow's jobs are configured as required status checks. The `paths` filter was removed entirely; the workflow now triggers on every pull request targeting `main`, unconditionally, trading the modest savings of skipping non-Terraform PRs for an always-present, deterministic required check.

---

## 15. Unresolved Decisions

These require an explicit answer, from the user, before implementation begins — none is guessed or defaulted in this document:

1. ~~**The real GitHub organization/repository identity**~~ — **RESOLVED (2026-08-07): `DataEngAA/Enterprise_Data_Platform`**, explicitly authorized and now used throughout Section 3's trust policy and slice 1's real Terraform source (`infrastructure/terraform/bootstrap/main.tf`).
2. **Whether the repository is (or will be) public or private** — materially changes the weight of the forked-PR risk (Section 14) and whether GitHub's branch-protection/environment-approval features are available on the plan being used (some GitHub Environment protection features are plan-tier-gated).
3. **Whether the OIDC provider and GitHub Actions role live inside `bootstrap/` itself, or in a new, dedicated `cicd/` stack** (Section 13) — both are human-direct, account-level, trust-root-adjacent resources by this design's own logic; `bootstrap/`'s existing self-referential nature is an argument for keeping the whole trust root in one place, while a dedicated stack is an argument for not letting `bootstrap/main.tf` grow indefinitely (echoing the same managed-policy-size discipline already applied elsewhere).
4. **Whether one parameterized apply workflow serves all eligible stacks, or each stack gets its own dedicated workflow file** (Section 13) — a maintainability/blast-radius trade-off not yet decided.
5. **The exact protected-GitHub-Environment name(s) and required-reviewer list** — `aws-dev` is proposed per the user's own naming, but the actual reviewer(s) who must approve a deployment is a real, human staffing decision this document cannot make.
6. **Whether future multi-environment work (`test`/`stage`/`prod`) reuses one GitHub Actions role with per-environment `sub` conditions, or gets a dedicated role per environment** — not decided; likely revisited once multi-environment groundwork (`PROJECT_BLUEPRINT.md` §11 Step 10) actually begins.
7. **Checkov version pinning and update cadence** — a real operational detail (unpinned scanner versions can introduce new, unreviewed-at-merge-time failures) not yet designed.

---

## Related Files

- `01_Architecture/ADRs/ADR-0006-cicd-foundation.md` — the companion architecture decision record.
- `infrastructure/terraform/bootstrap/main.tf` — the existing deployment-role trust policy this design's one new statement would extend.
- `infrastructure/terraform/logging/README.md` — the existing, considered rationale for human-direct authentication this design preserves for `logging/`.
- `10_Cost_and_FinOps/Cost_Controls.md`, `02_Infrastructure/KMS_and_Secrets.md` — the two most recent design-then-implement precedents this document's structure follows.
- `03_Development/Git_Workflow.md` — the existing branch/PR process this workstream's workflows attach to.
- `01_Architecture/Naming_Convention.md` — naming conventions this design's new resources (the GitHub Actions role, any new stack) must follow once implemented.

Last updated: 2026-08-07 (implementation slice 2A — PR validation workflow, `.github/workflows/terraform-ci.yml` — written to source: per-stack `fmt`/`init -backend=false`/`validate` matrix plus a pinned Checkov scan, no AWS access, no `id-token`, no write permissions. Slice 1 — AWS OIDC trust only, `infrastructure/terraform/bootstrap/` — remains written to source but not applied to real AWS. Neither slice constitutes CI/CD Foundation completion; no apply-capable workflow exists).
