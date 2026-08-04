# EC2 Development Workstation — Design Document

Status: **Design only. No AWS resources created or deployed. No Terraform written.**

This document is the authoritative, detailed design for the Pre-Phase EC2 development workstation described in `PROJECT_BLUEPRINT.md` Section 5 (EC2 Development Workstation Strategy) and Section 10, Step 4. It has been reviewed and revised to incorporate approved decisions. `02_Infrastructure/EC2_Development_Environment.md` now redirects here rather than duplicating this content (see the "Relationship to Existing Documentation" note at the end of this document).

Account-level decisions this design depends on (region, budget, billing alerts, dedicated VPC, default-VPC policy, no-NAT initial strategy, IAM/MFA prerequisites) are now approved and documented separately in `02_Infrastructure/AWS_Account_Preparation.md` — this document assumes those decisions and does not repeat them in full.

**Note on a naming inconsistency in the approved decisions:** the review request that produced this revision described the instance-sizing tiering (Section 6) using the `t4g` (Graviton/ARM64) family, but the same review's "Approved decisions" list explicitly sets the architecture to x86_64 with `t3.medium` / `t3.large` / `t3.xlarge`. This document follows the explicit x86_64 / `t3` approved decision as authoritative and applies the same tiering logic (default, heavy, exceptional-temporary) to the `t3` family. Flagging this rather than silently picking one — confirm this reading is correct.

---

## 1. Purpose and Scope

Provide a single, disciplined, stoppable cloud development workstation that lets the user build, test, and administer this project without depending on the local 8 GB laptop for anything heavier than a browser, an editor UI, and light terminal use.

In scope: instance design, OS, architecture, sizing, storage, networking placement, security group design, access model, IAM, tool installation, cost controls, backup/recovery, and acceptance criteria.

Out of scope (deliberately, per current constraints): actual deployment, Terraform code, AWS account creation, region/budget decisions, and any application workloads beyond the workstation itself (e.g., no Glue/Lambda/Redshift design here — those belong to Phase 0 and later).

## 2. Why EC2 Instead of the Local 8 GB Laptop

The laptop's 8 GB RAM cannot reliably run Docker-heavy workloads, local Spark, multiple databases, browser automation at scale, or memory-intensive integration tests (per `Memory.md` / `PROJECT_BLUEPRINT.md` Section 4). EC2 gives:

- Elastic memory/CPU sized to the task at hand (resize up for a Docker build, back down afterward).
- A consistent, reproducible Linux environment that matches what will eventually run in Fargate/Lambda/EMR, reducing "works on my machine" drift.
- A place to safely hold AWS CLI credentials via an instance role instead of long-lived keys on a personal laptop.
- Independence from the laptop's power/battery/connectivity — the workstation can be reached via Session Manager from any authorized device.

Trade-off: EC2 introduces a running cost and an operational surface (patching, shutdown discipline) that the laptop doesn't have. This is accepted because the alternative (local heavy workloads) isn't feasible on this hardware.

## 3. What Runs on EC2 vs. What Remains a Managed AWS Service

Runs on EC2 (development-time only, per `PROJECT_BLUEPRINT.md` Section 5):

- Git, GitHub CLI access
- Python development, virtual environments
- Terraform CLI (plan/apply from the workstation during Pre-Phase/Phase 0, before CI/CD takes over)
- Docker and Docker Compose (image builds, local container testing)
- dbt CLI
- Java (build tooling, Spark client libraries)
- Small/moderate local Spark samples
- AWS CLI
- PostgreSQL client
- Browser automation development (not production scraping — that is Fargate, per `Architecture.md`)
- Unit/integration test execution
- Documentation editing

Remains a separate, independent managed AWS service (never re-implemented on EC2):

- S3, Lambda, SQS, SNS, EventBridge, Step Functions, ECS Fargate, Glue, EMR Serverless, RDS/Aurora, DynamoDB, Kinesis, Redshift, OpenSearch, QuickSight, Lake Formation

The workstation must be stoppable at any time without affecting any of the above (`Memory.md` operational rule, carried from `PROJECT_BLUEPRINT.md` Section 5).

