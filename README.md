# 🎬 Cineverse – Production-inspired Serverless AWS Application

[![CI](https://github.com/Ibad84671/cineverse-serverless-app/actions/workflows/ci.yml/badge.svg)](https://github.com/Ibad84671/cineverse-serverless-app/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![AWS](https://img.shields.io/badge/Cloud-AWS-orange?logo=amazon-aws)](https://aws.amazon.com/)
[![Serverless](https://img.shields.io/badge/Serverless-Yes-brightgreen)](https://aws.amazon.com/serverless/)

A production-inspired serverless AWS portfolio application demonstrating infrastructure as code, authentication, CI/CD, security controls and operational practices.

---

## 📋 Table of Contents

- [Architecture Overview](#-architecture-overview)
- [Repository Structure](#-repository-structure)
- [Security & Best Practices](#-security--best-practices-implemented)
- [Technology Stack](#-technology-stack)
- [Step‑by‑Step Deployment Guide](#-step-by-step-deployment-guide)
- [Cost Estimation](#-cost-estimation)
- [CI/CD Pipeline](#-cicd-pipeline)
- [Testing & Validation](#-testing--validation)
- [License](#-license)

---

## 🏛️ Architecture Overview

The application follows a modern **serverless 3‑tier pattern**:

- **Frontend** – static website hosted on a **private S3 bucket** and delivered globally via **CloudFront** with Origin Access Control (OAC).
- **API Layer** – **API Gateway** REST API, with public GET access and Cognito‑authenticated POST/PUT/DELETE operations.
- **Backend** – **AWS Lambda** (Python 3.12) handling business logic, input validation, and DynamoDB interactions.
- **Data Layer** – **DynamoDB** (PAY_PER_REQUEST) with Point‑in‑Time Recovery (PITR) enabled.

```mermaid
flowchart TD
    User([Internet User])
    CF[CloudFront CDN]
    S3[Private S3 Bucket<br>Static Frontend]
    API[API Gateway REST API]
    CP[Cognito User Pool]
    Client[Cognito Client]
    Lambda[Lambda Function<br>Python 3.12]
    DB[(DynamoDB<br>MovieCatalog)]
    CW[CloudWatch<br>Logs + Alarms]

    User -->|"HTTPS :443"| CF
    CF -->|"OAC"| S3
    User -->|"GET /movies"| API
    API -->|"POST /movies"| CP
    API -->|"PUT /movies/{id}"| CP
    API -->|"DELETE /movies/{id}"| CP
    CP --> Client
    API -->|"GET /movies"| Lambda
    Client -->|"JWT Validation"| Lambda
    Lambda -->|"CRUD Operations"| DB
    Lambda -->|"Logs & Metrics"| CW
🔒 Security & Best Practices Implemented
Category	Implementation
Frontend Security	S3 bucket is private (Block Public Access) – only CloudFront OAC can read
CDN Security	CloudFront with Origin Access Control (OAC) and HTTPS‑only viewer policy
API Authentication	Cognito User Pool + Client – POST/PUT/DELETE require valid JWT
API Authorization	DELETE restricted to users in the admins Cognito group
Secrets Management	No hardcoded credentials – CI uses GitHub OIDC, Lambda uses environment variables
Input Validation	Movie name, rating, year, and allowed update fields are validated server‑side
XSS Protection	User-controlled movie fields are HTML-escaped before insertion into generated markup
IAM Least Privilege	Lambda role grants only required DynamoDB actions on the specific table
Encryption	DynamoDB encryption at rest (AWS‑managed)
Backup	DynamoDB Point‑in‑Time Recovery (PITR) enabled
🔐 Authorization Flow
text
Internet
    │
    ▼
┌─────────────────────────────────────┐
│ CloudFront (HTTPS + OAC)            │
│ 🔓 Port 443 – Public access         │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│ API Gateway                         │
│ ────────────────────────────        │
│ 🔓 GET /movies – Public             │
│ 🔒 POST /movies – Cognito JWT       │
│ 🔒 PUT /movies/{id} – Cognito JWT   │
│ 🔒 DELETE /movies/{id} – Admin only │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│ Lambda Function                     │
│ ────────────────────────────        │
│ ✅ Validates JWT from Cognito       │
│ ✅ Checks admin group for DELETE    │
│ ✅ Validates input schema           │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│ DynamoDB (MovieCatalog)             │
│ ────────────────────────────        │
│ 🔒 Only Lambda IAM role can access  │
│ 🔒 PITR enabled                     │
└─────────────────────────────────────┘
🛠️ Technology Stack
Component	Technology	Version
Infrastructure	Terraform	1.10+
Cloud Provider	AWS	-
Frontend Hosting	S3 + CloudFront (OAC)	-
API	API Gateway REST API	-
Compute	AWS Lambda (Python)	3.12
Database	DynamoDB	PAY_PER_REQUEST
Authentication	Cognito User Pool	-
CI/CD	GitHub Actions (OIDC)	-
Security Scanning	Checkov, CodeQL	-
Monitoring	CloudWatch Logs + Alarms + SNS	-
🚀 Step‑by‑Step Deployment Guide
📋 Prerequisites
AWS CLI configured (aws configure) with appropriate IAM permissions

Terraform CLI (1.10+) installed

Git installed

📥 1. Clone the Repository
bash
git clone https://github.com/Ibad84671/cineverse-serverless-app.git
cd cineverse-serverless-app
⚙️ 2. Configure Environment Variables
Create a terraform.tfvars file inside the infrastructure/ directory:

hcl
# infrastructure/terraform.tfvars
aws_region   = "us-east-1"
project_name = "cineverse"
table_name   = "MovieCatalog"

# Email for CloudWatch alarms (must be valid)
alert_email = "your-email@example.com"
Note: The CI/CD pipeline generates frontend/config.js automatically from the Terraform output. For local development, copy frontend/config.example.js to frontend/config.js and set your API endpoint manually.

🏗️ 3. Initialize & Deploy
bash
cd infrastructure
terraform init
terraform validate
terraform plan
terraform apply
Type yes when prompted.

🌐 4. Access the Application
Once deployment completes, get the CloudFront URL:

bash
terraform output cloudfront_url
Open the URL in your browser:

text
https://<cloudfront-id>.cloudfront.net
🔐 5. Create a Cognito User
Go to AWS Console → Cognito → User Pools → Your pool

Create a user (email/password)

Confirm the user (or use admin set password)

Add the user to the admins group to enable DELETE.

🧹 6. Clean Up (Destroy Infrastructure)
bash
terraform destroy
Type yes when prompted.

💰 Cost Estimation (us-east-1, Low Usage)
Resource	Approx. Monthly
S3 (static hosting)	< $0.01
CloudFront	$0.01 – $0.05
API Gateway	$0.01 – $0.05
Lambda (Python 3.12)	< $0.01
DynamoDB (PAY_PER_REQUEST)	< $0.01
Cognito (50 MAU)	~$2.50
CloudWatch Logs	< $0.01
Total	~$2.50 – $3.00 / month
⚙️ CI/CD Pipeline
🔍 Continuous Integration (.github/workflows/ci.yml)
Triggered on every push / pull request to main:

✅ Python linting (flake8)

✅ Unit tests (pytest + moto mocks)

✅ Terraform fmt, validate

✅ Security scanning (Checkov, CodeQL)

🚀 Continuous Deployment (.github/workflows/deploy.yml)
Triggered on push to main:

✅ Assumes AWS IAM role via OIDC (no long‑lived credentials)

✅ Terraform plan + apply

✅ Generates frontend/config.js from Terraform output

✅ Syncs frontend to S3 bucket

✅ Creates CloudFront invalidation

✅ Runs smoke test to verify frontend and API are accessible

🧪 Testing & Validation
Run Unit Tests Locally
bash
cd backend
pip install -r requirements.txt
pip install -r requirements-dev.txt
pytest ../tests/unit/ -v --cov=backend --cov-report=term-missing
Validate Terraform
bash
cd infrastructure
terraform fmt -check
terraform validate
📜 License
Distributed under the MIT License. See LICENSE for more information.

🤝 Contributing
Please read CONTRIBUTING.md for details.

🔒 Security
Please read SECURITY.md for details on reporting security vulnerabilities.

Made with ❤️ by Ibad