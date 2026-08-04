# Pre-Phase Checklist — Engineering Environment Setup

Source of truth for scope: `PROJECT_BLUEPRINT.md`, Section 10.
This checklist tracks completion of the Pre-Phase only. It does not cover Terraform bootstrap or Phase 0 (see `16_Implementation_Notes/Bootstrap_Checklist.md` and `04_Phases/Phase_0_AWS_Foundation/Phase_0.md` for those).

## Step 1 — Finalise project planning

- [x] PRD.md
- [x] Architecture.md
- [x] Rules.md
- [x] Phases.md
- [x] Memory.md
- [x] Roadmap.md
- [x] TechStack.md
- [x] Standards.md
- [x] Interview Guide structure
- [x] Naming_Convention.md — created as placeholder (file exists; detailed content not yet written)
- [x] Coding_Guidelines.md — created as placeholder (file exists; detailed content not yet written)
- [ ] Disaster_Recovery.md — missing, not yet created (deferred to Phase 9)
- [ ] CI_CD.md — missing, not yet created (deferred to Phase 8)
- [ ] Data_Governance.md — missing, not yet created (deferred to Phase 6)
- [x] AWS_Account_Preparation.md — created (`02_Infrastructure/`), not originally in this list but produced as part of Step 2 below

## Step 2 — Prepare the AWS account

- [x] AWS region decided and **verified**: `ap-south-1` (Mumbai); see `02_Infrastructure/AWS_Account_Preparation.md`
- [x] Budget decided and **verified created in AWS**: USD 30/month, USD 10–15 expected, USD 20 soft warning zone (user-confirmed 2026-07-24)
- [x] Billing alerts **verified created in AWS**: USD 5/15/24/30 actual, USD 30 forecasted (user-confirmed 2026-07-24)
- [x] Naming convention decided — `01_Architecture/Naming_Convention.md`
- [x] Tagging convention decided — `Project`, `Environment`, `ManagedBy`, `Owner=DataEngAA` (verified), `CostCenter=personal-learning` (verified), `DataClassification`
- [x] IAM access strategy decided — root and IAM user MFA **verified enabled** (user-confirmed 2026-07-24); no long-lived keys on EC2, instance profile, workstation/deployment role split still design-only, **not yet created in AWS**
- [x] Development environment strategy decided — dedicated project VPC, default VPC not used, public development subnet + IGW, zero inbound rules, Session Manager only, no NAT initially (`AWS_Account_Preparation.md` Sections 4–7) — **design only, VPC not yet created**
- [x] Free Tier vs pay-as-you-go expectations set and **verified**: account confirmed **not** Free Tier eligible (user-confirmed 2026-07-24); USD 10–15/month expectation is full pay-as-you-go pricing

## Step 3 — Create the GitHub repository

- [x] Repository exists
- [x] README exists
- [x] Branch strategy documented — `03_Development/Git_Workflow.md` (protected `main`, short-lived `feature/`/`fix/`/`docs/`/`refactor/`/`chore/` branches, no direct commits to `main`)
- [x] Folder structure exists
- [x] .gitignore exists
- [x] Pull request process documented — `03_Development/Git_Workflow.md` (PR required before merge, five required description sections, squash merge preferred, branch deleted after merge)
- [ ] Issue templates (optional) — not created; no existing template found in the repository

## Step 4 — Create the EC2 development workstation

- [x] Design document created: `02_Infrastructure/EC2_Development_Workstation.md` (OS, architecture, sizing, networking, IAM, security groups, tools, bootstrap, cost, backup/recovery, acceptance criteria — documentation only)
- [x] Design reviewed and approved by user (Amazon Linux 2023; x86_64 `t3.medium`/`t3.large`/`t3.xlarge`; 30 GiB encrypted gp3; public subnet + IGW with zero inbound rules; split workstation/deployment IAM roles; `uv`; GitHub CLI auth; bootstrap script; manual-then-scheduled shutdown — remaining open items tracked in design doc Section 28 and in Memory.md Pending Decisions)
- [ ] Instance created
- [ ] Secure access (Session Manager)
- [ ] Encrypted EBS
- [ ] IAM instance profile
- [ ] Automatic shutdown or disciplined stop process
- [ ] No unnecessary public exposure
- [ ] Reproducible setup (documented / scripted)

## Step 5 — Install development tools

- [ ] Git
- [ ] Python 3.12
- [ ] pip
- [ ] uv or Poetry
- [ ] Terraform
- [ ] AWS CLI
- [ ] Docker
- [ ] Docker Compose
- [ ] dbt
- [ ] Java
- [ ] PostgreSQL client
- [ ] jq
- [ ] curl
- [ ] make
- [ ] tmux
- [ ] Ruff
- [ ] Pytest
- [ ] Node.js (if required later)
- [ ] VS Code Remote support

## Step 6 — Configure VS Code remote development

- [ ] Open EC2 project folder from laptop
- [ ] Edit files in VS Code
- [ ] Run commands on EC2
- [ ] Use EC2 terminal
- [ ] Run Python
- [ ] Run Terraform
- [ ] Build Docker images
- [ ] Run tests

## Step 7 — Test the development workstation

- [ ] Git clone works
- [ ] Git push works
- [ ] Python runs
- [ ] Terraform runs
- [ ] Docker runs
- [ ] AWS CLI identifies the correct role
- [ ] Session Manager works
- [ ] VS Code remote works
- [ ] Instance can be stopped and started safely

## Step 8 — Terraform Bootstrap (tracked here for convenience; begins once Pre-Phase Steps 1–7 are complete)

- [x] Terraform Bootstrap design documented: `02_Infrastructure/Terraform_Bootstrap_Design.md` (bootstrap dependency order, state lifecycle, native S3 locking, deployment-role creation path, backend configuration mechanics, repository/module structure, role-assumption workflow, security checks, acceptance criteria — documentation only)
- [x] Design reviewed and approved by user (2026-07-24): Terraform >=1.10 + native S3 locking; SSE-S3 (no KMS during bootstrap); manual bootstrap from human identity's laptop/CloudShell; deployment role created by bootstrap Terraform config, trust updated to workstation role only after it exists; deployment-role max session duration 1 hour; existing AWS Budget not imported; VPC reserves all-tier CIDR space but deploys only the public tier now, no NAT; break-glass protections (prevent_destroy, no delete permission, versioning, BPA, TLS-only) confirmed; only `dev` scaffolded, `test`/`stage`/`prod` deferred
- [ ] Remote state created
- [ ] State locking verified
- [ ] Terraform deployment role created
- [ ] Workstation IAM role created
- [ ] Dedicated VPC created
- [ ] EC2 workstation created via Terraform
- [ ] Terraform validation (`fmt`, `validate`, `plan`) run successfully
- [ ] Terraform deployment executed and verified

## Pre-Phase Completion Criteria

- [ ] Documentation structure exists (mostly complete — see gaps above)
- [ ] GitHub repository exists (complete)
- [ ] AWS account access is secure — root/IAM MFA **verified enabled** (2026-07-24); IAM instance profile, workstation role, and deployment role still not created, so this criterion is only partially met
- [ ] EC2 workstation is operational
- [ ] Tools are installed
- [ ] VS Code remote works
- [ ] Git works
- [ ] AWS CLI works
- [ ] Docker works
- [ ] Terraform works
- [x] Budget controls exist — AWS Budget (USD 30) and all 5 alert thresholds (USD 5/15/24/30 actual, USD 30 forecasted) **verified created** (user-confirmed 2026-07-24)
- [ ] The workstation can be recreated

---

Last updated: 2026-07-24
