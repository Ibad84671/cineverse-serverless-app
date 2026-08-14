variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "cineverse"
}

variable "table_name" {
  description = "DynamoDB table name"
  type        = string
  default     = "MovieCatalog"
}

variable "allowed_origin" {
  description = "Frontend origin (CloudFront URL) – must be HTTPS"
  type        = string
  validation {
    condition     = startswith(var.allowed_origin, "https://")
    error_message = "allowed_origin must use HTTPS."
  }
}

variable "alert_email" {
  description = "Email address for CloudWatch alarms"
  type        = string
  default     = "admin@example.com"
}

variable "tags" {
  description = "Common tags"
  type        = map(string)
  default = {
    Environment = "dev"
    Project     = "cineverse"
    ManagedBy   = "Terraform"
  }
}