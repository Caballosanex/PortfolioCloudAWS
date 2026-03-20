# Architecture

**Analysis Date:** 2026-03-20

## Pattern Overview

**Overall:** Layered web infrastructure with reverse-proxy sandwich, microservice isolation via Docker, and defensive perimeter security.

**Key Characteristics:**
- Double-proxy architecture (Nginx → Anubis WAF → Nginx internal)
- Static content served directly from Nginx
- Microservices isolated in Docker Compose networks
- IaC-first approach with Terraform + Ansible
- Zero direct exposure of backend services to internet
- Pre-built Docker images (ARM64/Graviton) to prevent EC2 memory exhaustion

## Layers

**Infrastructure Layer (Terraform):**
- Purpose: Provision and manage AWS cloud resources
- Location: `terraform/` (vpc.tf, ec2.tf, security_groups.tf, dns.tf, budget.tf, variables.tf)
- Contains: VPC configuration, EC2 instance definition (t4g.small ARM64), Elastic IP, security groups, Cloudflare DNS records, budget alerts
- Depends on: AWS provider, Cloudflare API token
- Used by: Ansible inventory (target host: 34.250.192.166:2222)

**Configuration Management Layer (Ansible):**
- Purpose: Configure EC2 instance and deploy all services
- Location: `ansible/` (playbooks, roles, inventory, templates, files)
- Contains: 13 roles for system setup, security hardening, containerization, certificate management, and application deployment
- Depends on: Terraform outputs, SSH key pair
- Used by: Deployment pipeline (`site.yml` orchestrates all roles)

**Reverse Proxy Layer (Nginx):**
- Purpose: SSL termination, request routing, rate limiting, security headers
- Location: `nginx/conf.d/asanchezbl.dev.conf` (main config file)
- Contains: HTTP-to-HTTPS redirect, SSL certificate chain, location blocks for all routes
- Entry point: Listens on ports 80/443 (internet-facing)
- Routing logic:
  - `/` → `/var/www/landing/index.html` (static landing page)
  - `/assets/` → `/var/www/assets/` (cached images, certificates, photos)
  - `/cv/` → `127.0.0.1:8923` (Anubis WAF) → CV service on port 8001
  - `/portfolio` → `/var/www/portfolio/index.html` (static SPA)
  - `/demo/serp/` → Anubis → SERP frontend port 3001
  - `/demo/catlink/` → Anubis → CatLink frontend port 3002
  - `/demo/*/api/` → Anubis → respective API ports (5001 for SERP, 8002 for CatLink)
- Rate limiting: CV downloads (5 req/min), general routes (30 req/min)
- Security: HSTS, CSP, X-Frame-Options, Permissions-Policy, disable server tokens

**WAF Layer (Anubis):**
- Purpose: Proof-of-Work challenge mitigation against bots and AI scrapers
- Location: Configured by `ansible/roles/anubis/` (systemd unit, policy file)
- Runs on: `127.0.0.1:8923` (localhost-only, not exposed to internet)
- Difficulty: 6 (configurable in `ansible/inventory/group_vars/all.yml`)
- All external requests → Anubis → clean traffic forwarded to internal Nginx (:8080)
- Integration: Every Nginx location block proxies to `:8923`, not directly to services

**Internal Nginx Layer (Clean Traffic Handler):**
- Purpose: Route validated traffic from Anubis to backend services
- Location: Server block listening on `127.0.0.1:8080` in `nginx/conf.d/asanchezbl.dev.conf` (lines 169–222)
- Contains: Final destination proxy_pass blocks for CV, SERP frontend, CatLink frontend, API endpoints
- Adds demo banners via `sub_filter` (indicates "LIVE DEMO" with green badge)

**CV Service (FastAPI + WeasyPrint):**
- Purpose: Generate and serve multi-language PDF CVs, track visit counts
- Location: `web/cv-service/` (app.py, requirements.txt, data/, templates/)
- Runs on: `127.0.0.1:8001` (localhost, behind systemd unit `cv-service`)
- Stack: FastAPI, WeasyPrint (PDF generation from Jinja2 HTML templates), SQLite (visit counter)
- Entry points:
  - `GET /` → CV page with language selector and download buttons (increments visit counter)
  - `GET /preview/{lang}` → Serve PDF inline for browser preview (es/en/ca)
  - `GET /download/{lang}` → Download PDF with descriptive filename
  - `GET /api/visits` → Return global visit count (JSON)
- Data source: YAML files (`cv_es.yml`, `cv_en.yml`, `cv_ca.yml`) in `data/`
- Templates: Jinja2 HTML template (`templates/cv.html` rendered to PDF), web UI (`templates/cv_page.html`)
- Pre-generation: Startup warmup generates all 3 PDFs concurrently for instant first requests

