# infrastructure/terraform/kms-secrets

Status: **Deployed and validated on real AWS (2026-08-07).** Every resource described here exists in AWS; a final `terraform plan` reported no differences. Implements the approved design in `02_Infrastructure/KMS_and_Secrets.md` (Section 14 has real deployment evidence) and `01_Architecture/ADRs/ADR-0004-kms-and-secrets-foundation.md`. Full incident record: `PROJECT_EXECUTION_JOURNAL.md` Section 27ap.

## Responsibility

Owns Phase 0's KMS and Secrets foundation: one shared customer-managed KMS key with an explicit, per-principal key policy; one dev-scoped demonstration Secrets Manager secret (metadata only); one dev-scoped demonstration Parameter Store parameter. This is the fourth Phase 0 workstream, following IAM foundation (`bootstrap/`), Logging and Audit Foundation (`logging/`), and Networking Hardening (`environments/dev`, `modules/vpc`).

## Provider authentication — departs from `logging/`'s precedent

This stack authenticates via the shared deployment role (`assume_role`), the same pattern `environments/dev` uses — **not** `logging/`'s human-direct pattern. This is deliberate: this workstream's own scope requires new deployment-role KMS/Secrets Manager/Parameter Store permissions (`bootstrap/main.tf`'s new `deployment_shared_kms_secrets_permissions` policy), which only has a purpose if the deployment role actually applies this stack. See `providers.tf` for the full rationale.

**Dependency: `bootstrap/main.tf`'s `deployment_shared_kms_secrets_permissions` policy and its attachment must already be applied** before this stack's own `plan`/`apply` can succeed — without it, the deployment role has no `kms:CreateKey`, `secretsmanager:CreateSecret`, or `ssm:PutParameter` permission at all.

## Resources this stack creates

- `aws_kms_key.this` — the shared customer-managed key (`enterprise-data-platform-shared-cmk`), symmetric, `ENCRYPT_DECRYPT`, annual rotation, 30-day deletion window, `prevent_destroy`.
- `aws_kms_alias.this` — `alias/enterprise-data-platform-shared-primary`.
- `data.aws_iam_policy_document.cmk` / the key's own `policy` argument — two statements: account-root break-glass, and deployment-role administration (no usage rights).
- `aws_secretsmanager_secret.demo` — metadata only, name `enterprise-data-platform/dev/demo/ingestion-api`. **Uses the AWS-managed Secrets Manager default key, not the shared project CMK** — see "Why this secret does not use the shared CMK" below.
- `aws_ssm_parameter.demo` — `String`, Standard tier, name `/enterprise-data-platform/dev/demo/ingestion-config`, a literal, non-sensitive placeholder value.

## Why no KMS key-policy usage statement exists yet

The approved design (`KMS_and_Secrets.md` Section 3) anticipates a third key-policy statement granting `kms:Decrypt`/`kms:Encrypt`/`kms:GenerateDataKey*` to specific consuming principals. It is **not included in this implementation**:

- The demonstration parameter is a plain `String`, not `SecureString` — Parameter Store only calls KMS for `SecureString` values.
- The demonstration secret uses the AWS-managed Secrets Manager default key, not this CMK — see "Why this secret does not use the shared CMK" below.

Adding a usage statement is the well-defined next step for whenever a real `SecureString` parameter, a real CMK-backed secret, or a migrated CloudWatch Logs/S3/EBS consumer is introduced — each its own separate, later, explicitly reviewed key-policy edit, never a speculative advance grant.

## Why this secret does not use the shared CMK

**Corrected 2026-08-07, after a real, first `terraform apply`.** The original implementation set `kms_key_id = aws_kms_key.this.key_id` on the demonstration secret. A real apply was denied: `AccessDeniedException: Access to KMS is not allowed`. Root cause: AWS Secrets Manager validates that the caller can actually use the specified customer-managed key **at `CreateSecret` time**, even when no version/value is ever supplied — requiring `kms:GenerateDataKey`/`kms:Decrypt` against that key. The original design's assumption that a metadata-only secret invokes no KMS action was **technically incomplete**, corrected in `KMS_and_Secrets.md` Sections 6 and 13.

Rather than grant the deployment role any KMS data-use right (`kms:GenerateDataKey`/`kms:Decrypt`, however narrowly scoped) for a secret that holds no real value yet, `aws_secretsmanager_secret.demo` now omits `kms_key_id` and uses the AWS-managed Secrets Manager default key, which requires no caller KMS permission at all. **This demonstration secret is not protected by the shared project CMK.** Migrating it, or a real future secret, to the CMK is a separate, later, explicitly reviewed change using the dual-gate model already designed in `KMS_and_Secrets.md` Section 3: a matching key-policy usage statement, a matching narrowly scoped IAM identity grant, a `kms:ViaService=secretsmanager.<region>.amazonaws.com` condition, and the exact CMK ARN.

## Setting the demonstration secret's value (manual, outside Terraform, not part of this task)

Terraform never sets this secret's value, in this task or any future one — this is standing project policy (`KMS_and_Secrets.md` Section 6), not a Phase-0-only restriction. To exercise the read-path authorization tests in the Validation Plan (`KMS_and_Secrets.md` Section 11) after this stack is applied, a human runs, once, manually:

```
aws secretsmanager put-secret-value \
  --secret-id enterprise-data-platform/dev/demo/ingestion-api \
  --secret-string "PLACEHOLDER-NON-SENSITIVE-VALUE-DO-NOT-TREAT-AS-REAL"
```

This is a real AWS CLI command, run by an authorized human under their own credentials — not part of this Terraform stack, not run by this task, and not run against AWS by this task either.

## Explicitly out of scope for this stack (and this task)

- Migrating the Terraform state bucket's or the CloudTrail audit bucket's encryption from SSE-S3 to this CMK.
- Migrating the CloudTrail-to-CloudWatch-Logs log group's encryption to this CMK.
- Migrating the EC2 workstation's root EBS volume from the AWS-managed `aws/ebs` key to this CMK.
- Any real, non-placeholder secret or parameter value.
- Any Phase 1 runtime-role KMS/Secrets Manager grant (no Phase 1 runtime role exists yet).

Each is a separate, later, explicitly reviewed task — see `KMS_and_Secrets.md` "Related Files."

## Validation performed

Structural checks in this sandbox (no `terraform` binary here): Python `hcl2` parse and brace-balance check on every `.tf` file. Real `fmt`/`validate`/`plan`/`apply` were run by the user, on their own machine, against real AWS. **A real `terraform apply` succeeded, after four incremental bootstrap deployment-role IAM corrections and one corrected design decision (Section "Why this secret does not use the shared CMK" above). A final `terraform plan` reported "No changes. Your infrastructure matches the configuration." Every resource described in this stack exists in real AWS.** Full record: `02_Infrastructure/KMS_and_Secrets.md` Section 14; `PROJECT_EXECUTION_JOURNAL.md` Section 27ap.
