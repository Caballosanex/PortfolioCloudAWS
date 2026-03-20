# External Integrations

**Analysis Date:** 2026-03-20

## APIs & External Services

**Cloud Infrastructure:**
- AWS (EC2, Elastic IP, EBS, IAM, Budgets, S3 for Terraform state)
  - SDK/Client: Terraform AWS Provider ~5.0
  - Auth: AWS Access Keys (via `aws configure`)
- Cloudflare DNS
  - SDK/Client: Terraform Cloudflare Provider ~4.0
  - Auth: `cloudflare_api_token` (env var or tfvars)

**Demo Application APIs (Mocked):**
- **SERP (Emergency Response System):**
  - Nokia QoS API — **MOCKED** via environment variable bypass
  - SERP runs in Docker with mock backend (no real PostgreSQL required)
  - Config: `docker/serp/docker-compose.yml`
  - See MEMORY.md [serp-analysis.md] for mock implementation details

- **CatLink (AI EV Charger Agent):**
  - Nokia Location Verification API — **MOCKED** via `NOKIA_MOCK_MODE=true`
  - Nokia Number Verification API — **MOCKED**
  - Nokia SIM Swap Detection — **MOCKED**
  - Nokia QoD (Quality of Service) — **MOCKED**
  - Google Gemini AI (agent orchestration) — **MOCKED** (responses hardcoded/predefined)
  - Config: `docker/catlink/docker-compose.yml`
  - See MEMORY.md [catlink-analysis.md] for mock implementation details

## Data Storage

**Databases:**
- **CV Service Visit Counter:**
  - Type: SQLite (local file-based)
  - Location: `web/cv-service/visits.db` (created at runtime by `web/cv-service/app.py`)
  - Client: Python sqlite3 module
  - Purpose: Track global visit count to CV page

- **SERP Demo:**
  - Type: PostgreSQL (in Docker, for live demo)
  - Status: **Not running on production** — uses in-memory mock backend for demo
  - Container: `docker.io/caballosanex/serp-backend:latest`

- **CatLink Demo:**
  - Type: In-memory / mocked
  - Status: All data is mock, no persistent database
  - Container: `docker.io/caballosanex/catlink-backend:latest`

**File Storage:**
- **Static Assets:** Served locally from EC2 filesystem via Nginx
  - Landing page: `/var/www/landing/` (static HTML, robots.txt, sitemap.xml)
  - Portfolio: `/var/www/portfolio/` (static HTML, CSS)
  - Assets: `/var/www/assets/` (photos, certificates, images)
  - CV service: `/opt/www/cv-service/` (Jinja2 templates, generated PDFs)

- **Generated PDFs:** Cached on filesystem
  - Location: `web/cv-service/generated/` (on server: `/opt/www/cv-service/generated/`)
  - Files: `CV_Alex_Sanchez_Blabia_{ES,EN,CA}.pdf`

**Caching:**
- HTTP cache headers via Nginx (public, max-age=3600 for CV PDFs; immutable for static assets)
- No Redis or Memcached — relies on HTTP caching and filesystem

## Authentication & Identity

**Auth Provider:** None (public website)
- Landing page, portfolio, CV, and demos are publicly accessible
- SSH access to EC2 uses key-only authentication (configured via `ansible/roles/security/tasks/main.yml`)
  - SSH port: 2222 (custom, non-standard)
  - Username: ubuntu
  - Auth method: Public key only (PasswordAuthentication=no)
  - Root login disabled

**No user authentication system:**
- CV visitor counter is unauthenticated and global (single SQLite row)
- Demo data (SERP, CatLink) is public, shared across all visitors

## Monitoring & Observability

**Error Tracking:** None detected
- No Sentry, Rollbar, or similar service

**Logs:**
- **SSH & Firewall:** `/var/log/auth.log` (monitored by fail2ban)
- **Nginx:** `/var/log/nginx/error.log` and `/var/log/nginx/access.log`
- **systemd services:** journalctl (CV service logs)
- **Centralized logging:** Not in place

**Removed from production:**
- Prometheus (monitoring)
- Grafana (dashboards)
- Node Exporter (metrics)
- These were planned but removed due to 2 GB RAM constraint on t4g.small

## CI/CD & Deployment

**Hosting:**
- AWS EC2 t4g.small (eu-west-1)
- Elastic IP: 34.250.192.166
- DNS: Cloudflare (points asanchezbl.dev to EIP)

**Deployment Pipeline:**
- **IaC:** Terraform (local apply against AWS)
  - State stored in S3 bucket `asanchezbl-terraform-state` with DynamoDB lock
  - Bootstrap: `terraform/state-bootstrap/main.tf` creates S3 + DynamoDB
  - Main: `terraform/` provisions VPC, EC2, Security Groups, EIP, Route53-like DNS records

- **Configuration Management:** Ansible (local playbook execution)
  - Playbook: `ansible/playbooks/site.yml` orchestrates 11 roles
  - Inventory: `ansible/inventory/hosts.yml` (single portfolio host)
  - Execution: `ansible-playbook playbooks/site.yml` from developer machine

