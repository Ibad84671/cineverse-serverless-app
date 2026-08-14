# ─── S3 BUCKET (Frontend Hosting) ───
resource "aws_s3_bucket" "frontend" {
  bucket = "${var.project_name}-frontend-${data.aws_caller_identity.current.account_id}"
  tags   = var.tags
}

resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket = aws_s3_bucket.frontend.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ─── CLOUDFRONT ────────────────────────────────────────────────────────
resource "aws_cloudfront_origin_access_control" "frontend" {
  name                              = "${var.project_name}-oac"
  description                       = "OAC for S3 frontend"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "frontend" {
  enabled             = true
  default_root_object = "index.html"
  
  origin {
    domain_name              = aws_s3_bucket.frontend.bucket_regional_domain_name
    origin_id                = "S3-Frontend"
    origin_access_control_id = aws_cloudfront_origin_access_control.frontend.id
  }
  
  default_cache_behavior {
    target_origin_id = "S3-Frontend"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods = ["GET", "HEAD", "OPTIONS"]
    cached_methods  = ["GET", "HEAD"]
    compress        = true
    min_ttl         = 0
    default_ttl     = 300
    max_ttl         = 86400
    forwarded_values {
      query_string = false
      cookies { forward = "none" }
    }
  }
  
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
  
  viewer_certificate {
    cloudfront_default_certificate = true
  }
  
  tags = var.tags
}

# ─── COGNITO ────────────────────────────────────────────────────────────
resource "aws_cognito_user_pool" "this" {
  name = "${var.project_name}-user-pool"
  username_attributes = ["email"]
  auto_verified_attributes = ["email"]
  
  schema {
    name = "email"
    attribute_data_type = "String"
    required = true
    mutable = true
  }
  
  password_policy {
    minimum_length = 8
    require_lowercase = true
    require_numbers = true
    require_symbols = true
    require_uppercase = true
  }
  
  account_recovery_setting {
    recovery_mechanism {
      name = "verified_email"
      priority = 1
    }
  }
}

resource "aws_cognito_user_pool_client" "this" {
  name = "${var.project_name}-client"
  user_pool_id = aws_cognito_user_pool.this.id
  generate_secret = false
  explicit_auth_flows = ["ALLOW_USER_PASSWORD_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]
  prevent_user_existence_errors = "ENABLED"
}

resource "aws_cognito_user_pool_domain" "this" {
  domain = "${var.project_name}-${random_id.suffix.hex}"
  user_pool_id = aws_cognito_user_pool.this.id
}

resource "random_id" "suffix" {
  byte_length = 4
}

# ─── API GATEWAY AUTHORIZER ────────────────────────────────────────────
resource "aws_api_gateway_authorizer" "cognito" {
  name = "${var.project_name}-cognito"
  rest_api_id = aws_api_gateway_rest_api.api.id
  type = "COGNITO_USER_POOLS"
  identity_source = "method.request.header.Authorization"
  provider_arns = [aws_cognito_user_pool.this.arn]
}

# ─── UPDATE EXISTING METHODS TO USE AUTHORIZER ──────────────────────
# Replace existing methods with these:
# For POST, PUT, DELETE – use Cognito authorizer
# For GET – public

resource "aws_api_gateway_method" "movies_post_auth" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.movies.id
  http_method = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito.id
}

resource "aws_api_gateway_method" "movie_put_auth" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.movie_item.id
  http_method = "PUT"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito.id
}

resource "aws_api_gateway_method" "movie_delete_auth" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.movie_item.id
  http_method = "DELETE"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito.id
}

# ─── UPDATE INTEGRATIONS ───────────────────────────────────────────────
# (Use same integration as before but for auth methods)

# ─── CLOUDWATCH ALARMS ──────────────────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name = "${var.project_name}-lambda-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods = 1
  metric_name = "Errors"
  namespace = "AWS/Lambda"
  period = 300
  statistic = "Sum"
  threshold = 1
  alarm_description = "Lambda function errors"
  dimensions = {
    FunctionName = aws_lambda_function.movies.function_name
  }
}

resource "aws_cloudwatch_metric_alarm" "api_5xx" {
  alarm_name = "${var.project_name}-api-5xx"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods = 1
  metric_name = "5XXError"
  namespace = "AWS/ApiGateway"
  period = 300
  statistic = "Sum"
  threshold = 1
  alarm_description = "API Gateway 5xx errors"
  dimensions = {
    ApiName = aws_api_gateway_rest_api.api.name
  }
}