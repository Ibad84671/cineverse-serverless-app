# Deployment Guide

## Prerequisites

- AWS CLI v2
- An AWS identity permitted to deploy the CloudFormation template
- Bash/Git Bash or PowerShell

## Local deployment

Bash:

```bash
export AWS_REGION=us-east-1
./scripts/deploy.sh
```

PowerShell:

```powershell
$env:AWS_REGION = "us-east-1"
.\scripts\deploy.ps1
```

The scripts validate `infrastructure/cineverse.yaml`, deploy the stack, read CloudFormation outputs, generate `frontend/config.js`, publish the static frontend to the private S3 bucket and invalidate CloudFront.

## GitHub Actions

The CD workflow runs on `main` and can also be started manually. Configure a GitHub Actions environment named `production` with an `AWS_ROLE_ARN` secret. The IAM role should trust GitHub's OIDC provider and restrict the repository/branch in its trust policy.

The workflow does not store AWS access keys.

## Post-deployment

Open the `FrontendUrl` printed by the deployment. Use Cognito's hosted UI through the Sign in button. To enable catalog deletion, add the appropriate user to the `admins` Cognito group.

## Cleanup

Review retained S3/DynamoDB resources before deleting the stack. The default template retains application data to protect against accidental stack deletion.
