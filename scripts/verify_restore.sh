#!/usr/bin/env bash
# Print the record counts used to confirm a restore is complete.
#
#   ./scripts/verify_restore.sh            -> checks the live database
#   ./scripts/verify_restore.sh rehearsal  -> checks a scratch restore
#
# Compare the output against the same command run on the source database:
# identical counts mean the dump round-tripped without loss.
set -euo pipefail

cd "$(dirname "$0")/.."

CONTAINER="${DB_CONTAINER:-cubic-infra-db-1}"
[ -f .env ] && set -a && . ./.env && set +a

: "${POSTGRES_USER:?POSTGRES_USER is not set (expected in .env)}"
TARGET="${1:-${POSTGRES_DB:?POSTGRES_DB is not set}}"

docker exec -i "$CONTAINER" psql -U "$POSTGRES_USER" -d "$TARGET" -v ON_ERROR_STOP=1 <<'SQL'
\pset format aligned
SELECT 'courses'     AS entity, count(*) FROM courses
UNION ALL SELECT 'groups',      count(*) FROM groups
UNION ALL SELECT 'teachers',    count(*) FROM teachers
UNION ALL SELECT 'students',    count(*) FROM students
UNION ALL SELECT 'users',       count(*) FROM users
UNION ALL SELECT 'timeslots',   count(*) FROM timeslots
UNION ALL SELECT 'rooms',       count(*) FROM rooms
UNION ALL SELECT 'schedules',   count(*) FROM schedules
UNION ALL SELECT 'assignments', count(*) FROM assignments
ORDER BY entity;

-- A usable restore needs exactly one active schedule that actually has lessons.
SELECT s.label,
       s.is_active,
       count(a.assignment_id) AS assignments
FROM schedules s
LEFT JOIN assignments a ON a.schedule_id = s.schedule_id
GROUP BY s.schedule_id, s.label, s.is_active
ORDER BY s.is_active DESC, assignments DESC
LIMIT 5;
SQL
