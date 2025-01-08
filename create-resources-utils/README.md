# Create Resources Utils

## Requirements

- jq
- aws-cli version 2
- aws logged in
- flyctl authenticated

## Create AWS resources

`./create-aws-resources.sh`

1. Creates and configure bucket for the backups
2. Creates user with write permissions for the backup bucket

Output:

```
AWS_ACCESS_KEY_ID=aws_access_key_id
AWS_SECRET_ACCESS_KEY=aws_secret_access_key

BACKUP_CONFIGURATION_NAMES=STAGING,PRODUCTION
STAGING_S3_DESTINATION=s3://example-bucket/project-name-db-backup-staging.tar.gz
PRODUCTION_S3_DESTINATION=s3://example-bucket/project-name-db-backup-production.tar.gz
```

## Create database user and grant permissions

`./grant-db-permissions.sh`

1. Creates backup-worker-user
2. Grant permissions to the backup-worker-user in all schemas for all tables and sequences

Output:

```
[ENV]_DATABASE_URL=postgres://username:password@top2.nearest.of.example-db.internal:5432/database_name
...
```

## Create Fly.io resources

`./create-fly-resources.sh`

1. Creates database backup worker app on fly.io
2. Creates volume for worker app

After, you need will to import the secrets to the worker app and deploy it using:

```
fly -a [db-backup-worker-app] secrets import < .env
fly -a [db-backup-worker-app] deploy --remote-only
```

