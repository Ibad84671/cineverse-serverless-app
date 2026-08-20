$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$StackName = if ($env:CINEVERSE_STACK_NAME) { $env:CINEVERSE_STACK_NAME } else { 'cineverse-prod' }
$Region = if ($env:AWS_REGION) { $env:AWS_REGION } elseif ($env:AWS_DEFAULT_REGION) { $env:AWS_DEFAULT_REGION } else { 'us-east-1' }
$ProjectName = if ($env:CINEVERSE_PROJECT_NAME) { $env:CINEVERSE_PROJECT_NAME } else { 'cineverse' }
$Environment = if ($env:CINEVERSE_ENVIRONMENT) { $env:CINEVERSE_ENVIRONMENT } else { 'prod' }
$AccountId = (aws sts get-caller-identity --query Account --output text).Trim()
$DomainPrefix = if ($env:CINEVERSE_DOMAIN_PREFIX) { $env:CINEVERSE_DOMAIN_PREFIX } else { "$ProjectName-$AccountId" }
$Template = Join-Path $Root 'infrastructure\cineverse-v2.yaml'
if (-not (Get-Command aws -ErrorAction SilentlyContinue)) { throw 'AWS CLI is required.' }
if (-not (Test-Path $Template)) { throw "Missing $Template" }
Write-Host '==> Validating CloudFormation' -ForegroundColor Cyan
aws cloudformation validate-template --template-body "file://$Template" --region $Region | Out-Null
Write-Host "==> Deploying $StackName to $Region" -ForegroundColor Cyan
aws cloudformation deploy --template-file $Template --stack-name $StackName --region $Region --capabilities CAPABILITY_NAMED_IAM --no-fail-on-empty-changeset --parameter-overrides "ProjectName=$ProjectName" "EnvironmentName=$Environment" "CognitoDomainPrefix=$DomainPrefix"
function Get-Output($key) { return (aws cloudformation describe-stacks --stack-name $StackName --region $Region --query "Stacks[0].Outputs[?OutputKey=='$key'].OutputValue" --output text).Trim() }
$Bucket = Get-Output 'FrontendBucketName'; $ApiUrl = Get-Output 'ApiUrl'; $FrontendUrl = Get-Output 'FrontendUrl'; $CognitoDomain = Get-Output 'CognitoDomain'; $ClientId = Get-Output 'CognitoClientId'; $DistDomain = Get-Output 'CloudFrontDomainName'
@"
window.CINEVERSE_CONFIG = {
  apiUrl: "$ApiUrl",
  cognitoDomain: "$CognitoDomain",
  clientId: "$ClientId",
  redirectUri: "$FrontendUrl",
  logoutUri: "$FrontendUrl"
};
"@ | Set-Content -Path (Join-Path $Root 'frontend\config.js') -Encoding UTF8
Write-Host '==> Publishing frontend' -ForegroundColor Cyan
aws s3 sync (Join-Path $Root 'frontend') "s3://$Bucket/" --delete --exclude config.example.js --cache-control 'public,max-age=300'
$DistId = (aws cloudfront list-distributions --query "DistributionList.Items[?DomainName=='$DistDomain'].Id | [0]" --output text).Trim()
if ($DistId -and $DistId -ne 'None') { aws cloudfront create-invalidation --distribution-id $DistId --paths '/*' | Out-Null }
Write-Host ''
Write-Host 'CineVerse deployed successfully.' -ForegroundColor Green
Write-Host "Frontend: $FrontendUrl"
Write-Host "API:      $ApiUrl"
Write-Host "Stack:    $StackName"
