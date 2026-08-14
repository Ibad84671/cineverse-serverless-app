terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ─── DYNAMODB ───────────────────────────────────────────────────────────
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

# ─── LAMBDA ─────────────────────────────────────────────────────────────
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
  timeout          = 30
  memory_size      = 256
  environment {
    variables = {
      MOVIE_TABLE_NAME = aws_dynamodb_table.movies.name
      ALLOWED_ORIGIN   = var.allowed_origin
    }
  }
  tags = var.tags
}

# ─── IAM ────────────────────────────────────────────────────────────────
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
        "dynamodb:Scan",
        "dynamodb:Query"
      ]
      Resource = aws_dynamodb_table.movies.arn
    }]
  })
}
resource "aws_iam_role_policy_attachment" "lambda_dynamodb_attach" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.lambda_dynamodb.arn
}

# ─── API GATEWAY ────────────────────────────────────────────────────────
resource "aws_api_gateway_rest_api" "api" {
  name        = "${var.project_name}-api"
  description = "Cineverse Movie API"
  tags        = var.tags
}

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

resource "aws_api_gateway_method" "movies_get" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.movies.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_method" "movies_post" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.movies.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_method" "movie_get" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.movie_item.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_method" "movie_put" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.movie_item.id
  http_method   = "PUT"
  authorization = "NONE"
}

resource "aws_api_gateway_method" "movie_delete" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.movie_item.id
  http_method   = "DELETE"
  authorization = "NONE"
}

resource "aws_api_gateway_method" "movies_options" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.movies.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_method" "movie_options" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.movie_item.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

# Lambda integration for each method
resource "aws_api_gateway_integration" "movies_get" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.movies.id
  http_method             = aws_api_gateway_method.movies_get.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.movies.invoke_arn
}

resource "aws_api_gateway_integration" "movies_post" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.movies.id
  http_method             = aws_api_gateway_method.movies_post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.movies.invoke_arn
}

resource "aws_api_gateway_integration" "movie_get" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.movie_item.id
  http_method             = aws_api_gateway_method.movie_get.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.movies.invoke_arn
}

resource "aws_api_gateway_integration" "movie_put" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.movie_item.id
  http_method             = aws_api_gateway_method.movie_put.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.movies.invoke_arn
}

resource "aws_api_gateway_integration" "movie_delete" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.movie_item.id
  http_method             = aws_api_gateway_method.movie_delete.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.movies.invoke_arn
}

resource "aws_api_gateway_integration" "movies_options" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.movies.id
  http_method = aws_api_gateway_method.movies_options.http_method
  type        = "MOCK"
  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

resource "aws_api_gateway_integration" "movie_options" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.movie_item.id
  http_method = aws_api_gateway_method.movie_options.http_method
  type        = "MOCK"
  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

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

resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.movies.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/*/*"
}

# ─── OUTPUTS ────────────────────────────────────────────────────────────
output "api_url" {
  value = "${aws_api_gateway_deployment.prod.invoke_url}/movies"
}

output "table_name" {
  value = aws_dynamodb_table.movies.name
}