## 4. Recommended Operating System — APPROVED

**Approved: Amazon Linux 2023.**

Rationale: first-class AWS tooling support (SSM Agent preinstalled), long-term support cadence, minimal licensing/cost overhead, dnf package manager, good container and systemd support.

## 5. Processor Architecture — APPROVED

**Approved: x86_64.**

The instance family and sizing below (Section 6) use x86_64 `t3` instances. (An earlier draft of this document recommended ARM64/Graviton `t4g` for lower cost; that recommendation is superseded by this approved decision. Per `CLAUDE.md` Section 9, a reversible-but-costly architecture choice like this should get an ADR when the project reaches a point of recording ADRs — not created in this documentation-only pass, flagged as follow-up.)

## 6. Instance Family and Sizing — APPROVED

**Approved tiers, all x86_64 burstable `t3` family:**

| Tier | Instance type | vCPU / Memory | Use |
|---|---|---|---|
| Normal workstation (default) | `t3.medium` | 2 vCPU / 4 GiB | Git, editing, light Python, Terraform plan/validate, AWS CLI, small dbt runs, routine day-to-day work |
| Heavy work | `t3.large` | 2 vCPU / 8 GiB | Docker-heavy sessions, browser-automation development, local Spark samples, larger integration-test runs |
| Exceptional temporary work | `t3.xlarge` | 4 vCPU / 16 GiB | Short-lived, unusually demanding sessions (e.g., a large one-off Docker multi-stage build or a heavier local Spark test); not meant to run continuously |
| Optional light-duty | `t3.small` | 2 vCPU / 2 GiB | Not adopted by default. May be introduced later only if testing on `t3.medium` shows 2 GiB is consistently sufficient for routine work. Not recommended as a starting point. |

`t3.medium` replaces the previous `t4g.small` default. Rationale for moving the default up a tier: 2 GiB (the old default) left little headroom for Docker Desktop-equivalent daemon overhead, VS Code server processes, and routine Python/Terraform work running concurrently; 4 GiB gives comfortable routine headroom without jumping straight to a heavy-tier size.

## 7. When and How the Instance Should Be Resized

Resize **up** before starting a known heavy session (Docker build day, local Spark test, larger integration test run, browser-automation development). Resize **down** or stop when done. EC2 instance type changes require the instance to be stopped, the instance type changed, then started again — this is a manual (or scripted) stop/modify/start cycle, not a live resize.

Proposed discipline:
- Default running size: `t3.medium`.
- If a session is known in advance to need Docker-heavy work, browser automation, Spark, or larger integration tests, stop and resize to `t3.large` before starting that session, then resize back down to `t3.medium` afterward.
- Reserve `t3.xlarge` for short, exceptional, temporary sessions only — resize back down immediately afterward, don't leave it running.
- If testing later proves `t3.small` (2 GiB) is sufficient for routine work, it may replace `t3.medium` as the default — not adopted now.
- Document the exact resize command sequence in the eventual Runbook (`06_Runbooks/`) once implemented — not invented here.

## 8. EBS Volume Design — APPROVED

- **Volume type:** `gp3` (better baseline IOPS/throughput per dollar than `gp2`, and IOPS/throughput are independently tunable).
- **Size: 30 GiB, encrypted — approved.** Enough for AL2023, Docker images, a Python virtual environment, Terraform, and a working copy of this repository, with headroom. Increase only if evidence (disk pressure) justifies it.
- **Encryption:** required (approved), using a KMS key (default AWS-managed `aws/ebs` key acceptable initially; a customer-managed key is an option once KMS strategy is decided under Phase 0 Step 7 — not decided yet).
- **Backup:** EBS snapshots, taken manually before major changes at minimum; automating via AWS Backup or a scheduled Lambda is a Phase 0+ concern, not required for the Pre-Phase workstation itself. Snapshot cadence/retention is still a Pending Decision (Section 28).
- **Recovery approach:** treat the instance as disposable (approved principle — see Section 24). The volume itself is not the source of truth for anything durable — GitHub holds code, S3 holds durable artifacts. Recovery = launch a new instance from the bootstrap script/AMI and reclone the repo, not restore-from-snapshot as the primary path. Snapshots are a convenience/time-saver, not a dependency.

