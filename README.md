# Enterprise AWS Terraform Bootstrap

A minimal, security-first Terraform bootstrap for standing up the foundational AWS resources (remote state backend and a scoped deployment IAM role) needed before any further infrastructure is built.

## What this creates

- An S3 bucket for Terraform remote state, with versioning, encryption, and public-access blocking enabled
- A deployment IAM role intended for CI/CD or local `terraform apply` use, with **no permissions attached initially** — permissions are added incrementally as later infrastructure phases require them
- The role's trust policy is conditioned on MFA, so it cannot be assumed without a valid MFA session

## Why local state first

This bootstrap is deliberately applied once using **local Terraform state**, before any remote backend exists — you can't point Terraform at an S3 backend that Terraform itself hasn't created yet. Once the bucket exists and is verified, state is migrated to S3 in a follow-up step (`terraform init -migrate-state` with a real `backend.hcl`).

## Why the deployment role starts empty

Following least-privilege practice, the role is created with a trust policy only. Permissions are attached in later phases as specific infrastructure is introduced, rather than granting broad access upfront.

## Validation performed

- `terraform fmt` and `terraform validate` — passed
- `tflint` — passed, no findings requiring action
- `trivy` (IaC scan) — no blocking findings; all results reviewed

## Usage

This repo contains source and example files only. No real account values are included.

```bash
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars with your own values

cp backend.hcl.example backend.hcl
# edit backend.hcl with your own values (only needed after first apply)

terraform init
terraform plan
terraform apply
```

## What's intentionally excluded

This is a curated excerpt of a larger private project. Execution history, break-glass procedures, checklists, and operational runbooks are maintained privately and are not part of this public repo.
