# Networking

**Scope note (added 2026-07-26):** the principles below describe the target state for the platform's real data-workload VPC, from Phase 0 onward. They do not govern the Pre-Phase single-instance dev workstation network (`environments/dev`, `02_Infrastructure/EC2_Development_Workstation.md`), which is an explicitly approved, minimal, single-AZ, single-public-subnet exception scoped to standing up one disposable EC2 workstation at the lowest reasonable cost — not a production or multi-service workload. This distinction was flagged as a documentation conflict (single AZ vs. "at least two," no Flow Logs, no VPC endpoints) and resolved via `16_Implementation_Notes/Dev_Environment_Terraform_Implementation_Plan.md` §56 "Documentation Conflicts Flagged," conflict #2 — not by weakening the principles below, which remain authoritative once real Phase 0 workloads are deployed.

- VPC across at least two Availability Zones.
- Private application subnets for EC2/ECS.
- Private data subnets for RDS/Redshift.
- Public subnets only where required.
- VPC endpoints for S3, DynamoDB, ECR, CloudWatch, Secrets Manager, and Systems Manager where justified.
- No public database endpoints.
- VPC Flow Logs enabled.
- Review NAT Gateway cost carefully in development.
