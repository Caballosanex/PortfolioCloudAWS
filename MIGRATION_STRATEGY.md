# Migration Strategy: EC2 Monolith → AWS Well-Architected Portfolio

> **Purpose**: Complete execution plan for an AI agent to perform a blue/green migration.  
> **Author**: Alex Sanchez Blabia  
> **Date**: 2026-06-26  
> **DO NOT PUSH** — internal planning document only.  
> **AWS Profile**: `--profile personal` for all AWS CLI commands.  
> **AWS Account**: 649966626787, region eu-west-1 (Ireland).

---

## 1. Current State (Red Environment)

Single EC2 `t4g.small` (ARM64, 2GB RAM, Ubuntu 24.04) in eu-west-1a running everything behind a double-proxy sandwich: Nginx (:443) → Anubis WAF (:8923) → Nginx internal (:8080) → services.

| Service | Type | Port | Notes |
|---------|------|------|-------|
| Nginx | Reverse proxy + static | :80/:443 → :8080 | Landing (44K), portfolio (60K), assets (17MB) |
| Anubis | PoW WAF binary | :8923 | systemd, v1.25.0 |
| CV Service | Python/FastAPI/WeasyPrint | :8001 | PDF generation + SQLite visit counter, systemd |
| SERP frontend | Docker `caballosanex/serp-frontend` | :3001 | React SPA via `serve` |
| SERP backend | Docker `caballosanex/serp-backend` | :5001 | Mock FastAPI, in-memory data, no DB |
| CatLink frontend | Docker `caballosanex/catlink-frontend` | :3002 | React/Vite SPA via `serve` |
| CatLink backend | Docker `caballosanex/catlink-backend` | :8002 | Mock FastAPI, SQLite, WebSocket at `/ws` |
| MatchCota frontend | Docker `caballosanex/matchcota-frontend` | :3003 | React/Vite SPA via `serve` |
| MatchCota backend | Docker `caballosanex/matchcota-backend` | :8003 | FastAPI, multi-tenant, needs Postgres |
| MatchCota DB | Docker `postgres:15-alpine` | :5432 | Persistent volume `matchcota_pgdata` |
| Demo reset cron | crontab every 6h | — | Restarts SERP + wipes CatLink SQLite |

**Other infra**: EIP 34.250.192.166, VPC 10.0.0.0/16, Cloudflare DNS (asanchezbl.dev), Certbot SSL, fail2ban, SSH on port 2222.

**Docker Hub account**: `caballosanex` — all 6 images are pre-built for ARM64.

**Build pipeline**: `scripts/build-and-push.sh` copies source repos to temp dir, patches frontend URLs/Dockerfiles/mock files, builds ARM64 images, pushes to Docker Hub.

**⚠️ SERP and CatLink source repos no longer exist on disk.** Only MatchCota exists at `/Users/alex/Documents/GITs/MatchCota/`. To obtain the frontend SPA builds for S3, extract them from the existing Docker images:
```bash
# Example for SERP frontend:
docker create --name tmp-serp caballosanex/serp-frontend:latest
docker cp tmp-serp:/app/build ./serp-frontend-build
docker rm tmp-serp
# CatLink uses /app/dist instead of /app/build (Vite):
docker create --name tmp-catlink caballosanex/catlink-frontend:latest
docker cp tmp-catlink:/app/dist ./catlink-frontend-build
docker rm tmp-catlink
# MatchCota also uses /app/dist:
docker create --name tmp-matchcota caballosanex/matchcota-frontend:latest
docker cp tmp-matchcota:/app/dist ./matchcota-frontend-build
docker rm tmp-matchcota
```
The frontend build args (API URLs, base paths, demo tenant) are already baked into these images. No rebuild needed.

**All Docker images are ARM64.** Every ECS task definition must specify:
```hcl
runtime_platform {
  operating_system_family = "LINUX"
  cpu_architecture        = "ARM64"
}
```
Without this, Fargate defaults to x86_64 and containers crash with exec format errors.

**Terraform**: Flat `.tf` files in `terraform/` (no modules), S3 backend (`asanchezbl-terraform-state`), manages VPC/EC2/EIP/SG/Cloudflare DNS/Budget.

**Existing Lambda**: `asanchezbl-portfolio-cost-reporter` (weekly Discord cost reports) — keep as-is, no migration needed.

---

## 2. Target State (Green Environment)

