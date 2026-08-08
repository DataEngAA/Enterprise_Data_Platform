# Architecture Decision Records

Each ADR contains context, requirements, options, decision, benefits, costs, risks, rejected alternatives, and reconsideration conditions.

Initial ADRs (topic list, not yet all written as individual files): Terraform vs CDK, EC2 workstation strategy, Lambda vs Fargate, Fargate vs EC2, SQS vs direct calls, Kinesis vs MSK, Step Functions vs Airflow, DMS vs custom CDC, Iceberg vs Delta/Hudi, Athena vs Redshift.

## Index

| ADR | Title | Status |
|---|---|---|
| [ADR-0001](ADR-0001-iam-foundation-permission-boundaries-and-runtime-role-pattern.md) | IAM Foundation — Permission Boundaries and the Runtime-Role Pattern | Accepted, implemented, and validated (2026-08-04) — Phase 0 IAM foundation workstream complete |
| [ADR-0002](ADR-0002-logging-and-audit-foundation.md) | Logging and Audit Foundation — CloudTrail, Centralized Storage, and Security-Event Alarms | Accepted, implemented, and validated (2026-08-04) — Phase 0 logging and audit workstream complete |
| [ADR-0003](ADR-0003-networking-hardening-multi-az-nat-and-endpoint-strategy.md) | Networking Hardening — Multi-AZ Strategy, NAT Deferral, and VPC Endpoint Strategy | Accepted, implemented, and validated (2026-08-07) — Phase 0 networking hardening workstream complete |
| [ADR-0004](ADR-0004-kms-and-secrets-foundation.md) | KMS and Secrets Foundation — Shared CMK, Explicit Key-Policy Enumeration, and Metadata-Only Secrets Management | Accepted, implemented, and validated (2026-08-07) — Phase 0 KMS and secrets workstream complete |
| [ADR-0005](ADR-0005-cost-controls-foundation.md) | Cost Controls Foundation — Terraform-Managed Budgets, Scheduler-Direct EC2 Shutdown, and Deferred Anomaly Detection | Accepted, implemented, and validated (2026-08-07) — Phase 0 Cost Controls workstream complete |
| [ADR-0006](ADR-0006-cicd-foundation.md) | CI/CD Foundation — Two-Hop OIDC Trust, Bootstrap/Logging Exclusion, and Manual-Approval Apply | Proposed (2026-08-07) — implementation slice 1 (AWS OIDC trust only) written to source, not applied; Phase 0 CI/CD Foundation workstream in progress |

None of ADR-0001 through ADR-0006 was part of the initial topic list above — all six were written to cover Phase 0 workstreams (`PROJECT_BLUEPRINT.md` §11: IAM foundation, then logging and auditing, then networking hardening, then KMS and secrets, then cost controls, then CI/CD foundation) that the initial list didn't anticipate. The initial topics above remain a list of intended future ADRs, not resolved decisions, until each gets its own numbered file here.
