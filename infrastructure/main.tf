terraform {
  required_version = "~> 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  backend "s3" {
    # Replace these with your actual state bucket
    bucket       = "cineverse-terraform-state"
    key          = "cineverse/dev/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}

provider "aws" {
  region = var.aws_region
}

# ─── S3 FRONTEND ──────────────────────────────────────────────────────
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

resource "aws_s3_bucket_versioning" "frontend" {
  bucket = aws_s3_bucket.frontend.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "frontend" {
  bucket = aws_s3_bucket.frontend.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_ownership_controls" "frontend" {
  bucket = aws_s3_bucket.frontend.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# ─── S3 BUCKET POLICY FOR CLOUDFRONT OAC ────────────────────────────
resource "aws_s3_bucket_policy" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudFrontRead"
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.frontend.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.frontend.arn
          }
        }
      }
    ]
  })
}

# ─── CLOUDFRONT ──────────────────────────────────────────────────────
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

# ─── DYNAMODB ────────────────────────────────────────────────────────
resource "aws_dynamodb_table" "movies" {
  name           = var.table_name
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "MovieId"
  attribute {
    name = "MovieId"
    type = "S"
  }
  point_in_time_recovery {
    enabled = true
  }
  tags = var.tags
}

# ─── LAMBDA ──────────────────────────────────────────────────────────
data "archive_file" "lambda" {
  type        = "zip"
  source_dir  = "${path.module}/../backend"
  output_path = "${path.module}/lambda.zip"
}

resource "aws_lambda_function" "movies" {
  filename         = data.archive_file.lambda.output_path
  function_name    = "${var.project_name}-movies"
  role             = aws_iam_role.lambda_exec.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.12"
  timeout          = 10
  memory_size      = 256
  environment {
    variables = {
      MOVIE_TABLE_NAME = aws_dynamodb_table.movies.name
      ALLOWED_ORIGIN   = var.allowed_origin
    }
  }
  tags = var.tags
}

# ─── IAM ─────────────────────────────────────────────────────────────
resource "aws_iam_role" "lambda_exec" {
  name = "${var.project_name}-lambda-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_policy" "lambda_dynamodb" {
  name = "${var.project_name}-lambda-dynamodb"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:UpdateItem",
        "dynamodb:DeleteItem",
        "dynamodb:Scan"
      ]
      Resource = aws_dynamodb_table.movies.arn
    }]
  })
}
resource "aws_iam_role_policy_attachment" "lambda_dynamodb_attach" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.lambda_dynamodb.arn
}

# ─── COGNITO ────────────────────────────────────────────────────────
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

# ─── COGNITO ADMIN GROUP ────────────────────────────────────────────
resource "aws_cognito_user_group" "admins" {
  name         = "admins"
  user_pool_id = aws_cognito_user_pool.this.id
  description  = "Cineverse administrators"
}

# ─── API GATEWAY ────────────────────────────────────────────────────
resource "aws_api_gateway_rest_api" "api" {
  name        = "${var.project_name}-api"
  description = "Cineverse Movie API"
  tags        = var.tags
}

# API Gateway Authorizer (Cognito)
resource "aws_api_gateway_authorizer" "cognito" {
  name = "${var.project_name}-cognito"
  rest_api_id = aws_api_gateway_rest_api.api.id
  type = "COGNITO_USER_POOLS"
  identity_source = "method.request.header.Authorization"
  provider_arns = [aws_cognito_user_pool.this.arn]
}

# Resources
resource "aws_api_gateway_resource" "movies" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "movies"
}

resource "aws_api_gateway_resource" "movie_item" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_resource.movies.id
  path_part   = "{movie_id}"
}

# ─── GET (public) ───────────────────────────────────────────────────
resource "aws_api_gateway_method" "movies_get" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.movies.id
  http_method   = "GET"
  authorization = "NONE"
}
resource "aws_api_gateway_integration" "movies_get" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.movies.id
  http_method             = aws_api_gateway_method.movies_get.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.movies.invoke_arn
}
resource "aws_api_gateway_method" "movie_get" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.movie_item.id
  http_method   = "GET"
  authorization = "NONE"
}
resource "aws_api_gateway_integration" "movie_get" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.movie_item.id
  http_method             = aws_api_gateway_method.movie_get.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.movies.invoke_arn
}

# ─── POST (authenticated) ──────────────────────────────────────────
resource "aws_api_gateway_method" "movies_post" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.movies.id
  http_method   = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito.id
}
resource "aws_api_gateway_integration" "movies_post" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.movies.id
  http_method             = aws_api_gateway_method.movies_post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.movies.invoke_arn
}

