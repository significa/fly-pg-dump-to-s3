#!/bin/bash

set -e

VOLUME_SIZE_IN_GB="3"

read -p 'Name (ex: puzzle, bion, activeflow...): ' name
read -p 'Fly organization name: ' fly_organization_name

app_name="${name}-db-backup-worker"

echo "Creating ${app_name} app on fly"
fly apps create --name "$app_name" --org "$fly_organization_name"

echo "Creating volume for ${app_name}"
fly -a "$app_name" volumes create temp_data --no-encryption --size "$VOLUME_SIZE_IN_GB"

echo "App name: ${app_name}"







