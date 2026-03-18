#!/bin/bash

set -eo pipefail

if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <region> <bucket-name>"
    exit 1
fi

region="$1"
bucket_name="$2"

read -r -p 'Role name (example: sample-db-backup-role): ' role_name

read -r -p 'GitHub subject (ex: repo:org/repo:ref:refs/heads/main): ' github_subject

AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
PROVIDER_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com"

echo "Creating role ${role_name} in region ${region} for bucket ${bucket_name}"

assume_role_policy="{
    \"Version\": \"2012-10-17\",
    \"Statement\": [
        {
            \"Effect\": \"Allow\",
            \"Principal\": {
                \"Federated\": \"${PROVIDER_ARN}\"
            },
            \"Action\": \"sts:AssumeRoleWithWebIdentity\",
            \"Condition\": {
                \"StringEquals\": {
                    \"token.actions.githubusercontent.com:aud\": \"sts.amazonaws.com\"
                },
                \"StringLike\": {
                    \"token.actions.githubusercontent.com:sub\": \"${github_subject}\"
                }
            }
        }
    ]
}"

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

echo -e "\nDone. Role created:"
echo "Role Name: ${role_name}"
echo "Role ARN: ${role_arn}"
