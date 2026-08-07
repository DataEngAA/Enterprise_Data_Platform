# Outputs -- non-sensitive identifiers only. No secret, credential, or
# policy document is output.

output "budget_name" {
  description = "Name of the Terraform-managed shared, account-wide AWS Budget."
  value       = aws_budgets_budget.shared.name
}

output "budget_arn" {
  description = "ARN of the Terraform-managed AWS Budget."
  value       = aws_budgets_budget.shared.arn
}

output "budget_id" {
  description = "ID of the Terraform-managed AWS Budget (same as name for aws_budgets_budget)."
  value       = aws_budgets_budget.shared.id
}

output "sns_topic_arn_used" {
  description = "Echo of var.sns_topic_arn -- the existing Logging and Audit Foundation SNS topic this budget's notifications are routed through. Exposed for visibility without needing to inspect terraform.tfvars directly."
  value       = var.sns_topic_arn
}
