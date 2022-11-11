# Fly pg_dump to AWS S3

This is a **hacky** way to have a Fly app that dumps postgres databases that are also on Fly, to AWS S3 buckets.
This uses a dedicated app for the *backup worker* that is woken up to start the dump. When it finished it is scaled back to 0, meaning it is not billable when idle.


## Why this?

Indeed Fly's pg images support wal-g config to S3 via env vars. But I wanted a way to create simple archives periodically with pg_dump, making it easy for developers to replicate databases, and have a point in time recovery.

Since the backup worker is running on Fly, and not in some other external service like AWS or GitHub actions, we can create backups rather quickly. And also because the latency/bandwidth from Fly to AWS are quite good (in the regions I've tested).

And what about Fly machines? I haven't tried them.


## Requirements

Have a look into [create-resources-utils](./create-resources-utils) for scripts to setup all the requirements in a simple way.

1. Fly postgres instance and a user with read permissions.
   Create the `db_backup_worker` user with:
    ```sql
    CREATE USER db_backup_worker WITH PASSWORD '<password>';
    GRANT CONNECT ON DATABASE <db_name> TO db_backup_worker;
    -- For all schemas (example for public):
    GRANT USAGE ON SCHEMA public TO db_backup_worker;
    GRANT SELECT ON ALL TABLES IN SCHEMA public TO db_backup_worker;
    GRANT SELECT ON ALL SEQUENCES IN SCHEMA public TO db_backup_worker;
    ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO db_backup_worker;
    ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON SEQUENCES TO db_backup_worker;
    ```

2. AWS S3 bucket and an access token with write permissions to it.
   Iam policy:
   ```json
   {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Sid": "WriteDatabaseBackups",
                "Effect": "Allow",
                "Action": [
                    "s3:PutObject",
                    "s3:AbortMultipartUpload",
                    "s3:ListMultipartUploadParts"
                ],
                "Resource": [
                    "arn:aws:s3:::your-s3-bucket/backup.tar.gz"
                ]
            }
        ]
    }
   ```


## Installation

1. Launch your database backup worker with `fly launch --image ghcr.io/significa/fly-pg-dump-to-s3`

2. Add the volume to your `fly.toml`
    ```toml
    [mounts]
    destination = "/tmp/db-backups"
    source = "temp_data"
    ```

3. Set the required fly secrets (env vars). Example:
    ```env
    AWS_ACCESS_KEY_ID=XXXX
    AWS_SECRET_ACCESS_KEY=XXXX
    DATABASE_URL=postgresql://username:password@my-fly-db-instance.internal:5432/my_database
    S3_DESTINATION=s3://your-s3-bucket/backup.tar.gz
    FLY_API_TOKEN=XXXX
    ```

4. Run `fly volumes create --no-encryption --size $SIZE_IN_GB --region $REGION temp_data` whenever you want to start a backup.
   `SIZE_IN_GB` is the size of the temporary disk where the ephemeral files live during the backup, set it accordingly to the size of the db.
   `REGION` is the region of the volume and consequently the region where the worker will run. Choose one close to the db and the AWS bucket region.
   The volume will be deleted when the backup finishes.
   Add this command to any periodic runner along with the envs `FLY_APP` and `FLY_API_TOKEN` to perform backups periodically. 


## What about backup history?

You could add a date to the S3_DESTINATION filename (by changing the docker CMD). But I recommend adding versioning to your S3 and manage retention via policies.


## Backup multiple databases/backups in one go?

Just use the env vars like so:

```env
BACKUP_CONFIGURATION_NAMES=ENV1,STAGING_ENVIRONMENT,test

ENV1_DATABASE_URL=postgresql://username:password@env1/my_database
ENV1_S3_DESTINATION=s3://sample-bucket/sample.tar.gz

STAGING_ENVIRONMENT_DATABASE_URL=postgresql://username:password@sample/staging
STAGING_ENVIRONMENT_S3_DESTINATION=s3://sample-db-backups/staging_backup.tar.gz

TEST_DATABASE_URL=postgresql://username:password@sample/test
TEST_S3_DESTINATION=s3://sample-db-backups/test_backup.tar.gz
```

It will backup all the databases to the desired s3 destination. AWS and fly tokens are reused.


## Plain backups without compression (raw SQL backups)

Yes you can.
For example set `PG_DUMP_ARGS=--format=plain` and `S3_DESTINATION=s3://sample-db-backups/my_backup.sql`.

## Environment variables reference

- `DATABASE_URL`: Postgres database URL. Example: `postgresql://username:password@test:5432/my_database`
- `S3_DESTINATION`: AWS S3 fill file destination Postgres database URl
- `BACKUP_CONFIGURATION_NAMES`: Optional: Configuration names/prefixes for `DATABASE_URL` and `S3_DESTINATION`
- `FLY_APP_NAME`:  Optional to delete the volume and terminate the worker. Automatically set by Fly.
- `FLY_API_TOKEN`: Optional to delete the volume and terminate the worker. Fly API token created via `flyctl` or the web UI.
- `BACKUPS_TEMP_DIR`: Optional: Where the temp files should go. Defaults to: `/tmp/db-backups`
- `PG_DUMP_ARGS`: Optional: Override the default `pg_dump` args: `--no-owner --clean --no-privileges --jobs=4 --format=directory --compress=0`. Tar compression will only kick in if the resulting backup is a directory.


## Is this hacky? Does it work in production environments?

Yes. Yes :sweat_smile:


## Will this work outside fly?

Yes, if `FLY_APP_NAME` or `FLY_API_TOKEN` are not present, fly commands will be ignored.
