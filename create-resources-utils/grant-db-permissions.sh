#!/bin/bash

set -eo pipefail

DB_PASSWORD_SIZE=32

read -p 'Fly database app (PG>=14): ' database_app

read -p 'Database names: (separated with space) ' database_names_input
database_names=(${database_names_input})

database_backup_worker_user="db_backup_worker"
password=$(openssl rand -base64 "${DB_PASSWORD_SIZE}")
password=$(head /dev/urandom | LC_ALL=C tr -dc A-Za-z0-9 | head -c "$DB_PASSWORD_SIZE")

database_envs=""
database_script="
-- Creating db_backup_worker_user
CREATE USER db_backup_worker WITH PASSWORD '${password}';
"

for database_name in "${database_names[@]}"; do
    database_script+="
    -- Granting access & permissions to ${database_name}
    \c ${database_name};
    GRANT CONNECT ON DATABASE ${database_name} TO ${database_backup_worker_user};
    GRANT pg_read_all_data TO db_backup_worker;
    "

    database_envs+="[ENV]_DATABASE_URL=postgres://${database_backup_worker_user}:${password}@${database_app}.flycast:5432/${database_name}\n"
done

database_script+="\q"

echo "${database_script}" | fly pg connect -a "${database_app}"

echo -e "${database_envs}"