```
                         Internet
                            │
                            ▼
                    ┌───────────────┐
                    │  CloudFront   │  CDN + ACM SSL + throttling
                    │  Distribution │  + security headers
                    └──────┬────────┘
                           │
         ┌─────────────────┼──────────────────────┐
         │                 │                      │
         ▼                 ▼                      ▼
┌─────────────┐   ┌──────────────┐   ┌──────────────────────┐
│ S3 (static) │   │ Lambda       │   │ API Gateway HTTP API │
│             │   │ (cv-counter) │   │ (path rewrite + CORS │
│ - landing   │   │ + DynamoDB   │   │  + throttling)       │
│ - portfolio │   │              │   └──────────┬───────────┘
│ - CV PDFs   │   └──────────────┘              │ VPC Link
│ - assets    │                          ┌──────┴──────┐
│ - SERP SPA  │                          │ ECS Fargate │
│ - CatLink   │                          │ (Spot)      │
│   SPA       │                          │             │
│ - MatchCota │                          │ serp-be     │
│   SPA       │                          │ catlink-be  │
└─────────────┘                          │ matchcota-be│
                                         │  + postgres │
                                         │    sidecar  │
                                         │  + EFS vol  │
                                         └─────────────┘
```

**CatLink WebSocket**: Route `/demo/catlink/ws` through API Gateway HTTP API, same as the REST routes. API Gateway HTTP API supports WebSocket upgrade when the backend responds with `101 Switching Protocols` — the upgrade happens end-to-end through CloudFront → API Gateway → Fargate. This requires no special configuration beyond ensuring CloudFront forwards the `Connection`, `Upgrade`, and `Sec-WebSocket-*` headers (use a "All Viewer" origin request policy). If testing reveals API Gateway blocks the upgrade, the fallback is to replace the WebSocket with Server-Sent Events (SSE) in the CatLink mock agent code — SSE works natively through HTTP and provides the same real-time log streaming UX.

### Cost Estimate

| Service | Monthly Est. |
|---------|-------------|
| S3 (static hosting) | $0.03 |
| CloudFront (1TB free tier year 1) | $0.00-1.00 |
| ACM (free SSL) | $0.00 |
| API Gateway HTTP API | $0.01 |
| ECS Fargate Spot (3 tasks × 0.25 vCPU / 0.5GB) | $2-4 |
| EFS (MatchCota pgdata) | $0.05 |
| Cloud Map (service discovery) | $0.40 |
| DynamoDB (CV counter, free tier) | $0.00 |
| Lambda (counter + demo reset, free tier) | $0.00 |
| EventBridge (free) | $0.00 |
| ECR (500MB free tier) | $0.00 |
| **Total** | **~$3-6/month** |

No ALB (fixed $16.20/month — too expensive). No AWS WAF ($6/month — unnecessary for low-traffic portfolio). No NAT Gateway ($32/month). No RDS (free tier expires → $14/month time bomb). Rate limiting handled by API Gateway built-in throttling (free).

---

## 3. What Changes Per Service

### 3.1 Static Content → S3

Upload to S3 bucket (OAC, not public):
- `/var/www/landing/` → `s3://asanchezbl-static/` (root)
- `/var/www/portfolio/` → `s3://asanchezbl-static/portfolio/`
- `/var/www/assets/` → `s3://asanchezbl-static/assets/` (17MB: certificates, photos, docs)
- SERP SPA build → `s3://asanchezbl-static/demo/serp/`
- CatLink SPA build → `s3://asanchezbl-static/demo/catlink/`
- MatchCota SPA build → `s3://asanchezbl-static/demo/matchcota/`
- CV PDFs (3 files) → `s3://asanchezbl-static/cv/`
- CV static page → `s3://asanchezbl-static/cv/index.html`

### 3.2 SPA Frontends → S3 (not Docker anymore)

Currently, the 3 frontends are baked into Docker images with `serve`. After migration, they're static files on S3. The build script must be updated to:
1. Build each SPA normally (npm run build)
2. Upload the output to S3 under the correct prefix
3. NOT package them into Docker images

**Frontend build args stay the same** — all three use relative API paths baked at build time, which resolve against the same CloudFront domain:
- SERP: `REACT_APP_API_URL=/demo/serp/api`, `PUBLIC_URL=/demo/serp`, `basename="/demo/serp"`
- CatLink: `API_BASE='/demo/catlink/api'`, `base: '/demo/catlink/'`, WS URL uses `window.location.host` (resolves to `asanchezbl.dev` → CloudFront)
- MatchCota: `VITE_API_URL=/demo/matchcota/api/v1`, `VITE_DEMO_TENANT=demo`, `basename="/demo/matchcota"`

