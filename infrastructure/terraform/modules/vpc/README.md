# modules/vpc

Status: **Code created, not yet validated, planned, or applied.** No AWS resource described here exists.

## Responsibility

Owns every networking resource for a single environment: the dedicated VPC, its one public subnet, the Internet Gateway, and the public route table (including the route-table association). This module is the sole owner of the "networking" concern, kept separate from IAM (`modules/iam-workstation-role`) and compute (`modules/ec2-workstation`) per `Dev_Environment_Terraform_Implementation_Plan.md` Section 3.

## Resources owned

- `aws_vpc.this`
- `aws_subnet.public`
- `aws_internet_gateway.this`
- `aws_route_table.public`
- `aws_route.public_internet_ipv4`
- `aws_route_table_association.public`
- `data.aws_availability_zones.available`

## Inputs

| Variable | Description | Default |
|---|---|---|
| `project_name` | Project identifier for naming/tags. | none (required) |
| `environment` | Deployment environment (e.g. `"dev"`). | none (required) |
| `vpc_cidr` | CIDR block for the VPC. Approved dev value: `10.20.0.0/16`. | none (required) |
| `public_subnet_cidr` | CIDR block for the public subnet. Approved dev value: `10.20.1.0/24`. | none (required) |
| `availability_zone_override` | Optional literal AZ name override. Leave `null` to use the dynamic first-AZ lookup. | `null` |
| `tags` | Common tag map from the caller's `locals.tf`. | `{}` |

## Outputs

`vpc_id`, `vpc_cidr`, `public_subnet_id`, `availability_zone` (the AZ actually selected), `internet_gateway_id`, `public_route_table_id`.

## Security decisions

- **No literal AZ name is ever hardcoded.** `data.aws_availability_zones` is queried and index `0` of the returned list is used deterministically, because AZ *names* (the `1a`/`1b`/`1c` suffixes) have account-specific physical mappings — the same suffix can point at a different physical AZ in a different AWS account.
- **DNS support and DNS hostnames are both enabled** on the VPC — required for Session Manager and standard AWS service name resolution to work correctly from inside the VPC.
- **`map_public_ip_on_launch` is deliberately not set on the subnet.** Public-IP assignment is set explicitly on the instance itself (`modules/ec2-workstation`), not implied by a subnet-wide default that could silently affect a future second instance placed in the same subnet.

## What this module intentionally does not manage

- **No private subnet** for either the application or data tier. Their CIDR ranges (`10.20.11.0/24`, `10.20.21.0/24`) are reserved only in the caller's documentation/variables — no `aws_subnet` resource for either exists.
- **No NAT Gateway** — accepted trade-off for this phase (`Dev_Environment_Terraform_Implementation_Plan.md` Section 19); outbound reachability for the public subnet comes from the Internet Gateway route only.
- **No VPC endpoints** (S3, SSM, etc.) — deferred; not created in this phase.
- **No Network ACL customization** — the VPC's default NACL (allow-all) is left untouched; the workstation's actual traffic control is the security group in `modules/ec2-workstation`, not a custom NACL.
- **No IPv6 resources** of any kind.
- **No security group** — owned by `modules/ec2-workstation`, since its only consumer today is the workstation instance.
