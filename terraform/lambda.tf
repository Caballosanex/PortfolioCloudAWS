# --- CV Counter Lambda ---
data "archive_file" "cv_counter" {
  type        = "zip"
  source_file = "${path.module}/../lambda/cv_counter/handler.py"
  output_path = "${path.module}/../lambda/cv_counter/handler.zip"
}

resource "aws_iam_role" "cv_counter" {
  name = "${var.project_name}-cv-counter-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })

  tags = { Name = "${var.project_name}-cv-counter-role" }
}

resource "aws_iam_role_policy_attachment" "cv_counter_basic" {
  role       = aws_iam_role.cv_counter.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "cv_counter_dynamodb" {
  name = "${var.project_name}-cv-counter-dynamodb"
  role = aws_iam_role.cv_counter.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:UpdateItem"
      ]
      Resource = aws_dynamodb_table.cv_counter.arn
    }]
  })
}

resource "aws_lambda_function" "cv_counter" {
  function_name    = "${var.project_name}-cv-counter"
  runtime          = "python3.12"
  handler          = "handler.lambda_handler"
  role             = aws_iam_role.cv_counter.arn
  filename         = data.archive_file.cv_counter.output_path
  source_code_hash = data.archive_file.cv_counter.output_base64sha256
  timeout          = 10
  memory_size      = 128

  tags = { Name = "${var.project_name}-cv-counter" }
}

resource "aws_lambda_function_url" "cv_counter" {
  function_name      = aws_lambda_function.cv_counter.function_name
  authorization_type = "NONE"
}

# --- Demo Reset Lambda ---
data "archive_file" "demo_reset" {
  type        = "zip"
  source_file = "${path.module}/../lambda/demo_reset/handler.py"
  output_path = "${path.module}/../lambda/demo_reset/handler.zip"
}

resource "aws_iam_role" "demo_reset" {
  name = "${var.project_name}-demo-reset-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })

  tags = { Name = "${var.project_name}-demo-reset-role" }
}

resource "aws_iam_role_policy_attachment" "demo_reset_basic" {
  role       = aws_iam_role.demo_reset.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "demo_reset_ecs" {
  name = "${var.project_name}-demo-reset-ecs"
  role = aws_iam_role.demo_reset.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "ecs:UpdateService"
      Resource = [
        aws_ecs_service.serp.id,
        aws_ecs_service.catlink.id
      ]
    }]
  })
}

resource "aws_lambda_function" "demo_reset" {
  function_name    = "${var.project_name}-demo-reset"
  runtime          = "python3.12"
  handler          = "handler.lambda_handler"
  role             = aws_iam_role.demo_reset.arn
  filename         = data.archive_file.demo_reset.output_path
  source_code_hash = data.archive_file.demo_reset.output_base64sha256
  timeout          = 30
  memory_size      = 128

  environment {
    variables = {
      ECS_CLUSTER  = aws_ecs_cluster.main.name
      ECS_SERVICES = "serp-backend,catlink-backend"
    }
  }

  tags = { Name = "${var.project_name}-demo-reset" }
}

# EventBridge: every 6 hours
resource "aws_cloudwatch_event_rule" "demo_reset" {
  name                = "${var.project_name}-demo-reset"
  schedule_expression = "cron(0 */6 * * ? *)"

  tags = { Name = "${var.project_name}-demo-reset" }
}

resource "aws_cloudwatch_event_target" "demo_reset" {
  rule = aws_cloudwatch_event_rule.demo_reset.name
  arn  = aws_lambda_function.demo_reset.arn
}

resource "aws_lambda_permission" "eventbridge_demo_reset" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.demo_reset.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.demo_reset.arn
}
