# 🎬 Cineverse – Serverless Movie Catalog

[![CI](https://github.com/Ibad84671/cineverse-serverless-app/actions/workflows/ci.yml/badge.svg)](https://github.com/Ibad84671/cineverse-serverless-app/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Cineverse is a serverless movie catalog application built with AWS S3, API Gateway, Lambda, and DynamoDB.

## Architecture
User → S3 (Frontend) → API Gateway → Lambda → DynamoDB

## Features
- ✅ View movie catalog
- ✅ Add new movies
- ✅ Update movies (PUT)
- ✅ Delete movies (DELETE)
- ✅ XSS protection
- ✅ Input validation
- ✅ Responsive dark UI

## Tech Stack
| Layer | Technology |
|-------|------------|
| Frontend | HTML/CSS/JavaScript |
| Backend | AWS Lambda (Python) |
| API | API Gateway REST API |
| Database | DynamoDB |
| IaC | Terraform |
| CI/CD | GitHub Actions |

## Quick Start
1. Deploy infrastructure:
```bash
cd infrastructure
terraform init
terraform apply
Update frontend/index.html with your API URL.

Upload frontend/ to S3.

Security
✅ XSS protection with textContent

✅ Input validation (rating, year, length)

✅ Environment variables for config

✅ Least-privilege IAM

License

MIT © Ibad Shaikh