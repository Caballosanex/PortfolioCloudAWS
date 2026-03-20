# Codebase Structure

**Analysis Date:** 2026-03-20

## Directory Layout

```
PortfolioCloudAWS/
├── terraform/              # AWS infrastructure as code
│   ├── vpc.tf              # VPC, subnet, internet gateway, route table
│   ├── ec2.tf              # EC2 instance, Elastic IP, SSH key pair
│   ├── security_groups.tf  # Security group rules (80, 443, 2222)
│   ├── dns.tf              # Cloudflare DNS A records
│   ├── budget.tf           # AWS Budgets alert (<$15/month)
│   ├── providers.tf        # Terraform providers (AWS, Cloudflare)
│   ├── variables.tf        # Input variables (AWS region, instance type, etc.)
│   ├── outputs.tf          # Output values (EC2 IP, instance ID)
│   ├── terraform.tfvars    # Variable values (user-filled)
│   ├── .terraform/         # Terraform working directory (generated)
│   └── state-bootstrap/    # Bootstrap scripts for S3 remote state
│
├── ansible/                # Configuration management
│   ├── playbooks/
│   │   ├── site.yml        # Full deployment (calls all roles)
│   │   ├── base.yml        # System setup only
│   │   └── deploy.yml      # App deployment only
│   ├── inventory/
│   │   ├── hosts.yml       # EC2 host definition (IP, port, SSH key)
│   │   └── group_vars/
│   │       └── all.yml     # Shared variables (domain, ports, directories)
│   ├── roles/
│   │   ├── base/           # Core packages, system config
│   │   ├── security/       # SSH hardening, UFW, fail2ban
│   │   ├── docker/         # Docker CE installation (ARM64)
│   │   ├── nginx/          # Nginx installation & config
│   │   ├── certbot/        # Let's Encrypt SSL certificate
│   │   ├── anubis/         # PoW WAF installation
│   │   ├── deploy-landing/ # Landing page static files
│   │   ├── deploy-cv/      # CV FastAPI service
│   │   ├── deploy-portfolio/ # Portfolio static files
│   │   ├── deploy-serp/    # SERP Docker Compose
│   │   ├── deploy-catlink/ # CatLink Docker Compose
│   │   └── demo-reset/     # Cron job for demo reset
│   ├── templates/          # Jinja2 templates for Ansible tasks
│   └── files/              # Static files copied to EC2
│
├── nginx/                  # Nginx configuration
│   └── conf.d/
│       └── asanchezbl.dev.conf # Full server block (SSL, routing, security headers)
│
├── web/                    # Web application source code
│   ├── landing/            # Landing page
│   │   ├── index.html      # Main landing page (hero, nav, links)
│   │   ├── robots.txt      # SEO robots rules
│   │   ├── sitemap.xml     # SEO sitemap
│   │   ├── favicon.svg     # Browser favicon
│   │   └── .well-known/    # ACME challenge directory (Certbot)
│   ├── portfolio/          # Portfolio web app
│   │   ├── index.html      # Portfolio SPA (project showcase)
│   │   └── style.css       # Portfolio styles
│   └── cv-service/         # CV FastAPI service
│       ├── app.py          # FastAPI application (endpoints, PDF generation)
│       ├── requirements.txt # Python dependencies (FastAPI, WeasyPrint, etc.)
│       ├── data/           # CV content
│       │   ├── cv_es.yml   # Spanish CV (YAML)
│       │   ├── cv_en.yml   # English CV (YAML)
│       │   └── cv_ca.yml   # Catalan CV (YAML)
│       ├── templates/      # Jinja2 HTML templates
│       │   ├── cv.html     # CV template (rendered to PDF)
│       │   └── cv_page.html # CV web UI (language selector, download buttons)
│       ├── static/         # Client-side assets
│       │   ├── cv.js       # CV page JavaScript
│       │   ├── pdf.min.js  # PDF.js library (PDF canvas rendering)
│       │   └── pdf.worker.min.js # PDF.js worker thread
│       └── generated/      # Pre-generated PDFs (cache directory)
│
├── docker/                 # Docker Compose configurations
│   ├── serp/               # SERP Emergency Response System
│   │   ├── docker-compose.yml # SERP services definition (backend, frontend)
│   │   ├── mock_backend.py # Mocked FastAPI backend (no Nokia APIs)
│   │   └── mock_requirements.txt # SERP backend dependencies
│   └── catlink/            # CatLink EV Charger Agent
│       ├── docker-compose.yml # CatLink services definition
│       └── [other configs]
│
├── scripts/                # Deployment and utility scripts
│   ├── build-and-push.sh   # Build ARM64 Docker images, push to Docker Hub
│   └── reset-demos.sh      # Reset demo databases (called by cron)
│
├── assets/                 # Static media assets
│   ├── images/             # Icons, logos
│   ├── photos/             # Portfolio project screenshots
│   └── certificates/       # Certification images
│
├── mfkey/                  # mfkey project documentation
├── NAS_Ismael_Prego/       # NAS proposal documentation
├── CVs_pdte_actualizar/    # Old CV files (for reference)
│
├── .planning/              # GSD planning documents (generated)
│   └── codebase/           # Codebase analysis documents
│
├── .git/                   # Git repository
├── .gitignore              # Git ignore rules
├── .env (if exists)        # NOT COMMITTED - environment secrets
│
├── README.md               # Main repository documentation
└── CLAUDE.md               # Project specifications and requirements

```

