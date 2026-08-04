# IAM and Access

Use IAM Identity Center or temporary credentials, instance profiles, separate deployment/runtime/read-only roles, least privilege, Secrets Manager, MFA, and auditable access. Never store credentials in code, AMIs, or user data.

## Approved Pre-Phase Decisions

- **Root user MFA: verified enabled.** **IAM user MFA: verified enabled.** (Confirmed by user, 2026-07-24 — see `02_Infrastructure/AWS_Account_Preparation.md` Section 8.)
- **No IAM user long-lived access keys are used on EC2.** The workstation authenticates solely via its IAM instance profile.
- **EC2 must use an IAM instance profile** — never static/long-lived credentials placed on the instance.
- **Two-role split (approved), not one combined role:**
  - **Workstation instance role** — narrow scope: SSM connectivity, minimal CloudWatch Logs write permissions, narrowly scoped artifact access only where justified, and `sts:AssumeRole` permission limited to the Terraform deployment role. No broad infrastructure-management permissions.
  - **Terraform deployment role** — a separate, assumed role (not attached to the instance) that holds the actual infrastructure-management permissions Terraform needs. Reached only via explicit `sts:AssumeRole` from the workstation role (or later, CI/CD), auditable via CloudTrail.
- Full detail and rationale: `02_Infrastructure/EC2_Development_Workstation.md` Section 13.

Naming for both roles follows `01_Architecture/Naming_Convention.md` (`enterprise-data-platform-<environment>-workstation-role`, `enterprise-data-platform-shared-deployment-role`). **Corrected 2026-07-26** — the deployment role is a single, project-wide role shared across environments (not one per environment); this line previously showed a stale `-<environment>-deployment-role` pattern that conflicted with `Naming_Convention.md`'s already-corrected (2026-07-25) naming. Flagged and resolved via `16_Implementation_Notes/Dev_Environment_Terraform_Implementation_Plan.md` §56 "Documentation Conflicts Flagged," conflict #3. No roles have been created in AWS yet — this remains a Terraform Bootstrap / `environments/dev` deliverable.
