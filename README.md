# Enterprise Data Platform

An Enterprise AWS Data Engineering Platform, built to practice and demonstrate real-world data engineering and cloud infrastructure skills: multi-source ingestion, a Landing → Bronze → Silver → Gold storage progression, Spark/dbt-based processing, and analytics serving, all running on AWS infrastructure managed entirely through Terraform.

This repository currently covers the **engineering foundation** of that platform: AWS account preparation, a Terraform state/IAM bootstrap, and a single Terraform-managed development environment (VPC, IAM, and an EC2 development workstation). Later platform phases (ingestion, storage layers, processing, serving) are tracked separately and are not yet implemented in this repository.

## Problem this project addresses

Most personal or portfolio AWS projects start by clicking around the console and retrofitting Infrastructure as Code later, if at all. This project inverts that: every AWS resource, from the very first S3 bucket, is created and managed by Terraform, with a deliberately staged bootstrap sequence, least-privilege IAM from day one, and a documented decision and validation trail for every non-trivial choice. The goal is infrastructure that is reproducible, auditable, and safe to iterate on — the same standard expected of a production data platform, applied to a learning project.

## High-level architecture

```
infrastructure/terraform/
├── bootstrap/            # Terraform state bucket + shared deployment IAM role
├── environments/dev/     # VPC, workstation IAM role, EC2 dev workstation
├── modules/
│   ├── vpc/               # VPC, public subnet, Internet Gateway, route table
│   ├── iam-workstation-role/  # Workstation IAM role + instance profile
│   └── ec2-workstation/       # Security group + EC2 instance
└── scripts/
    └── bootstrap_workstation.sh   # EC2 user-data: baseline dev tooling only
```

- **`bootstrap/`** creates the foundation everything else depends on: a versioned, encrypted, public-access-blocked S3 bucket for Terraform remote state (with native S3 locking, no separate lock table), and a shared deployment IAM role that every later Terraform stack authenticates through.
- **`environments/dev/`** is the first environment built on that foundation: a dedicated VPC with a single public subnet, zero inbound security-group rules, and one EC2 development workstation reachable only through AWS Systems Manager Session Manager — never SSH.
- Both stacks store their state in the same S3 bucket, under different state keys, and are managed as **separate Terraform root modules with separate state** — a `plan`/`apply` in one never touches the other.

## Current implementation status

| Component | Status |
|---|---|
| State bucket + deployment role (bootstrap) | Implemented, applied, and independently verified against real AWS output |
| Remote state migration (local → S3) | Complete and verified |
| Deployment role permissions for `environments/dev` | Implemented; applied; re-verified via a no-drift `terraform plan` at the bootstrap level |
| `environments/dev` VPC, workstation IAM role, EC2 workstation | Implemented and deployed; state confirmed to match configuration |
| Bootstrap IAM-condition deployment validation (see journal) | **Pending** — see `16_Implementation_Notes/PROJECT_EXECUTION_JOURNAL.md` Section 7 |
| Deployment role trust update for the workstation role ("Bootstrap Update 2") | Not started — depends on the pending item above |
| Native S3 state-locking contention test | Deferred, not yet performed |

For the full, dated implementation history — including problems encountered, root-cause investigations, and fixes — see `16_Implementation_Notes/PROJECT_EXECUTION_JOURNAL.md`.

## Repository structure

```
00_Project_Management/      Project blueprint, roadmap, phase definitions
01_Architecture/             Architecture, naming conventions, standards
02_Infrastructure/            AWS account prep, IAM/access, networking, bootstrap design
03_Development/               Coding guidelines, git workflow, engineering rules
04_Phases/                    Per-phase scope and completion criteria
06_Runbooks/, 07_Testing/, 08_Security/, 09_Observability/, 10_Cost_and_FinOps/
15_Lessons_Learned/
16_Implementation_Notes/      Execution journal, checklists, implementation plans
infrastructure/terraform/     All Terraform source (see architecture diagram above)
scripts/login.ps1.example     Example MFA authentication workflow (see below)
```

## Authentication approach

