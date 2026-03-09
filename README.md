# Portfolio Infrastructure — asanchezbl.dev

Infrastructure-as-Code and deployment automation behind my personal portfolio at [asanchezbl.dev](https://asanchezbl.dev). Everything here — from DNS records to systemd units — is reproducible from scratch with Terraform and Ansible.

## Live

| URL | What |
|-----|------|
| [asanchezbl.dev](https://asanchezbl.dev) | Landing page |
| [asanchezbl.dev/cv](https://asanchezbl.dev/cv) | CV — PDF preview + download (ES / EN / CA) |
| [asanchezbl.dev/portfolio](https://asanchezbl.dev/portfolio) | Portfolio |
| [asanchezbl.dev/demo/serp](https://asanchezbl.dev/demo/serp) | SERP — Emergency Response System (live demo) |
| [asanchezbl.dev/demo/catlink](https://asanchezbl.dev/demo/catlink) | CatLink — AI EV Charger Agent (live demo) |

## Architecture

```
Internet
   │
   ▼
Cloudflare (DNS-only, grey-cloud)
   │
   ▼
AWS EC2 t4g.small — eu-west-1 (ARM64/Graviton)
   │
   ├── Nginx :80/:443  (SSL via Let's Encrypt / Certbot)
   │      │
   │      ▼
   ├── Anubis :8923   (PoW WAF — blocks AI scrapers & bots)
   │      │
   │      ▼
   ├── Nginx :8080    (internal — clean traffic only)
   │      ├── /cv/          → CV service :8001  (FastAPI + WeasyPrint)
   │      ├── /demo/serp/   → SERP frontend :3001
   │      ├── /demo/catlink/→ CatLink frontend :3002
   │      ├── /demo/*/api/  → SERP API :5001 / CatLink API :8002
   │      └── /             → static files (landing, portfolio, assets)
   │
   ├── Docker Compose
   │      ├── SERP (FastAPI + React + PostgreSQL, Nokia API mocked)
   │      └── CatLink (FastAPI + React + Gemini mocked)
   │
   └── Security
          ├── UFW — ports 80, 443, 2222 only
          ├── fail2ban — SSH + Nginx brute-force protection
          └── Anubis — PoW challenge (difficulty 6) for all proxied routes
```

Pre-built ARM64 Docker images are built locally and pushed to Docker Hub (`caballosanex/*`), then pulled on the server — the EC2 instance never builds images (OOM prevention on 2 GB RAM).

## Stack

| Layer | Technology |
|-------|-----------|
| Cloud | AWS EC2 (t4g.small), Elastic IP, AWS Budgets |
| DNS | Cloudflare (DNS-only) |
| IaC | Terraform — VPC, EC2, security groups, EIP, budget alerts |
| Config management | Ansible — 11 roles, idempotent full-stack deployment |
| Reverse proxy / SSL | Nginx + Certbot (Let's Encrypt, auto-renewal) |
| WAF | Anubis (Proof-of-Work bot mitigation) |
| CV service | Python / FastAPI + WeasyPrint + SQLite visit counter |
| Demos | Docker Compose (SERP + CatLink) |
| OS | Ubuntu 24.04 LTS (ARM64) |

## Repository Structure

```
.
├── terraform/              # AWS infrastructure (VPC, EC2, EIP, budget)
│   ├── vpc.tf
│   ├── ec2.tf
│   ├── security_groups.tf
│   ├── dns.tf              # Cloudflare DNS records
│   ├── budget.tf           # AWS Budgets alert (<$15/month)
│   ├── variables.tf
│   ├── terraform.tfvars.example
│   └── state-bootstrap/    # S3 + DynamoDB for remote state
│
├── ansible/
│   ├── playbooks/
│   │   ├── site.yml        # Full deploy (base + apps)
│   │   ├── base.yml        # System setup only
│   │   └── deploy.yml      # App deploy only
│   ├── inventory/
│   │   ├── hosts.yml
│   │   └── group_vars/all.yml
│   └── roles/
│       ├── base            # Packages, system config
│       ├── security        # SSH hardening, UFW, fail2ban
│       ├── docker          # Docker CE (ARM64)
│       ├── nginx           # Nginx config (double-proxy setup)
│       ├── certbot         # SSL certificates
│       ├── anubis          # PoW WAF
│       ├── deploy-landing  # Landing page static files
│       ├── deploy-cv       # CV FastAPI service + systemd unit
│       ├── deploy-portfolio# Portfolio static files
│       ├── deploy-serp     # SERP Docker Compose
│       ├── deploy-catlink  # CatLink Docker Compose
│       └── demo-reset      # Cron: reset demo data every 6h
│
├── nginx/
│   └── conf.d/asanchezbl.dev.conf   # Full Nginx config with security headers
│
├── web/
│   ├── landing/            # index.html, robots.txt, sitemap.xml
│   ├── portfolio/          # index.html, style.css
│   └── cv-service/         # FastAPI app, Jinja2 templates, YAML CV data
│       ├── app.py
│       ├── data/           # cv_es.yml, cv_en.yml, cv_ca.yml
│       ├── templates/      # cv.html (PDF), cv_page.html (web UI)
│       └── static/         # cv.js
│
├── docker/
│   ├── serp/               # docker-compose.yml + Nokia API mock patches
│   └── catlink/            # docker-compose.yml + Gemini/Nokia mock patches
│
└── scripts/
    ├── build-and-push.sh   # Build ARM64 images locally, push to Docker Hub
    └── reset-demos.sh      # Reset demo DBs (run by cron on server)
```

## Deploy

### Prerequisites

- Terraform ≥ 1.5
- Ansible ≥ 2.15
- AWS CLI configured (`aws configure`)
- Cloudflare API token with DNS edit permissions
- SSH key pair

### 1 — Infrastructure (Terraform)

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
# Fill in: cloudflare_api_token, cloudflare_zone_id, ssh_public_key_path

cd terraform
terraform init
terraform apply
```

### 2 — Full server setup + deploy (Ansible)

```bash
cd ansible
ansible-playbook playbooks/site.yml
```

This installs and configures everything on the EC2 instance in one shot: packages, SSH hardening, firewall, Nginx, SSL, Anubis, CV service, Docker demos, cron jobs.

### 3 — Rebuild demo Docker images

Only needed when demo source code changes:

```bash
./scripts/build-and-push.sh
ansible-playbook ansible/playbooks/site.yml
```

## Security

- SSH on port 2222, key-only auth, root login disabled
- UFW: only ports 80, 443, 2222 open
- fail2ban: blocks after 3 failed SSH attempts, monitors Nginx logs
- Anubis WAF (difficulty 6): PoW challenge for all proxied routes — filters AI crawlers, headless browsers, scrapers
- Nginx security headers: HSTS, CSP, X-Frame-Options, Permissions-Policy, `server_tokens off`
- All demo APIs run on localhost-only ports, never directly exposed

## Cost

Targeting < $15 USD/month on AWS:

| Resource | ~Cost |
|----------|-------|
| EC2 t4g.small (eu-west-1) | ~$12/mo |
| EBS 8 GB gp3 | ~$0.65/mo |
| Elastic IP | $0 (attached) |
| Data transfer | ~$0.50/mo |
| Cloudflare DNS | Free |

AWS Budgets alert configured at $15/month threshold.
