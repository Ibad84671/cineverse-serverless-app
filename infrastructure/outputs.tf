output "bucket_name" {
  value = aws_s3_bucket.frontend.id
}

output "api_url" {
  value = "${aws_api_gateway_deployment.prod.invoke_url}/movies"
}

output "cloudfront_url" {
  value = aws_cloudfront_distribution.frontend.domain_name
}

output "user_pool_id" {
  value = aws_cognito_user_pool.this.id
}

output "user_pool_client_id" {
  value = aws_cognito_user_pool_client.this.id
}

output "sns_topic_arn" {
  value = aws_sns_topic.alerts.arn
}