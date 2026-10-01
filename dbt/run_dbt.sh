#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"

set -a
. "$project_root/.env"
set +a

exec "$project_root/.venv/bin/dbt" \
  "$@" \
  --project-dir "$project_root/dbt" \
  --profiles-dir "$project_root/dbt"
