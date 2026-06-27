# --- API Gateway HTTP API ---
resource "aws_apigatewayv2_api" "main" {
  name          = "${var.project_name}-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["https://${var.domain}"]
    allow_methods = ["GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS"]
    allow_headers = ["*"]
    max_age       = 3600
  }

  tags = { Name = "${var.project_name}-api" }
}

# --- CV Counter Lambda Integration ---
resource "aws_apigatewayv2_integration" "cv_counter" {
  api_id                 = aws_apigatewayv2_api.main.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.cv_counter.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "cv_counter" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "ANY /cv/api/{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.cv_counter.id}"
}

resource "aws_lambda_permission" "apigw_cv_counter" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.cv_counter.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*/*"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.main.id
  name        = "$default"
  auto_deploy = true

  default_route_settings {
    throttling_burst_limit = 100
    throttling_rate_limit  = 50
  }

  tags = { Name = "${var.project_name}-api-stage" }
}

# VPC Link for Fargate access
resource "aws_apigatewayv2_vpc_link" "main" {
  name               = "${var.project_name}-vpc-link"
  security_group_ids = [aws_security_group.fargate.id]
  subnet_ids         = [aws_subnet.public.id, aws_subnet.public_b.id]

  tags = { Name = "${var.project_name}-vpc-link" }
}

# --- SERP Backend Integration ---
resource "aws_apigatewayv2_integration" "serp" {
  api_id             = aws_apigatewayv2_api.main.id
  integration_type   = "HTTP_PROXY"
  integration_method = "ANY"
  integration_uri    = aws_service_discovery_service.serp.arn
  connection_type    = "VPC_LINK"
  connection_id      = aws_apigatewayv2_vpc_link.main.id

  request_parameters = {
    "overwrite:path" = "/$request.path.proxy"
  }
}

resource "aws_apigatewayv2_route" "serp" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "ANY /demo/serp/api/{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.serp.id}"
}

# --- CatLink Backend Integration ---
resource "aws_apigatewayv2_integration" "catlink" {
  api_id             = aws_apigatewayv2_api.main.id
  integration_type   = "HTTP_PROXY"
  integration_method = "ANY"
  integration_uri    = aws_service_discovery_service.catlink.arn
  connection_type    = "VPC_LINK"
  connection_id      = aws_apigatewayv2_vpc_link.main.id

  request_parameters = {
    "overwrite:path" = "/api/$request.path.proxy"
  }
}

resource "aws_apigatewayv2_route" "catlink" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "ANY /demo/catlink/api/{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.catlink.id}"
}

# CatLink WebSocket upgrade
resource "aws_apigatewayv2_integration" "catlink_ws" {
  api_id             = aws_apigatewayv2_api.main.id
  integration_type   = "HTTP_PROXY"
  integration_method = "GET"
  integration_uri    = aws_service_discovery_service.catlink.arn
  connection_type    = "VPC_LINK"
  connection_id      = aws_apigatewayv2_vpc_link.main.id

  request_parameters = {
    "overwrite:path" = "/ws"
  }
}

resource "aws_apigatewayv2_route" "catlink_ws" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "GET /demo/catlink/ws"
  target    = "integrations/${aws_apigatewayv2_integration.catlink_ws.id}"
}

# --- MatchCota Backend Integration ---
resource "aws_apigatewayv2_integration" "matchcota" {
  api_id             = aws_apigatewayv2_api.main.id
  integration_type   = "HTTP_PROXY"
  integration_method = "ANY"
  integration_uri    = aws_service_discovery_service.matchcota.arn
  connection_type    = "VPC_LINK"
  connection_id      = aws_apigatewayv2_vpc_link.main.id

  request_parameters = {
    "overwrite:path"                 = "/api/$request.path.proxy"
    "overwrite:header.X-Tenant-Slug" = "demo"
  }
}

resource "aws_apigatewayv2_route" "matchcota" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "ANY /demo/matchcota/api/{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.matchcota.id}"
}
