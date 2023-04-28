#!/bin/bash

set -e

DB_PASSWORD_SIZE=32

read -p 'Fly database app: ' database_app

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

    DO 
    \$grant_permissions\$
    DECLARE
        schemaname text;
    BEGIN
        FOR schemaname IN SELECT nspname FROM pg_namespace
        LOOP
            EXECUTE format(\$\$ GRANT USAGE ON SCHEMA %I TO ${database_backup_worker_user} \$\$, schemaname);
            EXECUTE format(\$\$ GRANT SELECT ON ALL TABLES IN SCHEMA %I TO ${database_backup_worker_user} \$\$, schemaname);
            EXECUTE format(\$\$ GRANT SELECT ON ALL SEQUENCES IN SCHEMA %I TO ${database_backup_worker_user} \$\$, schemaname);
            EXECUTE format(\$\$ ALTER DEFAULT PRIVILEGES FOR USER ${database_backup_worker_user} IN SCHEMA %I GRANT SELECT ON TABLES TO ${database_backup_worker_user} \$\$, schemaname);
            EXECUTE format(\$\$ ALTER DEFAULT PRIVILEGES FOR USER ${database_backup_worker_user} IN SCHEMA %I GRANT SELECT ON SEQUENCES TO ${database_backup_worker_user} \$\$, schemaname);
        END LOOP;
    END;
    \$grant_permissions\$;
    "

    database_envs+="[ENV]_DATABASE_URL=postgres://${database_backup_worker_user}:${password}@top2.nearest.of.${database_app}.internal:5432/${database_name}\n"
done

database_script+="\q"

echo "${database_script}" | fly pg connect -a "${database_app}"

echo -e "${database_envs}"
