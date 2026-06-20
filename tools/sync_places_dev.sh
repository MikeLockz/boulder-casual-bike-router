#!/bin/bash
# Developer helper script to sync regional places locally in dev environment.
# Sets up a temporary superuser, runs sync_places.py, and cleans up on exit.

set -euo pipefail

cd "$(dirname "$0")/.."

REGION="${1:-broomfield}"
PB_URL="http://localhost:8090"
PB_SYNC_EMAIL="tmp-places-sync@boulder.lockdev.com"
PB_SYNC_CREATED=0

echo "=== Region Place Sync Automation ==="
echo "Target Region: $REGION"

# Ensure PocketBase is reachable
echo "Checking if local PocketBase is running at $PB_URL..."
if ! curl -sSf --max-time 3 "$PB_URL/api/health" >/dev/null; then
    echo "Error: Local PocketBase is not running or not reachable."
    echo "Please start the local docker containers using 'docker compose up -d' first."
    exit 1
fi

# Cleanup trap to delete the temporary admin account on exit
cleanup() {
    if [ "$PB_SYNC_CREATED" = "1" ]; then
        echo "Cleaning up temporary PocketBase superuser..."
        docker compose exec -T pocketbase \
            /usr/local/bin/pocketbase superuser delete "$PB_SYNC_EMAIL" --dir /pb_data >/dev/null 2>&1 || true
        echo "✓ Temporary credentials removed."
    fi
}
trap cleanup EXIT

# Generate temporary password
TEMP_PASS=$(dd if=/dev/urandom bs=24 count=1 2>/dev/null | base64 | tr -d '+/=' | cut -c1-24)

echo "Creating temporary PocketBase credentials..."
docker compose exec -T pocketbase \
    /usr/local/bin/pocketbase superuser upsert "$PB_SYNC_EMAIL" "$TEMP_PASS" --dir /pb_data >/dev/null
PB_SYNC_CREATED=1
echo "✓ Temporary credentials created."

echo "Starting place synchronization..."
POCKETBASE_URL="$PB_URL" \
POCKETBASE_ADMIN_EMAIL="$PB_SYNC_EMAIL" \
POCKETBASE_ADMIN_PASSWORD="$TEMP_PASS" \
  ./venv/bin/python3 tools/sync_places.py \
    --region "$REGION" \
    "${@:2}"

echo "✓ Place sync completed successfully!"
