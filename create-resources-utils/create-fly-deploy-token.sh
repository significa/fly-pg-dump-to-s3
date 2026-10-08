#!/bin/bash

# Creates a scoped Fly deploy token for the database app.
# This is the only long lived secret of the OIDC setup: GitHub Actions uses it to run
# `flyctl proxy` against the database.

set -eo pipefail

read -r -p 'Fly database app: ' database_app

token=$(fly tokens create deploy -a "${database_app}" --name "github-actions-db-backup")

echo -e "\nDone. Save the following GitHub secret:\n"
echo "FLY_API_TOKEN=${token}"
