#!/usr/bin/env bash
# On-demand database dump, e.g. before a migration or an upgrade.
#
#   ./scripts/backup.sh                    -> backups/<db>-<timestamp>.sql.gz
#   ./scripts/backup.sh /tmp/before.sql.gz -> that exact path
#
# Same format as the automated db_backup service in docker-compose.yml
# (plain SQL, gzipped), so restore.sh handles both interchangeably.
set -euo pipefail

cd "$(dirname "$0")/.."

CONTAINER="${DB_CONTAINER:-cubic-infra-db-1}"
[ -f .env ] && set -a && . ./.env && set +a

: "${POSTGRES_USER:?POSTGRES_USER is not set (expected in .env)}"
: "${POSTGRES_DB:?POSTGRES_DB is not set (expected in .env)}"

if ! docker ps --format '{{.Names}}' | grep -qx "$CONTAINER"; then
    echo "database container '$CONTAINER' is not running" >&2
    echo "start the stack first, or set DB_CONTAINER=<name>" >&2
    exit 1
fi

OUT="${1:-backups/$POSTGRES_DB-$(date +%Y%m%d-%H%M%S).sql.gz}"
mkdir -p "$(dirname "$OUT")"

umask 077
docker exec "$CONTAINER" pg_dump -U "$POSTGRES_USER" "$POSTGRES_DB" | gzip > "$OUT.tmp"
mv "$OUT.tmp" "$OUT"

echo "backup written to $OUT ($(du -h "$OUT" | cut -f1))"
