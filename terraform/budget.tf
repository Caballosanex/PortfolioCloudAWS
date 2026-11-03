# AWS Budget alert at 80% of monthly limit
resource "aws_budgets_budget" "monthly" {
  name         = "${var.project_name}-monthly-budget"
  budget_type  = "COST"
  limit_amount = var.monthly_budget
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = 80
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_email_addresses = ["alexsanchezblabia@gmail.com"]
  }
}

# Gross spend budget (credits and refunds excluded). The budget above is measured net of credits and
# stays at 0 while credits last, so it cannot warn about the real run rate. Normal gross spend is ~21 USD.
# Alerts go to Discord through the alarm notifier (SNS) and by email.
resource "aws_budgets_budget" "gross" {
  name         = "${var.project_name}-gross-budget"
  budget_type  = "COST"
  limit_amount = var.gross_budget_limit
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  cost_types {
    include_credit = false
    include_refund = false
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = ["alexsanchezblabia@gmail.com"]
    subscriber_sns_topic_arns  = [aws_sns_topic.alarms.arn]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = ["alexsanchezblabia@gmail.com"]
    subscriber_sns_topic_arns  = [aws_sns_topic.alarms.arn]
  }

  depends_on = [aws_sns_topic_policy.alarms]
}

resource "aws_sns_topic_policy" "alarms" {
  arn = aws_sns_topic.alarms.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowCloudWatchAlarms"
        Effect    = "Allow"
        Principal = { Service = "cloudwatch.amazonaws.com" }
        Action    = "sns:Publish"
        Resource  = aws_sns_topic.alarms.arn
        Condition = { StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id } }
      },
      {
        Sid       = "AllowBudgets"
        Effect    = "Allow"
        Principal = { Service = "budgets.amazonaws.com" }
        Action    = "sns:Publish"
        Resource  = aws_sns_topic.alarms.arn
        Condition = { StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id } }
      }
    ]
  })
}

data "aws_caller_identity" "current" {}
