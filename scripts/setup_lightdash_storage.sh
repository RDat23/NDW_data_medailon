#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"

set -a
. "$project_root/.env"
set +a

bucket="${LIGHTDASH_S3_BUCKET:-lightdash}"
storage_user="${LIGHTDASH_S3_USER:-lightdash_storage}"
storage_password="${LIGHTDASH_S3_PASSWORD:-lightdash_local_storage_change_me}"
policy_name="lightdash-storage"

if [[ "$bucket" != "lightdash" ]]; then
  echo "LIGHTDASH_S3_BUCKET moet 'lightdash' zijn; de policy is tot die bucket beperkt." >&2
  exit 1
fi

if [[ ! "$storage_user" =~ ^[A-Za-z_][A-Za-z0-9_-]*$ ]]; then
  echo "Ongeldige LIGHTDASH_S3_USER: $storage_user" >&2
  exit 1
fi

mc_command=(docker compose --project-directory "$project_root" exec -T minio mc)

"${mc_command[@]}" alias set local http://localhost:9000 \
  "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" >/dev/null
"${mc_command[@]}" mb --ignore-existing "local/$bucket" >/dev/null

"${mc_command[@]}" admin user add local "$storage_user" "$storage_password" >/dev/null

"${mc_command[@]}" admin policy create local "$policy_name" \
  /policies/lightdash-storage.json >/dev/null
"${mc_command[@]}" admin policy attach local "$policy_name" \
  --user "$storage_user" >/dev/null

echo "MinIO-bucket '$bucket' en gebruiker '$storage_user' zijn ingericht voor Lightdash."
