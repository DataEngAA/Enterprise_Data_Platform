# Phase 0 Cost Controls -- shared, account-wide AWS Budget.
#
# Implements the approved design in 10_Cost_and_FinOps/Cost_Controls.md
# Section 1-2 and 01_Architecture/ADRs/ADR-0005-cost-controls-foundation.md:
# ONE Terraform-managed monthly budget, replacing the existing, manually
# created console budget (10_Cost_and_FinOps/Cost.md) -- same amount, same
# five thresholds, notifications routed through the EXISTING Logging and
# Audit Foundation SNS topic (var.sns_topic_arn), not a new one.
#
# EXPLICITLY DOES NOT touch, delete, or modify the existing manually
# created budget -- that budget is left fully alone by this configuration.
# Retiring it is a separate, later, manual (non-Terraform) step, performed
# only after this Terraform-managed budget is confirmed live and correctly
# alerting (Cost_Controls.md Section 13's validation plan). Running both
# budgets in parallel briefly is harmless -- AWS Budgets themselves carry no
# charge.
#
# No automated destructive action is attached to any threshold below --
# every notification ends in an SNS publish only.
#
# NOT YET APPLIED. No `terraform apply` has been run against this
# configuration.

resource "aws_budgets_budget" "shared" {
  name        = var.budget_name
  budget_type = "COST"
  time_unit   = "MONTHLY"

  limit_amount = var.budget_limit_amount_usd
  limit_unit   = "USD"

  # --- Actual-spend thresholds (Cost_Controls.md Section 2) -----------------
  # Approved, unchanged four-rung ladder from the existing manually created
  # budget: early warning, serious warning, hard attention threshold,
  # ceiling reached. ABSOLUTE_VALUE (USD), not PERCENTAGE -- matches how
  # these thresholds have always been reasoned and communicated in this
  # project's own documentation. Driven from var.budget_actual_thresholds_usd
  # (a plain list, default [5, 15, 24, 30]) via a dynamic block rather than
  # four hand-written blocks, so the exact same threshold values reviewed in
  # variables.tf are what a real `terraform plan` will show -- no value is
  # duplicated or re-typed here.
  dynamic "notification" {
    for_each = var.budget_actual_thresholds_usd

    content {
      comparison_operator        = "GREATER_THAN"
      threshold                  = notification.value
      threshold_type             = "ABSOLUTE_VALUE"
      notification_type          = "ACTUAL"
      subscriber_sns_topic_arns  = [var.sns_topic_arn]
      subscriber_email_addresses = []
    }
  }

  # --- Forecasted-spend threshold (Cost_Controls.md Section 1-2) ------------
  # Fires when AWS's own trend-based projection says the month will end
  # over this amount -- can fire before any ACTUAL threshold above, since it
  # is trend-based, not threshold-based. Approved, unchanged value from the
  # existing manually created budget.
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = var.budget_forecasted_threshold_usd
    threshold_type             = "ABSOLUTE_VALUE"
    notification_type          = "FORECASTED"
    subscriber_sns_topic_arns  = [var.sns_topic_arn]
    subscriber_email_addresses = []
  }
}
