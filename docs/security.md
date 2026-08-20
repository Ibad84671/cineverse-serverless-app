# CineVerse Security Model

## Identity

Amazon Cognito provides the hosted sign-in experience and JWTs. The web client is public and uses Authorization Code + PKCE, so no client secret is embedded in the browser.

## API authorization

- Public: catalog reads.
- Authenticated: create movies, update owned movies, read/write personal watchlist.
- Admin: delete movies and update other users' movies.

Authorization is enforced at both API Gateway and Lambda. Lambda does not trust a frontend-only “logged in” flag.

## Data protection

S3 blocks public access and is readable through CloudFront OAC. DynamoDB is encrypted at rest and uses point-in-time recovery. Application logs use a bounded retention period.

## Secrets

No AWS credentials or movie API keys are required by the current architecture. Runtime frontend configuration contains only public endpoints and a Cognito public client ID.

## Threats considered

- Direct public S3 access: blocked.
- Unauthorized writes: Cognito authorizer + Lambda identity checks.
- Cross-user watchlist access: partitioned by Cognito `sub`.
- Catalog deletion by normal users: admin group required.
- Client-side HTML injection: movie metadata is escaped before DOM insertion.
- Token leakage through persistent storage: tokens are held in session storage for the browser session.

For a larger public deployment, add AWS WAF, stricter API throttling, centralized alerting, a custom domain/ACM certificate and formal penetration testing.
