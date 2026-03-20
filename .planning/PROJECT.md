# PortfolioCloudAWS

## What This Is

A professional portfolio and CV platform deployed on AWS, designed to showcase Alex Sanchez Blabia's skills to recruiters. It includes a landing page, multi-language PDF CV generator, interactive project portfolio, and two live demo applications (SERP and CatLink) — all running on a single EC2 instance managed with Terraform and Ansible.

## Core Value

A recruiter visits asanchezbl.dev and gets a flawless, professional impression — everything loads fast, works correctly, and looks polished.

## Requirements

### Validated

- ✓ Landing page with links to CV, portfolio, GitHub, LinkedIn — existing
- ✓ Multi-language CV generation (ES/EN/CA) from YAML data with WeasyPrint — existing
- ✓ CV download with descriptive filenames and visit counter — existing
- ✓ Portfolio web page showcasing all projects with descriptions and links — existing
- ✓ SERP emergency response demo running live in Docker with mocked Nokia APIs — existing
- ✓ CatLink EV charger agent demo running live in Docker with mocked APIs — existing
- ✓ AWS infrastructure provisioned via Terraform (VPC, EC2 t4g.small, EIP, Security Groups) — existing
- ✓ Server configuration automated via Ansible (13 roles, full playbook) — existing
- ✓ SSL/TLS via Let's Encrypt with Certbot auto-renewal — existing
- ✓ Anubis WAF with Proof-of-Work challenge against bots — existing
- ✓ SSH hardening (port 2222, key-only, fail2ban) — existing
- ✓ Firewall (UFW) allowing only ports 80, 443, 2222 — existing
- ✓ Demo data reset cron job (every 6 hours) — existing
- ✓ Pre-built ARM64 Docker images on Docker Hub (no builds on EC2) — existing
- ✓ Double-proxy architecture (Nginx → Anubis → Nginx internal → services) — existing
- ✓ Cloudflare DNS (free, replacing Route53) — existing
- ✓ AWS Budget alerts (<$15/month) — existing
- ✓ Rate limiting on CV downloads and general routes — existing

### Active

- [ ] Fix all identified bugs and broken behaviors across the stack
- [ ] Optimize frontend performance (load times, asset sizes, caching)
- [ ] Optimize backend/infra performance (resource usage, deployment efficiency)
- [ ] Polish UI/UX to recruiter-ready quality (visual consistency, responsiveness, professional feel)
- [ ] Clean up technical debt (fragile Nginx sub_filter, hardcoded paths, dangling Docker images)
- [ ] Improve deployment reliability (handle edge cases, idempotent runs)
- [ ] Ensure all pages and demos work flawlessly on mobile and desktop

### Out of Scope

- Monitoring stack (Prometheus/Grafana/Node Exporter) — dropped to save RAM on 2GB instance
- Real Nokia APIs for SERP/CatLink — no production access, mocked permanently
- Real Gemini AI for CatLink — would require paid API key, mocked permanently
- CI/CD pipeline — manual Ansible deploy is sufficient for single maintainer
- Multi-instance scaling — single EC2 is sufficient for portfolio traffic
- Database migration from SQLite — traffic too low to justify

## Context

- Alex is an ASIX student (graduating soon) building this as his professional showcase
- The portfolio is live at asanchezbl.dev and has been working
- Both SERP and CatLink demos are running and accessible
- CV content is essentially finalized, only updated for new certifications
- Deployment is manual: edit code locally, run Ansible playbook
- Docker images are pre-built locally (ARM64) and pushed to Docker Hub
- The codebase map (.planning/codebase/) documents the full technical state
- No recruiter feedback yet — this polish pass is proactive

## Constraints

- **Budget**: <$15 EUR/month on AWS — no additional services
- **Instance**: t4g.small (2GB RAM) — all services must fit within memory
- **Stability**: Every commit must leave the site in a working state — no breaking deploys
- **No external paid APIs**: All third-party services must be mocked/free
- **Single repo**: Everything (Terraform, Ansible, web, Docker, scripts) lives in one Git repository
- **ARM64**: EC2 runs Graviton — all Docker images and binaries must be ARM64 compatible

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Cloudflare DNS over Route53 | Free vs $0.50/month hosted zone | ✓ Good |
| t4g.small (ARM) over t3.small (x86) | Better price/performance, Graviton | ✓ Good |
| Pre-built Docker images on Hub | EC2 OOM during builds with 2GB RAM | ✓ Good |
| Drop monitoring stack | Save ~150MB RAM on constrained instance | ✓ Good |
| Double-proxy (Nginx→Anubis→Nginx) | WAF isolation, clean separation | ⚠️ Revisit — adds complexity |
| WeasyPrint for PDF generation | Good HTML→PDF quality, ATS compatible | ✓ Good |
| SQLite for visit counter | Simple, no extra service needed | ✓ Good |
| Manual Ansible deploys | Single maintainer, no CI/CD overhead | ✓ Good |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd:transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd:complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-03-20 after initialization*
