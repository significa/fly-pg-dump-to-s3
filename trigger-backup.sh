#!/bin/bash

# Triggers a database backup using fly-pg-dump-to-s3
# Doc and source: https://github.com/significa/fly-pg-dump-to-s3

set -e

REGION=${REGION:-cdg}
MACHINE_SIZE=${MACHINE_SIZE:-shared-cpu-4x}
VOLUME_SIZE=${VOLUME_SIZE:-3}
VOLUME_NAME=${VOLUME_NAME:-temp_data}
DOCKER_IMAGE=${DOCKER_IMAGE:-ghcr.io/significa/fly-pg-dump-to-s3}
ENSURE_NO_VOLUMES_LEFT=${ENSURE_NO_VOLUMES_LEFT-true}

if [[ -z "$FLY_APP" || -z "$FLY_API_TOKEN" ]]; then
  >&2 echo "Env vars FLY_APP and FLY_API_TOKEN must not be empty"
  exit 1
fi

echo "Creating volume"
volume_id=$(
  flyctl volumes create \
    --json \
    --yes \
    --require-unique-zone=false \
    --no-encryption \
    --app="$FLY_APP" \
    --size="$VOLUME_SIZE" \
    --region="$REGION" \
    "$VOLUME_NAME" \
  | jq -er '.id'
)

echo "Starting machine with volume $volume_id"
flyctl machines run \
    --app="$FLY_APP" \
    --size="$MACHINE_SIZE" \
    --region="$REGION" \
    --volume "$volume_id:/tmp/db-backups" \
    --restart=no \
    --rm \
    "$DOCKER_IMAGE" \

sleep 10

echo "Waiting for volume to become detached."
until flyctl volumes show "$volume_id" --json | jq -er '.AttachedMachine == null'; do
  printf "."
  sleep 5
done

sleep 10

echo "Deleting volume $volume_id"
flyctl volumes delete --yes "$volume_id" 

if "$ENSURE_NO_VOLUMES_LEFT" && fly volumes list --json | jq -e 'length != 0' ; then
  >&2 echo "Backup completed but the app still has volumes. ENSURE_NO_VOLUMES_LEFT is true, exiting"
  exit 1
fi

echo "Done"
