output "domain" {
  description = "Domain name"
  value       = var.domain
}

output "cloudfront_domain" {
  description = "CloudFront distribution domain"
  value       = aws_cloudfront_distribution.main.domain_name
}

output "api_gateway_endpoint" {
  description = "API Gateway endpoint URL"
  value       = aws_apigatewayv2_api.main.api_endpoint
}

output "cv_counter_url" {
  description = "CV counter via API Gateway"
  value       = "${aws_apigatewayv2_api.main.api_endpoint}/cv/api/count"
}