**Static Web Layer:**
- Purpose: Serve landing page, portfolio, and assets
- Location: `web/landing/`, `web/portfolio/`, plus `assets/` (images, certificates, photos)
- Landing page: `web/landing/index.html` (entry point to portfolio, links to CV/portfolio/GitHub/LinkedIn)
- Portfolio: `web/portfolio/index.html` (project showcase with demo links)
- Assets: `assets/` directory (images, certificates, project screenshots)
- Deployment: Copied to `/var/www/landing/`, `/var/www/portfolio/`, `/var/www/assets/` during Ansible execution
- Caching: Static assets cached 30 days, HTML not cached (expires: -1)

**Demo Services (Docker Compose):**
- Purpose: Run interactive demos (SERP emergency response, CatLink EV charger agent)
- Location: `docker/serp/` and `docker/catlink/` (docker-compose.yml + mock patches)
- SERP (Emergency Response System):
  - Services: FastAPI backend (port 5001), React frontend (port 3001), mock data
  - Original: PostgreSQL + real Nokia QoS APIs (mocked for portfolio)
  - Deployment: Image pulled from Docker Hub (`caballosanex/serp-backend:latest`, `caballosanex/serp-frontend:latest`)
  - Network: `serp-net` bridge network (isolated)
- CatLink (EV Charger Agent):
  - Services: FastAPI backend (port 8002), React frontend (port 3002), Gemini mock
  - Original: Real Nokia APIs + Gemini AI (mocked for portfolio)
  - Deployment: Image pulled from Docker Hub (`caballosanex/catlink-backend:latest`, `caballosanex/catlink-frontend:latest`)
  - Network: `catlink-net` bridge network (isolated)
  - WebSocket support: `/demo/catlink/ws` proxied to backend port 8002/ws
- Pre-built images: Built on developer machine (ARM64), pushed to Docker Hub; EC2 only pulls
- Reset cron: `demo-reset` role configures periodic reset of demo databases (every 6 hours)

## Data Flow

**User Request Flow (Standard Route):**

1. Client HTTP request → Internet → Cloudflare DNS (grey-cloud, forwards to EIP)
2. EIP 34.250.192.166:80 → Nginx (external listener on ports 80/443)
3. Nginx redirects HTTP → HTTPS, validates SSL certificate
4. Nginx proxies HTTPS request → `127.0.0.1:8923` (Anubis WAF)
5. Anubis validates PoW challenge (difficulty 6)
   - If challenge fails → 403 error with PoW page (`.within.website/` static assets)
   - If challenge passes → Anubis forwards validated request to `127.0.0.1:8080`
6. Internal Nginx (:8080) receives clean request
7. Nginx routes based on path:
   - `/` → serves `/var/www/landing/index.html`
   - `/cv/` → proxies to FastAPI service on `:8001`
   - `/demo/serp/` → proxies to SERP frontend on `:3001` (injects demo banner)
   - `/demo/serp/api/` → proxies to SERP backend on `:5001`
   - `/demo/catlink/` → proxies to CatLink frontend on `:3002`
   - `/demo/catlink/api/` → proxies to CatLink backend on `:8002`
8. Destination service processes request
9. Response flows back through proxy chain → client

**CV Generation Flow:**

1. User visits `/cv/` → Nginx proxies to FastAPI `:8001`
2. FastAPI handler `cv_page()` increments SQLite counter, renders `cv_page.html`
3. User selects language (es/en/ca) and clicks "Download"
4. Browser calls `/download/{lang}` endpoint
5. Handler calls `generate_pdf(lang)`:
   - Checks if PDF already exists (cached)
   - If not cached: loads YAML data (`cv_{lang}.yml`), renders Jinja2 template, uses WeasyPrint to convert HTML → PDF
   - Returns PDF file path
6. FastAPI serves PDF with filename `CV_Name_Surname_{SUFFIX}.pdf`
7. Browser downloads/previews

**Demo Reset Flow:**

1. Cron job triggers every 6 hours (configured by `demo-reset` role)
2. Executes `scripts/reset-demos.sh` on EC2
3. Script connects to SERP and CatLink Docker containers
4. Resets demo databases to initial state (clean data for next visitor)

**Static State Management:**

- Landing page, portfolio, CV YAML data: Stored in Git repository
- Visit counter: SQLite database persisted at `web/cv-service/visits.db` (not committed)
- Demo data: In Docker container volumes (reset by cron)
- Assets (photos, certificates): Committed to Git under `assets/` and `photos/`

## Key Abstractions

**Ansible Role:**
- Purpose: Encapsulate a logical configuration unit (e.g., "install Docker", "deploy CV service")
- Examples: `ansible/roles/docker/`, `ansible/roles/deploy-cv/`, `ansible/roles/anubis/`
- Pattern: Each role has `tasks/main.yml`, optional `handlers/main.yml`, optional `templates/`, optional files
- Composition: Roles are composed into playbooks (`site.yml` includes all roles in order)

