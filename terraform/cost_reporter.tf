# --- Cost Reporter Lambda ---
# Weekly AWS cost digest delivered via Discord webhook (and optionally SES).
# SSM parameter must be populated manually before first invocation:
#   aws ssm put-parameter --name /cost-reporter/discord_webhook_url --type SecureString --value "WEBHOOK_URL" --region eu-west-1 --profile personal

data "archive_file" "cost_reporter" {
  type        = "zip"
  source_file = "${path.module}/../lambda/cost_reporter/handler.py"
  output_path = "${path.module}/../lambda/cost_reporter/handler.zip"
}

# IAM role
resource "aws_iam_role" "cost_reporter" {
  name = "${var.project_name}-cost-reporter-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })

  tags = { Name = "${var.project_name}-cost-reporter-role" }
}

resource "aws_iam_role_policy_attachment" "cost_reporter_basic" {
  role       = aws_iam_role.cost_reporter.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "cost_reporter" {
  name = "${var.project_name}-cost-reporter-policy"
  role = aws_iam_role.cost_reporter.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CostExplorer"
        Effect = "Allow"
        Action = ["ce:GetCostAndUsage", "ce:GetCostForecast"]
        Resource = "*"
      },
      {
        Sid    = "SSMRead"
        Effect = "Allow"
        Action = ["ssm:GetParameter", "ssm:GetParameters"]
        Resource = "arn:aws:ssm:${var.aws_region}:*:parameter/cost-reporter/*"
      },
      {
        Sid    = "SES"
        Effect = "Allow"
        Action = ["ses:SendEmail", "ses:SendRawEmail"]
        Resource = "*"
      },
    ]
  })
}

# Lambda function
resource "aws_lambda_function" "cost_reporter" {
  function_name    = "${var.project_name}-cost-reporter"
  runtime          = "python3.12"
  handler          = "handler.lambda_handler"
  role             = aws_iam_role.cost_reporter.arn
  filename         = data.archive_file.cost_reporter.output_path
  source_code_hash = data.archive_file.cost_reporter.output_base64sha256
  timeout          = 30
  memory_size      = 128

  tags = { Name = "${var.project_name}-cost-reporter" }
}

# EventBridge: every Monday at 08:00 UTC
resource "aws_cloudwatch_event_rule" "cost_reporter_weekly" {
  name                = "${var.project_name}-cost-reporter-weekly"
  schedule_expression = "cron(0 8 ? * MON *)"

  tags = { Name = "${var.project_name}-cost-reporter-weekly" }
}

resource "aws_cloudwatch_event_target" "cost_reporter" {
  rule = aws_cloudwatch_event_rule.cost_reporter_weekly.name
  arn  = aws_lambda_function.cost_reporter.arn
}

resource "aws_lambda_permission" "eventbridge_cost_reporter" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.cost_reporter.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.cost_reporter_weekly.arn
}
