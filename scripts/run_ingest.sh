#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"

set -a
. "$project_root/.env"
set +a

exec "$project_root/.venv/bin/python" \
  "$project_root/scripts/ingest_ndw_csv.py" \
  "$@"

# scripts/run_ingest.sh \
#   --object-key bronze/intensiteit-snelheid/2026/09/intensiteit-snelheid-export.csv \
#   --exportnaam intensiteit-snelheid-export \
#   --aanvraag-id 00000000-0000-4000-8000-000000000001 \
#   --bron-periode-van 2026-01-01T00:00:00+01:00 \
#   --bron-periode-tot 2026-09-22T23:59:59+02:00
