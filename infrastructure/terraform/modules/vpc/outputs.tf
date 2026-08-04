# Outputs -- identifiers only. No secrets.

output "vpc_id" {
  description = "ID of the created VPC."
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "CIDR block of the created VPC (echoed back for convenience/review)."
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_id" {
  description = "ID of the single public subnet."
  value       = aws_subnet.public.id
}

output "availability_zone" {
  description = "The Availability Zone actually selected for the public subnet (Section 20) -- exposed explicitly so the dynamically-resolved AZ is visible to anyone reviewing a plan/apply/output, not an invisible internal detail of this module."
  value       = local.selected_availability_zone
}

output "internet_gateway_id" {
  description = "ID of the Internet Gateway attached to the VPC."
  value       = aws_internet_gateway.this.id
}

output "public_route_table_id" {
  description = "ID of the public route table."
  value       = aws_route_table.public.id
}
