# Fly pg_dump to AWS S3

This is ~~a hacky~~ an interesting way to have a Fly app that dumps postgres databases
that are also on Fly, to AWS S3 buckets.
It uses a dedicated app for the _backup worker_ that is _woken up_ to start the dump.
When it finishes it is _scaled_ back to 0, meaning **it is not billable when idle**,
you only pay for the backup time (it is close to free, and supper affordable even with
high end machines). It leverages Fly machines to dynamically deploy volumes and servers on demand.


## Why this?

Indeed Fly's pg images support `wal-g` config to S3 via env vars.
But I wanted a way to create simple archives periodically with `pg_dump`,
making it easy for developers to replicate databases, and have a **point in time recovery**.

Since this setup is running the backup worker on Fly, and not in some other external service like
AWS or GitHub Actions, **we can create backups rather quickly**.
From our experience the latency and bandwidth from Fly to AWS is extremely good.


## Requirements

Have a look into [create-resources-utils](./create-resources-utils) for scripts to setup all the
requirements in a simple way.

1. In a PG shell inside your Fly Postgres instance, create an user with read permissions:

   ```sql
   CREATE USER db_backup_worker WITH PASSWORD '<password>';
   GRANT CONNECT ON DATABASE <db_name> TO db_backup_worker;
   -- For each schema (ex: public):
   GRANT USAGE ON SCHEMA public TO db_backup_worker;
   GRANT SELECT ON ALL TABLES IN SCHEMA public TO db_backup_worker;
   GRANT SELECT ON ALL SEQUENCES IN SCHEMA public TO db_backup_worker;
   ALTER DEFAULT PRIVILEGES FOR USER db_backup_worker IN SCHEMA public
    GRANT SELECT ON TABLES TO db_backup_worker;
   ALTER DEFAULT PRIVILEGES FOR USER db_backup_worker IN SCHEMA public
    GRANT SELECT ON SEQUENCES TO db_backup_worker;
   -- Optionally, for PG >= 14 you could use the `pg_read_all_data` role
   ```

2. Create an AWS S3 bucket and an access token with write permissions to it.
   IAM policy:
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
         "Resource": ["arn:aws:s3:::your-s3-bucket/backup.tar.gz"]
       }
     ]
   }
   ```


## Installation

1. Launch your database backup worker with `fly apps create --machines`

2. Set the required fly secrets (env vars). Example:

   ```env
   AWS_ACCESS_KEY_ID=XXXX
   AWS_SECRET_ACCESS_KEY=XXXX
   DATABASE_URL=postgresql://username:password@my-fly-db-instance.internal:5432/my_database
   S3_DESTINATION=s3://your-s3-bucket/backup.tar.gz
   ```

3. OPTION A: Run `./trigger-backup.sh` whenever you want to start a backup.

   - `FLY_APP`: (Required) Your fly application.
   - `FLY_API_TOKEN`: (Required) Fly token (PAT or Deploy token).
   - `FLY_REGION`: the region of the volume and consequently the region where the worker will run.
     Choose one close to the db and the AWS bucket region. Defaults to `cdg`.
   - `FLY_MACHINE_SIZE`: the fly machine size, list available in
     [Fly's pricing page](https://fly.io/docs/about/pricing/#machines). Defaults to `shared-cpu-4x`
   - `FLY_VOLUME_SIZE`: the size of the temporary disk where the ephemeral files live during the
     backup, set it accordingly to the size of the db. Defaults to `3`.
   - `DOCKER_IMAGE`:
     Option to override the default docker image `ghcr.io/significa/fly-pg-dump-to-s3:3`
   - `ENSURE_NO_VOLUMES_LEFT`: When the backup completes and the volume is deleted, checks if there
     are any volumes still available, and crashes if so. This might be useful to alert that there
     are dangling volumes (that you might want to be paying for).
     Defaults to `false` (warning to stderr only).

   OPTION B: Call the reusable GitHub Actions workflow found in
   `.github/workflows/trigger-backup.yaml`. Example workflow definition:

   ```yaml
   name: Backup databases
   on:
     workflow_dispatch:
     schedule:
       # Runs Every day at 5:00am UTC
       - cron: "00 5 * * *"

   jobs:
     backup-databases:
       name: Backup databases
       uses: significa/fly-pg-dump-to-s3/.github/workflows/trigger-backup.yaml@v3
       with:
         fly-app: my-db-backup-worker
         volume-size: 3
         machine-size: shared-cpu-4x
         region: ewr
       secrets:
         FLY_API_TOKEN: ${{ secrets.FLY_API_TOKEN }}
   ```


## Backup history

The best way to keep a backup history is to setup versioning in your S3, this allows you to
leverage retention policies.
Alternatively, if you wish to have dedicated keys per backup you can play with `S3_DESTINATION`
(by changing the docker CMD).


## Backup multiple databases/backups in one go

Use `BACKUP_CONFIGURATION_NAMES` to define multiple configurations (env var prefix) and backup
multiple connection strings (to their dedicated s3 destination):

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

Just tweak `PG_DUMP_ARGS` to your liking.
Tar compression will only kick in if the resulting backup is a directory.
For example set `PG_DUMP_ARGS=--format=plain` and
`S3_DESTINATION=s3://sample-db-backups/my_backup.sql`.


## Environment variables reference (backup worker)

- `DATABASE_URL`: Postgres database URL.
  For example: `postgresql://username:password@test:5432/my_database`
- `S3_DESTINATION`: AWS S3 fill file destination Postgres database URL.
- `BACKUP_CONFIGURATION_NAMES`: Optional: Configuration names/prefixes for `DATABASE_URL` and
  `S3_DESTINATION`.
- `BACKUPS_TEMP_DIR`: Optional: Where the temp files should go. Defaults to: `/tmp/db-backups`
- `PG_DUMP_ARGS`: Optional: Override the default `pg_dump` args:
  `--no-owner --clean --no-privileges --jobs=4 --format=directory --compress=0`.


## Will this work outside fly?

Yes, everything that is part of the backup worker (docker image) will work outside Fly.
The script `./trigger-backup.sh` and the GitHub workflow is obviously targetted to fly apps.


## Migrating to v3 (Fly machines - apps v2)

From version 3 _fly-pg-dump-to-s3_ uses Fly machines API (also known as _Fly apps v2_).
Migrating an existing backup worker should be quite simple:

1. Remove the `FLY_API_TOKEN` environment variable: `fly secrets unset FLY_API_TOKEN -a YOUR_APP`
2. Migrate your app to v2: `fly migrate-to-v2 -a YOUR_APP`
3. Start making use of `trigger-backup.sh` or the action `.github/workflows/trigger-backup.yaml`
   to trigger the backup.
