#!/bin/bash

# Creates the IAM role that GitHub Actions or a Fly machine assumes via OIDC to push backups
# to the bucket. No access keys involved.
#
# Requires the matching identity provider to exist (see `setup-aws-oidc-provider.sh`).
#
# Usage: ./create-aws-role.sh <fly|github> [bucket-name]

set -euo pipefail

export AWS_PAGER=""

provider_type="${1:-}"
bucket_name="${2:-}"

if [[ -z "$provider_type" ]]; then
    echo "Usage: $0 <fly|github> [bucket-name]"
    exit 1
fi

if [[ "$provider_type" != "fly" && "$provider_type" != "github" ]]; then
    echo "Error: provider type must be 'fly' or 'github'"
    exit 1
fi

if [[ -z "$bucket_name" ]]; then
    read -r -p 'Backups bucket name (ex: sample-db-backups): ' bucket_name
fi

read -r -p 'Role name (example: sample-db-backup-role): ' role_name

aws_account_id=$(aws sts get-caller-identity --query 'Account' --output text)

case "$provider_type" in
    github)
        provider_host="token.actions.githubusercontent.com"
        provider_arn="arn:aws:iam::${aws_account_id}:oidc-provider/${provider_host}"

        subject_condition="StringEquals"

        cat <<'HELP'

Subject (`sub`): which GitHub Actions runs may assume this role.
Matched exactly, no wildcards.
Format: repo:<org>/<repo>:ref:refs/heads/<branch>

  repo:significa/sample:ref:refs/heads/main
  repo:significa/sample@XXXXXX:ref:refs/heads/main   (repos with a name suffix, paste as is)

`workflow_dispatch` and `schedule` runs use the repository default branch, so
`refs/heads/main` is what you want unless the workflow lives elsewhere.
To allow more than one ref, edit the role trust policy afterwards and swap the
StringEquals condition for StringLike.

HELP
        ;;
    fly)
        read -r -p 'Fly.io organization name (slug): ' fly_org

        provider_host="oidc.fly.io/${fly_org}"
        provider_arn="arn:aws:iam::${aws_account_id}:oidc-provider/${provider_host}"
        subject_condition="StringLike"

        cat <<HELP

Subject (\`sub\`): which Fly machines may assume this role.
Format: <org-slug>:<app-name>:<machine-id>

  ${fly_org}:sample-db-backup-worker:*   (any machine of the backup worker app, recommended)
  ${fly_org}:sample-db-backup-worker:148e2d1bc23198

Machine ids change on every deploy, so keep the trailing \`*\`.
Matched with StringLike, wildcards are allowed.

HELP
        ;;
esac

read -r -p 'Subject: ' oidc_subject

if [[ -z "$oidc_subject" ]]; then
    echo "Error: subject cannot be empty"
    exit 1
fi

if ! aws iam get-open-id-connect-provider --open-id-connect-provider-arn "${provider_arn}" &>/dev/null; then
    echo "Error: identity provider ${provider_arn} not found in this account."
    echo "Run ./setup-aws-oidc-provider.sh ${provider_type} first."
    exit 1
fi

if [[ "$subject_condition" == "StringEquals" ]]; then
    # Both conditions share the same operator, they must live in the same JSON object.
    condition_block="{
                \"StringEquals\": {
                    \"${provider_host}:aud\": \"sts.amazonaws.com\",
                    \"${provider_host}:sub\": \"${oidc_subject}\"
                }
            }"
else
    condition_block="{
                \"StringEquals\": {
                    \"${provider_host}:aud\": \"sts.amazonaws.com\"
                },
                \"${subject_condition}\": {
                    \"${provider_host}:sub\": \"${oidc_subject}\"
                }
            }"
fi

assume_role_policy="{
    \"Version\": \"2012-10-17\",
    \"Statement\": [
        {
            \"Effect\": \"Allow\",
            \"Principal\": {
                \"Federated\": \"${provider_arn}\"
            },
            \"Action\": \"sts:AssumeRoleWithWebIdentity\",
            \"Condition\": ${condition_block}
        }
    ]
}"

echo "Trust policy:"
echo "${assume_role_policy}" | jq .

echo "Creating role ${role_name}"
aws iam create-role \
    --role-name "${role_name}" \
    --assume-role-policy-document "${assume_role_policy}" \
    --no-paginate

db_backup_access_policy="{
    \"Version\": \"2012-10-17\",
    \"Statement\": [
        {
            \"Sid\": \"DBBackupBucketAccess\",
            \"Effect\": \"Allow\",
            \"Action\": [
                \"s3:PutObject\",
                \"s3:AbortMultipartUpload\",
                \"s3:ListMultipartUploadParts\"
            ],
            \"Resource\": \"arn:aws:s3:::${bucket_name}/*\"
        }
    ]
}"

echo "Attaching in-line policy"
aws iam put-role-policy \
    --role-name "${role_name}" \
    --policy-name "DBBackupBucketAccess" \
    --policy-document "${db_backup_access_policy}"

role_arn=$(aws iam get-role --role-name "${role_name}" --query 'Role.Arn' --output text)

echo -e "\nDone. Save the following:\n"
echo "AWS_ROLE_ARN=${role_arn}"
