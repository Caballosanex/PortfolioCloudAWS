# Requirements: PortfolioCloudAWS Polish Pass

**Defined:** 2026-03-20
**Core Value:** A recruiter visits asanchezbl.dev and gets a flawless, professional impression

## v1 Requirements

Requirements for this polish pass. Each maps to roadmap phases.

### Nginx & Infrastructure

- [ ] **INFRA-01**: Nginx serves all text responses with gzip compression enabled (HTML, CSS, JS, JSON, SVG)
- [ ] **INFRA-02**: Nginx uses TLS session cache for faster repeat SSL handshakes
- [ ] **INFRA-03**: Nginx serves HTTP/2 for all HTTPS connections
- [x] **INFRA-04**: Nginx uses upstream keepalive blocks for all backend services (no per-request TCP overhead)
- [ ] **INFRA-05**: Nginx worker processes tuned for ARM64 t4g.small (auto workers, correct rlimit)
- [x] **INFRA-06**: EC2 instance has a 2GB swap file configured via Ansible (OOM protection)

### Frontend Polish

- [x] **FRONT-01**: Portfolio and landing page navigation works correctly on phones below 380px wide (hamburger menu or collapsing nav)
- [ ] **FRONT-02**: Portfolio page has active nav scroll highlighting via IntersectionObserver (current section highlighted as user scrolls)

### CV Service

- [ ] **CV-01**: SQLite visit counter uses WAL mode for concurrent request correctness

### Docker & Ansible

- [ ] **DOCK-01**: SERP and CatLink Docker containers have memory limits configured (prevent OOM cascade)
- [ ] **DOCK-02**: Docker image cleanup runs on a schedule to prevent EBS volume fill (dangling image prune)
- [ ] **DOCK-03**: Ansible CV service deploy uses idempotent restart (only restarts when files change, not unconditionally)

### SEO & Structured Data

- [ ] **SEO-01**: Landing page and portfolio page include JSON-LD Person schema for Google rich snippets

## v2 Requirements

Deferred to future pass. Tracked but not in current roadmap.

### Frontend

- **FRONT-03**: Custom Nginx 404 and 502 error pages (replace default Nginx pages)
- **FRONT-04**: All external links use consistent `target="_blank"` with `rel="noopener noreferrer"`
- **FRONT-05**: Zero console errors (all referenced assets return 200)
- **FRONT-06**: Anubis PoW exemption for landing page (instant first impression)

### CV Service

- **CV-02**: Post-deploy Ansible smoke test verifies all 3 language PDF downloads
- **CV-03**: WeasyPrint uses locally hosted fonts (no Google Fonts CDN dependency during PDF generation)

### Docker & Ansible

- **DOCK-04**: SERP Docker container has health check (matching CatLink's existing pattern)
- **DOCK-05**: `ansible.cfg` with pipelining enabled for faster deploys
- **DOCK-06**: Centralized `repo_root` variable replaces fragile relative paths in Ansible roles

### Performance

- **PERF-01**: Landing and portfolio pages self-host fonts (eliminate Google Fonts CDN dependency)
- **PERF-02**: Demo API endpoints have rate limiting configured

### Polish

- **POL-01**: Demo banner migrated from Nginx sub_filter to JavaScript injection in React builds

## Out of Scope

| Feature | Reason |
|---------|--------|
| Blog section | Content maintenance overhead not worth it |
| Dark/light mode toggle | Doubles CSS complexity for zero return |
| Contact form | Complexity for zero gain over mailto link |
| Skills progress bars | Meaningless to technical recruiters |
| Real Gemini AI for CatLink | Paid API, permanently mocked |
| Real Nokia APIs for SERP/CatLink | No production access, permanently mocked |
| Monitoring stack (Prometheus/Grafana) | Dropped to save RAM on 2GB instance |
| CI/CD pipeline | Manual Ansible deploy is sufficient |
| Particle.js / Three.js backgrounds | Heavy, distracting, OOM risk |
| Typewriter animations | Delays content readability |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| INFRA-01 | Phase 1 | Pending |
| INFRA-02 | Phase 1 | Pending |
| INFRA-03 | Phase 1 | Pending |
| INFRA-04 | Phase 1 | Complete |
| INFRA-05 | Phase 1 | Pending |
| INFRA-06 | Phase 1 | Complete |
| FRONT-01 | Phase 2 | Complete |
| FRONT-02 | Phase 5 | Pending |
| CV-01 | Phase 3 | Pending |
| DOCK-01 | Phase 4 | Pending |
| DOCK-02 | Phase 4 | Pending |
| DOCK-03 | Phase 4 | Pending |
| SEO-01 | Phase 5 | Pending |

**Coverage:**
- v1 requirements: 13 total
- Mapped to phases: 13
- Unmapped: 0

---
*Requirements defined: 2026-03-20*
*Last updated: 2026-03-20 after roadmap creation*
