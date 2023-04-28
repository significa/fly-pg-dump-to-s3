#!/bin/bash

set -e

BACKUP_RETENTION_DAYS=${BACKUP_RETENTION_DAYS:-60}


read -r -p 'Name (ex: puzzle, bion, activeflow...): ' name
read -r -p 'Aws region to create the bucket (ex: eu-central-1, eu-west-3): ' region

bucket_name="${name}-db-backups"
iam_user_name="${name}-db-backup-user"


echo "Creating bucket ${bucket_name}"
aws s3api create-bucket \
    --bucket "${bucket_name}" \
    --region "${region}" \
    --create-bucket-configuration LocationConstraint="${region}" \
    --no-cli-pager


echo "Enabling bucket versioning"
aws s3api put-bucket-versioning \
    --bucket "${bucket_name}" \
    --versioning-configuration Status=Enabled


bucket_lifecycle_configuration="
{
  \"Rules\": [
      {
          \"ID\": \"Delete database backups after $BACKUP_RETENTION_DAYS days\",
          \"Filter\": {},
          \"Status\": \"Enabled\",
          \"NoncurrentVersionExpiration\": {
              \"NoncurrentDays\": $BACKUP_RETENTION_DAYS,
              \"NewerNoncurrentVersions\": $BACKUP_RETENTION_DAYS
          }
      }
  ]
}
"

echo "Adding bucket lifecycle configuration"
aws s3api put-bucket-lifecycle-configuration \
    --bucket "${bucket_name}" \
    --lifecycle-configuration "${bucket_lifecycle_configuration}"


echo "Creating user ${iam_user_name}"
aws iam create-user \
    --user-name "${iam_user_name}" \
    --no-cli-pager


db_backup_access_policy="{
    \"Version\": \"2012-10-17\",
    \"Statement\": [
        {
            \"Sid\": \"VisualEditor0\",
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
aws iam put-user-policy \
    --user-name "${iam_user_name}" \
    --policy-name "DBBackupBucketAccess" \
    --policy-document "${db_backup_access_policy}"


echo "Creating ${iam_user_name} access key"
create_access_key_response=$(
    aws iam create-access-key \
    --user-name "${iam_user_name}"
)

aws_access_key_id=$(echo "${create_access_key_response}" | jq -r '.AccessKey.AccessKeyId')
aws_secret_access_key=$(echo "${create_access_key_response}" | jq -r '.AccessKey.SecretAccessKey')


echo "AWS_ACCESS_KEY_ID=${aws_access_key_id}"
echo "AWS_SECRET_ACCESS_KEY=${aws_secret_access_key}"
echo "BACKUP_CONFIGURATION_NAMES=STAGING,PRODUCTION"
echo "STAGING_S3_DESTINATION=s3://${bucket_name}/${name}-db-backup-staging.tar.gz"
echo "PRODUCTION_S3_DESTINATION=s3://${bucket_name}/${name}-db-backup-production.tar.gz"
