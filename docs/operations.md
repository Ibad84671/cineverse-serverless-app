# Operations Guide

## Monitoring
- CloudWatch alarms for Lambda errors, throttles, API 4xx/5xx
- SNS email notifications

## Disaster Recovery
- DynamoDB PITR enabled
- RTO: < 30 minutes
- RPO: < 5 minutes

## Rollback
- Frontend: CloudFront invalidation + S3 versioning
- Infrastructure: Terraform state rollback