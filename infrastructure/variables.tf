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
  description = "CORS allowed origin"
  type        = string
  default     = "*"
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