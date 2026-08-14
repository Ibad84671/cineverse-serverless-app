# Deployment Guide

## Prerequisites
- AWS CLI configured
- Terraform 1.6+
- Git

## Steps
1. Clone repository
2. Create terraform.tfvars
3. Initialize Terraform
4. Apply infrastructure
5. Sync frontend to S3
6. Create CloudFront invalidation

## CI/CD Pipeline
- CI: Lint, test, validate, security scan
- CD: Deploy on push to main with OIDC