All Terraform commands run as a human operator's IAM user, authenticated with MFA, who assumes the shared deployment role for the duration of each `plan`/`apply`. Terraform's own provider and backend configuration each perform exactly one role assumption; the operator never manually pre-assumes the deployment role, since doing so from an already-assumed session causes a self-assume failure (documented in the execution journal).

`scripts/login.ps1.example` shows the authentication workflow used in practice: clear stale session credentials, request a fresh MFA-backed session token for the base IAM user (not a role assumption), stop immediately on any failure, and confirm the resulting identity before proceeding. Copy it to `login.ps1`, fill in your own MFA device ARN and region, and run it before any `terraform plan`/`apply`. The real `login.ps1` is gitignored and must never be committed.

## Prerequisites

- Terraform (see each stack's `versions.tf` for the exact constraint)
- AWS CLI, configured with an IAM user that has MFA enabled
- An AWS account you control, with no existing conflicting resources at the naming/CIDR conventions this project uses
- `tflint` and `trivy`, if you want to reproduce this project's own validation steps

## How to initialize and plan safely

1. Read `02_Infrastructure/Terraform_Bootstrap_Design.md` and the relevant stack's `README.md` before running anything.
2. In `infrastructure/terraform/bootstrap/`: copy `terraform.tfvars.example` → `terraform.tfvars` and fill in your own account-specific values (never committed). Run `terraform init`, `terraform plan`, and review the plan in full before ever running `terraform apply`.
3. Only after the bootstrap stack is applied and verified, migrate to the S3 backend using a real, gitignored `backend.hcl` (copy from `backend.hcl.example`).
4. In `infrastructure/terraform/environments/dev/`, repeat the same copy-and-fill pattern for its own `terraform.tfvars.example`/`backend.hcl.example`, then `terraform init`, `terraform plan`, review, and only then `terraform apply`.
5. Always run `terraform fmt -check -recursive`, `terraform validate`, `tflint`, and a Trivy config scan before any `plan`, and always review a `plan`'s full output — especially any proposed resource `destroy` or `replace` — before approving an `apply`.

## Security principles

- **Least privilege, added incrementally.** The deployment role starts with no permissions; every permission it has was added in a specific, reviewed step tied to a real infrastructure need, not granted broadly upfront.
- **Zero inbound network access.** The development workstation has no open inbound ports of any kind. Access is exclusively through AWS Systems Manager Session Manager.
- **MFA-gated deployment access.** The deployment role's trust policy requires an active MFA session; it cannot be assumed with unauthenticated or non-MFA credentials.
- **Encrypted, versioned, access-blocked state.** The Terraform state bucket has encryption, versioning, and full public-access blocking enabled, with a bucket policy denying any non-TLS access.
- **No secrets in source.** Real credentials, account IDs, ARNs, and any other account-specific values are never committed — only placeholders and `.example` templates are.

## Important: do not commit these

This repository intentionally excludes, and you must never commit:

- `terraform.tfvars`, `backend.hcl` (real, filled-in values — only the `.example` templates belong here)
- `*.tfstate`, `*.tfstate.*`, `.terraform/`, `*.tfplan`, `*.tflock` (state and plan artifacts)
- `login.ps1` (the real authentication script — only `scripts/login.ps1.example` belongs here)
- Any AWS access key, secret key, session token, or MFA device serial number
- `schema.json`, `crash.log`, or any other generated/debug output

See `.gitignore` for the full list. If you fork or reuse this project, review that file before your first commit.

## What's implemented vs. planned

**Implemented:** the Terraform state/IAM bootstrap, remote state migration, and the `environments/dev` VPC/IAM/EC2-workstation stack, as described above.

**Planned, not yet implemented:** the trust-policy update allowing the workstation role to assume the deployment role directly; later platform phases (multi-source ingestion, the Bronze/Silver/Gold data lake, processing, warehousing, serving, security/governance, observability, CI/CD, reliability/disaster-recovery, and cost/performance engineering) described at a roadmap level in `00_Project_Management/`. None of these later phases has infrastructure in this repository yet — they are documented as future scope only.
