# 🎬 Cineverse - Serverless Movie Catalog on AWS

[![Terraform CI/Validation](https://github.com/Ibad84671/cineverse-serverless-app/actions/workflows/ci.yml/badge.svg)](https://github.com/Ibad84671/cineverse-serverless-app/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![AWS](https://img.shields.io/badge/Cloud-AWS-orange?logo=amazon-aws)](https://aws.amazon.com/)
[![Serverless](https://img.shields.io/badge/Serverless-Yes-brightgreen)](https://aws.amazon.com/serverless/)

Production‑grade, fully serverless movie catalog application deployed on AWS using **Terraform** (Infrastructure as Code) and automated through **GitHub Actions CI/CD**.

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
    User([Internet User]) -->|"HTTPS :443"| CF[CloudFront CDN]
    CF -->|"OAC"| S3["Private S3 Bucket<br/>Static Frontend"]

    User -->|"GET /movies"| API["API Gateway REST API"]

    subgraph Auth["Cognito Authentication"]
        CP[Cognito User Pool]
        CP --> Client[Cognito Client]
    end

    API -->|"POST /movies"| Auth
    API -->|"PUT /movies/{id}"| Auth
    API -->|"DELETE /movies/{id}"| Auth
    API -->|"GET /movies"| Lambda["Lambda Function<br/>Python 3.12"]
    Auth -->|"JWT Validation"| Lambda

    Lambda -->|"CRUD Operations"| DB[("DynamoDB<br/>MovieCatalog")]
    Lambda -->|"Logs & Metrics"| CW[CloudWatch<br/>Logs + Alarms]
---

## 📂 Repository Structure

The project follows a clean, decoupled layout:

```
cineverse-serverless-app/
├── .github/
│   └── workflows/
│       ├── ci.yml               # Lint, test, terraform validate, security scan
│       └── deploy.yml           # OIDC-based deployment pipeline
├── backend/
│   ├── lambda_function.py       # Main Lambda handler (CRUD + validation)
│   └── requirements.txt         # Python dependencies
├── frontend/
│   └── index.html               # Single‑page frontend (dark theme, responsive)
├── infrastructure/
│   ├── main.tf                  # Root Terraform module
│   ├── variables.tf             # Input variables (region, origin, etc.)
│   └── outputs.tf               # CloudFront URL, API endpoint, Cognito IDs
├── tests/
│   └── unit/
│       └── test_lambda.py       # Unit tests (pytest + mocks)
├── .gitignore
├── CHANGELOG.md
├── CONTRIBUTING.md
├── SECURITY.md
├── LICENSE
└── README.md                    # This file
```

---

## 🔒 Security & Best Practices Implemented

| Category | Implementation |
|----------|----------------|
| **Frontend Security** | S3 bucket is **private** (Block Public Access) – only CloudFront OAC can read |
| **CDN Security** | CloudFront with **Origin Access Control (OAC)** and HTTPS‑only viewer policy |
| **API Authentication** | Cognito User Pool + Client – POST/PUT/DELETE require valid JWT |
| **API Authorization** | DELETE restricted to users in the `admins` Cognito group |
| **Secrets Management** | No hardcoded credentials – CI uses GitHub OIDC, Lambda uses environment variables |
| **Input Validation** | Movie name, rating, year, and allowed update fields are validated server‑side |
| **XSS Protection** | Frontend uses `textContent` for dynamic content rendering |
| **IAM Least Privilege** | Lambda role grants only required DynamoDB actions on the specific table |
| **Encryption** | DynamoDB encryption at rest (AWS‑managed) |
| **Backup** | DynamoDB Point‑in‑Time Recovery (PITR) enabled |

### 🔐 Security Group / Authorization Flow

```
Internet
    │
    ▼
┌─────────────────────────────────────┐
│ CloudFront (HTTPS + OAC)            │
│ ────────────────────────────        │
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
```

---

## 🛠️ Technology Stack

| Component | Technology | Version |
|-----------|------------|---------|
| **Infrastructure** | Terraform | 1.6+ |
| **Cloud Provider** | AWS | - |
| **Frontend Hosting** | S3 + CloudFront (OAC) | - |
| **API** | API Gateway REST API | - |
| **Compute** | AWS Lambda (Python) | 3.12 |
| **Database** | DynamoDB | PAY_PER_REQUEST |
| **Authentication** | Cognito User Pool | - |
| **CI/CD** | GitHub Actions (OIDC) | - |
| **Security Scanning** | Checkov, CodeQL | - |
| **Monitoring** | CloudWatch Logs + Alarms | - |

---

## 🚀 Step‑by‑Step Deployment Guide

### 📋 Prerequisites

- AWS CLI configured (`aws configure`) with appropriate IAM permissions
- Terraform CLI (v1.6+) installed
- Git installed
- (Optional) Python 3.12+ for local testing

### 📥 1. Clone the Repository

```bash
git clone https://github.com/Ibad84671/cineverse-serverless-app.git
cd cineverse-serverless-app
```

### ⚙️ 2. Configure Environment Variables

Create a `terraform.tfvars` file inside the `infrastructure/` directory:

```hcl
# infrastructure/terraform.tfvars
aws_region      = "us-east-1"
project_name    = "cineverse"
allowed_origin  = "https://your-cloudfront-url"   # will be shown after apply
```

> **Note:** `allowed_origin` must be an HTTPS URL (CloudFront will provide it after deployment). You can update it later.

### 🏗️ 3. Initialize & Deploy

```bash
cd infrastructure
terraform init
terraform validate
terraform plan
terraform apply
```

Type `yes` when prompted.

### 🌐 4. Access the Application

Once deployment completes, get the CloudFront URL:

```bash
terraform output cloudfront_url
```

Open the URL in your browser:
```
https://<cloudfront-id>.cloudfront.net
```

You can also get the API endpoint:

```bash
terraform output api_url
```

### 🔐 5. Create a Cognito User

- Go to AWS Console → Cognito → User Pools → Your pool
- Create a user (email/password)
- Confirm the user (or use admin set password)

### 🧹 6. Clean Up (Destroy Infrastructure)

To avoid ongoing AWS charges:

```bash
terraform destroy
```

Type `yes` when prompted.

---

## 💰 Cost Estimation (us-east-1, Low Usage)

| Resource | Approx. Monthly |
|----------|-----------------|
| S3 (static hosting) | < $0.01 |
| CloudFront | $0.01 – $0.05 (free tier covers 1TB/mo) |
| API Gateway | $0.01 – $0.05 |
| Lambda (Python 3.12) | < $0.01 |
| DynamoDB (PAY_PER_REQUEST) | < $0.01 |
| Cognito (50 MAU) | ~$2.50 |
| CloudWatch Logs | < $0.01 |
| **Total** | **~$2.50 – $3.00 / month** |

> **Note:** Costs scale with usage. The architecture is designed to stay within the AWS Free Tier for light workloads.

---

## ⚙️ CI/CD Pipeline

The repository includes **two** GitHub Actions workflows:

### 🔍 Continuous Integration (`.github/workflows/ci.yml`)

Triggered on every push / pull request to `main`:

- ✅ Python linting (`flake8`)
- ✅ Unit tests (`pytest` + `moto` mocks)
- ✅ Terraform `fmt`, `validate`
- ✅ Security scanning (Checkov, CodeQL)

### 🚀 Continuous Deployment (`.github/workflows/deploy.yml`)

Triggered on push to `main`:

- ✅ Assumes AWS IAM role via **OIDC** (no long‑lived credentials)
- ✅ Terraform `plan` + `apply`
- ✅ Syncs frontend to S3 bucket

**OIDC Trust Policy** – the AWS role is restricted to this repository and branch, following least‑privilege principles.

---

## 🧪 Testing & Validation

### Run Unit Tests Locally

```bash
cd backend
pip install -r requirements.txt
pip install pytest moto
pytest ../tests/unit/ -v
```

### Validate Terraform

```bash
cd infrastructure
terraform fmt -check
terraform validate
```

### Security Scanning (Optional)

```bash
# Install Checkov
pip install checkov
checkov -d ./

# Run CodeQL locally (requires GitHub CLI)
gh codeql database create --language=python
```

---

## 📜 License

Distributed under the MIT License. See `LICENSE` for more information.

---

## 🤝 Contributing

Please read [CONTRIBUTING.md](CONTRIBUTING.md) for details on our code of conduct and the process for submitting pull requests.

## 🔒 Security

Please read [SECURITY.md](SECURITY.md) for details on reporting security vulnerabilities.

---

**Made with ❤️ by Ibad**