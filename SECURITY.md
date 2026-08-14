# Security Policy

## Supported Versions
| Version | Supported |
|---------|-----------|
| 1.x     | ✅ |

## Reporting a Vulnerability
If you discover a security vulnerability, please email `ibad84671@gmail.com`.  
Do **not** create a public GitHub issue.

## Security Controls
- ✅ **Cognito Authentication** – User Pool with email verification and password policy
- ✅ **API Gateway Authorizer** – Cognito JWT validation at edge
- ✅ **Admin-only DELETE** – Only users in the `admins` Cognito group can delete
- ✅ **Owner authorization** – Users can only edit their own movies
- ✅ **Input validation** – Server-side validation of movie name, rating, year, and allowed update fields
- ✅ **XSS protection** – User-controlled movie fields are HTML-escaped before being inserted into generated markup
- ✅ **IAM Least Privilege** – Lambda role grants only required DynamoDB actions on the specific table
- ✅ **Encryption at rest** – DynamoDB encryption enabled
- ✅ **Backup** – Point‑in‑Time Recovery (PITR) enabled
- ✅ **CI/CD security scanning** – Checkov, CodeQL, and Dependabot
- ✅ **No hardcoded secrets** – All credentials are environment‑based or OIDC‑assumed