## 9. VPC and Subnet Placement — REVISED

**Initial default: public subnet, with an Internet Gateway (IGW) providing outbound reachability.**

This replaces the previous "private subnet, endpoint-first" initial recommendation. Rationale for the change: a public subnet with an IGW gives straightforward, low-friction outbound access for package installation, GitHub, container registries, and general tool downloads, without needing to provision and pay for a NAT Gateway or a set of VPC interface endpoints before Phase 0 networking exists. This keeps the workstation's own design independent of the eventual Phase 0 VPC endpoint strategy.

Critically, **placement in a public subnet does not by itself make the instance reachable from the internet** — reachability is governed entirely by the security group's inbound rules (Section 11), which are empty. See Section 10 for the explicit public-IP-vs-inbound-accessibility distinction.

**Future hardened alternative (not the initial default):** once Phase 0 networking (VPC, subnets, NAT or endpoints) is designed and built, the workstation can be moved into a private application subnet with NAT Gateway or VPC-endpoint egress, removing the public IP and IGW dependency entirely. This is documented as a planned hardening step, not required before the workstation can be used.

## 10. Public IP Requirement — REVISED

**Approved: assign a public IPv4 address to the instance**, to support the public-subnet/IGW networking model in Section 9.

Important clarification: **a public IP address does not create inbound accessibility on its own.** Whether a host with a public IP can be reached from the internet is determined entirely by its security group's inbound rules. This workstation's security group has **zero inbound rules** (Section 11) — no rule permits any inbound connection from any source, on any port, including port 22. The public IP only enables outbound-initiated traffic (the instance reaching out to the internet) and return traffic for connections the instance itself opened; it does not open any door inward. Systems Manager Session Manager access does not depend on the public IP at all — it works over the SSM agent's outbound connection to the SSM service.

Note the cost implication: AWS charges an hourly rate for public IPv4 addresses attached to running instances (in addition to standard data transfer charges) — see Section 26.

## 11. Security Group Design

Principle: default-deny inbound, scoped outbound.

- **Inbound rules: zero.** No rule for SSH (port 22), RDP, or any development port (Jupyter, Docker daemon, databases), to any CIDR — including the user's own IP. This holds regardless of the subnet's public/private status (Section 10). Port 22 is not opened to any CIDR under any circumstance in this design.
- **Outbound rules:** allow HTTPS (443) outbound for package managers, GitHub, AWS APIs, and container registries via the IGW (Section 9). Avoid a blanket `0.0.0.0/0` allow-all if a more scoped rule set is practical once real destinations are known; acceptable to start with outbound-443-anywhere and tighten later, since this is a dev workstation, not a production node.
- No security group rule should ever open a database, Docker daemon, or Jupyter port to `0.0.0.0/0` — this is a hard rule carried from `08_Security/Security.md`.

## 12. Systems Manager Session Manager Access

Primary and only interactive access method — there is no directly network-accessible SSH into this instance:

- SSM Agent must be running (preinstalled on AL2023).
- Requires outbound reachability to `ssm`, `ssmmessages`, `ec2messages` (via the IGW in the initial public-subnet design, or via VPC endpoints/NAT if the future private-subnet hardening in Section 9 is adopted).
- Access controlled through IAM (who can start a Session Manager session), not through network exposure — consistent with the zero-inbound-rule security group (Section 11).
- No key pair is required for interactive login. `sshd` may run on the instance, but solely to support the Session Manager port-forwarding tunnel used for VS Code Remote-SSH (Section 15) — it is never reachable directly over the network, since no inbound security group rule permits a connection to port 22 from anywhere, including via the public IP.
- See Section 23 for what Session Manager logging can and cannot capture for this style of access.

## 13. IAM Architecture — REVISED (Workstation Role Separated from Deployment Role)

Two distinct IAM roles, not one combined role:

### 13.1 Workstation instance role (attached to the EC2 instance profile)

