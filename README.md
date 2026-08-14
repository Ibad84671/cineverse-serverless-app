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