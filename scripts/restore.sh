#!/usr/bin/env bash
# Restore a .sql.gz dump — either an on-demand one from backup.sh or a daily
# one written by the db_backup service into ./backups.
#
#   ./scripts/restore.sh backups/schedule_db-2026-10-27.sql.gz
#       restore into the scratch database 'rehearsal' — safe, the default
#
#   ./scripts/restore.sh backups/schedule_db-2026-10-27.sql.gz --into-live --yes
#       drop and rebuild the real database — destructive, needs both flags
#
# Afterwards run scripts/verify_restore.sh to compare the record counts.
set -euo pipefail

cd "$(dirname "$0")/.."

CONTAINER="${DB_CONTAINER:-cubic-infra-db-1}"
[ -f .env ] && set -a && . ./.env && set +a

: "${POSTGRES_USER:?POSTGRES_USER is not set (expected in .env)}"
: "${POSTGRES_DB:?POSTGRES_DB is not set (expected in .env)}"

DUMP="${1:?usage: restore.sh <dump.sql.gz> [--into <db> | --into-live --yes]}"
shift

TARGET="rehearsal"
CONFIRMED=0
while [ $# -gt 0 ]; do
    case "$1" in
        --into)      TARGET="${2:?--into needs a database name}"; shift 2 ;;
        --into-live) TARGET="$POSTGRES_DB"; shift ;;
        --yes)       CONFIRMED=1; shift ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

[ -f "$DUMP" ] || { echo "dump file not found: $DUMP" >&2; exit 1; }

if [ "$TARGET" = "$POSTGRES_DB" ] && [ "$CONFIRMED" -ne 1 ]; then
    echo "refusing to overwrite the live database '$POSTGRES_DB' without --yes" >&2
    exit 1
fi

psql_admin() { docker exec -i "$CONTAINER" psql -U "$POSTGRES_USER" -d postgres -v ON_ERROR_STOP=1 "$@"; }

if [ "$TARGET" = "$POSTGRES_DB" ]; then
    echo "stopping API containers so they release their connections"
    docker compose stop main_api db_backup >/dev/null 2>&1 || true
    # Plain-SQL dumps carry no DROP statements, so the database is rebuilt empty.
    psql_admin -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity
                   WHERE datname = '$TARGET' AND pid <> pg_backend_pid();" >/dev/null
fi

echo "recreating database '$TARGET'"
psql_admin -c "DROP DATABASE IF EXISTS \"$TARGET\";" >/dev/null
psql_admin -c "CREATE DATABASE \"$TARGET\";" >/dev/null

# citext is normally created by the app at startup; a fresh database needs it first.
docker exec -i "$CONTAINER" psql -U "$POSTGRES_USER" -d "$TARGET" -v ON_ERROR_STOP=1 \
    -c 'CREATE EXTENSION IF NOT EXISTS "citext";' >/dev/null

gunzip -c "$DUMP" | docker exec -i "$CONTAINER" \
    psql -U "$POSTGRES_USER" -d "$TARGET" -v ON_ERROR_STOP=1 --quiet

echo "restored $DUMP into '$TARGET'"

if [ "$TARGET" = "$POSTGRES_DB" ]; then
    docker compose start main_api db_backup >/dev/null 2>&1 || true
    echo "API containers started again"
fi

echo "now run: ./scripts/verify_restore.sh $([ "$TARGET" = "$POSTGRES_DB" ] || echo "$TARGET")"