## Directory Purposes

**`terraform/`:**
- Purpose: Define and manage AWS cloud infrastructure
- Contains: AWS resource definitions (VPC, EC2, security groups, EIP, Cloudflare DNS, budgets)
- Key files: `vpc.tf` (networking), `ec2.tf` (instance), `security_groups.tf` (firewall rules)
- Executed by: `terraform apply` (creates resources in AWS account 649966626787)

**`ansible/`:**
- Purpose: Configure EC2 instance and deploy all services
- Contains: Playbooks, roles, inventory, templates
- Key files: `playbooks/site.yml` (orchestrator), `inventory/hosts.yml` (target host), `roles/*/tasks/main.yml` (task definitions)
- Executed by: `ansible-playbook playbooks/site.yml` (configures EC2 after Terraform provision)

**`nginx/`:**
- Purpose: Reverse proxy and SSL termination configuration
- Contains: Single Nginx site config with routing logic, rate limiting, security headers
- Key files: `conf.d/asanchezbl.dev.conf` (complete Nginx config for asanchezbl.dev)
- Deployed by: `ansible/roles/nginx/` role (copied to `/etc/nginx/sites-available/asanchezbl.dev`)

**`web/`:**
- Purpose: Web application source code (landing, portfolio, CV service)
- Contains: HTML/CSS/JS for landing and portfolio, Python FastAPI app for CV service
- Subdirectories:
  - `landing/`: Static landing page (index.html, robots.txt, sitemap.xml)
  - `portfolio/`: Static portfolio SPA (index.html, style.css)
  - `cv-service/`: FastAPI app with Jinja2 templates, YAML data, SQLite counter

**`docker/`:**
- Purpose: Docker Compose definitions and mock backend code for demo services
- Contains: docker-compose.yml files for SERP and CatLink, mocked Nokia APIs, patched requirements
- Key files:
  - `serp/docker-compose.yml`: SERP backend + frontend services
  - `serp/mock_backend.py`: Replaces original FastAPI main.py (disables Nokia API calls)
  - `catlink/docker-compose.yml`: CatLink backend + frontend services

**`scripts/`:**
- Purpose: Deployment and maintenance automation
- Contains: Bash scripts for building Docker images and resetting demo data
- Key files:
  - `build-and-push.sh`: Clones SERP/CatLink, applies patches, builds ARM64 images, pushes to Docker Hub
  - `reset-demos.sh`: Connects to Docker containers, resets demo databases (called by cron every 6h)

