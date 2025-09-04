#!/bin/bash

set -eo pipefail

read -p 'Name prefix (PREFIX-db-backup-worker):' name_prefix
read -p 'Fly organization name: ' fly_organization_name

app_name="$name_prefix-db-backup-worker"

echo "Creating $app_name app on fly"
fly apps create --machines --name "$app_name" --org "$fly_organization_name"

echo "App name: $app_name"