Since all content serves from the same CloudFront distribution under `asanchezbl.dev`, relative API paths work without CORS. No cross-origin issue.

**Demo banners**: Currently injected by Nginx `sub_filter`. After migration, inject this HTML before `</body>` in each SPA's `index.html` after extracting from Docker. Per-project banner text:

SERP:
```html
<div id="demo-banner" style="position:fixed;top:0;left:0;right:0;z-index:99999;background:#12121a;border-bottom:2px solid #6366f1;padding:8px 16px;display:flex;align-items:center;justify-content:space-between;font-family:Inter,sans-serif;font-size:13px;color:#e4e4e7"><div style="display:flex;align-items:center;gap:10px"><span style="background:#22c55e;color:#fff;padding:2px 8px;border-radius:4px;font-weight:600;font-size:11px">LIVE DEMO</span><span style="font-weight:500">SERP - Emergency Response System</span><span style="color:#8b8b9e;font-size:11px">ECS Fargate on AWS</span></div><div><a href="/portfolio#projects" style="color:#6366f1;text-decoration:none;font-size:12px">&larr; Back to Portfolio</a></div></div><style>body{padding-top:40px !important}.MuiAppBar-root{top:40px !important}.MuiDrawer-root .MuiDrawer-paper{top:40px !important;height:calc(100% - 40px) !important}</style>
```

CatLink:
```html
<div id="demo-banner" style="position:fixed;top:0;left:0;right:0;z-index:99999;background:#12121a;border-bottom:2px solid #6366f1;padding:8px 16px;display:flex;align-items:center;justify-content:space-between;font-family:Inter,sans-serif;font-size:13px;color:#e4e4e7"><div style="display:flex;align-items:center;gap:10px"><span style="background:#22c55e;color:#fff;padding:2px 8px;border-radius:4px;font-weight:600;font-size:11px">LIVE DEMO</span><span style="font-weight:500">CatLink - AI EV Charger Agent</span><span style="color:#8b8b9e;font-size:11px">ECS Fargate on AWS</span></div><div><a href="/portfolio#projects" style="color:#6366f1;text-decoration:none;font-size:12px">&larr; Back to Portfolio</a></div></div><style>body{padding-top:40px !important}</style>
```

MatchCota:
```html
<div id="demo-banner" style="position:fixed;top:0;left:0;right:0;z-index:99999;background:#12121a;border-bottom:2px solid #6366f1;padding:8px 16px;display:flex;align-items:center;justify-content:space-between;font-family:Inter,sans-serif;font-size:13px;color:#e4e4e7"><div style="display:flex;align-items:center;gap:10px"><span style="background:#22c55e;color:#fff;padding:2px 8px;border-radius:4px;font-weight:600;font-size:11px">LIVE DEMO</span><span style="font-weight:500">MatchCota - Pet Adoption Platform</span><span style="color:#8b8b9e;font-size:11px">ECS Fargate + PostgreSQL on AWS</span></div><div style="display:flex;gap:12px;align-items:center"><a href="/portfolio#projects" style="color:#6366f1;text-decoration:none;font-size:12px">&larr; Back to Portfolio</a><span style="color:#8b8b9e;font-size:11px">admin@matchcota.demo / demo123</span></div></div><style>body{padding-top:40px !important}</style>
```

**SPA routing**: A CloudFront Function (viewer-request event) must rewrite non-file paths to the correct `index.html` per SPA prefix. Attach to the default behavior:
```javascript
function handler(event) {
  var request = event.request;
  var uri = request.uri;
  // If the URI has a file extension, serve it as-is
  if (uri.match(/\.[a-zA-Z0-9]+$/)) return request;
  // Route SPA prefixes to their index.html
  if (uri.startsWith('/demo/serp'))     { request.uri = '/demo/serp/index.html'; }
  else if (uri.startsWith('/demo/catlink'))  { request.uri = '/demo/catlink/index.html'; }
  else if (uri.startsWith('/demo/matchcota')){ request.uri = '/demo/matchcota/index.html'; }
  else if (uri.startsWith('/portfolio'))     { request.uri = '/portfolio/index.html'; }
  else if (uri.startsWith('/cv'))            { request.uri = '/cv/index.html'; }
  return request;
}
```
Do NOT use CloudFront custom error pages (they can only return a single `index.html` for all paths). Use this function instead. **Note**: CloudFront evaluates cache behaviors by most-specific path pattern first, so `/cv/api/*`, `/demo/*/api/*`, and `/demo/catlink/ws` behaviors match before the default behavior where this SPA routing function runs. The function only fires for paths that reach the S3 origin.

