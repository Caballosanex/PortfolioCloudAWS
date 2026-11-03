# --- Observability: CloudWatch alarms -> SNS -> Lambda -> Discord ---
# The Discord webhook is shared with the cost reporter (SSM /cost-reporter/discord_webhook_url).
# CloudFront publishes its metrics in us-east-1 only, so that alarm and its SNS topic live there.

locals {
  ecs_services = ["serp-backend", "catlink-backend", "matchcota"]
  lambda_names = {
    cv_counter    = aws_lambda_function.cv_counter.function_name
    demo_reset    = aws_lambda_function.demo_reset.function_name
    cost_reporter = aws_lambda_function.cost_reporter.function_name
  }
}

# --- Notifier Lambda ---
data "archive_file" "alarm_notifier" {
  type        = "zip"
  source_file = "${path.module}/../lambda/alarm_notifier/handler.py"
  output_path = "${path.module}/../lambda/alarm_notifier/handler.zip"
}

resource "aws_iam_role" "alarm_notifier" {
  name = "${var.project_name}-alarm-notifier-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })

  tags = { Name = "${var.project_name}-alarm-notifier-role" }
}

resource "aws_iam_role_policy_attachment" "alarm_notifier_basic" {
  role       = aws_iam_role.alarm_notifier.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "alarm_notifier" {
  name = "${var.project_name}-alarm-notifier-policy"
  role = aws_iam_role.alarm_notifier.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "SSMReadWebhook"
      Effect   = "Allow"
      Action   = ["ssm:GetParameter"]
      Resource = "arn:aws:ssm:${var.aws_region}:*:parameter/cost-reporter/discord_webhook_url"
    }]
  })
}

resource "aws_lambda_function" "alarm_notifier" {
  function_name    = "${var.project_name}-alarm-notifier"
  runtime          = "python3.12"
  handler          = "handler.lambda_handler"
  role             = aws_iam_role.alarm_notifier.arn
  filename         = data.archive_file.alarm_notifier.output_path
  source_code_hash = data.archive_file.alarm_notifier.output_base64sha256
  timeout          = 15
  memory_size      = 128

  lifecycle {
    ignore_changes = [filename, source_code_hash]
  }

  tags = { Name = "${var.project_name}-alarm-notifier" }
}

# --- SNS topics (one per region) ---
resource "aws_sns_topic" "alarms" {
  name = "${var.project_name}-alarms"
  tags = { Name = "${var.project_name}-alarms" }
}

resource "aws_sns_topic" "alarms_us_east_1" {
  provider = aws.us_east_1
  name     = "${var.project_name}-alarms-us-east-1"
  tags     = { Name = "${var.project_name}-alarms-us-east-1" }
}

resource "aws_sns_topic_subscription" "alarms" {
  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.alarm_notifier.arn
}

resource "aws_sns_topic_subscription" "alarms_us_east_1" {
  provider  = aws.us_east_1
  topic_arn = aws_sns_topic.alarms_us_east_1.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.alarm_notifier.arn
}

resource "aws_lambda_permission" "sns_alarms" {
  statement_id  = "AllowSNSInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.alarm_notifier.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.alarms.arn
}

resource "aws_lambda_permission" "sns_alarms_us_east_1" {
  statement_id  = "AllowSNSInvokeUsEast1"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.alarm_notifier.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.alarms_us_east_1.arn
}

# --- Alarms ---

# CloudFront 5xx rate (us-east-1 metrics). Sustained over 15 min so a single bad request does not page.
resource "aws_cloudwatch_metric_alarm" "cloudfront_5xx" {
  provider            = aws.us_east_1
  alarm_name          = "${var.project_name}-cloudfront-5xx"
  alarm_description   = "CloudFront is returning 5xx errors (rate above 5% for 15 minutes)."
  namespace           = "AWS/CloudFront"
  metric_name         = "5xxErrorRate"
  dimensions          = { DistributionId = aws_cloudfront_distribution.main.id, Region = "Global" }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 3
  threshold           = 5
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alarms_us_east_1.arn]
  ok_actions          = [aws_sns_topic.alarms_us_east_1.arn]
}

# API Gateway 5xx (covers backend 502/503/504 when a Fargate task is down).
resource "aws_cloudwatch_metric_alarm" "apigw_5xx" {
  alarm_name          = "${var.project_name}-apigw-5xx"
  alarm_description   = "API Gateway returned 3+ 5xx responses in 5 minutes (a demo backend may be down)."
  namespace           = "AWS/ApiGateway"
  metric_name         = "5xx"
  dimensions          = { ApiId = aws_apigatewayv2_api.main.id }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 3
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]
}

# ECS service liveness. A running service publishes CPUUtilization; when no task runs the metric
# disappears. Missing data is treated as breaching against an impossible threshold, so the alarm
# fires only when the service stops reporting for 10 minutes (no Container Insights needed).
resource "aws_cloudwatch_metric_alarm" "ecs_service_down" {
  for_each            = toset(local.ecs_services)
  alarm_name          = "${var.project_name}-ecs-${each.key}-down"
  alarm_description   = "ECS service ${each.key} reported no metrics for 10 minutes (no running task)."
  namespace           = "AWS/ECS"
  metric_name         = "CPUUtilization"
  dimensions          = { ClusterName = aws_ecs_cluster.main.name, ServiceName = each.key }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  threshold           = -1
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "breaching"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]
}

# Lambda errors.
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  for_each            = local.lambda_names
  alarm_name          = "${var.project_name}-lambda-${replace(each.key, "_", "-")}-errors"
  alarm_description   = "Lambda ${each.value} had at least one error in 5 minutes."
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  dimensions          = { FunctionName = each.value }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]
}