**`assets/`:**
- Purpose: Static media assets (images, photos, certificates)
- Contains: Images used on landing page, portfolio screenshots, certification PDFs
- Caching: Served with `expires: 30d` and `immutable` flag

**`mfkey/`, `NAS_Ismael_Prego/`, `CVs_pdte_actualizar/`, `Weather_master Screenshots/`, `Certificaciones/`, `photos/`:**
- Purpose: Reference documentation and media for portfolio content
- Contains: Project documentation, screenshots, certification images
- Status: Reference only; some content appears in portfolio

## Key File Locations

**Entry Points:**

- `terraform/` — Infrastructure initialization (`terraform init && terraform apply`)
- `ansible/playbooks/site.yml` — Full deployment orchestrator
- `ansible/inventory/hosts.yml` — EC2 target host definition (IP: 34.250.192.166, port: 2222)
- `web/landing/index.html` — Landing page (served as root `/`)
- `web/cv-service/app.py` — CV FastAPI service (entry point: `uvicorn app:app`)

**Configuration:**

- `terraform/terraform.tfvars` — Terraform variables (AWS region, instance type, Cloudflare token)
- `ansible/inventory/group_vars/all.yml` — Shared Ansible variables (domain, ports, directories)
- `nginx/conf.d/asanchezbl.dev.conf` — Complete Nginx configuration (routing, SSL, rate limiting, security headers)
- `web/cv-service/data/cv_*.yml` — CV content in YAML format (3 languages: es, en, ca)

**Core Logic:**

- `ansible/roles/docker/tasks/main.yml` — Docker CE installation for ARM64
- `ansible/roles/nginx/tasks/main.yml` — Nginx installation and configuration
- `ansible/roles/deploy-cv/tasks/main.yml` — CV service deployment (systemd unit, venv setup)
- `ansible/roles/anubis/tasks/main.yml` — Anubis WAF installation and systemd unit
- `web/cv-service/app.py` — FastAPI endpoints (CV preview, download, visit counter)
- `scripts/build-and-push.sh` — Docker image build and push pipeline
- `docker/serp/mock_backend.py` — Mocked SERP backend (replaces Nokia API calls)

**Testing:**

- No automated test suite present; manual testing via browser

## Naming Conventions

**Files:**

- Ansible role directories: `kebab-case` (e.g., `deploy-cv`, `deploy-serp`)
- Terraform files: `snake_case` (e.g., `security_groups.tf`, `state-bootstrap`)
- Python files: `snake_case` (e.g., `mock_backend.py`, `mock_nokia_patch.py`)
- HTML files: `index.html` (standard), `cv_page.html` (CV service web UI), `cv.html` (CV PDF template)
- YAML files: Lowercase with underscores (e.g., `cv_es.yml`, `cv_en.yml`, `cv_ca.yml`)
- Bash scripts: `.sh` extension (e.g., `build-and-push.sh`, `reset-demos.sh`)

**Directories:**

- Cloud resources: `terraform/`
- Automation: `ansible/`
- Web apps: `web/`
- Containerization: `docker/`
- Utilities: `scripts/`
- Documentation: `.planning/codebase/` (generated), root `.md` files

**Variables & Functions (Python):**

- FastAPI: Endpoints as lowercase paths (e.g., `@app.get("/")`), functions as `snake_case` (e.g., `generate_pdf()`, `increment_visits()`)
- Ansible: Variables as lowercase/kebab-case (e.g., `domain`, `base_dir`, `anubis_port`)
- Terraform: Resource names as kebab-case (e.g., `aws_security_group.web`, `aws_instance.web`)

## Where to Add New Code

**New Feature (e.g., add a page to landing):**
- Edit: `web/landing/index.html` (add HTML structure)
- Edit: `web/landing/style.css` (if new styles needed; currently used elsewhere but landing may need custom styles)
- Deploy: `ansible-playbook playbooks/site.yml --tags deploy-landing`

