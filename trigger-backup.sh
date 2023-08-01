#!/bin/bash

# Triggers a database backup using fly-pg-dump-to-s3
# Doc and source: https://github.com/significa/fly-pg-dump-to-s3

set -e

# Configuration parameters
FLY_REGION=${FLY_REGION:-cdg}
FLY_MACHINE_SIZE=${FLY_MACHINE_SIZE:-shared-cpu-4x}
FLY_VOLUME_SIZE=${FLY_VOLUME_SIZE:-3}
DEFAULT_DOCKER_IMAGE="ghcr.io/significa/fly-pg-dump-to-s3:3"
DOCKER_IMAGE=${DOCKER_IMAGE:-$DEFAULT_DOCKER_IMAGE}
ERROR_ON_DANGLING_VOLUMES=${ERROR_ON_DANGLING_VOLUMES:-true}
DELETE_ALL_VOLUMES=${DELETE_ALL_VOLUMES:-true}
VOLUME_NAME=${VOLUME_NAME:-temp_data}
MAX_RETRIES=6

# Fly has been proucing very inconsistent results, where the state is not propagated.
# TODO: Sleeping between operations is not ideal.
SLEEP_TIME_SECONDS=${SLEEP_TIME_SECONDS:-15}

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
    --size="$FLY_VOLUME_SIZE" \
    --region="$FLY_REGION" \
    "$VOLUME_NAME" \
  | jq -er '.id'
)

echo "Starting machine with volume $volume_id"
flyctl machines run \
    --app="$FLY_APP" \
    --size="$FLY_MACHINE_SIZE" \
    --region="$FLY_REGION" \
    --volume "$volume_id:/tmp/db-backups" \
    --restart=no \
    --rm \
    "$DOCKER_IMAGE" \

sleep "$SLEEP_TIME_SECONDS"

echo "Waiting for volume to become detached"
until flyctl volumes show "$volume_id" --json | jq -er '.AttachedMachine == null' > /dev/null; do
  printf "."
  sleep "$SLEEP_TIME_SECONDS"
done

sleep "$SLEEP_TIME_SECONDS"

volume_id=vol_nylzrem87pd4qmk

delete_volume_or_volumes () {
  if "$DELETE_ALL_VOLUMES" ; then
    echo "Deleting all volumes in app '$FLY_APP'"
    flyctl volumes list --json -a "$FLY_APP" | jq -r '.[].id' |  xargs -n1 flyctl volumes delete --yes
  else
    echo "Deleting volume '$volume_id'"
    flyctl volumes delete --yes "$volume_id"
  fi
}

attempt_num=0
set +e
while ! delete_volume_or_volumes; do
  attempt_num=$(( attempt_num + 1 ))

  if [ $attempt_num -ge $MAX_RETRIES ]; then
    echo "Exceeded max retries ($MAX_RETRIES) deleting volume(s), exiting"
    exit 1
  fi

  sleep "$SLEEP_TIME_SECONDS"
done
set -e

sleep "$SLEEP_TIME_SECONDS"

volumes_left=$(flyctl volumes list --app="$FLY_APP" --json)

if jq -e 'length != 0' <<< "$volumes_left" > /dev/null ; then
  >&2 echo -e "WARNING: Backup completed but the app still has volumes. Response:\n$volumes_left"

  if "$ERROR_ON_DANGLING_VOLUMES" ; then
    >&2 echo "ERROR: ERROR_ON_DANGLING_VOLUMES is true, exiting"
    exit 1
  fi
fi

echo "Done"
