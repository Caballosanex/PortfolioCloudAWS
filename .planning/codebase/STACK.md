# Technology Stack

**Analysis Date:** 2026-03-20

## Languages

**Primary:**
- Python 3 - CV service (FastAPI), WeasyPrint PDF generation, data validation
- JavaScript/HTML/CSS - Landing page, portfolio, static web content
- TypeScript/React - SERP frontend and CatLink frontend (in Docker images)
- HCL (Terraform) - Infrastructure as Code
- YAML - Ansible configuration, CV data files
- Bash - Build and deployment scripts

**Secondary:**
- Go (CatLink backend) - HTTP server and AI agent orchestration (in Docker images)
- FastAPI/Python (SERP backend) - REST API server (in Docker images)

## Runtime

**Environment:**
- Ubuntu 24.04 LTS (ARM64) - Base OS on EC2
- Python 3.10+ (system) and isolated venv for CV service
- Node.js (in SERP/CatLink frontend containers, built into Docker images)

**Package Manager:**
- pip (Python) - used in venv for Python dependencies
- npm/yarn (in Docker containers for React frontend builds)
- apt (Ubuntu package manager)

**Lockfile:**
- `terraform.lock.hcl` - Terraform provider versions locked
- `requirements.txt` - Python dependencies pinned at `web/cv-service/requirements.txt`

## Frameworks

**Core:**
- FastAPI 0.104+ - CV service (lightweight, async Python web framework)
- Uvicorn - ASGI server for FastAPI
- Jinja2 - HTML template engine for PDF/HTML rendering
- Nginx 1.18+ - Reverse proxy, SSL/TLS termination, static file serving

**Testing:**
- None detected in codebase

**Build/Dev:**
- Terraform 1.0+ - Infrastructure provisioning
- Ansible 2.15+ - Configuration management and deployment
- Docker & Docker Compose - Container orchestration for SERP and CatLink demos
- Certbot 2.x - SSL certificate automation (Let's Encrypt)

## Key Dependencies

**Critical:**
- FastAPI ~0.104 - async web framework for CV service
- Uvicorn - ASGI application server (`web/cv-service/requirements.txt`)
- Jinja2 - template rendering for HTML/PDF (`web/cv-service/requirements.txt`)
- WeasyPrint 61.2 - PDF generation from HTML templates (`web/cv-service/requirements.txt`)
  - Depends on libpango, libgdk-pixbuf, libgobject (installed via Ansible)
  - Depends on system fonts (fonts-liberation, fonts-dejavu-core)
- pydyf 0.10.0 - PDF backend helper for WeasyPrint

**Infrastructure:**
- Terraform AWS provider ~5.0 - AWS resource management
- Terraform Cloudflare provider ~4.0 - DNS record management
- Anubis WAF - HTTP reverse proxy with Proof-of-Work challenge (external binary, installed via Ansible)
- fail2ban 0.11.x - intrusion prevention system (installed via apt)
- UFW (Uncomplicated Firewall) - Linux firewall frontend (installed via apt)

**Demo Applications (containerized):**
- SERP: FastAPI, React, PostgreSQL (in Docker)
- CatLink: Go (backend), React (frontend) (in Docker)

## Configuration

**Environment:**
- Terraform variables file: `terraform/terraform.tfvars` (not in repo, template: `terraform/terraform.tfvars.example`)
  - Sensitive: cloudflare_api_token, cloudflare_zone_id
  - Public: aws_region (eu-west-1), instance_type (t4g.small), ssh_port (2222), domain (asanchezbl.dev)
- Ansible inventory: `ansible/inventory/hosts.yml`, `ansible/inventory/group_vars/all.yml`
- Docker Compose environment variables: inline in `docker/serp/docker-compose.yml` and `docker/catlink/docker-compose.yml`
  - `NOKIA_MOCK_MODE=true` for CatLink to disable real Nokia API calls
  - `DEBUG=0` for SERP backend production mode

**Build:**
- `terraform/` - All Terraform configuration files (providers, AWS resources, Cloudflare DNS)
- `ansible/playbooks/` - Ansible playbooks (site.yml orchestrates all roles)
- `ansible/roles/*/tasks/main.yml` - Task definitions for each deployment stage
- `nginx/conf.d/asanchezbl.dev.conf` - Complete Nginx configuration (reverse proxy, SSL, security headers)
- `docker/serp/docker-compose.yml` - SERP container orchestration
- `docker/catlink/docker-compose.yml` - CatLink container orchestration
- `scripts/build-and-push.sh` - Multi-stage ARM64 Docker image builds + Docker Hub push
- `scripts/reset-demos.sh` - Demo data reset for scheduled jobs (cron)

## Platform Requirements

**Development:**
- Terraform ≥ 1.5
- Ansible ≥ 2.15
- AWS CLI (configured with credentials)
- Cloudflare account with API token and zone ID for asanchezbl.dev
- SSH key pair for EC2 access (default path: `~/.ssh/id_rsa.pub`)
- Docker & Docker Compose (for local builds of SERP/CatLink images)
- Git

**Production:**
- **Cloud Provider:** AWS EC2 t4g.small (ARM64/Graviton2) in eu-west-1 (Ireland)
  - 2 GB RAM
  - 20 GB gp3 EBS root volume (encrypted)
  - Elastic IP: 34.250.192.166 (managed by Terraform)
- **DNS:** Cloudflare (DNS-only, grey-cloud mode — CNAME points to Elastic IP)
- **OS:** Ubuntu 24.04 LTS (ARM64) — latest available AMI queried by Terraform
- **Deployment:** Ansible from local development machine (SSH to port 2222 on EIP)
- **Container Registry:** Docker Hub (images pulled from `docker.io/caballosanex/*`)

## Cost & Budget

- Monthly target: < $15 USD/month on AWS
- Tracked via AWS Budgets alert (terraform/budget.tf)
- Breakdown:
  - EC2 t4g.small: ~$12/month
  - EBS gp3 20GB: ~$0.65/month
  - Elastic IP: $0 (not charged when attached)
  - Data transfer: ~$0.50/month
  - Cloudflare DNS: Free
  - Route53: Not used (DNS via Cloudflare)

---

*Stack analysis: 2026-03-20*