**New CV Section (e.g., add skills):**
- Edit: `web/cv-service/data/cv_es.yml`, `cv_en.yml`, `cv_ca.yml` (add YAML section)
- Edit: `web/cv-service/templates/cv.html` (add HTML rendering for new section)
- Regenerate PDFs: Delete files in `web/cv-service/generated/` and restart CV service (automatic on next request)
- Deploy: `ansible-playbook playbooks/site.yml --tags deploy-cv`

**New Portfolio Project:**
- Edit: `web/portfolio/index.html` (add project card, link, description)
- Edit: `web/portfolio/style.css` (if new styles needed)
- Add: Screenshots to `assets/photos/` or `assets/images/`
- Deploy: `ansible-playbook playbooks/site.yml --tags deploy-portfolio`

**New Static Asset:**
- Add file to: `assets/images/` (icons, logos) or `assets/photos/` (screenshots)
- Reference in: `web/landing/index.html` or `web/portfolio/index.html`
- Caching: Will be served with `expires: 30d` (see `nginx/conf.d/asanchezbl.dev.conf`, line 58-61)
- Deploy: `ansible-playbook playbooks/site.yml --tags deploy-landing`

**New Ansible Role (e.g., monitoring):**
- Create: `ansible/roles/monitoring/tasks/main.yml` (task definitions)
- Create: `ansible/roles/monitoring/handlers/main.yml` (handlers for service restarts)
- Add to: `ansible/playbooks/site.yml` (include role in appropriate play)
- Execute: `ansible-playbook playbooks/site.yml --tags monitoring`

**New Terraform Resource (e.g., S3 bucket for backups):**
- Create: `terraform/s3.tf` (new resource definitions)
- Add to: `terraform/variables.tf` (if new input variables needed)
- Add to: `terraform/outputs.tf` (export resource attributes)
- Apply: `cd terraform && terraform plan && terraform apply`

**New Docker Service (e.g., add monitoring stack):**
- Create: `docker/monitoring/docker-compose.yml`
- Create: `ansible/roles/deploy-monitoring/tasks/main.yml` (pulls images, starts containers)
- Update: `nginx/conf.d/asanchezbl.dev.conf` (add location block for proxy to new service)
- Update: `ansible/playbooks/site.yml` (add new role)
- Build images: `./scripts/build-and-push.sh` (if custom images needed)
- Deploy: `ansible-playbook playbooks/site.yml`

## Special Directories

**`.planning/codebase/`:**
- Purpose: GSD (Go, Ship, Deploy) codebase analysis documents
- Generated: By `/gsd:map-codebase` command
- Committed: Yes (part of project documentation)
- Contents: ARCHITECTURE.md, STRUCTURE.md, CONVENTIONS.md, TESTING.md, STACK.md, INTEGRATIONS.md, CONCERNS.md (as applicable)

**`.terraform/`:**
- Purpose: Terraform working directory (provider binaries, cache, state)
- Generated: By `terraform init`
- Committed: No (in `.gitignore`)
- Note: Remote state stored in S3 + DynamoDB (see `terraform/state-bootstrap/`)

**`web/cv-service/generated/`:**
- Purpose: Pre-generated PDF caches
- Generated: By FastAPI startup and on-demand
- Committed: No (generated at runtime)
- Cleared: Automatically when CV data changes and role is re-applied

**`web/cv-service/venv/`:**
- Purpose: Python virtual environment (after Ansible deployment)
- Generated: By `python3 -m venv` in deploy role
- Committed: No
- Contains: pip packages (FastAPI, WeasyPrint, YAML parser, etc.)

**`ansible/roles/*/templates/` and `ansible/roles/*/files/`:**
- Purpose: Jinja2 templates and static files for Ansible tasks
- Committed: Yes
- Used by: `copy` and `template` tasks in role `tasks/main.yml`

**`docker/serp/` and `docker/catlink/`:**
- Purpose: Docker Compose and mock backend code
- Contents: docker-compose.yml, mock_*.py files, requirements.txt
- Used by: `scripts/build-and-push.sh` (applies patches before building images)
- Committed: Yes

---

*Structure analysis: 2026-03-20*
