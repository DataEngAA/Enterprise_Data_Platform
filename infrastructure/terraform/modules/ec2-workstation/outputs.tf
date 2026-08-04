# Outputs -- identifiers only. No secrets.

output "instance_id" {
  description = "ID of the EC2 workstation instance."
  value       = aws_instance.workstation.id
}

output "public_ip" {
  description = "Public IPv4 address of the workstation instance. A public IP does not, by itself, create inbound accessibility -- that is governed entirely by the zero-inbound security group (Section 16)."
  value       = aws_instance.workstation.public_ip
}

output "security_group_id" {
  description = "ID of the workstation's security group."
  value       = aws_security_group.workstation.id
}