### 3.3 CV Service → S3 + Lambda + DynamoDB

The current CV service (`web/cv-service/app.py`) is a FastAPI app that generates PDFs with WeasyPrint and tracks visits with SQLite. Replace entirely:

1. **PDFs**: Pre-generate locally using existing WeasyPrint code, upload 3 files to S3:
   - `s3://asanchezbl-static/cv/CV_Alex_Sanchez_Blabia_ES.pdf`
   - `s3://asanchezbl-static/cv/CV_Alex_Sanchez_Blabia_EN.pdf`
   - `s3://asanchezbl-static/cv/CV_Alex_Sanchez_Blabia_CA.pdf`

2. **Visit counter**: New Lambda function (`lambda/cv_counter/handler.py`) with DynamoDB table. Exposes a Function URL. The static CV page calls this via `fetch()` to get/increment the count.

3. **CV page**: New static HTML (`web/cv-page/index.html`). Base it on the existing Jinja2 template at `web/cv-service/templates/cv_page.html` — render it once (hit `http://EC2_IP:8001/` via SSH tunnel or `ssh -p 2222 ubuntu@34.250.192.166 "curl localhost:8001/"`) and save the output as a static file. Then modify:
   - Replace the server-rendered `{{ visit_count }}` with a `<span id="counter">...</span>` that JavaScript populates
   - Add a `fetch('/cv/api/count')` call on page load to get the count from the Lambda (routed through CloudFront behavior `/cv/api/*` → Lambda Function URL, so it's same-origin)
   - Change download links from `/download/{lang}` to direct S3 paths (`/cv/CV_Alex_Sanchez_Blabia_ES.pdf`, etc.)
   - Keep the existing CSS and styling

4. **Migrate existing count**: Extract from EC2 and write to DynamoDB:
   ```bash
   # Get current count from EC2
   COUNT=$(ssh -p 2222 ubuntu@34.250.192.166 "sqlite3 /opt/portfolio/cv-service/visits.db 'SELECT count FROM visits WHERE id=1;'")
   # Write to DynamoDB
   aws dynamodb put-item --table-name cv-visit-counter \
     --item '{"id":{"S":"global"},"count":{"N":"'$COUNT'"}}' \
     --region eu-west-1 --profile personal
   ```
   SSH key: `~/.ssh/portfolio_ed25519`.

### 3.4 SERP Backend → ECS Fargate Spot

**Image**: Pull `caballosanex/serp-backend:latest` from Docker Hub, re-tag, push to ECR `asanchezbl-portfolio/serp-backend`.

**Task definition**:
- 0.25 vCPU, 0.5GB memory, Fargate Spot
- Command: `uvicorn main:app --host 0.0.0.0 --port 5001`
- Env: `DEBUG=0`
- Health check: `curl -f http://localhost:5001/health` (endpoint exists in mock backend)
- No volumes, no sidecar

**CORS**: The mock backend already has `allow_origins=["*"]` in `docker/serp/mock_backend.py`. No change needed. However, since the frontend and API serve from the same CloudFront domain, CORS is not even triggered (same origin). The wildcard CORS is a safety net.

**Path stripping**: API Gateway route `/demo/serp/api/{proxy+}` must strip the prefix. The backend expects requests at `/` (root), not `/demo/serp/api/`. Configure the API Gateway integration with path rewriting.

**Demo reset**: EventBridge every 6h → Lambda calls `ecs:UpdateService` with `forceNewDeployment=true`. Container restart resets in-memory data.

### 3.5 CatLink Backend → ECS Fargate Spot

**Image**: Pull `caballosanex/catlink-backend:latest` from Docker Hub, re-tag, push to ECR `asanchezbl-portfolio/catlink-backend`.

**Task definition**:
- 0.25 vCPU, 0.5GB memory, Fargate Spot
- Env: `NOKIA_MOCK_MODE=true`, `BACKEND_HOST=0.0.0.0`, `BACKEND_PORT=8000`
- Health check: `curl -f http://localhost:8000/health`
- No volumes, no sidecar

**CORS**: Same-origin via CloudFront, no CORS issue. If needed, add CORSMiddleware in the mock backend code.

**Path stripping**: API Gateway route `/demo/catlink/api/{proxy+}` must rewrite to `/api/{proxy+}`. The backend exposes endpoints under `/api/`.

**WebSocket**: The CatLink backend exposes a WebSocket at `/ws` for real-time agent log streaming. The frontend connects to `wss://asanchezbl.dev/demo/catlink/ws`.

**WebSocket routing**: Route through API Gateway HTTP API + VPC Link, same as REST routes. Add a route `GET /demo/catlink/ws` → catlink-backend integration (rewrite to `/ws`). API Gateway HTTP API supports WebSocket upgrade when the backend responds with `101 Switching Protocols`. CloudFront must forward `Connection`, `Upgrade`, and `Sec-WebSocket-*` headers — use the "AllViewer" origin request policy on the `/demo/catlink/ws` CloudFront behavior.

**Fallback if WebSocket fails through API Gateway**: Replace WebSocket with Server-Sent Events (SSE) in `docker/catlink/mock_agent_patch.py`. Change `manager.broadcast()` calls to write to an SSE endpoint. The frontend `useWebSocket.js` hook would be replaced with an `EventSource` hook. This is a code change to the mock patches only (not the original CatLink repo).

**Demo reset**: Same EventBridge + Lambda pattern as SERP. Restart clears ephemeral SQLite.

### 3.6 MatchCota Backend → ECS Fargate Spot (with Postgres sidecar)

**Images**: 
- Pull `caballosanex/matchcota-backend:latest` from Docker Hub → ECR `asanchezbl-portfolio/matchcota-backend`
- Pull `postgres:15-alpine` from Docker Hub → ECR `asanchezbl-portfolio/matchcota-db`

**Task definition** (single task, two containers):

Container 1 — Backend:
- 0.25 vCPU, 0.5GB memory
- Env vars (from `docker/matchcota/docker-compose.yml`):
  - `ENVIRONMENT=development` (keeps CORS permissive, uses DATABASE_URL directly)
  - `DEBUG=false`
  - `DATABASE_URL=postgresql://matchcota:matchcota_demo_pass@localhost:5432/matchcota` ← **changed `db` to `localhost`**
  - `REDIS_ENABLED=false`
  - `S3_ENABLED=false`
  - `SECRET_KEY=demo-portfolio-secret-key-not-for-production`
  - `JWT_SECRET_KEY=demo-portfolio-jwt-secret-key-not-for-production`
  - `WILDCARD_DOMAIN=matchcota.local`
- Health check: `curl -f http://localhost:8000/api/v1/health`
- Depends on: Container 2 (Postgres) must be healthy first
- Entrypoint: `entrypoint.sh` (runs Alembic migrations + seed_demo.py before starting uvicorn)

Container 2 — Postgres sidecar:
- 0.25 vCPU, 0.25GB memory
- Env: `POSTGRES_USER=matchcota`, `POSTGRES_PASSWORD=matchcota_demo_pass`, `POSTGRES_DB=matchcota`
- Health check: `pg_isready -U matchcota`
- Volume: EFS mount at `/var/lib/postgresql/data`

**Total task**: 0.5 vCPU, 0.75GB (combined for backend + postgres sidecar). Fargate Spot.

**Path stripping**: API Gateway route `/demo/matchcota/api/{proxy+}` must rewrite to `/api/{proxy+}`.

**X-Tenant-Slug header**: API Gateway must inject `X-Tenant-Slug: demo` header on all requests to `/demo/matchcota/api/*`. Exact Terraform syntax on the `aws_apigatewayv2_integration` resource:
```hcl
request_parameters = {
  "overwrite:header.X-Tenant-Slug" = "demo"
}
```

**Demo reset**: MatchCota is NOT reset (persistent Postgres on EFS). Data survives task restarts. This matches current behavior.

### 3.7 Cloudflare DNS Changes

All managed by Terraform (Cloudflare provider already configured with token in `terraform.tfvars`):

| Record | Current | After migration |
|--------|---------|----------------|
| `@` A | 34.250.192.166 (EIP) | CNAME → `d*.cloudfront.net` (Cloudflare CNAME flattening at root) |
| `www` A | 34.250.192.166 | CNAME → `d*.cloudfront.net` |
| CAA `issue` | `letsencrypt.org` | **Add** `amazon.com` (for ACM). Keep `letsencrypt.org` until EC2 decomm |
| New: ACM validation | — | CNAME record for ACM DNS validation |

Keep `proxied = false` (CloudFront handles SSL, not Cloudflare proxy).

### 3.8 Security Headers

Currently Nginx adds these headers. Replicate via CloudFront response headers policy:
- `Strict-Transport-Security: max-age=31536000; includeSubDomains; preload`
- `X-Frame-Options: SAMEORIGIN`
- `X-Content-Type-Options: nosniff`
- `Referrer-Policy: strict-origin-when-cross-origin`
- `Permissions-Policy: camera=(), microphone=(), geolocation=(), payment=()`
- `Content-Security-Policy: default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; font-src 'self' https://fonts.gstatic.com; img-src 'self' data: blob:; connect-src 'self' wss://asanchezbl.dev; worker-src 'self' blob:; object-src 'none'; base-uri 'self'; form-action 'self'; upgrade-insecure-requests;`

---

## 4. Execution Plan (Blue/Green)

EC2 stays live serving traffic throughout Phases 0-3. DNS switches in Phase 4.

### Phase 0: Prerequisites

1. **ACM Certificate** (must be in `us-east-1` for CloudFront):
   - Request for `asanchezbl.dev` + `*.asanchezbl.dev`
   - DNS validation via Cloudflare CNAME (Terraform creates the validation record)
   - Add `amazon.com` to CAA records in Cloudflare

2. **Terraform provider alias**: Add `us-east-1` provider alias in `providers.tf` for ACM + CloudFront resources.

3. **ECR Repositories** — create in eu-west-1:
   - `asanchezbl-portfolio/serp-backend`
   - `asanchezbl-portfolio/catlink-backend`
   - `asanchezbl-portfolio/matchcota-backend`
   - `asanchezbl-portfolio/matchcota-db`

4. **Re-tag and push images from Docker Hub to ECR**:
   ```
   docker pull caballosanex/serp-backend:latest
   docker tag caballosanex/serp-backend:latest 649966626787.dkr.ecr.eu-west-1.amazonaws.com/asanchezbl-portfolio/serp-backend:latest
   docker push 649966626787.dkr.ecr.eu-west-1.amazonaws.com/asanchezbl-portfolio/serp-backend:latest
   # Repeat for catlink-backend, matchcota-backend, postgres:15-alpine → matchcota-db
   ```

5. **S3 bucket**: `asanchezbl-static` in eu-west-1, private (OAC access only), versioning optional.

6. **DynamoDB table**: `cv-visit-counter` (partition key: `id`, type: String). Single item with `id="global"`, `count=N` (migrate current value from EC2 SQLite).

7. **EFS file system**: For MatchCota Postgres data. Must create:
   - `aws_efs_file_system` with encryption enabled
   - `aws_efs_mount_target` in **both** public subnets (eu-west-1a AND eu-west-1b) — EFS mount targets are AZ-scoped, so Fargate Spot can schedule the MatchCota task in either AZ
   - Security group allowing NFS (port 2049) inbound from the Fargate task security group
   - `aws_efs_access_point` for the Postgres data directory

### Phase 1: Static Content + CloudFront

1. Upload static content to S3:
   - Pull from EC2: `/var/www/landing/`, `/var/www/portfolio/`, `/var/www/assets/`
   - Build SPA frontends (SERP, CatLink, MatchCota) with current build args, upload build outputs to S3 under respective prefixes
   - Upload pre-generated CV PDFs to `cv/`
   - Upload CV static page to `cv/index.html`

2. Create CloudFront distribution:
   - S3 origin with OAC
   - ACM certificate (from Phase 0)
   - Alternate domain: `asanchezbl.dev`, `www.asanchezbl.dev`
   - Default behavior → S3 origin
   - Response headers policy with all security headers from section 3.8
   - CloudFront Function for SPA routing (rewrite 404 → correct `index.html` per path prefix)

3. **Test**: Access `https://d*.cloudfront.net/`, `/portfolio`, `/cv/`, `/demo/serp/`, `/demo/catlink/`, `/demo/matchcota/`. Verify static content renders. API calls will fail (expected — backends not migrated yet).

### Phase 2: CV Counter Lambda

1. Create Lambda function `asanchezbl-portfolio-cv-counter`:
   - Runtime: Python 3.12, 128MB, 10s timeout
   - Function URL enabled (for CloudFront to call)
   - DynamoDB permissions on `cv-visit-counter` table
   - Endpoints: GET (return count), POST (increment + return count)

2. Add CloudFront behavior: `/cv/api/*` → Lambda Function URL origin.

3. **Test**: Access CV page via CloudFront, verify counter works.

### Phase 3: Backend APIs (ECS Fargate + API Gateway)

1. **Networking**:
   - Use existing VPC. Add a second public subnet in `eu-west-1b` (10.0.2.0/24) for Fargate Spot resilience across AZs. **Must also add a second `aws_route_table_association`** linking this subnet to the existing `aws_route_table.public` — without it, the subnet has no internet route and ECR pulls fail
   - Create security group for Fargate tasks: allow inbound on ports 5001/8000 from VPC CIDR (for VPC Link), allow outbound all
   - No NAT Gateway — tasks get public IPs in public subnets for ECR image pulls (existing IGW + route table handle this)
   - Create EFS security group: allow inbound port 2049 (NFS) from Fargate task SG only

2. **ECS Cluster**: `asanchezbl-portfolio` in eu-west-1

3. **ECS Task Definitions** (3 tasks as specified in sections 3.4, 3.5, 3.6):
   - `serp-backend` — 0.25 vCPU / 0.5GB
   - `catlink-backend` — 0.25 vCPU / 0.5GB
   - `matchcota` — 0.5 vCPU / 0.75GB (backend + postgres sidecar + EFS)
   - All Fargate Spot capacity provider

4. **ECS Services** (desired count: 1 each, no auto-scaling)

5. **Service Discovery** (Cloud Map): Private DNS namespace `portfolio.local`
   - `serp-backend.portfolio.local`
   - `catlink-backend.portfolio.local`
   - `matchcota-backend.portfolio.local`

6. **API Gateway HTTP API**:
   - VPC Link to the VPC (reuse existing subnet + SG)
   - Routes with path rewriting via integration `request_parameters`:
     - `ANY /demo/serp/api/{proxy+}` → serp-backend, `"overwrite:path" = "/$request.path.proxy"`
     - `ANY /demo/catlink/api/{proxy+}` → catlink-backend, `"overwrite:path" = "/api/$request.path.proxy"`
     - `ANY /demo/matchcota/api/{proxy+}` → matchcota-backend, `"overwrite:path" = "/api/$request.path.proxy"` + `"overwrite:header.X-Tenant-Slug" = "demo"`
     - `GET /demo/catlink/ws` → catlink-backend, `"overwrite:path" = "/ws"` (WebSocket upgrade)
   - CORS: Configure as safety net (`https://asanchezbl.dev`), though same-origin via CloudFront means CORS is not triggered for normal requests. Only matters if API Gateway is accessed directly.
   - Throttling: 100 requests/second burst, 50 sustained (default)

7. **CloudFront behaviors** (add to existing distribution):
   - `/demo/serp/api/*` → API Gateway origin
   - `/demo/catlink/api/*` → API Gateway origin
   - `/demo/matchcota/api/*` → API Gateway origin
   - `/demo/catlink/ws` → API Gateway origin (same as REST routes, WebSocket upgrade passes through). Use "AllViewer" origin request policy to forward `Connection`, `Upgrade`, `Sec-WebSocket-*` headers

8. **Demo reset Lambda** (`asanchezbl-portfolio-demo-reset`):
   - EventBridge rule: `cron(0 */6 * * ? *)` (every 6 hours)
   - Calls `ecs:UpdateService` with `forceNewDeployment=true` for serp-backend and catlink-backend services
   - IAM: `ecs:UpdateService` permission on the two services
   - MatchCota is NOT reset (persistent EFS data)

9. **Test**: Access all 3 demos via CloudFront domain. Verify:
   - SERP: login page loads, can create incidents, map renders
   - CatLink: map loads, agent chat works (WebSocket), charger list renders
   - MatchCota: login works (admin@matchcota.demo / demo123), animal list renders, can create records

### Phase 4: DNS Cutover (Blue → Green)

**Pre-cutover checklist**:
- [ ] `https://d*.cloudfront.net/` — landing renders
- [ ] `/portfolio` — portfolio renders
- [ ] `/cv/` — CV page loads, counter increments, all 3 PDF downloads work
- [ ] `/demo/serp/` — full demo functional
- [ ] `/demo/catlink/` — full demo + WebSocket agent chat functional
- [ ] `/demo/matchcota/` — full demo + DB persistence functional
- [ ] Demo reset Lambda runs successfully
- [ ] SSL certificate valid and attached
- [ ] Security headers present in responses

**Cutover** (Terraform apply):
1. Lower Cloudflare TTL to 60s, wait 5 minutes for propagation
2. Set `var.enable_cloudfront_dns = true` in `terraform.tfvars` and apply
3. This switches `@` and `www` records from A (EIP) to CNAME (CloudFront domain)
4. Monitor for errors

**⚠️ DNS toggle variable**: Add `variable "enable_cloudfront_dns" { default = false }` to `variables.tf`. In `dns.tf`, use a conditional: when `false`, keep the existing A records pointing to EIP; when `true`, create CNAME records pointing to CloudFront. This prevents `terraform apply` during Phases 0-3 from accidentally flipping DNS. Only Phase 4 sets it to `true`.

**Rollback**: Revert DNS to EIP `34.250.192.166` (instant, ~60s propagation).

### Phase 5: Decommission (Red Teardown)

1. Keep EC2 running for 48 hours as safety net
2. After 48 hours with no issues:
   - Stop EC2 instance (keep 1 week as cold backup)
3. After 1 week:
   - Terminate EC2
   - Release EIP
   - Remove EC2 security group, key pair
   - Remove EC2/EIP Terraform resources from `ec2.tf`
   - **Update `outputs.tf`**: Remove `instance_id`, `public_ip`, `ssh_command` outputs (they reference `aws_instance.web` and `aws_eip.web` which no longer exist). Replace with CloudFront distribution domain output
   - Archive Ansible playbooks (don't delete — they're portfolio artifacts)
4. Update `CLAUDE.md` and project documentation
5. Remove Certbot/Anubis references from docs
6. Update `build-and-push.sh` to push to ECR (not Docker Hub) and upload SPA builds to S3

---

## 5. Files to Create/Modify

```
terraform/
  providers.tf           # MODIFY: add us-east-1 provider alias
  variables.tf           # MODIFY: new vars (enable_cloudfront_dns, etc.)
  dns.tf                 # MODIFY: conditional DNS (A vs CNAME), CAA + ACM validation CNAME
  vpc.tf                 # MODIFY: add second public subnet in eu-west-1b (10.0.2.0/24)
  outputs.tf             # MODIFY: add CloudFront domain output (Phase 5: remove EC2 outputs)
  cloudfront.tf          # NEW: distribution, behaviors, OAC, response headers, CF Function
  s3_static.tf           # NEW: bucket + policies
  acm.tf                 # NEW: certificate in us-east-1
  ecr.tf                 # NEW: 4 repos + lifecycle policy (keep last 5 images)
  ecs.tf                 # NEW: cluster, 3 task defs (ARM64 runtime_platform), 3 services,
                         #   EFS file system + mount targets (2 AZs) + access point + SG,
                         #   IAM task execution role (ECR pull + CloudWatch logs),
                         #   IAM task role (EFS access), CloudWatch log groups,
                         #   Fargate Spot capacity provider
  api_gateway.tf         # NEW: HTTP API, routes with path rewriting (request_parameters),
                         #   VPC Link, header injection (X-Tenant-Slug), CORS
  dynamodb.tf            # NEW: cv-visit-counter table

lambda/
  cv_counter/
    handler.py           # NEW: DynamoDB visit counter
  demo_reset/
    handler.py           # NEW: ECS forceNewDeployment for SERP + CatLink

scripts/
  build-and-push.sh      # MODIFY: ECR targets + S3 SPA uploads
  migrate-static.sh      # NEW: pull from EC2, upload to S3
  migrate-images.sh      # NEW: Docker Hub → ECR re-tag
  migrate-cv-counter.sh  # NEW: SQLite → DynamoDB

web/cv-page/
  index.html             # NEW: static CV page (language selector + counter JS)
```

---

## 6. Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| CatLink WebSocket fails through API Gateway | Test WebSocket upgrade through CloudFront → API Gateway → Fargate. If blocked, replace WebSocket with SSE in `docker/catlink/mock_agent_patch.py` (code change to mock only) |
| Path stripping misconfigured (404s) | Test each API route individually before DNS cutover |
| Demo banners missing after S3 migration | Bake into SPA `index.html` at build time |
| Fargate Spot interruption or zero capacity | ECS auto-recovers when Spot returns. If unavailable in both AZs, services are down until capacity returns. Acceptable for portfolio. To add on-demand fallback: capacity provider strategy `FARGATE_SPOT` weight 1, `FARGATE` weight 0, base 1 |
| SPA routing 404 on direct URL access | CloudFront Function rewrites to correct `index.html` per path prefix |
| Security headers missing | CloudFront response headers policy replicates all Nginx headers |
| MatchCota DB data loss on task restart | EFS volume persists. Demo data expendable anyway |
| DNS propagation delay | Low TTL (60s) before cutover. Rollback is instant |