Scope, kept deliberately narrow:
- **SSM core permissions** — to allow Session Manager connectivity (`AmazonSSMManagedInstanceCore`-equivalent).
- **Minimal logging permissions** — to ship instance/session logs to CloudWatch Logs (write-only, scoped to the project's log groups once they exist).
- **Narrowly scoped artifact access, where justified** — e.g., read/write to a specific S3 prefix or bucket used for durable dev artifacts, only if and when such a bucket exists; not account-wide S3 access.
- **`sts:AssumeRole` permission scoped to the Terraform deployment role only** (Section 13.2) — this is how the workstation is allowed to run Terraform, without holding infrastructure-management permissions itself.
- Explicitly **no** broad infrastructure-management permissions (no direct EC2/VPC/IAM/Glue/etc. create-modify-delete permissions on the workstation role itself).
- Explicitly **no** IAM permissions to create/modify IAM (no self-escalation), no permanent-key creation permissions.

### 13.2 Terraform deployment role (separate role, assumed — not attached to the instance)

- Holds the actual infrastructure-management permissions Terraform needs (scoped to the resources Terraform is expected to manage in Phase 0+).
- Is only reachable by explicitly calling `sts:AssumeRole` from the workstation role (or from CI/CD once Phase 8 exists) — it is never the instance's default identity.
- Trust policy restricts who/what can assume it (the workstation role now; the CI/CD pipeline role later).
- Reviewed and scoped in detail during Terraform Bootstrap — exact policy JSON is not written here, per the "do not invent ARNs/policies ahead of the relevant phase" rule.

This split means a compromised or misconfigured workstation session cannot directly mutate infrastructure — it must explicitly assume the deployment role, which is auditable via CloudTrail `AssumeRole` events, and which can be revoked or tightened independently of the workstation's own permissions.

## 14. GitHub Access — APPROVED

**Approved: GitHub CLI (`gh`) interactive authentication** (`gh auth login`, browser/device-flow), performed per session.

- Do not bake a personal access token or SSH private key into the AMI, launch template, or user data script.
- No long-lived GitHub credential is stored on the instance between sessions beyond what `gh`'s own credential storage handles locally on that ephemeral instance.
- Never commit `.git-credentials`, tokens, or SSH private keys to the repository (already enforced by `.gitignore` patterns for `.env`; recommend adding explicit patterns for credential files if any alternate mechanism is used later).

## 15. VS Code Remote Development Approach — CLARIFIED

**Approved mechanism: VS Code Remote-SSH, where the SSH connection itself is tunneled through AWS Systems Manager Session Manager port forwarding — not a directly network-accessible SSH endpoint.**

Clarifications:
- There is **no directly network-accessible SSH** into this instance. No security group rule permits inbound connections to port 22 from any source (Section 11), regardless of the instance having a public IP (Section 10).
- `sshd` may run on the instance, but its only purpose is to serve the local end of the tunnel that Session Manager port forwarding creates. Nothing on the network can reach `sshd` directly; the only path to it is through an authenticated SSM session.
- Flow: `aws ssm start-session --document-name AWS-StartPortForwardingSession` (or the equivalent SSH-over-SSM helper) tunnels a local port on the user's machine to the instance's `sshd`, over the authenticated SSM channel. VS Code's Remote-SSH extension is then pointed at that tunneled local port, giving the full remote experience (integrated terminal, extensions, debugging) with no inbound network exposure at any point.
- Alternative if this proves awkward: `code tunnel` (VS Code's own tunnel service) run from the instance, which also avoids inbound ports, at the cost of depending on Microsoft's tunnel relay rather than AWS-native tooling. Documented as an alternative, not the default recommendation.

## 16. Required Development Tools

Per `PROJECT_BLUEPRINT.md` Section 5 and `PRE_PHASE_CHECKLIST.md` Step 5:

Git, Python 3.12, pip, uv, Terraform, AWS CLI v2, Docker, Docker Compose, dbt, Java (JDK, version to match Spark's requirement when Spark is actually used), PostgreSQL client (`psql`), jq, curl, make, tmux, Ruff, Pytest, Node.js (only if/when a later phase needs it — not installed speculatively), VS Code Remote support (server-side component installed automatically by the Remote-SSH extension on first connect).

## 17. Python Environment and Dependency Management — APPROVED

- Python 3.12, matching `Standards.md`.
- **Approved: `uv`** for dependency management and virtual environments (Poetry was the alternative under consideration; `uv` is now the approved choice).
- One virtual environment per project component once code exists; no global `pip install` of project dependencies onto system Python.
- `pyproject.toml`-based dependency declarations, lockfile committed, consistent with reproducibility goals.

## 18. Docker and Docker Compose Setup

- Install Docker Engine (not Docker Desktop — this is a headless Linux server) via the distribution's official repository, plus the `docker-compose-plugin` for `docker compose` (v2 syntax).
- Add the workstation's primary user to the `docker` group so Docker commands don't require `sudo` for routine development (accepted convenience trade-off for a single-user dev box; not appropriate for a shared/production host).
- No Docker daemon TCP port exposed (Section 11) — local Unix socket only.
- Use Docker Compose for local multi-container testing (e.g., a local Postgres for integration tests) — these containers are development-time only and never a substitute for RDS in any real pipeline.

## 19. Terraform and AWS CLI Setup

- Install Terraform via HashiCorp's official package repository (version pinned once Terraform Bootstrap phase selects a version — not invented here), using the x86_64 build (Section 5).
- Install AWS CLI v2 via the official installer for x86_64.
- Configure AWS CLI to use the instance's workstation IAM role automatically (no `aws configure` with static keys) — confirms the "no permanent AWS keys on EC2" rule (`CLAUDE.md` Section 7). Terraform commands assume the separate deployment role (Section 13.2) rather than running directly under the workstation role's own permissions.
- Terraform state access from this instance is only for Pre-Phase/Phase 0 bootstrap convenience; once CI/CD (Phase 8) exists, routine applies should move to the pipeline, not the workstation, but that is a future-phase decision, not required now.

## 20. dbt, Java, PostgreSQL Client, and Other Data Engineering Tools

- **dbt**: install via `uv` into its own virtual environment (dbt has stricter dependency pinning than typical projects; isolating it avoids conflicts with other Python tooling).
- **Java**: install a current LTS JDK (e.g., Java 17 or 21) once the exact Spark version target is known in Phase 3; not pinned here to avoid inventing a version ahead of that decision.
- **PostgreSQL client**: `psql` and related client libraries, for connecting to RDS/Aurora once those exist, and for local Docker Compose Postgres during development.
- **jq, curl, make, tmux**: standard Linux CLI utilities, installed via the distribution package manager.

## 21. Bootstrap and Reproducibility Strategy — APPROVED

**Approved: a single, version-controlled, idempotent bootstrap script.**

- Store the script in this GitHub repository (e.g., `scripts/bootstrap_workstation.sh`, exact location TBD), not on the instance only, so recreation never depends on the old instance being reachable.
- The script must be idempotent — safe to re-run on an already-configured instance without duplicating work or erroring.
- It installs all tools listed in Sections 16–20 on a fresh Amazon Linux 2023 instance.
- Longer-term option once Terraform Bootstrap begins: run the bootstrap script via EC2 user data or `cloud-init` so a fresh instance self-configures on first boot; this document only recommends the pattern, it does not implement it.
- Treat the instance as cattle, not a pet: if something breaks, prefer terminating and relaunching over manual repair, since code and durable data live in GitHub/S3, not on the instance (Section 24).

## 22. Automatic Shutdown and Cost Controls — APPROVED SEQUENCING

**Approved: manual shutdown discipline initially, followed later by scheduled automatic shutdown.**

- **Phase 1 (now):** the user stops the instance manually at the end of each session. This is the accepted interim control — no automation is required before the workstation can be used.
- **Phase 2 (later):** introduce a scheduled automatic stop (e.g., an EventBridge Scheduler rule invoking a small Lambda that stops the instance outside expected working hours), so a forgotten manual stop doesn't run up cost. Exact schedule and mechanism are not decided yet (Section 28).
- **Budget alarms:** AWS Budgets covering EC2 + EBS + public IPv4 address charges, at the approved thresholds in `02_Infrastructure/AWS_Account_Preparation.md` Section 3 (USD 5 / 15 / 24 / 30 actual, USD 30 forecasted) — not yet configured in AWS as of this documentation pass.
- **Idle-resource cleanup:** delete unattached EBS volumes and stale snapshots periodically (`Cost.md`).
- **Right-sizing discipline:** default to `t3.medium` (Section 6), resize temporarily rather than running `t3.large`/`t3.xlarge` continuously.

## 23. Logging, Monitoring, and Operational Checks — CORRECTED

- Enable the CloudWatch unified agent (or minimal CloudWatch Agent config) for basic instance metrics (CPU, memory, disk) — memory/disk are not default EC2 metrics and require the agent.
- **Corrected logging expectation:** Session Manager's command-content logging (recording the actual keystrokes/output of a session) is **not available for SSH sessions or port-forwarding sessions** — which is exactly how this design's VS Code Remote-SSH access works (Section 15). Command-level content logging only applies to standard interactive shell sessions started directly through Session Manager, not to SSH-over-SSM or port-forwarding sessions.
- What **is** still available for audit regardless of session type: **session start/stop events** (who started a session, against which instance, when it ended) and the relevant **API activity** (e.g., `StartSession`, `TerminateSession`, `AssumeRole` calls) via CloudTrail and Session Manager's session history. This gives an audit trail of *who accessed the instance and when*, even though it cannot show *what was typed* during an SSH-tunneled session.
- Basic operational checks: instance status checks (AWS-provided), disk space threshold alarm, and a simple "instance running longer than expected" alarm to catch a forgotten shutdown (relevant during the manual-shutdown interim period, Section 22).
- Detailed dashboards and alerting are a `09_Observability/Monitoring.md` / Phase 0 concern; this section defines the minimum needed for a single dev workstation, not the platform-wide monitoring stack.

## 24. Backup, Recovery, and Instance Recreation Process — APPROVED PRINCIPLE

**Approved principle: disposable workstation; GitHub and S3 are the durable sources of truth, not the instance or its EBS volume.**

Recovery tiers, cheapest/fastest first:
1. **Instance lost/corrupted, volume intact:** stop instance, detach volume, attach to a new instance (or just restart if it's a transient issue).
2. **Volume lost/corrupted:** restore from the most recent EBS snapshot (Section 8), attach to a new instance.
3. **Everything lost:** launch a fresh instance from the standard Amazon Linux 2023 AMI, run the bootstrap script (Section 21), reclone the GitHub repository, re-authenticate via `gh auth login` (Section 14). No data is uniquely lost because the instance never held the only copy of code (GitHub) or durable artifacts (S3).

This tiered approach means snapshot cadence is a convenience optimization, not a hard dependency — full rebuild from bootstrap script + GitHub is always the guaranteed fallback.

## 25. Security Risks and Mitigations

| Risk | Mitigation |
|---|---|
| Long-lived AWS credentials leaked from the instance | Workstation IAM instance profile only, never static keys; deployment permissions held in a separate, assumed role (Sections 13, 19) |
| Instance reachable from the internet | Public IP present, but zero inbound security group rules — no rule permits any inbound connection, on any port, from any source (Sections 10–11) |
| SSH port scanning / brute force | No inbound rule for port 22 from any CIDR; `sshd`, if running, is reachable only through the SSM tunnel, never directly (Sections 11, 12, 15) |
| GitHub token/session leakage | Interactive `gh auth login` per session, nothing baked into AMI/user data (Section 14) |
| Unencrypted data at rest on EBS | Mandatory EBS encryption (Section 8) |
| Unmonitored privileged access | Session start/stop and API activity (`AssumeRole`, `StartSession`) audited via CloudTrail/Session Manager history; note command-content logging does not apply to SSH/port-forwarding sessions (Section 23) |
| Forgotten running instance driving up cost | Manual shutdown discipline now, scheduled automatic shutdown later, plus budget alarms (Section 22) |
| Docker daemon or dev ports exposed | No inbound rules for Docker/Jupyter/databases; Unix socket only (Sections 11, 18) |
| Workstation role over-permissioned | Workstation role scoped to SSM, minimal logging, narrow artifact access, and `sts:AssumeRole` to the deployment role only — no direct infrastructure-management permissions (Section 13) |
| Deployment role misuse | Deployment role is only reachable via explicit `AssumeRole`, auditable via CloudTrail, and can be revoked/tightened independently of the workstation role (Section 13.2) |
| Supply-chain risk from unpinned tool versions | Pin tool versions in the bootstrap script once written (Section 21) |

## 26. Estimated Cost Drivers (No Exact Prices Invented)

Cost drivers to budget for (region `ap-south-1` and the USD 30 monthly ceiling are approved in `AWS_Account_Preparation.md`; exact per-service dollar figures are not invented here):
- EC2 instance hours while running (`t3.medium` by default, `t3.large`/`t3.xlarge` for temporary heavier sessions; burstable `t3` bills for actual usage, cheaper if stopped when idle).
- **Public IPv4 address charge** — AWS bills hourly for a public IPv4 address attached to a running instance; this is a direct consequence of the approved public-subnet design (Section 9-10) and should be weighed against the future private-subnet/NAT-or-endpoint hardening option.
- EBS `gp3` storage (per-GB-month, plus optional additional provisioned IOPS/throughput above the free baseline).
- EBS snapshot storage (incremental, grows with snapshot frequency/retention).
- Data transfer: outbound data transfer over the IGW for package/tool downloads (typically modest for this use case).
- CloudWatch Logs ingestion/storage for session logging and metrics (small for a single dev instance).

The dominant levers the user controls directly are **uptime discipline** (Section 22 — a stopped instance incurs no compute charge, only EBS storage) and, longer-term, **whether the public IP / IGW design is later replaced by the private-subnet hardening option** (Section 9), which would remove the public IPv4 charge at the cost of NAT Gateway or VPC endpoint charges instead.

## 27. Acceptance Criteria

Design is considered acceptance-ready for implementation now that OS, architecture, instance sizing tiers, EBS configuration, networking model, IAM role split, GitHub access, Python tooling, bootstrap strategy, and shutdown sequencing are approved (this document). Remaining before implementation:
- Security group design has zero inbound rules and only necessary outbound rules (already specified, Section 11 — confirm during Terraform authoring).
- IAM policy documents for both the workstation role and the deployment role are written and reviewed (Section 13) — not yet written, no ARNs invented.
- Bootstrap script is written and tested on a disposable instance (Section 21).
- Remaining Section 28 decisions are resolved.
- This document has been reviewed and approved by the user before any Terraform or AWS Console work begins (this revision reflects that approval for the items marked APPROVED above; items still in Section 28 remain open).

Post-implementation acceptance tests (to run once actually built, per `PRE_PHASE_CHECKLIST.md` Step 7): Git clone/push works, Python/Terraform/Docker/AWS CLI all run correctly, AWS CLI reports the correct workstation role (and can successfully assume the deployment role), Session Manager connects, VS Code Remote connects via the SSM-tunneled SSH, and the instance can be stopped and restarted without losing code or configuration.

## 28. Decisions Still Requiring User Approval

With OS, architecture, instance sizing, EBS size/encryption, Python tooling, GitHub access, bootstrap strategy, and shutdown sequencing now approved (Sections 4–8, 14, 17, 21, 22), and with region, budget, billing alert thresholds, VPC/subnet strategy, and IAM/MFA prerequisites now approved and documented in `02_Infrastructure/AWS_Account_Preparation.md`, the remaining open decisions are:

- EBS snapshot cadence and retention.
- Exact automatic-shutdown mechanism and schedule for the "later" phase in Section 22 (EventBridge + Lambda is the anticipated approach; exact schedule not decided).
- Timing and trigger for moving from the initial public-subnet/IGW design to the future private-subnet/NAT-or-endpoint hardened alternative (Section 9).
- Whether `t3.small` is later adopted as a lighter default, contingent on testing evidence (Section 6).
- Exact IAM policy documents (both workstation role and deployment role) and any resource ARNs — deferred to Terraform Bootstrap, not invented here.
- Whether an ADR should be written now for the ARM64→x86_64 architecture reversal, or deferred until ADRs are actively being maintained (flagged in Section 5).

## 29. Proposed Implementation Sequence

1. Confirm the remaining Section 28 decisions.
2. Finalize AWS account basics that this design depends on (region, budget) — tracked as Pending Decisions in `Memory.md`, not part of this document.
3. Terraform Bootstrap phase: create remote state, then networking (VPC, public subnet with IGW per the approved initial design; Section 9's future private-subnet hardening deferred).
4. Author both IAM roles: the workstation instance role and the separate Terraform deployment role, including the `sts:AssumeRole` trust relationship between them (Section 13).
5. Author the bootstrap script (Section 21) and test it locally on a disposable instance before relying on it.
6. Provision the EC2 instance via Terraform (public subnet, public IP, encrypted `gp3` volume, the workstation instance profile, and the zero-inbound security group from Section 11).
7. Configure Session Manager access and verify connectivity (Section 12).
8. Configure VS Code Remote via the Session-Manager-tunneled SSH approach (Section 15).
9. Run the bootstrap script; verify every tool in Sections 16–20 installs correctly, including `uv`-managed Python and `gh` GitHub authentication.
10. Configure manual shutdown discipline immediately; plan the scheduled automatic shutdown mechanism for later (Section 22).
11. Configure basic monitoring and confirm what Session Manager logging can and cannot capture for this access pattern (Section 23).
12. Run the full acceptance test list (Section 27) and record results as evidence, not an assumption.
13. Update `Memory.md`, `PRE_PHASE_CHECKLIST.md`, and consider an ADR for the architecture decision and the public-subnet-vs-private-subnet networking choice, per `CLAUDE.md` Section 9.

## 30. Proposed Future Terraform Resources (Documented Only — Not Created)

The following resources are anticipated for whenever Terraform Bootstrap/Phase 0 actually implements this design. None of these are created, stubbed, or scaffolded by this document — `infrastructure/terraform/` remains untouched.

- `aws_instance` (Amazon Linux 2023, x86_64, `t3.medium` default)
- `aws_iam_role` + `aws_iam_instance_profile` — **workstation role** (Section 13.1: SSM core, minimal CloudWatch Logs write, narrow S3 artifact access, `sts:AssumeRole` to the deployment role)
- `aws_iam_role` — **Terraform deployment role** (Section 13.2), with a trust policy scoped to the workstation role (and later the CI/CD role)
- `aws_iam_role_policy` / `aws_iam_policy` for both roles, least-privilege
- `aws_security_group` (Section 11: zero inbound rules, scoped outbound)
- `aws_internet_gateway` + route table association for the public subnet (Section 9)
- `aws_eip` or the instance's auto-assigned public IP, depending on whether a stable address is wanted (Section 10)
- `aws_ebs_volume` parameters expressed via the instance's `root_block_device` (gp3, encrypted, 30 GiB per Section 8)
- `aws_kms_key` or reference to the AWS-managed EBS key (Section 8)
- `aws_cloudwatch_metric_alarm` (idle/runtime alarm, disk space alarm — Section 23)
- `aws_scheduler_schedule` (or `aws_cloudwatch_event_rule`) + a small `aws_lambda_function` for the later automatic-stop phase (Section 22)
- `aws_budgets_budget` (Section 22/26 cost controls)
- Future hardening (not initial scope): `aws_nat_gateway` or `aws_vpc_endpoint` resources + a private subnet, if/when the Section 9 hardened alternative is adopted

---

## Relationship to Existing Documentation

`02_Infrastructure/EC2_Development_Environment.md` has been replaced with a short redirect to this document, which is now the authoritative EC2 workstation design (per user instruction). The old file was not deleted, since other documents may still reference it by name.

Last updated: 2026-07-24
