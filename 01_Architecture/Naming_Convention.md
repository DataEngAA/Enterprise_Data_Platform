# Naming Convention

Status: **Initial practical standard — approved for use starting with AWS account preparation.** This is a first working convention, not a final, immutable spec; revise deliberately and record why if changed later.

## Project identifier

`enterprise-data-platform`

Used as the base token in nearly every name below. No other authoritative project name currently exists in the repository, so this is adopted per user instruction.

## Environment values

`dev`, `test`, `stage`, `prod`

These are the only four **deployment environment** values used anywhere a name, tag, or Terraform workspace needs one. Per `PROJECT_BLUEPRINT.md` Section 11 Step 3, `dev` is expected to be implemented first while the multi-environment design is documented; the other three values are reserved, not yet built.

**`shared` — a resource-scope tag value, not a fifth deployment environment (approved 2026-07-25).** A small number of account-level Terraform Bootstrap resources (the remote-state S3 bucket and the Terraform deployment IAM role, see `02_Infrastructure/Terraform_Bootstrap_Design.md`) are not owned by any single deployment environment — they exist once, project-wide, and are used to manage `dev`/`test`/`stage`/`prod` alike. These resources use `Environment = shared` on the `Environment` tag (Required tags, below) and, where a name includes an environment token, use `shared` in that position (e.g. `enterprise-data-platform-shared-deployment-role`). `shared` must never be used as a Terraform workspace/environment-directory value (`environments/shared/` is not a thing) and must never be selected for any resource that is actually owned by a specific deployment environment — it exists solely to tag/name the small set of bootstrap-level resources correctly.

## General pattern

Most AWS resource names follow:

```text
<project>-<environment>-<component>-<purpose>
```

All lowercase, hyphen-separated, no underscores, no spaces, ASCII only (matches AWS resource-name restrictions such as S3 bucket naming). Keep names descriptive but short enough to stay under each service's name-length limit.

## AWS resource naming

| Resource type | Pattern | Example |
|---|---|---|
| EC2 instance (Name tag) | `<project>-<environment>-<purpose>` | `enterprise-data-platform-dev-workstation` |
| VPC | `<project>-<environment>-vpc` | `enterprise-data-platform-dev-vpc` |
| Subnet | `<project>-<environment>-<public\|private>-<az-suffix>` | `enterprise-data-platform-dev-public-1a` |
| Internet Gateway | `<project>-<environment>-igw` | `enterprise-data-platform-dev-igw` |
| Route table | `<project>-<environment>-<public\|private>-rt` | `enterprise-data-platform-dev-public-rt` |
| Security group | see "Security group naming" below | |
| IAM role | see "IAM role naming" below | |
| S3 bucket | see "S3 bucket naming pattern" below | |
| CloudWatch log group | `/enterprise-data-platform/<environment>/<component>` | `/enterprise-data-platform/dev/workstation` |
| Lambda function | `<project>-<environment>-<function-purpose>` | `enterprise-data-platform-dev-workstation-autostop` |
| KMS key alias | `alias/<project>-<environment>-<purpose>` | `alias/enterprise-data-platform-dev-ebs` |

Exact values (AZ suffixes, specific component names) are filled in as each resource is actually designed — no ARNs, account IDs, or resource IDs are invented here.

## Terraform resource naming

- Terraform **logical resource names** (the identifier after the resource type, e.g. `resource "aws_instance" "this"`) use `snake_case`, short and descriptive, without repeating the resource type or the project name (Terraform already namespaces by module/state): e.g. `resource "aws_instance" "workstation" { ... }`, not `resource "aws_instance" "enterprise_data_platform_dev_workstation" { ... }`.
- Terraform **workspace / state naming** (once remote state exists) uses `<project>-<environment>`, e.g. `enterprise-data-platform-dev`.
- Terraform **variable names** use `snake_case` (e.g. `instance_type`, `environment`, `project_name`).
- Terraform **module directory names** use `kebab-case` describing the module's responsibility (e.g. `modules/ec2-workstation`, `modules/vpc`) — no modules exist yet; this is the convention to apply once Terraform Bootstrap begins.

## S3 bucket naming pattern

```text
<project>-<environment>-<purpose>
```

Example: `enterprise-data-platform-dev-landing`, `enterprise-data-platform-dev-quarantine`, `enterprise-data-platform-dev-tfstate`.

S3 bucket names must be globally unique across all AWS accounts. If the plain pattern above collides with an existing bucket name (which cannot be verified without an AWS account), a short random or account-derived suffix will need to be appended at creation time — flagged here as a likely necessity, not resolved in advance since no account ID is available to derive it from.

## IAM role naming

```text
<project>-<environment>-<role-purpose>-role
```

Examples, consistent with the two-role split already approved in `02_Infrastructure/EC2_Development_Workstation.md` Section 13:

- `enterprise-data-platform-dev-workstation-role` (EC2 instance profile role — SSM, minimal logging, narrow artifact access, `sts:AssumeRole` only; environment-scoped, since each environment eventually gets its own workstation/runtime identities)
- `enterprise-data-platform-shared-deployment-role` (Terraform deployment role — assumed, holds infrastructure-management permissions; **corrected 2026-07-25** from an earlier `-dev-` example — the deployment role is a single, project-wide bootstrap resource used to manage every environment, not a `dev`-specific one, so it takes the `shared` environment token per the "Environment values" section above)

IAM **policy** names follow the same pattern with `-policy` instead of `-role`, e.g. `enterprise-data-platform-dev-workstation-policy`.

## Security group naming

```text
<project>-<environment>-<purpose>-sg
```

Example: `enterprise-data-platform-dev-workstation-sg`.

## Required tags

Every taggable AWS resource must carry:

| Tag key | Value | Status |
|---|---|---|
| `Project` | `enterprise-data-platform` | Set |
| `Environment` | `dev` \| `test` \| `stage` \| `prod` \| `shared` | Set (choose per resource). `shared` is reserved for the small set of account-level Terraform Bootstrap resources not owned by a single deployment environment (see "Environment values" above) — not a deployment environment itself. |
| `ManagedBy` | `terraform` (or `manual` only for the rare resource created outside Terraform, which should be an exception, not the norm) | Set |
| `Owner` | `DataEngAA` | Set — confirmed by user 2026-07-24. |
| `CostCenter` | `personal-learning` | Set — confirmed by user 2026-07-24. |
| `DataClassification` | `public` \| `internal` \| `confidential` \| `restricted` | Set the classification scheme; the value per resource is chosen when the resource is created — no data exists yet to classify. |

`Owner` and `CostCenter` values are now confirmed and ready to use on real resources once they exist.

## Related files

- `01_Architecture/Standards.md` — engineering standards (Python, Terraform, data, S3 layout).
- `02_Infrastructure/AWS_Account_Preparation.md` — the account-level decisions (region, budget, VPC, IAM/MFA) this naming convention supports.
- `02_Infrastructure/EC2_Development_Workstation.md` — the workstation design that uses these IAM role and security group naming patterns.

Last updated: 2026-07-25