**Service (Systemd Unit):**
- Purpose: Run a service as a persistent process on the EC2 instance
- Examples: `cv-service.service` (FastAPI), `anubis.service` (WAF), Nginx, Docker
- Managed by: Ansible tasks (copy unit file, enable, start, restart on config change)
- Restart policy: `always`, with 5-second backoff

**Docker Service (via docker-compose):**
- Purpose: Run containerized application with multiple services (backend, frontend, network)
- Examples: SERP and CatLink compositions
- Isolation: Private bridge network (serp-net, catlink-net) prevents cross-service communication
- Lifecycle: Started with `docker compose up -d`, pulled images before starting

**Nginx Location Block:**
- Purpose: Route HTTP requests to backend services based on URI path
- Examples: `location /cv/`, `location /demo/serp/`, `location /assets/`
- Pattern: `proxy_pass` directives forward requests; `proxy_set_header` preserves client info
- Rate limiting: `limit_req` zones apply to specific locations

## Entry Points

**HTTP/HTTPS Entry (Port 80/443):**
- Location: Nginx external listeners in `nginx/conf.d/asanchezbl.dev.conf`
- Triggers: Client HTTP/HTTPS requests to asanchezbl.dev
- Responsibilities:
  - Redirect HTTP to HTTPS
  - SSL/TLS termination
  - Request logging
  - Rate limiting
  - Security headers

**SSH Entry (Port 2222):**
- Location: EC2 security group allows inbound port 2222
- Triggers: SSH key-based login for administration
- Responsibilities:
  - Access to EC2 for debugging, manual deployments
  - Disabled password auth (key-only)
  - Block after 3 failed attempts (fail2ban)

**Cron Entry (Demo Reset):**
- Location: `ansible/roles/demo-reset/` (configures cron job)
- Triggers: Every 6 hours (0 */6 * * *)
- Responsibilities:
  - Reset SERP database to initial state
  - Reset CatLink database to initial state

**Terraform Entry Point:**
- Location: `terraform/`
- Triggers: `terraform init`, `terraform plan`, `terraform apply`
- Responsibilities:
  - Create VPC, subnet, internet gateway, route table
  - Launch EC2 instance (t4g.small, Ubuntu 24.04 ARM64)
  - Allocate Elastic IP
  - Create security groups (allow 80, 443, 2222)
  - Configure Cloudflare DNS A records
  - Set up budget alert (<$15/month)

**Ansible Entry Point:**
- Location: `ansible/playbooks/site.yml`
- Triggers: `cd ansible && ansible-playbook playbooks/site.yml`
- Responsibilities:
  - System configuration (packages, firewall, SSH)
  - Install services (Nginx, Docker, Certbot, Anubis)
  - Deploy applications (landing, CV, portfolio, SERP, CatLink)
  - Configure cron jobs
  - Enable systemd units

## Error Handling

**Strategy:** Graceful degradation with user-visible feedback.

**Patterns:**

- **Nginx errors:** Return standard HTTP status codes (404 for missing assets, 429 for rate limit, 502 for upstream unavailable)
- **PoW challenge failure:** Anubis returns 403 with challenge page (user must solve PoW to continue)
- **PDF generation failure:** FastAPI returns 500 error; fallback is to pre-generated cached PDF
- **Docker service down:** Nginx returns 502 Bad Gateway; client sees "Service temporarily unavailable"
- **Certificate renewal failure:** Certbot logs error; manual intervention needed (monitored by AWS Budgets for cost anomalies)
- **Visit counter database error:** CV service still serves PDFs (counter just doesn't increment)

## Cross-Cutting Concerns

**Logging:**
- Nginx: Access logs at `/var/log/nginx/access.log`, error logs at `/var/log/nginx/error.log`
- SSH: Login attempts logged to `/var/log/auth.log` (monitored by fail2ban)
- systemd services: Logged to journal (`journalctl -u service-name`)
- Approach: Centralized syslog; no external log aggregation (single server)

**Validation:**
- Nginx rate limiting: Per-IP request counts checked against zones
- Anubis PoW: Cryptographic verification of client-computed hash
- CV data: YAML schema validation (basic, via `yaml.safe_load()`)
- File uploads: None (static content only)

**Authentication:**
- No user authentication on public routes
- SSH only: Key-based authentication (no password)
- Internal services (Grafana, monitoring): Not exposed to internet

**Caching:**
- Static HTML (landing, portfolio): `expires: -1` (no caching, always fresh)
- Static assets (images, fonts): `expires: 30d` with `immutable` flag (browser cache)
- PDFs (CV): `max-age: 3600` (1 hour, then revalidate)
- Docker images: Pulled fresh on each deploy (no local cache reuse)

---

*Architecture analysis: 2026-03-20*
