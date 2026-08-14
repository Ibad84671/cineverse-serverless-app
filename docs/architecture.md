# Cineverse Architecture

## Overview
Cineverse is a serverless movie catalog application built on AWS.

## Components
- S3: Static frontend hosting
- CloudFront: CDN with OAC
- API Gateway: REST API with Cognito authorizer
- Lambda: Python 3.12 business logic
- DynamoDB: NoSQL database with PITR
- Cognito: User authentication
- CloudWatch: Logging and alarms

## Data Flow
User → CloudFront → S3 (frontend)
User → API Gateway → Cognito → Lambda → DynamoDB

## Security
- Private S3 with OAC
- Cognito authentication
- Admin-only DELETE
- IAM least privilege