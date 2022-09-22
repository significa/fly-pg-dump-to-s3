#!/bin/bash

set -e

BACKUP_CONFIGURATION_NAMES=${BACKUP_CONFIGURATION_NAMES:-}

backup () {
  local prefix=$1

  database_url_var_name="${prefix}DATABASE_URL"
  database_url=${!database_url_var_name}

  s3_destination_var_name="${prefix}S3_DESTINATON"
  s3_destination=${!s3_destination_var_name}

  if [[ -z $database_url || -z $s3_destination ]]; then
    echo "Required env vars: ${database_url_var_name}, ${s3_destination_var_name}"
    exit 1
  fi

  ./pg-dump-to-s3.sh "${database_url}" "${s3_destination}"
}

main () {
  if [[ -z $BACKUP_CONFIGURATION_NAMES ]]; then
      echo "Backup starting"
      backup ""
  else
    for configuration_name in ${BACKUP_CONFIGURATION_NAMES//,/ }; do
      echo "Backing up $configuration_name"
      backup "${configuration_name^^}_"
    done
  fi
}

main || echo "ERROR backing up, see the logs above."

if [[ -n $FLY_APP_NAME && -n $FLY_API_TOKEN ]]; then
  echo "Scaling $FLY_APP_NAME to 0"
  /root/.fly/bin/flyctl -a "$FLY_APP_NAME" scale count 0
fi

echo "Done! Sleeping..."
sleep infinity
