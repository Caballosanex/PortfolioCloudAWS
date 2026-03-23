---
phase: 03-cv-service-quality
plan: 01
subsystem: database
tags: [sqlite, wal, concurrency, cv-service, fastapi, ansible]

# Dependency graph
requires:
  - phase: 01-performance-and-infra
    provides: CV service running as systemd unit on EC2 with Ansible deploy role
provides:
  - SQLite WAL mode enabled in CV service visit counter (journal_mode=WAL, busy_timeout=5000)
  - Concurrent requests to /cv/preview/{lang} no longer risk database-locked errors
affects: []

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "SQLite WAL mode set via PRAGMA on every connection (idempotent, persistent)"
    - "busy_timeout=5000 as safety net for WAL checkpoint contention"

key-files:
  created: []
  modified:
    - web/cv-service/app.py

key-decisions:
  - "Set PRAGMA journal_mode=wal on every sqlite3.connect() call — harmless and ensures correctness even if db is recreated"
  - "Set PRAGMA busy_timeout=5000 to wait up to 5s before SQLITE_BUSY under WAL checkpoint load"

patterns-established:
  - "SQLite WAL pragma: set both journal_mode=wal and busy_timeout on every connection open"

requirements-completed: [CV-01]

# Metrics
duration: 2min
completed: 2026-03-23
---

# Phase 3 Plan 1: CV Service Quality Summary

**SQLite WAL mode enabled in CV service get_db() via two PRAGMAs, eliminating database-locked errors under concurrent requests**

## Performance

- **Duration:** 2 min
- **Started:** 2026-03-23T18:48:03Z
- **Completed:** 2026-03-23T18:50:56Z
- **Tasks:** 2
- **Files modified:** 2 (app.py, nginx/conf.d/asanchezbl.dev.conf)

## Accomplishments
- Added `PRAGMA journal_mode=wal` and `PRAGMA busy_timeout=5000` to `get_db()` in the CV service
- Deployed to EC2 via `ansible-playbook --tags deploy-cv` with no failed tasks
- Verified WAL mode active on server: `PRAGMA journal_mode` returns `wal`
- Two simultaneous curl requests to `/cv/preview/en` both return HTTP 200

## Task Commits

Each task was committed atomically:

1. **Task 1: Enable SQLite WAL mode in CV service get_db()** - `4f8ed4d` (feat)
2. **Task 2: Deploy to EC2 and verify WAL mode is active** - `a8267ca` (feat)

**Plan metadata:** (included in final docs commit)

## Files Created/Modified
- `web/cv-service/app.py` - Added PRAGMA journal_mode=wal and PRAGMA busy_timeout=5000 inside get_db() after sqlite3.connect()
- `nginx/conf.d/asanchezbl.dev.conf` - Pre-existing demo banner style improvements (not part of this plan's scope)

## Decisions Made
- Issue PRAGMA on every connection, not just on DB creation: WAL mode is persistent once set, but re-issuing is safe and ensures correctness if the db file is ever deleted/recreated.
- Use busy_timeout=5000 (5 seconds): WAL auto-checkpoint can briefly block new writers; 5s wait avoids spurious SQLITE_BUSY without risking hung requests.

## Deviations from Plan

None - plan executed exactly as written.

The only minor issue: the plan specified `--tags cv` but the correct Ansible tag is `deploy-cv`. Detected immediately from tag listing and corrected.

## Issues Encountered
- `ansible-playbook --tags cv` matched no tasks (0 changes). Checked tag list from site.yml, used `--tags deploy-cv` instead. Resolved immediately.
- WAL companion files (`visits.db-wal`, `visits.db-shm`) were not visible after requests because SQLite immediately auto-checkpoints at low traffic levels. Verified WAL mode directly via Python PRAGMA query: returned `wal` as expected.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- CV service is now concurrency-safe for visit counter writes
- No blockers for remaining plans in Phase 3

## Self-Check: PASSED

- FOUND: web/cv-service/app.py
- FOUND: .planning/phases/03-cv-service-quality/03-01-SUMMARY.md
- FOUND: commit 4f8ed4d (feat: WAL mode in get_db())
- FOUND: commit a8267ca (feat: deploy and verify)

---
*Phase: 03-cv-service-quality*
*Completed: 2026-03-23*
