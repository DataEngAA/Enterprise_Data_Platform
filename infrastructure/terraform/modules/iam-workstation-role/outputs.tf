# Outputs -- identifiers only. No policy documents or secrets.

output "role_name" {
  description = "Name of the workstation IAM role."
  value       = aws_iam_role.workstation.name
}

output "role_arn" {
  description = "ARN of the workstation IAM role. Needed as a future input to Bootstrap Update 2 (adding this ARN to the shared deployment role's trust policy) -- copy this value from real output, never retype or guess it."
  value       = aws_iam_role.workstation.arn
}

output "instance_profile_name" {
  description = "Name of the instance profile wrapping the workstation role. Passed into modules/ec2-workstation as iam_instance_profile."
  value       = aws_iam_instance_profile.workstation.name
}

output "instance_profile_arn" {
  description = "ARN of the instance profile wrapping the workstation role."
  value       = aws_iam_instance_profile.workstation.arn
}