- **Container Builds:** Local + Docker Hub (manual)
  - Script: `scripts/build-and-push.sh` builds multi-stage ARM64 images locally
  - Push: Images pushed to Docker Hub (`docker.io/caballosanex/serp-backend`, `caballosanex/catlink-backend`, etc.)
  - EC2 deployment: `docker-compose pull && docker-compose up -d`

- **CI Server:** None (no GitHub Actions, GitLab CI, or Jenkins)
  - Deployments are manual: run Terraform, run Ansible

- **No automated testing pipeline**

## Security & Secrets

**TLS/SSL:**
- Let's Encrypt (ACME protocol)
- Certificate manager: Certbot
- Renewal: Automated via systemd timer or cron (configured by `ansible/roles/certbot/tasks/main.yml`)
- Certificates: `/etc/letsencrypt/live/asanchezbl.dev/`
- Nginx config includes: `include /etc/letsencrypt/options-ssl-nginx.conf`

**WAF:**
- Anubis (external PoW-based WAF)
  - Proof-of-Work difficulty: 6
  - Purpose: Mitigate AI scrapers, bots, headless browsers
  - Implementation: Deployed as systemd service (configured via `ansible/roles/anubis/tasks/main.yml`)
  - Runs on localhost port 8923
  - All external traffic proxied through Anubis before reaching Nginx

**Firewall:**
- UFW (Uncomplicated Firewall) — configured by `ansible/roles/security/tasks/main.yml`
  - Incoming: DENY (default)
  - Outgoing: ALLOW (default)
  - Open ports:
    - 80 (HTTP)
    - 443 (HTTPS)
    - 2222 (SSH custom port)
  - All other ports blocked

**Intrusion Prevention:**
- fail2ban
  - Monitors: SSH (port 2222) and Nginx logs
  - SSH rule: 3 failed attempts → 3600s (1h) ban
  - Nginx rule: 5 failed auth attempts → 3600s ban
  - Config: `/etc/fail2ban/jail.local` (deployed by Ansible)

**Secrets Management:**
- Terraform variables (sensitive):
  - `cloudflare_api_token` — marked sensitive in `terraform/variables.tf`
  - `cloudflare_zone_id` — not sensitive but deployment-specific
  - Stored in: `terraform/terraform.tfvars` (local, NOT in git)
- AWS credentials:
  - Via `aws configure` (standard AWS CLI config)
  - Credentials NOT in repository
- Environment variables (non-sensitive):
  - Ansible group_vars: `ansible/inventory/group_vars/all.yml`
  - Docker Compose: `docker/*/docker-compose.yml` (inline)

**Nginx Security Headers:**
- HSTS: `Strict-Transport-Security: max-age=31536000; includeSubDomains; preload`
- CSP: `Content-Security-Policy` with self-origin policy, Cloudflare Insights allowed
- X-Frame-Options: SAMEORIGIN
- X-Content-Type-Options: nosniff
- Referrer-Policy: strict-origin-when-cross-origin
- Permissions-Policy: disabled camera, microphone, geolocation, payment
- Server tokens hidden: `server_tokens off`
- See full config: `nginx/conf.d/asanchezbl.dev.conf` lines 158–165

## Webhooks & Callbacks

**Incoming Webhooks:** None
**Outgoing Webhooks:** None
- Website is read-only for visitors
- No integrations with external services that require callbacks

## Demo-Specific Integrations

**SERP Demo:**
- **Original Nokia APIs:** QoS for emergency vehicle network prioritization
- **Demo Mode:** Disabled/mocked in Docker image
- **How It Works:** SERP backend (FastAPI) patches/skips Nokia API calls, returns mock responses
- **Data:** Pre-loaded demo incidents and vehicle assignments

**CatLink Demo:**
- **Original Nokia APIs:** Location Verification, Number Verification, SIM Swap Detection, QoD
- **Demo Mode:** Enabled via `NOKIA_MOCK_MODE=true` environment variable
- **Gemini AI:** Original integration uses Google Gemini for agent decisions
- **Demo Mode:** Gemini calls are mocked with predefined agent responses
- **How It Works:** CatLink backend (Go) checks env vars, returns mock data instead of calling real APIs
- **Data:** Mock charger locations, fake EV owner profiles, predefined agent interactions

## Rate Limiting

**Nginx Configuration:**
- General: 30 requests/minute per IP (zone: general)
  - Burst: 10 requests
  - Soft reject: 429 status code
- CV Downloads (stricter): 5 requests/minute per IP (zone: cv_downloads)
  - Burst: 2 requests
  - Soft reject: 429 status code
- See: `nginx/conf.d/asanchezbl.dev.conf` lines 5–6, 70–72, 81–89

## Cost-Related Integrations

**AWS Budgets:**
- Alert threshold: $15/month (default, configurable in `terraform/variables.tf`)
- Configured via: `terraform/budget.tf`
- Notification: CloudWatch event (delivery method not specified in IaC)

---

*Integration audit: 2026-03-20*
