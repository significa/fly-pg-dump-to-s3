#!/bin/bash

set -e

_USAGE="
Usage: ./backup-db <database_url> <s3-destination>
Example:
  ./backup-db postgresql://username:password@hostname:5432/my_database s3://my-bucket-name/my_backup.tar.gz
"

BACKUPS_TEMP_DIR=${BACKUPS_TEMP_DIR:-/tmp/db-backups}

# we are not using pg_dump for compression as we want concurrrency, later we compress with tar manually
default_pg_dump_args="--no-owner --clean --no-privileges --no-sync --jobs=4 --format=directory --compress=0"
PG_DUMP_ARGS=${PG_DUMP_ARGS:-$default_pg_dump_args}

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

mkdir -p "${BACKUPS_TEMP_DIR}"

backup_dir="${BACKUPS_TEMP_DIR}/db_dump"
backup_filename="${BACKUPS_TEMP_DIR}/db_dump.tar.gz"

# In the future we could add a configuration to prevent deletion of existing files
rm -rf "${backup_dir}" "${backup_filename}"

echo "Dumping database to ${backup_dir}"
pg_dump $PG_DUMP_ARGS \
    --dbname="${database_url}" \
    --file="${backup_dir}"

echo "Compressing backup to ${backup_filename}"
tar -czf "${backup_filename}" -C "${backup_dir}" .

echo "Uploading backup to ${destination}"
aws s3 cp --only-show-errors "${backup_filename}" "${destination}"

rm -rf "${backup_dir}" "${backup_filename}"

echo "Database backup finished!"
