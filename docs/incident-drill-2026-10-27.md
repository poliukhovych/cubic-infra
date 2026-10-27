# Training incident, monitoring and recovery — 27 Oct 2026

Raw evidence for CS-54, CS-55, CS-59, CS-73 and the QR checks of CS-9.
Everything below was executed against the local stack
(`docker compose -f docker-compose.yml -f docker-compose.local.yml`);
copy the filled tables into Confluence pages *4. Quality and releases*,
*5. Risks and incident* and *7. Handover*.

Backend ran with `USE_JSON_LOGS=true` (added to `docker-compose.local.yml`),
which is what makes `cubic-backend/scripts/log_report.py` usable.

## Scenario (CS-55)

| Item | Record |
| --- | --- |
| Scenario | Solver microservice unavailable — risk R1 |
| Injection method | `docker compose stop scheduler_api` |
| Stop condition | 5 failed generation attempts recorded, or 10 min elapsed |
| Return to normal | `docker compose start scheduler_api`, then confirm `/health/` 200 and a schedule read 200 |
| Scale and priority | Single admin function (schedule generation) unavailable; reading existing schedules unaffected → degraded, not an outage |
| Blast radius | Local environment only; no data written |

Roles for the rehearsal: coordinator, technical executor and communications were
the same person. For the graded run these must be three different people.

## Timeline

| Time (UTC) | Event | Evidence |
| --- | --- | --- |
| 18:16:29 | Baseline traffic starts, 60 requests | report "BEFORE": 60×200, p95 7.7 ms |
| 18:16:41 | Impact starts — `scheduler_api` stopped | `Container cubic-infra-scheduler_api-1 Stopped` |
| 18:16:41 | Detected on the first generation attempt | HTTP 500, `X-Request-ID: 27a9f0ef-b5da-4bdd-bba5-082d73356e4c`, 170.56 ms |
| 18:16:44–18:16:58 | 4 more attempts, all 500 | report "DURING": 5/5 failures, alert rule BREACHED |
| 18:16:58 | Data integrity checked during impact | active schedule still 200 assignments, no new empty rows |
| 18:17:14 | Recovery action — `scheduler_api` started | solver answered after 2 s |
| 18:17:16 | Recovery confirmed | `/health/` 200, `/api/schedules/latest` 200, report "AFTER": 21/21 success, 0 % 5xx |

Total impact: **35 s**. Time to detect: **first request**.

## Hypotheses

| # | Hypothesis | Evidence / test | Result |
| --- | --- | --- | --- |
| H1 | Generation fails because the solver is unreachable | Stop only `scheduler_api`; reads keep working, only `/api/schedules/generate` fails | Confirmed |
| H2 | A failed run leaves an empty schedule that shadows the good one (old defect) | Count assignments per schedule after 5 failures | Rejected — the active schedule kept its 200 assignments, no row added |

Chosen recovery action: restart the solver container, because H1 localised the
fault to that single service and no data had been corrupted. Checks after
recovery: `/health/` 200, `/api/schedules/latest` 200, 21 consecutive successful
requests with p95 7.8 ms, record counts unchanged.

## Monitoring (CS-54)

Command: `docker compose logs --no-color --no-log-prefix main_api | python3 cubic-backend/scripts/log_report.py - --since <t0> --until <t1>`

| Window | Requests | 2xx | 5xx | 5xx share | p50 | p95 | p99 | Alert rule |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Before 18:16:29–18:16:41 | 60 | 60 | 0 | 0.0 % | 4.2 ms | 7.7 ms | 17.6 ms | ok |
| During 18:16:41–18:17:14 | 5 | 0 | 5 | 100 % | 132.8 ms | 179.7 ms | 179.7 ms | **BREACHED** |
| After 18:17:14→ | 21 | 21 | 0 | 0.0 % | 4.4 ms | 7.8 ms | 8.8 ms | ok |

Alert rule implemented in the script: more than 20 % 5xx in the window, exit
code 2. It stayed green before and after and fired only during the impact.

Tracing a failed operation: take `X-Request-ID` from the response headers, then
`grep <request-id>` over the backend logs — the start line, the completion line
with `duration`, and the failure line with `error_type` all carry it.

## Post-incident analysis (CS-59)

Failure factors:

1. The backend has a hard runtime dependency on the solver and no degraded mode
   for generation.
2. The failure surfaces as a generic `500 {"detail":"Schedule generation failed"}`.

Protection gaps found by the drill:

- **The documented behaviour does not match the code.** The risk register claims
  R1 is reduced to a `503` after bounded polling (PR #43). With the solver fully
  down the API returns **500** in ~170 ms — the bounded-polling path is never
  reached, because the very first connection attempt raises.
- **The error body carries no `request_id`.** Page 5 states error responses
  return it; the observed body is `{"detail":"Schedule generation failed"}` only.
  The id is present in the `X-Request-ID` header, so a user reporting a problem
  cannot quote anything useful from the screen.

| Action | Jira | Owner | Verification |
| --- | --- | --- | --- |
| CA-2: map "solver unreachable" to `503` with `Retry-After`, and include `request_id` in the error body | CS-59 | Volodymyr | Re-run this drill: expect 503 and a body containing the request id |

Re-assessed risk after the drill: **R1 residual risk stays Low** — detection is
immediate, recovery is a container restart (2 s), and no data is lost. The
probability/impact rating 2/3 is unchanged; only the status-code handling is
wrong, which CA-2 covers.

## Backup and restore (CS-73)

The stack already runs a `db_backup` service: daily `pg_dump | gzip` into
`./backups/<db>-<date>.sql.gz`, 7-day retention. What was missing is the restore
side, now in `scripts/`.

```bash
./scripts/backup.sh                                          # on-demand dump
./scripts/restore.sh backups/schedule_db-2026-10-27.sql.gz   # -> scratch db 'rehearsal'
./scripts/verify_restore.sh rehearsal                        # compare counts
```

Restoring into the live database requires `--into-live --yes`; the script stops
`main_api` and `db_backup` first so the database can be dropped, then starts them
again.

Verified on 27 Oct 2026 by restoring the daily backup into a scratch database —
counts identical to the source:

| Entity | Count |
| --- | --- |
| assignments | 200 |
| courses | 160 |
| groups | 20 |
| rooms | 25 |
| schedules | 3 |
| students | 121 |
| teachers | 35 |
| timeslots | 60 |
| users | 157 |

Plus exactly one active schedule holding all 200 assignments. Note these numbers
differ from the figures currently on page 7 (156 users, no rooms/students rows) —
page 7 should be corrected to the table above.

## Quality requirement checks (CS-9)

| QR | Requirement | Method | Result |
| --- | --- | --- | --- |
| QR-1 | Non-admin JWT on `/api/admin/*` → 403, no token → 401 | `tests/api/test_access_control.py`, 12 cases over 4 admin endpoints × {student, teacher} + anonymous | Pass, automated |
| QR-2 | Schedule readable after restart and after restore | Stack stopped and restarted during this session, counts unchanged; restore round-trip above | Pass |
| QR-3 | `GET /api/students/{id}/schedule` p95 ≤ 1 s over 100 sequential requests on seed data | 100 requests, measured from the request log | **Pass** — p50 5.9 ms, p95 6.8 ms, p99 13.6 ms, max 20.1 ms |
