# infrastructure/terraform/cost-controls

Status: **Code created, NOT YET APPLIED.** No AWS resource described here exists. Implements the approved design in `10_Cost_and_FinOps/Cost_Controls.md` and `01_Architecture/ADRs/ADR-0005-cost-controls-foundation.md`.

## Responsibility

Owns Phase 0's shared, account-wide AWS Budget: one Terraform-managed monthly budget (USD 30 ceiling), five notification thresholds (four actual-spend, one forecasted), routed through the **existing** Logging and Audit Foundation SNS topic. This is the sixth Phase 0 workstream, following IAM foundation (`bootstrap/`), Logging and Audit Foundation (`logging/`), Networking Hardening (`environments/dev`, `modules/vpc`), and KMS and Secrets Foundation (`kms-secrets/`).

The automatic EC2 workstation shutdown schedule is **NOT** part of this stack — it lives in `environments/dev/` (Cost_Controls.md Section 10: the shutdown schedule targets one specific `dev` environment's one specific instance, so it belongs in that same-lifecycle stack, not here).

## Provider authentication — departs from `logging/`'s precedent

This stack authenticates via the shared deployment role (`assume_role`), the same pattern `environments/dev` and `kms-secrets/` use — **not** `logging/`'s human-direct pattern. This is deliberate: this workstream's own scope requires new deployment-role Budgets/EventBridge Scheduler/EC2 permissions (`bootstrap/main.tf`'s new `deployment_shared_cost_controls_permissions` policy), which only has a purpose if the deployment role actually applies this stack. See `providers.tf` for the full rationale.

**Dependency: `bootstrap/main.tf`'s `deployment_shared_cost_controls_permissions` policy and its attachment must already be applied** before this stack's own `plan`/`apply` can succeed — without it, the deployment role has no `budgets:ViewBudget`/`ModifyBudget` permission at all.

**Dependency: `infrastructure/terraform/logging/` must already be applied** — this stack does not create an SNS topic; it reuses the existing, already-validated `security_alerts_topic_arn` output from that stack, supplied via `terraform.tfvars` (`sns_topic_arn`).

## Resources this stack creates

- `aws_budgets_budget.shared` — one account-wide, `COST`-type, `MONTHLY` budget, USD 30 ceiling, four `ACTUAL` notifications (USD 5/15/24/30, `ABSOLUTE_VALUE`) plus one `FORECASTED` notification (USD 30, `ABSOLUTE_VALUE`), each routed through `var.sns_topic_arn` (the existing Logging and Audit topic). No new SNS topic, no new subscription, no automated destructive action attached to any threshold.

## Does NOT touch the existing manual budget

The existing, manually created AWS Budget (`10_Cost_and_FinOps/Cost.md`) is left completely alone by this configuration — not imported, not modified, not deleted. Running both budgets in parallel briefly is harmless (AWS Budgets carry no charge). Retiring the manual budget is a separate, later, **manual** (non-Terraform) step, performed only after this Terraform-managed budget is confirmed live and correctly alerting — see `Cost_Controls.md` Section 13's validation plan and Section 1's migration approach.

## Explicitly out of scope for this stack (and this task)

- The automatic EC2 shutdown schedule and its execution IAM role — see `environments/dev/main.tf`.
- AWS Cost Anomaly Detection — deferred, `Cost_Controls.md` Section 3.
- Any new mandatory tag — `Cost_Controls.md` Section 4.
- Any change to NAT/VPC-endpoint deferral, CloudWatch/S3 retention, or resource-cleanup automation — `Cost_Controls.md` Sections 6-9.
- Retiring the existing manual budget — a separate, later, manual action.

## Validation performed

Structural only (no `terraform` binary in this sandbox): Python `hcl2` parse and brace-balance check on every `.tf` file. No `terraform fmt`/`validate`/`plan` has been run in this sandbox. **No `terraform apply` has been run. No AWS resource described in this stack exists.**
