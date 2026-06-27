variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-west-1"
}

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "asanchezbl-portfolio"
}

variable "domain" {
  description = "Domain name"
  type        = string
  default     = "asanchezbl.dev"
}

variable "cloudflare_api_token" {
  description = "Cloudflare API token"
  type        = string
  sensitive   = true
}

variable "cloudflare_zone_id" {
  description = "Cloudflare zone ID for asanchezbl.dev"
  type        = string
}

variable "monthly_budget" {
  description = "Monthly budget alert threshold in USD"
  type        = number
  default     = 15
}
