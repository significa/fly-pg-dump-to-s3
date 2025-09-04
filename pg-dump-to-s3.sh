#!/bin/bash

set -e

_USAGE="
Usage: ./backup-db <database-url> <s3-destination>
Examples:
  ./backup-db postgresql://username:password@hostname:5432/my_database s3://my-bucket-name/my_backup.tar.gz
  PG_DUMP_ARGS=\"--format=plain\" ./backup-db postgresql://user:pass@host/db s3://bucket/backup.sql

By default we do not compress with pg_dump as we want concurrency,
later we compress with tar manually. Customize this behavior with PG_DUMP_ARGS env var.
Tar will only be called in case the pg_dump output is a directory.
"

BACKUPS_TEMP_DIR=${BACKUPS_TEMP_DIR:-/tmp/db-backups}
THREAD_COUNT=${THREAD_COUNT:-4}
COMPRESSION_THREAD_COUNT=${COMPRESSION_THREAD_COUNT:-$THREAD_COUNT}

default_pg_dump_args="--no-owner --clean --no-privileges --jobs=${THREAD_COUNT} --format=directory --compress=0"
PG_DUMP_ARGS=${PG_DUMP_ARGS:-$default_pg_dump_args}
PG_DUMP_PATH=${PG_DUMP_PATH:-pg_dump}

database_url=$1
destination=$2

if [[ -z "$database_url" || -z "$destination" ]]; then
  echo "$_USAGE"
  exit 1
fi

if [[ -z $AWS_ACCESS_KEY_ID || -z $AWS_SECRET_ACCESS_KEY ]]; then
  echo "Required env vars: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY"
  exit 1
fi

mkdir -p "$BACKUPS_TEMP_DIR"

raw_backup_path="${BACKUPS_TEMP_DIR}/db_dump"
resulting_backup_path="${BACKUPS_TEMP_DIR}/db_dump.tar.gz"

rm -rf "$raw_backup_path" "$resulting_backup_path"

echo "Dumping database to $raw_backup_path"
$PG_DUMP_PATH $PG_DUMP_ARGS \
    --dbname="$database_url" \
    --file="$raw_backup_path"

if [[ -d "$raw_backup_path" ]]; then
  echo "Compressing backup to $resulting_backup_path"
  tar -cf - -C "$raw_backup_path" . | pigz -p "$COMPRESSION_THREAD_COUNT" > "$resulting_backup_path"
else
  echo "Skipping compression"
  resulting_backup_path="$raw_backup_path"
fi

echo "Uploading $resulting_backup_path to $destination"
aws s3 cp --only-show-errors "$resulting_backup_path" "$destination"

rm -rf "$raw_backup_path" "$resulting_backup_path"

echo "Database backup finished!"
