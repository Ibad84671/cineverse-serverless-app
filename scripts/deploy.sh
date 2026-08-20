#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STACK_NAME="${CINEVERSE_STACK_NAME:-cineverse-prod}"
REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"
PROJECT_NAME="${CINEVERSE_PROJECT_NAME:-cineverse}"
ENVIRONMENT="${CINEVERSE_ENVIRONMENT:-prod}"
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
DOMAIN_PREFIX="${CINEVERSE_DOMAIN_PREFIX:-${PROJECT_NAME}-${ACCOUNT_ID}}"
TEMPLATE="$ROOT/infrastructure/cineverse-v2.yaml"
command -v aws >/dev/null || { echo 'AWS CLI is required.' >&2; exit 1; }
[[ -f "$TEMPLATE" ]] || { echo "Missing $TEMPLATE" >&2; exit 1; }
echo "==> Validating CloudFormation"
aws cloudformation validate-template --template-body "file://$TEMPLATE" --region "$REGION" >/dev/null
echo "==> Deploying $STACK_NAME to $REGION"
aws cloudformation deploy --template-file "$TEMPLATE" --stack-name "$STACK_NAME" --region "$REGION" --capabilities CAPABILITY_NAMED_IAM --no-fail-on-empty-changeset --parameter-overrides ProjectName="$PROJECT_NAME" EnvironmentName="$ENVIRONMENT" CognitoDomainPrefix="$DOMAIN_PREFIX"
output(){ aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" --output text; }
BUCKET="$(output FrontendBucketName)"; API_URL="$(output ApiUrl)"; FRONTEND_URL="$(output FrontendUrl)"; COGNITO_DOMAIN="$(output CognitoDomain)"; CLIENT_ID="$(output CognitoClientId)"; DIST_DOMAIN="$(output CloudFrontDomainName)"
cat > "$ROOT/frontend/config.js" <<EOF
window.CINEVERSE_CONFIG = { apiUrl: "$API_URL", cognitoDomain: "$COGNITO_DOMAIN", clientId: "$CLIENT_ID", redirectUri: "$FRONTEND_URL", logoutUri: "$FRONTEND_URL" };
EOF
echo "==> Publishing frontend"
aws s3 sync "$ROOT/frontend/" "s3://$BUCKET/" --delete --exclude 'config.example.js' --cache-control 'public,max-age=300'
DIST_ID="$(aws cloudfront list-distributions --region "$REGION" --query "DistributionList.Items[?DomainName=='$DIST_DOMAIN'].Id | [0]" --output text)"
if [[ -n "$DIST_ID" && "$DIST_ID" != "None" ]]; then aws cloudfront create-invalidation --distribution-id "$DIST_ID" --paths '/*' >/dev/null; fi
echo
echo "CineVerse deployed successfully."
echo "Frontend: $FRONTEND_URL"
echo "API:      $API_URL"
echo "Stack:    $STACK_NAME"
