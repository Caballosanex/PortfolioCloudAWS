#!/bin/bash
set -e

# Uploads the local assets/ directory (photos, certificates, images) straight to S3.
# assets/ is intentionally NOT tracked in git — it's binary, rarely changes, and
# doesn't need to round-trip through CI. Run this manually whenever assets/ changes.

AWS_REGION="eu-west-1"
AWS_PROFILE="personal"
S3_BUCKET="asanchezbl-static"

PORTFOLIO_DIR="/Users/alex/Documents/GITs/PortfolioCloudAWS"

aws s3 sync "$PORTFOLIO_DIR/assets/" "s3://$S3_BUCKET/assets/" --delete \
  --region "$AWS_REGION" --profile "$AWS_PROFILE"

DIST_ID=$(aws cloudfront list-distributions --profile "$AWS_PROFILE" \
  --query "DistributionList.Items[?contains(Aliases.Items, 'asanchezbl.dev')].Id | [0]" --output text)

aws cloudfront create-invalidation \
  --distribution-id "$DIST_ID" \
  --paths "/assets/*" \
  --profile "$AWS_PROFILE" >/dev/null

echo "Synced assets/ to s3://$S3_BUCKET/assets/ and invalidated CloudFront cache."
