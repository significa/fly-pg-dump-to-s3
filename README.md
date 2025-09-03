# Fly pg_dump to AWS S3

Utilities to backup a Fly.io Postgres database to AWS S3 buckets.

This repository contains two backup strategies:

1. The simple method: a github action that connects to your Fly.io application and dumps it to AWS
   S3. Quite useful for small projects (where the database is not that big).

   Advantages: simplicity, maintenance free and easy to understand.

2. A more complex setup, useful for bigger databases, which triggers a backup workers via github
   actions and performs the database dump, and backup upload directly within the Fly infrastructure.
   From my experience the latency and bandwidth from Fly to AWS is extremely good, meaning it we
   can create medium sized backups rather quickly.
   It uses a dedicated app for the _backup worker_ that is _woken up_ to start the dump.
   When it finishes it is _scaled_ back to 0, meaning **it is not billable when idle**,
   you only pay for the backup time (it is close to free, and supper affordable even with
   high end machines).
   It leverages Fly machines to dynamically deploy volumes and servers on demand.
   
   Advantages: handles bigger databases, performs backups quickly with performant Fly.io machines
   (instead of slow github actions), data goes directly from Fly to your bucket without going
   though GitHub (security, compliance and obviously performance).

## Why this?

Indeed Fly's pg images support `wal-g` config to S3 via env vars.
But I wanted a way to create simple archives periodically with `pg_dump`,
making it easy for developers to replicate databases, and have a simple daily snapshot that can be
restored with `pg_restore`.


## Setup

Create your resources, credentials and permissions following the
[create resources utils documentation](./create-resources-utils).

### Method 1: Simple github actions backup

Create a `.github/workflows/backup-database.yaml` in your project:

```yaml
name: Backup database

on:
  workflow_dispatch:
  schedule:
    # Every day at 6:22am UTC
    - cron: "22 6 * * *"

jobs:
  backup-db:
    name: Backup db
    uses: significa/fly-pg-dump-to-s3/.github/workflows/backup-fly-db.yaml
    with:
      fly-db-name: your-fly-db-name
    secrets:
      FLY_API_TOKEN: ${{ secrets.DB_BACKUP_FLY_API_TOKEN }}
      DATABASE_URL: ${{ secrets.DB_BACKUP_DATABASE_URL }}
      S3_DESTINATION_URL: ${{ secrets.DB_BACKUP_S3_DESTINATION_URL }}
      AWS_ACCESS_KEY_ID: ${{ secrets.DB_BACKUP_AWS_ACCESS_KEY_ID }}
      AWS_SECRET_ACCESS_KEY: ${{ secrets.DB_BACKUP_AWS_SECRET_ACCESS_KEY }}
```

That's it, trigger the backup at any time with the `workflow_dispatch` event and adapt the 
`schedule` to your preference.

### Method 2: Worker installation

1. Launch your database backup worker with `fly apps create`

2. Set the required fly secrets (env vars). Example:

   ```env
   AWS_ACCESS_KEY_ID=XXXX
   AWS_SECRET_ACCESS_KEY=XXXX
   DATABASE_URL=postgresql://username:password@my-fly-db-instance.internal:5432/my_database
   S3_DESTINATION=s3://your-s3-bucket/backup.tar.gz
   ```

3. Automate the Call the reusable GitHub Actions workflow found in
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
   
You can also trigger a manual backup without GitHub actions with `./trigger-backup.sh`:

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
   - `ERROR_ON_DANGLING_VOLUMES`: After the backup completes, checks if there are any volumes still
     available, and crashes if so. This might be useful to alert that there are dangling volumes
     (that you might want to be paying for). Defaults to `true`.
   - `DELETE_ALL_VOLUMES`: True to delete all volumes in the backup worker instead of the one used
      in the machine. Fly has been very inconsistent with what volume does the machine start.
      This solves the problem but prevents having multiple backup workers running in the same app.
      Default to `true`.


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
`S3_DESTINATION=s3://sample-db-backups/my_backup.sql` for a raw sql backup.


## Environment variables reference (backup worker)

- `DATABASE_URL`: Postgres database URL.
  For example: `postgresql://username:password@test:5432/my_database`
- `S3_DESTINATION`: AWS S3 fill file destination Postgres database URL.
- `BACKUP_CONFIGURATION_NAMES`: Optional: Configuration names/prefixes for `DATABASE_URL` and
  `S3_DESTINATION`.
- `BACKUPS_TEMP_DIR`: Optional: Where the temp files should go. Defaults to: `/tmp/db-backups`
- `THREAD_COUNT`: Optional: The number of threads to use for backup and compression.
  Defaults to `4`.
- `PG_DUMP_ARGS`: Optional: Override the default `pg_dump` args:
  `--no-owner --clean --no-privileges --jobs=4 --format=directory --compress=0`.
  The `--jobs` parameter defaults to `$THREAD_COUNT`.
- `COMPRESSION_THREAD_COUNT`: Optional: The number of threads to use for compression.
  Defaults to `$THREAD_COUNT`.


## Will this work outside fly?

Yes, everything that is part of the backup worker (docker image) and creation scripts will work
outside Fly.
The script `./trigger-backup.sh` and the GitHub workflow is obviously targeted to fly apps.


## Migrating to v3 (Fly machines - apps v2)

From version 3 _fly-pg-dump-to-s3_ uses Fly machines API (also known as _Fly apps v2_).
Migrating an existing backup worker should be quite simple:

1. Remove the `FLY_API_TOKEN` environment variable: `fly secrets unset FLY_API_TOKEN -a YOUR_APP`
2. Migrate your app to v2: `fly migrate-to-v2 -a YOUR_APP`
3. Start making use of `trigger-backup.sh` or the action `.github/workflows/trigger-backup.yaml`
   to trigger the backup.


## Manual resource creation

To create the resources without the scripts in [create-resources-utils](./create-resources-utils),
one could do it with:

Postgres user setup:

```sql
CREATE USER db_backup_worker WITH PASSWORD '<password>';
GRANT CONNECT ON DATABASE <db_name> TO db_backup_worker;
GRANT pg_read_all_data TO db_backup_worker;
```

> **Note**: For Postgres >= 14, `pg_read_all_data` is used for simplicity


<details>
<summary>For older Postgres versions (< 14)</summary>

```sql
-- Grant these permissions for each schema (ex: public):
GRANT USAGE ON SCHEMA public TO db_backup_worker;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO db_backup_worker;
GRANT SELECT ON ALL SEQUENCES IN SCHEMA public TO db_backup_worker;
ALTER DEFAULT PRIVILEGES FOR USER db_backup_worker IN SCHEMA public
GRANT SELECT ON TABLES TO db_backup_worker;
ALTER DEFAULT PRIVILEGES FOR USER db_backup_worker IN SCHEMA public
GRANT SELECT ON SEQUENCES TO db_backup_worker;
```
</details>

Create an AWS S3 bucket and an access token with write permissions to it, attaching the following
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
