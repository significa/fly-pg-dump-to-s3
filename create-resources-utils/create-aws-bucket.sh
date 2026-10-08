#!/bin/bash

# Creates and configures the backups bucket, without any IAM user or long lived credentials.
# Use this with `create-aws-oidc-provider.sh` + `create-aws-role.sh` for the OIDC setup.

set -eo pipefail

BACKUP_RETENTION_DAYS=${BACKUP_RETENTION_DAYS:-60}

read -r -p 'Project prefix (will create resources like: PREFIX-db-backups): ' name
read -r -p 'Aws region to create the bucket (ex: eu-central-1, eu-west-3): ' region

bucket_name="${name}-db-backups"

read -r -p "Create bucket '${bucket_name}'? (yes/no): " accept_input

if [[ "$accept_input" != "yes" ]]; then
    read -r -p "Please enter the bucket name (ex: $bucket_name): " bucket_name
fi

echo "Creating bucket ${bucket_name}"
aws s3api create-bucket \
    --bucket "${bucket_name}" \
    --region "${region}" \
    --create-bucket-configuration LocationConstraint="${region}" \
    --no-paginate

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

echo -e "Done. Save the following environment variables:\n"

echo "BACKUP_CONFIGURATION_NAMES=STAGING,PRODUCTION"
echo "STAGING_S3_DESTINATION=s3://${bucket_name}/${name}-db-backup-staging.tar.gz"
echo "PRODUCTION_S3_DESTINATION=s3://${bucket_name}/${name}-db-backup-production.tar.gz"
echo ""
echo "Next: ./setup-aws-oidc-provider.sh <fly|github>, then ./create-aws-role.sh <fly|github> ${bucket_name}"
