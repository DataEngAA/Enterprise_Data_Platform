# Cost and FinOps

Budgets, tags, EC2 shutdown, S3 lifecycle, log retention, NAT monitoring, right-sizing, and idle-resource cleanup. Track cost per source, run, million records, document, and environment.

## Approved Budget (Pre-Phase) — VERIFIED CREATED

- **Monthly AWS budget ceiling: USD 30**, region `ap-south-1` (Mumbai) — created in AWS, confirmed by user 2026-07-24. See `02_Infrastructure/AWS_Account_Preparation.md`.
- **Expected normal workstation spend:** approximately USD 10–15/month — read as full pay-as-you-go pricing, since the account is confirmed **not** Free Tier eligible.
- **Soft warning zone:** USD 20 — spend above this level should prompt a review even though it's still under budget.
- No AWS service carrying non-trivial cost may be added without a cost estimate and explicit user approval first.

## Billing Alerts — VERIFIED CREATED

AWS Budgets alert thresholds, confirmed created by the user 2026-07-24:

| Alert type | Threshold | Status |
|---|---|---|
| Actual spend | USD 5 | Created (user-confirmed) |
| Actual spend | USD 15 | Created (user-confirmed) |
| Actual spend | USD 24 | Created (user-confirmed) |
| Actual spend | USD 30 | Created (user-confirmed) |
| Forecasted spend | USD 30 | Created (user-confirmed) |

This reflects the user's own explicit report, not independently observed evidence (no screenshots or exports reviewed).

## Workstation-Specific Cost Drivers

Per `02_Infrastructure/EC2_Development_Workstation.md` Section 26: EC2 instance hours (`t3.medium` default, `t3.large`/`t3.xlarge` temporary), the public IPv4 address hourly charge (a direct consequence of the approved public-subnet/no-NAT initial design), `gp3` EBS storage, EBS snapshot storage, and modest outbound data transfer. No NAT Gateway cost in the initial design — NAT/VPC-endpoint costs would only appear if the future private-subnet hardening option is adopted.
