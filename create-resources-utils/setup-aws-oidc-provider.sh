#!/bin/bash

# Creates an AWS OIDC identity provider for GitHub Actions or for a Fly.io organization.
# This is a one time operation per AWS account (per Fly org, in the fly case).
#
# Usage: ./setup-aws-oidc-provider.sh <fly|github>

set -euo pipefail

export AWS_PAGER=""

AUDIENCE="sts.amazonaws.com"

provider_type="${1:-}"

if [[ -z "$provider_type" ]]; then
    echo "Usage: $0 <fly|github>"
    echo "  $0 github  # trust GitHub Actions workflows (Method 1)"
    echo "  $0 fly     # trust Fly machines of an org (Method 2)"
    exit 1
fi

aws_account_id=$(aws sts get-caller-identity --query 'Account' --output text)

case "$provider_type" in
    fly)
        read -r -p 'Fly.io organization name (slug): ' fly_org

        if [[ -z "$fly_org" ]]; then
            echo "Error: Fly org name cannot be empty"
            exit 1
        fi

        provider_url="https://oidc.fly.io/${fly_org}"
        provider_arn="arn:aws:iam::${aws_account_id}:oidc-provider/oidc.fly.io/${fly_org}"
        ;;
    github)
        provider_url="https://token.actions.githubusercontent.com"
        provider_arn="arn:aws:iam::${aws_account_id}:oidc-provider/token.actions.githubusercontent.com"
        ;;
    *)
        echo "Error: provider type must be 'fly' or 'github'"
        exit 1
        ;;
esac

echo "Checking if the identity provider already exists..."

if aws iam get-open-id-connect-provider --open-id-connect-provider-arn "${provider_arn}" &>/dev/null; then
    echo "The identity provider already exists, nothing to do."
    echo "  ARN: ${provider_arn}"
    exit 0
fi

echo "Creating identity provider..."
echo "  Provider URL: ${provider_url}"
echo "  Audience: ${AUDIENCE}"

aws iam create-open-id-connect-provider \
    --url "${provider_url}" \
    --client-id-list "${AUDIENCE}" \
    --output text >/dev/null

echo ""
echo "Done. Identity provider created:"
echo "  ARN: ${provider_arn}"
echo ""
echo "Next: ./create-aws-role.sh ${provider_type}"
