# Roadmap: PortfolioCloudAWS Polish Pass

## Overview

This is a targeted polish pass on a working production portfolio at asanchezbl.dev. All core features are live. The goal is recruiter-ready quality: fast loads, zero broken behaviors, professional feel. Five phases ordered by impact-to-effort ratio, each delivering independently verifiable improvements. Every commit leaves the site working.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [ ] **Phase 1: Nginx and Infrastructure Hardening** - Enable gzip, TLS session cache, HTTP/2, upstream keepalive, worker tuning, and swap file
- [ ] **Phase 2: Frontend Polish and Mobile UX** - Fix mobile navigation breakpoint for small screens
- [ ] **Phase 3: CV Service Quality** - Enable SQLite WAL mode for concurrent request correctness
- [ ] **Phase 4: Docker and Ansible Reliability** - Add memory limits, image cleanup cron, and idempotent CV deploys
- [ ] **Phase 5: Polish and Differentiators** - Add scroll-based nav highlighting and JSON-LD structured data

## Phase Details

### Phase 1: Nginx and Infrastructure Hardening
**Goal**: Every page and API response loads measurably faster, and the instance is protected against OOM during future deploys
**Depends on**: Nothing (first phase)
**Requirements**: INFRA-01, INFRA-02, INFRA-03, INFRA-04, INFRA-05, INFRA-06
**Success Criteria** (what must be TRUE):
  1. `curl -H 'Accept-Encoding: gzip' https://asanchezbl.dev/ -sI` returns `Content-Encoding: gzip` header for HTML, CSS, JS, JSON, and SVG responses
  2. `openssl s_client -reconnect` to port 443 shows TLS session reuse on the second connection (session ticket or session ID match)
  3. `curl -sI https://asanchezbl.dev/` shows HTTP/2 in the response protocol (via `--http2` or visible in headers)
  4. Nginx error log shows no upstream connection errors under normal load; `nginx -T` output contains `upstream` blocks with `keepalive` directives for all backend services
  5. `free -h` on the EC2 instance shows a 2GB swap file active; `swapon --show` confirms it
**Plans:** 2 plans

Plans:
- [x] 01-01-PLAN.md — Nginx global config (gzip, TLS session cache, HTTP/2, worker tuning) + Ansible role with nginx -t validation
- [x] 01-02-PLAN.md — Upstream keepalive blocks for all backends + 2GB swap file Ansible role

### Phase 2: Frontend Polish and Mobile UX
**Goal**: A recruiter on any phone screen size can navigate the portfolio without layout breakage
**Depends on**: Phase 1 (gzip must be active before addressing sub_filter/gzip interaction on demo pages)
**Requirements**: FRONT-01
**Success Criteria** (what must be TRUE):
  1. On a 320px-wide viewport (smallest common phone), the portfolio and landing page navigation is fully usable -- either a hamburger menu or a collapsing layout that does not overflow or clip
  2. On a 375px-wide viewport (iPhone SE/Mini), all nav links are tappable without horizontal scroll
**Plans**: TBD

Plans:
- [ ] 02-01: TBD

### Phase 3: CV Service Quality
**Goal**: The CV visit counter never loses counts or locks up under concurrent requests
**Depends on**: Phase 2 (mobile UX is a higher-visibility recruiter gate than CV counter correctness)
**Requirements**: CV-01
**Success Criteria** (what must be TRUE):
  1. SQLite database file has a `-wal` companion file present after the first write, confirming WAL mode is active
  2. Two simultaneous `curl` requests to `/cv/preview/en` both succeed (HTTP 200) without either returning a database-locked error
**Plans**: TBD

Plans:
- [ ] 03-01: TBD

### Phase 4: Docker and Ansible Reliability
**Goal**: Docker containers cannot OOM-kill each other, disk space does not silently fill up, and CV deploys only restart the service when something actually changed
**Depends on**: Phase 3 (CV correctness before deploy reliability; Phase 1 swap file must exist before Docker image operations)
**Requirements**: DOCK-01, DOCK-02, DOCK-03
**Success Criteria** (what must be TRUE):
  1. `docker inspect` on SERP and CatLink containers shows memory limits configured (not `0` / unlimited)
  2. `crontab -l` or systemd timer list shows a scheduled Docker image prune job
  3. Running `ansible-playbook playbooks/site.yml --tags cv` twice in a row without changing any CV files produces no service restart on the second run (handler not triggered)
**Plans**: TBD

Plans:
- [ ] 04-01: TBD

### Phase 5: Polish and Differentiators
**Goal**: The portfolio demonstrates frontend skill (scroll-aware navigation) and is discoverable via structured data in search engines
**Depends on**: Phase 4 (Docker stability before any image rebuilds; all infrastructure must be solid)
**Requirements**: FRONT-02, SEO-01
**Success Criteria** (what must be TRUE):
  1. Scrolling through the portfolio page causes the nav item corresponding to the visible section to gain an active/highlighted class (observable in browser DevTools or visually)
  2. Viewing page source of the landing page shows a `<script type="application/ld+json">` block with a valid Person schema containing name, url, and sameAs fields
  3. Viewing page source of the portfolio page shows a `<script type="application/ld+json">` block with valid Person schema
  4. Google Rich Results Test (or manual JSON-LD validation) returns no errors on the schema markup
**Plans**: TBD

Plans:
- [ ] 05-01: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 1 -> 2 -> 3 -> 4 -> 5

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Nginx and Infrastructure Hardening | 0/2 | Planned | - |
| 2. Frontend Polish and Mobile UX | 0/? | Not started | - |
| 3. CV Service Quality | 0/? | Not started | - |
| 4. Docker and Ansible Reliability | 0/? | Not started | - |
| 5. Polish and Differentiators | 0/? | Not started | - |
