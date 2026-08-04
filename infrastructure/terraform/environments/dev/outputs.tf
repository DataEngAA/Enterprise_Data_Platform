# Outputs -- identifiers only. No secrets, credentials, or policy documents
# are output.

output "vpc_id" {
  description = "ID of the dev VPC."
  value       = module.vpc.vpc_id
}

output "public_subnet_id" {
  description = "ID of the single public subnet."
  value       = module.vpc.public_subnet_id
}

output "availability_zone" {
  description = "The Availability Zone actually selected for the public subnet (Section 20) -- exposed so the dynamically-resolved AZ is visible without hardcoding a literal AZ name anywhere in this configuration."
  value       = module.vpc.availability_zone
}

output "security_group_id" {
  description = "ID of the workstation's zero-inbound security group."
  value       = module.ec2_workstation.security_group_id
}

output "workstation_role_arn" {
  description = "ARN of the workstation IAM role. Needed as a future input to Bootstrap Update 2 (adding this ARN to the shared deployment role's trust policy, infrastructure/terraform/bootstrap/) -- copy this value from real output, never retype or guess it."
  value       = module.workstation_role.role_arn
}

output "workstation_instance_profile_name" {
  description = "Name of the instance profile attached to the workstation instance."
  value       = module.workstation_role.instance_profile_name
}

output "workstation_instance_profile_arn" {
  description = "ARN of the instance profile attached to the workstation instance."
  value       = module.workstation_role.instance_profile_arn
}

output "instance_id" {
  description = "ID of the EC2 workstation instance."
  value       = module.ec2_workstation.instance_id
}

output "instance_public_ip" {
  description = "Public IPv4 address of the workstation instance. Does not by itself imply inbound accessibility -- governed entirely by the zero-inbound security group."
  value       = module.ec2_workstation.public_ip
}

output "ami_id" {
  description = "The AMI ID actually resolved/used for the workstation instance -- either the automatic latest-AL2023-x86_64 lookup result or the explicit var.ami_id_override, exposed for review (Section 22)."
  value       = local.resolved_ami_id
}

output "deployment_role_arn_targeted" {
  description = "Echo of var.deployment_role_arn -- the shared deployment role ARN this root module's provider and backend both assume. Exposed as an output so it is visible in `terraform output` without needing to inspect terraform.tfvars directly."
  value       = var.deployment_role_arn
}
