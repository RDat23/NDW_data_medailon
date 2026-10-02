#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"

set -a
. "$project_root/.env"
set +a

reader_user="${LIGHTDASH_WAREHOUSE_USER:-lightdash_reader}"
app_db_user="${LIGHTDASH_DB_USER:-lightdash}"
app_db_name="${LIGHTDASH_DB_NAME:-lightdash}"

: "${LIGHTDASH_WAREHOUSE_PASSWORD:?LIGHTDASH_WAREHOUSE_PASSWORD is verplicht}"
: "${LIGHTDASH_DB_PASSWORD:?LIGHTDASH_DB_PASSWORD is verplicht}"

reader_password="$LIGHTDASH_WAREHOUSE_PASSWORD"
app_db_password="$LIGHTDASH_DB_PASSWORD"

if [[ ! "$reader_user" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
  echo "Ongeldige LIGHTDASH_WAREHOUSE_USER: $reader_user" >&2
  exit 1
fi

if [[ ! "$app_db_user" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
  echo "Ongeldige LIGHTDASH_DB_USER: $app_db_user" >&2
  exit 1
fi

if [[ ! "$app_db_name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
  echo "Ongeldige LIGHTDASH_DB_NAME: $app_db_name" >&2
  exit 1
fi

"$project_root/scripts/setup_lightdash_storage.sh"

docker compose --project-directory "$project_root" up -d --wait lightdash-db

docker compose --project-directory "$project_root" exec -T lightdash-db \
  psql \
    -v app_db_user="$app_db_user" \
    -v app_db_password="$app_db_password" \
    -U "$app_db_user" \
    -d "$app_db_name" \
    -f - < "$project_root/sql/03_sync_lightdash_app_password.sql"

echo "Wachtwoord van de bestaande Lightdash-applicatiedatabase is gesynchroniseerd."

docker compose --project-directory "$project_root" exec -T postgres \
  psql \
    -v reader_user="$reader_user" \
    -v reader_password="$reader_password" \
    -v database_name="$POSTGRES_DB" \
    -v owner_user="$POSTGRES_USER" \
    -U "$POSTGRES_USER" \
    -d "$POSTGRES_DB" \
    -f /docker-entrypoint-initdb.d/02_setup_lightdash_reader.sql

echo "Lightdash-reader '$reader_user' heeft alleen-lezen toegang tot schema gold."

docker compose --project-directory "$project_root" up -d lightdash

echo "Lightdash is gestart op http://localhost:${LIGHTDASH_PORT:-8080}."
