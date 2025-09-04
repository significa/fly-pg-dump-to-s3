#!/bin/bash

set -eo pipefail

BACKUP_CONFIGURATION_NAMES=${BACKUP_CONFIGURATION_NAMES:-}

backup_database () {
  local prefix=$1

  database_url_var_name="${prefix}DATABASE_URL"
  database_url=${!database_url_var_name}

  s3_destination_var_name="${prefix}S3_DESTINATION"
  s3_destination=${!s3_destination_var_name}

  if [[ -z $database_url || -z $s3_destination ]]; then
    echo "Required env vars: ${database_url_var_name}, ${s3_destination_var_name}"
    exit 1
  fi

  ./pg-dump-to-s3.sh "$database_url" "$s3_destination"
}

backup_databases () {
  if [[ -z $BACKUP_CONFIGURATION_NAMES ]]; then
      echo "Backup starting"
      backup_database ""
  else
    for configuration_name in ${BACKUP_CONFIGURATION_NAMES//,/ }; do
      echo "Backing up $configuration_name"
      backup_database "${configuration_name^^}_"
    done
  fi
}

backup_databases || echo "ERROR backing up, see the logs above."

echo "Exiting"