# ─── PUT (authenticated + owner) ──────────────────────────────────
resource "aws_api_gateway_method" "movie_put" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.movie_item.id
  http_method   = "PUT"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito.id
}
resource "aws_api_gateway_integration" "movie_put" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.movie_item.id
  http_method             = aws_api_gateway_method.movie_put.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.movies.invoke_arn
}

# ─── DELETE (admin only) ───────────────────────────────────────────
resource "aws_api_gateway_method" "movie_delete" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.movie_item.id
  http_method   = "DELETE"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito.id
}
resource "aws_api_gateway_integration" "movie_delete" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.movie_item.id
  http_method             = aws_api_gateway_method.movie_delete.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.movies.invoke_arn
}

# ─── OPTIONS (CORS) with proper headers ────────────────────────────
resource "aws_api_gateway_method" "movies_options" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.movies.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}
resource "aws_api_gateway_integration" "movies_options" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.movies.id
  http_method = aws_api_gateway_method.movies_options.http_method
  type        = "MOCK"
  request_templates = { "application/json" = "{\"statusCode\": 200}" }
  integration_responses {
    status_code = "200"
    response_parameters = {
      "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,Authorization'"
      "method.response.header.Access-Control-Allow-Methods" = "'GET,POST,PUT,DELETE,OPTIONS'"
      "method.response.header.Access-Control-Allow-Origin"  = var.allowed_origin
    }
  }
}
resource "aws_api_gateway_method_response" "movies_options_200" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.movies.id
  http_method = aws_api_gateway_method.movies_options.http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_method" "movie_options" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.movie_item.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}
resource "aws_api_gateway_integration" "movie_options" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.movie_item.id
  http_method = aws_api_gateway_method.movie_options.http_method
  type        = "MOCK"
  request_templates = { "application/json" = "{\"statusCode\": 200}" }
  integration_responses {
    status_code = "200"
    response_parameters = {
      "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,Authorization'"
      "method.response.header.Access-Control-Allow-Methods" = "'GET,POST,PUT,DELETE,OPTIONS'"
      "method.response.header.Access-Control-Allow-Origin"  = var.allowed_origin
    }
  }
}
resource "aws_api_gateway_method_response" "movie_options_200" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.movie_item.id
  http_method = aws_api_gateway_method.movie_options.http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

# ─── API THROTTLING ────────────────────────────────────────────────
resource "aws_api_gateway_deployment" "prod" {
  depends_on = [
    aws_api_gateway_integration.movies_get,
    aws_api_gateway_integration.movies_post,
    aws_api_gateway_integration.movie_get,
    aws_api_gateway_integration.movie_put,
    aws_api_gateway_integration.movie_delete,
    aws_api_gateway_integration.movies_options,
    aws_api_gateway_integration.movie_options
  ]
  rest_api_id = aws_api_gateway_rest_api.api.id
  stage_name  = "dev"
}

resource "aws_api_gateway_stage" "dev" {
  stage_name    = "dev"
  rest_api_id   = aws_api_gateway_rest_api.api.id
  deployment_id = aws_api_gateway_deployment.prod.id

  method_settings {
    resource_path = "/*/*"
    http_method   = "*"
    metrics_enabled = true
    logging_level   = "INFO"
    throttling_burst_limit = 20
    throttling_rate_limit  = 10
  }
}

resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.movies.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/*/*"
}

# ─── CLOUDWATCH ALARMS ─────────────────────────────────────────────
resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

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
  alarm_actions = [aws_sns_topic.alerts.arn]
  dimensions = { FunctionName = aws_lambda_function.movies.function_name }
}

resource "aws_cloudwatch_metric_alarm" "lambda_throttles" {
  alarm_name = "${var.project_name}-lambda-throttles"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods = 1
  metric_name = "Throttles"
  namespace = "AWS/Lambda"
  period = 300
  statistic = "Sum"
  threshold = 1
  alarm_description = "Lambda function throttles"
  alarm_actions = [aws_sns_topic.alerts.arn]
  dimensions = { FunctionName = aws_lambda_function.movies.function_name }
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
  alarm_actions = [aws_sns_topic.alerts.arn]
  dimensions = { ApiName = aws_api_gateway_rest_api.api.name }
}

resource "aws_cloudwatch_metric_alarm" "api_4xx" {
  alarm_name = "${var.project_name}-api-4xx"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods = 1
  metric_name = "4XXError"
  namespace = "AWS/ApiGateway"
  period = 300
  statistic = "Sum"
  threshold = 10
  alarm_description = "API Gateway 4xx errors (spike)"
  alarm_actions = [aws_sns_topic.alerts.arn]
  dimensions = { ApiName = aws_api_gateway_rest_api.api.name }
}

# ─── DATA SOURCES ──────────────────────────────────────────────────
data "aws_caller_identity" "current" {}