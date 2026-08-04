# AWS Account Preparation

Status: **Account-level settings (MFA, budget, billing alerts, region, tags) verified by user report on 2026-07-24. No VPC, IAM roles, or EC2 resources exist yet — this remains documentation only for anything beyond the account-level settings.** This document records the approved Pre-Phase Step 2 decisions (`PROJECT_BLUEPRINT.md` Section 10, `PRE_PHASE_CHECKLIST.md` Step 2) and their verification status.

## 1. Approved Region

**Primary region: `ap-south-1` (Mumbai).**

The project stays in Mumbai for now. Region is not being changed for small workstation-level cost savings elsewhere — any future region change would be a deliberate, separately justified decision (and would likely warrant an ADR given the blast radius of a region change once resources exist).

## 2. Budget Ceiling — VERIFIED CREATED

**Monthly AWS budget: USD 30 — confirmed created in AWS by user, 2026-07-24.**

- Expected normal workstation spend: approximately USD 10–15 per month.
- Soft warning zone: USD 20 (spend above this level, while still under budget, should prompt a check on what's driving it).
- No AWS service may be added if it carries a non-trivial cost, without a cost estimate and the user's explicit approval first. This applies beyond the workstation itself, to any future Phase 0+ service.
- **Free Tier eligibility: confirmed NOT eligible** (user-verified, 2026-07-24). The USD 10–15/month expected-spend estimate should be read as full pay-as-you-go pricing, with no Free Tier discount to rely on.

## 3. Billing Alert Thresholds — VERIFIED CREATED

**Confirmed by user 2026-07-24: the monthly AWS Budget (USD 30) and all five alerts below have been created in AWS.**

| Alert type | Threshold | Status |
|---|---|---|
| Actual spend | USD 5 | Created (user-confirmed) |
| Actual spend | USD 15 | Created (user-confirmed) |
| Actual spend | USD 24 | Created (user-confirmed) |
| Actual spend | USD 30 | Created (user-confirmed) |
| Forecasted spend | USD 30 | Created (user-confirmed) |

This confirmation is based on the user's explicit statement, not on independently observed evidence (e.g., a screenshot or exported config) — recorded here as user-verified per their report.

## 4. Dedicated VPC Decision

**Use a dedicated project VPC.** The AWS account default VPC is not the permanent project design — it should not be relied on for the workstation or any later Phase 0+ resources.

This dedicated VPC does not exist yet. It is a Terraform Bootstrap / Phase 0 networking deliverable (`02_Infrastructure/Networking.md`, `PROJECT_BLUEPRINT.md` Section 11 Step 4). No VPC, subnet, or networking resource has been created as part of this documentation pass.

## 5. Default VPC Policy

The AWS account's default VPC (the one AWS creates automatically per region) is **not** to be used for any project resource, including the EC2 workstation. It may exist in the account passively (AWS creates it by default and it costs nothing to leave alone), but nothing in this project should be launched into it. If it is ever deleted or left as-is is a matter of account hygiene the user can decide independently; not a project dependency either way.

## 6. Public Development Subnet Decision

**Initial EC2 placement: a public development subnet within the dedicated project VPC**, per the approved design in `02_Infrastructure/EC2_Development_Workstation.md` Sections 9–11:

- Internet access via an Internet Gateway, with the instance holding a public IPv4 address while running.
- Security group: **zero inbound rules** — a public IP does not create inbound accessibility; that is governed entirely by the security group.
- Administrative access exclusively through **Systems Manager Session Manager**. Port 22 (SSH) is not opened to any CIDR, under any circumstance.
- Private subnets remain reserved in the VPC design for future application and data workloads (RDS, ECS/Fargate tasks, etc. in Phase 0+) — they are not being built as part of this documentation pass, just reserved in the design.

## 7. No-NAT Initial Strategy

**No NAT Gateway is being added for the initial workstation.** The public-subnet + Internet Gateway model (Section 6 above) provides outbound reachability without NAT Gateway cost. Private subnet + NAT Gateway (or VPC endpoints) is documented as a **future hardening option only**, to be adopted later if/when the project moves the workstation (or other resources) into private subnets — not part of the current approved design, and no NAT Gateway resource is created or planned for creation now.

## 8. IAM and MFA Prerequisites

- **Root user MFA: VERIFIED ENABLED** (confirmed by user, 2026-07-24).
- **IAM user MFA: VERIFIED ENABLED** (confirmed by user, 2026-07-24).
- **No IAM user long-lived access keys are used on EC2.** The workstation must authenticate via its IAM instance profile only (`02_Infrastructure/EC2_Development_Workstation.md` Section 13.1) — never `aws configure` with static access keys. Not yet applicable/verified — no EC2 instance or instance profile exists yet.
- **EC2 uses an IAM instance profile** (the workstation role, Section 13.1 of the workstation design) — **not created yet**, this remains a Terraform Bootstrap deliverable.
- **Terraform assumes a separate deployment role** (Section 13.2 of the workstation design) rather than running under the workstation role's own permissions directly — **not created yet**.
- **The workstation role does not hold broad infrastructure-management permissions directly** — those live only in the deployment role, reached via `sts:AssumeRole`. This remains a design requirement; no role exists yet to verify against.

MFA is now verified. The instance profile / deployment role split remains a design requirement only, pending Terraform Bootstrap — no IAM role has been created in AWS.

## 9. EC2 Sizing and Storage Decisions

Approved (full detail and rationale in `02_Infrastructure/EC2_Development_Workstation.md`):

- **Architecture:** x86_64.
- **Operating system:** Amazon Linux 2023.
- **Default instance:** `t3.medium`.
- **Temporary heavy-work instance:** `t3.large`.
- **Exceptional short-term instance:** `t3.xlarge`.
- **Root volume:** 30 GiB, encrypted, `gp3`.

## 10. Manual AWS Actions — Status

All Pre-Phase Step 2 account-preparation actions the user was asked to verify have been reported complete (user confirmation, 2026-07-24):

1. ~~Confirm root user MFA is enabled.~~ **Verified enabled.**
2. ~~Confirm MFA is required for the IAM user(s) that will administer this account.~~ **Verified enabled.**
3. ~~Create or confirm the AWS Budgets alert at each of the five thresholds.~~ **Verified created** (USD 5/15/24/30 actual, USD 30 forecasted).
4. ~~Confirm the AWS account region.~~ **Verified: `ap-south-1`.**
5. ~~Decide and record the real `Owner` and `CostCenter` tag values.~~ **Set: `Owner=DataEngAA`, `CostCenter=personal-learning`.**
6. ~~Verify Free Tier eligibility/status.~~ **Verified: not eligible.**

This confirmation is the user's own explicit report, not independently observed evidence (no screenshots or exports were reviewed) — recorded as user-verified accordingly.

**Not yet done, and not part of what was verified here:** no IAM instance profile, no workstation role, no Terraform deployment role, no VPC, no EC2 instance, and no Terraform code exist yet. These remain Terraform Bootstrap / Phase 0 deliverables. Terraform Bootstrap or EC2 deployment should not begin until those are designed, reviewed, and then actually created with their own evidence.

Last updated: 2026-07-24
