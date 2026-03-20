# Codebase Concerns

**Analysis Date:** 2026-03-20

## Tech Debt

**SQLite visit counter in CV service - concurrency safety:**
- Issue: The visit counter in `web/cv-service/app.py` uses SQLite with sequential increments and reads. Under high concurrent load (e.g., multiple requests hitting `/` endpoint simultaneously), SQLite's locking behavior may cause contention, especially with the `db.commit()` call blocking until lock release.
- Files: `web/cv-service/app.py` (lines 47-70)
- Impact: Incorrect visit counts under load; potential for lost updates or WAL mode conflicts. Not critical for a personal portfolio, but unreliable metrics.
- Fix approach: Use Redis instead of SQLite for atomic increment operations. Alternatively, add write-ahead logging (WAL) to SQLite and implement connection pooling. For now, acceptable as traffic is expected to be low.

**Mock API data hardcoded in containers:**
- Issue: SERP and CatLink demo APIs use hardcoded in-memory data and pre-seeded SQLite databases (CatLink). Any customization or extension of demo data requires rebuilding the Docker image.
- Files: `docker/serp/mock_backend.py`, `docker/catlink/docker-compose.yml`, `scripts/reset-demos.sh`
- Impact: Cannot modify demo data at runtime. Reset script deletes data every 6 hours, losing any user-created incidents. Not a major issue for a portfolio, but limits interactivity.
- Fix approach: Move demo data to mounted volumes or environment-seeded JSON. Allow optionally persisting demo data between resets with a toggle flag.

**Double-proxy architecture adds complexity:**
- Issue: Traffic flows through two Nginx instances (external port 80/443 → Anubis on 8923 → internal Nginx on 8080). This creates multiple layers where errors can occur and increases debugging difficulty.
- Files: `nginx/conf.d/asanchezbl.dev.conf` (server block on 443), Anubis config in `ansible/roles/anubis/tasks/main.yml`
- Impact: Higher latency (negligible, <10ms per hop). More moving parts to configure and monitor. If Anubis crashes, Nginx on 8923 becomes unreachable.
- Fix approach: Monitor Anubis health and auto-restart. Consider simplifying to single Nginx + PoW middleware if CPU allows. Current architecture is justified for WAF isolation.

**Anubis version pinned to 1.25.0 with hardcoded SHA256:**
- Issue: `ansible/roles/anubis/tasks/main.yml` line 6 pins the Anubis version with a hardcoded checksum. If the release is ever deleted or checksum changes, deployment fails.
- Files: `ansible/roles/anubis/tasks/main.yml` (line 6)
- Impact: Prevents updates to newer Anubis releases without manual checksum verification. Future-proofs against dependency issues, but creates friction for upgrades.
- Fix approach: Set up automated checksum verification against GitHub releases API, or use a version variable in `group_vars/all.yml` for easier updates.

**Ansible uses file sources with relative paths:**
- Issue: Several roles use `src: "{{ playbook_dir }}/../../..."` paths to locate source files. This is fragile if repository structure changes.
- Files: `ansible/roles/deploy-cv/tasks/main.yml` (line 12), `ansible/roles/nginx/tasks/main.yml` (line 20), `ansible/roles/anubis/tasks/main.yml` (line 60)
- Impact: Refactoring the directory structure requires updating all role task files. Moving playbooks or using different working directories will break file resolution.
- Fix approach: Define a base source path variable (e.g., `source_repo_dir`) in `group_vars/all.yml` and use `{{ source_repo_dir }}/web/cv-service/` throughout.

---

## Known Bugs

**Anubis binary extraction may fail if tar structure changes:**
- Symptoms: Anubis systemd unit fails to start; "anubis binary not found in extracted files"
- Files: `ansible/roles/anubis/tasks/main.yml` (lines 19-34)
- Trigger: Techarο releases Anubis with a different directory structure in the tarball (e.g., `anubis-v1.25.0/bin/anubis` vs just `anubis`)
- Workaround: Manually extract the tarball locally to inspect structure, then update the `find` patterns in the task. Currently assumes flat extraction.

**PDF.js downloads may timeout on slow connections:**
- Symptoms: CV service fails to generate PDFs; "PDF.js library not downloaded"
- Files: `ansible/roles/deploy-cv/tasks/main.yml` (lines 48-61)
- Trigger: Network latency >60 seconds, unpkg.com CDN unavailable, or large file download on ARM64 edge device
- Workaround: Pre-download PDF.js locally and bundle it in the repository instead of fetching at deploy time. Set timeout to 120 seconds.

**Docker Compose `pull` may leave dangling images:**
- Symptoms: Disk space usage grows over time; old container versions remain on disk
- Files: `ansible/roles/deploy-serp/tasks/main.yml` (line 14), `ansible/roles/deploy-catlink/tasks/main.yml` (line 14)
- Trigger: Repeated `docker compose pull` and `up -d` cycles without cleanup
- Workaround: Add `docker image prune -a -f --filter "until=168h"` to `reset-demos.sh` to clean unused images weekly.

**CSS sub_filter in Nginx may not work on all content types:**
- Symptoms: Demo banner (LIVE DEMO badge) may not appear on some CatLink pages; Nginx logs show "sub_filter match not found"
- Files: `nginx/conf.d/asanchezbl.dev.conf` (lines 180-194)
- Trigger: Frontend responses without `</body>` tag (e.g., JSON API responses, minified HTML with no newline before closing tag)
- Workaround: Ensure React builds always include proper `</body>` closing tag. Consider adding banner via JavaScript instead of Nginx sub_filter.

---

## Security Considerations

**SSH key in `terraform/terraform.tfvars` may be exposed:**
- Risk: If `terraform.tfvars` is committed to Git (instead of using `terraform.tfvars.example` as template), SSH public key becomes visible in repository history.
- Files: `terraform/terraform.tfvars.example` (shows the pattern)
- Current mitigation: `.gitignore` should exclude `terraform/terraform.tfvars` and `.env` files. Verify with `git check-ignore terraform/terraform.tfvars`.
- Recommendations: Add explicit entries in `.gitignore` for `*.tfvars` and `*.tfvars.json`. Use GitHub branch protection to prevent accidental commits. Document in CONTRIBUTING.md that `terraform.tfvars` must never be committed.

**Certbot email in group_vars is plaintext:**
- Risk: Email address in `ansible/inventory/group_vars/all.yml` line 4 is exposed in repository history.
- Files: `ansible/inventory/group_vars/all.yml`
- Current mitigation: Email is already public (used in CLAUDE.md and CV). Not a secret, just unverified information.
- Recommendations: Keep as-is; email addresses in version control are generally acceptable.

**AWS credentials in Terraform state:**
- Risk: If S3 remote state is not encrypted or is publicly accessible, Terraform state files leak AWS resource IDs, EIP addresses, and potentially sensitive variables.
- Files: `terraform/` (state stored in S3)
- Current mitigation: Terraform state-bootstrap should create S3 with versioning and encryption enabled. Verify with `aws s3api head-bucket --bucket asanchezbl-portfolio-state --region eu-west-1`.
- Recommendations: Enable S3 server-side encryption (SSE-S3 or SSE-KMS). Block public access with `BlockPublicAcls=true`. Restrict S3 bucket policy to AWS account only.

**Cloudflare API token may be exposed:**
- Risk: If `terraform.tfvars` is committed, `cloudflare_api_token` is visible in plaintext.
- Files: `terraform/terraform.tfvars.example` (example shows the requirement)
- Current mitigation: `.gitignore` should prevent `terraform.tfvars` from being committed.
- Recommendations: Use AWS Secrets Manager or Vault to store the token, pass it via environment variable `TF_VAR_cloudflare_api_token` instead of `terraform.tfvars`. If token is ever leaked, revoke immediately in Cloudflare dashboard.

**Anubis PoW difficulty set to 6 — potential for high CPU usage:**
- Risk: Anubis difficulty 6 requires clients to solve crypto puzzles. On slow devices or high traffic, this may cause legitimate user frustration.
- Files: `ansible/inventory/group_vars/all.yml` line 14
- Current mitigation: Difficulty 6 is moderate; typical solve time ~2-5 seconds on modern browsers. No login required, so impact is aesthetic.
- Recommendations: Monitor Anubis metrics at `127.0.0.1:9091/metrics` to check solve times. Reduce to difficulty 4-5 if users complain. Document in README that first page load requires PoW challenge.

**fail2ban ban time 3600 seconds (1 hour) — may block legitimate users:**
- Risk: If a user makes 3 failed SSH attempts within 10 minutes, they're blocked for 1 hour. This is relatively aggressive.
- Files: `ansible/roles/security/tasks/main.yml` (lines 70-75)
- Current mitigation: SSH key-based auth only; accidental failures are rare. Attacks would require compromised key + repeated attempts.
- Recommendations: Keep ban time at 1 hour for security. If legitimate users are blocked, document in README how to unlock: `sudo fail2ban-client set sshd unbanip <IP>`. Consider alerting on repeated failures via email.

**Nginx rate limiting zones in memory — not shared across workers:**
- Risk: Nginx rate limiting (`limit_req_zone`) is per-worker process. With multiple workers, rate limits are not perfectly enforced (each worker maintains separate counters).
- Files: `nginx/conf.d/asanchezbl.dev.conf` (lines 5-6)
- Current mitigation: t4g.small has 2 vCPU; at most 2 workers. Combined limit still enforces roughly 10r/m overall. Not a problem for a portfolio.
- Recommendations: Keep as-is. If traffic increases and per-IP limits become critical, use `limit_req_zone` with `shared` parameter (requires nginx shared memory support).

**Demo reset script runs as root via cron:**
- Risk: `scripts/reset-demos.sh` is executed by cron with `docker` commands. If the script is compromised, attacker can delete containers/data.
- Files: `ansible/roles/demo-reset/tasks/main.yml` (line 19), `scripts/reset-demos.sh`
- Current mitigation: Script is checked into version control; changes visible in git history. Only executes Docker restart and DB deletion, no network calls.
- Recommendations: Pin script SHA256 in cron job. Create a dedicated non-root user for demo resets. Add audit logging: `logger "Demo reset executed by cron"` at start/end of script.

---

## Performance Bottlenecks

**WeasyPrint PDF generation on first request may timeout:**
- Problem: CV PDF generation is CPU-intensive (HTML → PDF via Cairo rendering). First request to `/cv/preview` or `/cv/download` may take 5-10 seconds on t4g.small (2 GB RAM, 2 vCPU ARM64).
- Files: `web/cv-service/app.py` (lines 79-96)
- Cause: WeasyPrint must render Jinja2 template, load fonts from Google Fonts, and generate PDF. On ARM64 with limited CPU, this is slow. Multi-language startup warmup (line 23) helps, but only runs once.
- Improvement path:
  1. Pre-generate all 3 PDF variants at startup (already done in warmup, good).
  2. Cache PDFs for 24 hours instead of regenerating on every request.
  3. Consider switching to Typst (Rust-based, faster PDF rendering) if WeasyPrint becomes too slow.

**Docker image pulls may timeout on first deploy:**
- Problem: `docker compose pull` on EC2 with 2 GB RAM and ARM64 architecture may timeout if Docker Hub is slow or if images are large (SERP frontend + backend ~500 MB combined).
- Files: `ansible/roles/deploy-serp/tasks/main.yml` (line 14), `ansible/roles/deploy-catlink/tasks/main.yml` (line 14)
- Cause: ARM64 images are built locally on dev machine, pushed to Docker Hub, then pulled on EC2. Network latency + image size = slow pull.
- Improvement path:
  1. Add `timeout` parameter to Ansible docker_compose module or wrap in shell task with explicit timeout.
  2. Pre-cache images during initial Terraform provisioning (add to user_data script).
  3. Use a local registry or S3 presigned URLs if Docker Hub is unreliable.

**CV service startup loads all 3 PDFs in parallel:**
- Problem: Warmup task (line 23-36 in `app.py`) generates 3 PDFs in parallel threads. If PDF generation fails for one language, entire service fails to start.
- Files: `web/cv-service/app.py` (lines 23-36)
- Cause: Exception in ThreadPoolExecutor is not caught properly; if one PDF fails, the `startup` event may be marked as incomplete.
- Improvement path:
  1. Wrap each `_gen(lang)` call in try/except and log failures without failing startup.
  2. Serve a degraded version (e.g., "PDF not available" message) if one language fails.
  3. Generate PDFs lazily on first request if warmup times out.

**Anubis PoW challenge adds latency to all requests:**
- Problem: Every request to `/cv/`, `/demo/*`, etc. must first solve a PoW challenge (1-5 seconds). Cumulative delay for a portfolio tour = 10-20 seconds just waiting for Anubis.
- Files: Anubis config in `ansible/roles/anubis/tasks/main.yml`
- Cause: Difficulty 6 is intentionally expensive to prevent bot scraping.
- Improvement path:
  1. Whitelist `/` (landing page) and `/robots.txt` in Anubis policy to skip PoW for non-protected routes.
  2. Implement JavaScript-based PoW worker so challenge happens in background while page loads.
  3. Cache PoW solutions per IP for 1 hour (Anubis supports this via policy).
  4. Consider reducing difficulty to 5 or 4 for faster solve times.

---

## Fragile Areas

**Nginx sub_filter for demo banners is brittle:**
- Files: `nginx/conf.d/asanchezbl.dev.conf` (lines 180-194)
- Why fragile: Frontend HTML structure changes (minification, build tool updates, React version) may remove `</body>` tag or change final bytes. Sub_filter depends on exact tag match.
- Safe modification: Keep frontend `/public/index.html` or build output with explicit `</body>` tag at end. Test sub_filter after every frontend rebuild: `curl https://asanchezbl.dev/demo/serp/ | grep 'demo-banner'`.
- Test coverage: No automated tests for Nginx config. Add a curl-based smoke test in `scripts/test-deploy.sh`.

**Demo reset cron assumes Docker containers always exist:**
- Files: `scripts/reset-demos.sh` (lines 10, 13-14)
- Why fragile: If a container exits and is not restarted, `docker restart` or `docker exec` silently succeeds (returns 0) even if the container doesn't exist. Demo data "resets" but container remains dead.
- Safe modification: Check container health before resetting. Modify script:
  ```bash
  docker exec serp-backend test -d /app && docker restart serp-backend || echo "WARN: serp-backend not running"
  ```
- Test coverage: No health checks. Add `docker ps | grep serp-backend` check in monitoring.

**PDF.js download in Ansible has no fallback:**
- Files: `ansible/roles/deploy-cv/tasks/main.yml` (lines 48-61)
- Why fragile: If `unpkg.com` CDN is unavailable, PDF viewer feature breaks. No retry logic, no cache.
- Safe modification: Bundle PDF.js in repository or use a pinned CDN with SHA256 verification. Alternative: pre-download during dev and commit to repo (check file size first).
- Test coverage: Deploy task doesn't verify PDF.js was downloaded. Add check: `test -f {{ base_dir }}/cv-service/static/pdf.min.js`.

**Terraform remote state assumes S3 bucket exists:**
- Files: `terraform/` (backend config not shown, but critical)
- Why fragile: If S3 state bucket is deleted or inaccessible, Terraform can't read/write state. `terraform plan` fails entirely.
- Safe modification: Document state bootstrap process in README. Store state bucket name in a `.terraformrc` or `backend-config.tfbackend` file checked into repo.
- Test coverage: No pre-flight check. Add `aws s3 ls asanchezbl-portfolio-state` to deployment script.

**Anubis policy file is static YAML with no validation:**
- Files: `ansible/roles/anubis/files/policy.yaml`
- Why fragile: Invalid YAML or missing required fields cause Anubis to fail on startup with cryptic error messages.
- Safe modification: Validate policy.yaml before copying to server. Add Ansible task: `command: anubis --policy /tmp/policy.yaml --check-only`.
- Test coverage: No policy validation. Test locally: `anubis --policy policy.yaml &` then check `lsof -i :8923`.

---

## Scaling Limits

**EC2 t4g.small RAM (2 GB) — tight for all services:**
- Current capacity: Docker (base ~200 MB) + SERP containers (~500 MB) + CatLink containers (~400 MB) + Nginx (~50 MB) + CV service (~150 MB) + Anubis (~100 MB) = ~1.4 GB reserved, leaving ~600 MB free.
- Limit: Adding another Docker app or increasing container memory limits will cause OOM kills.
- Scaling path:
  1. Monitor RSS memory with `free -h` and `docker stats`.
  2. If approaching 90% (1.8 GB), upgrade to t4g.medium (4 GB, cost ~$18/month) or optimize images (reduce Node.js image layers, use `--compress` in Docker).
  3. Consider moving Prometheus/Grafana back to a separate t4g.micro instance if monitoring is needed.

**SQLite visit counter — no concurrent writer support:**
- Current capacity: ~100 concurrent visits before contention. SQLite locks the entire DB for writes.
- Limit: High traffic (>1000 req/min) will cause slow/blocked requests to `/cv/` endpoint.
- Scaling path:
  1. Switch to Redis: `redis-cli INCR cv:visits` is atomic, non-blocking, and supports 100k+ ops/sec.
  2. If Redis is overkill, use PostgreSQL (requires `docker run postgres` or RDS, adds cost).
  3. For now (portfolio), acceptable. Add caching header `Cache-Control: max-age=60` to reduce actual requests.

**Docker Compose network isolation — no inter-container traffic monitoring:**
- Current capacity: SERP and CatLink run in isolated networks. No visibility into cross-container calls or latency.
- Limit: If more demos are added, Docker network topology becomes complex. Hard to debug which service is slow.
- Scaling path:
  1. Use Prometheus + cAdvisor to monitor container metrics (removed due to RAM constraints).
  2. Add `network_mode: host` for demos to reduce isolation overhead (but less secure).
  3. Use Nomad or Kubernetes instead of Docker Compose for production (overkill for portfolio).

**Anubis single instance — no failover:**
- Current capacity: Anubis runs as single systemd unit on 127.0.0.1:8923. If it crashes, entire site is unreachable (PoW middleware down).
- Limit: No redundancy. Crash or OOM kill blocks traffic.
- Scaling path:
  1. Add `Restart=always` with exponential backoff in systemd unit (already present, good).
  2. Monitor Anubis process: `systemctl status anubis` in cron every 5min, restart if dead.
  3. Run Anubis in Docker instead of systemd for easier management and resource limits.

---

## Dependencies at Risk

**Anubis version 1.25.0 — young WAF project:**
- Risk: Anubis (github.com/TecharoHQ/anubis) is an active but young open-source project. May have undiscovered security issues or breaking changes in future releases.
- Impact: PoW challenge may suddenly stop working; policy.yaml format may change; binary may not be available for ARM64 in newer versions.
- Migration plan:
  1. Monitor GitHub releases for security advisories.
  2. Keep a local copy of Anubis binary in S3 as fallback (current setup downloads from GitHub).
  3. Alternative WAF: OpenResty (Nginx + Lua) for custom PoW, or use AWS WAF (integrates with Cloudflare).

**PDF.js 3.11.174 — external CDN dependency:**
- Risk: unpkg.com CDN may be discontinued, moved, or have breaking changes. Version 3.x may have bugs discovered post-release.
- Impact: CV PDF viewer feature breaks silently if CDN is unavailable.
- Migration plan:
  1. Bundle PDF.js 3.11.174 in repository under `web/cv-service/static/` (check license).
  2. Update Ansible task to skip download if file already exists: `stat` check before `get_url`.
  3. Monitor PDF.js releases for security fixes; pin version in `get_url`.

**WeasyPrint 60.x — Python HTML → PDF library:**
- Risk: WeasyPrint is well-maintained but large (depends on Cairo, GDK, Pango libraries). Breaking changes between major versions.
- Impact: CV PDF generation may fail after Python package updates; CSS rendering may change.
- Migration plan:
  1. Pin WeasyPrint version in `web/cv-service/requirements.txt`: `weasyprint==60.x`.
  2. Test PDF rendering after each minor package update.
  3. Alternative: Switch to Typst (faster, more modern) or use headless Chromium (heavier).

**Node.js 20 in Docker images:**
- Risk: Node.js 20 reaches end-of-life in April 2026. After that, security patches stop.
- Impact: Demos (SERP, CatLink) may have unpatched vulnerabilities. Node.js EOL images may be removed from Docker Hub.
- Migration plan:
  1. Upgrade to Node.js 22 LTS (released October 2024) in Dockerfiles.
  2. Update `docker/serp/Dockerfile` and `docker/catlink/Dockerfile` image bases.
  3. Rebuild and test demos after upgrade.

**Ubuntu 24.04 LTS — EOL April 2029:**
- Risk: 5-year support window is reasonable. Security updates will be available until April 2029.
- Impact: After 2029, no more kernel/library updates.
- Migration plan: Plan EC2 OS upgrade in 2028; switch to Ubuntu 26.04 LTS or newer. Not urgent.

---

## Missing Critical Features

**No automated backups of EC2 or CV database:**
- Problem: Visit counter (SQLite) and any user state in SERP/CatLink are lost if EC2 instance is terminated.
- Blocks: Long-term reliability; can't prove historical visit counts.
- Recommendations:
  1. Snapshot visits.db daily to S3 via cron job.
  2. Enable EBS snapshots (AWS Backup) for root volume.
  3. Document disaster recovery: `terraform taint aws_instance.web && terraform apply` to respawn.

**No error alerting or log aggregation:**
- Problem: If CV service crashes, Nginx throws 502 errors. No notifications sent. Errors only visible if someone visits the site.
- Blocks: Can't detect/respond to outages. No audit trail for security incidents.
- Recommendations:
  1. Send Nginx error logs to CloudWatch (AWS native).
  2. Set CloudWatch alarm for >5 errors/min → email alert.
  3. Optionally: Datadog, Sentry, or ELK stack (adds cost/complexity).

**No HTTPS certificate renewal monitoring:**
- Problem: Certbot auto-renewal is configured (systemd timer) but no alert if it fails.
- Blocks: If Let's Encrypt renewal fails silently, certificate expires in 90 days, site becomes untrusted.
- Recommendations:
  1. Add check to cron job that verifies certificate expiry: `certbot certificates | grep "Expiry Date"`.
  2. Alert if expiry <7 days away.
  3. Certbot sends expiration notices to `certbot_email`, but that's not monitored.

**No rate limiting for API endpoints (SERP, CatLink APIs):**
- Problem: `/demo/serp/api/` and `/demo/catlink/api/` have no per-IP rate limits. Bot could spam create incidents in SERP.
- Blocks: Demo endpoints can be abused by scrapers.
- Recommendations:
  1. Add `limit_req_zone` in Nginx for `/demo/*/api/` routes (similar to `/cv/download/`).
  2. Implement token bucket or sliding window rate limiter in FastAPI backends (add `SlowAPI` middleware).

---

## Test Coverage Gaps

**Nginx configuration has no syntax validation in CI:**
- What's not tested: `nginx -t` never runs before deploying. Syntax errors discovered only after deployment fails.
- Files: `nginx/conf.d/asanchezbl.dev.conf`, `ansible/roles/nginx/tasks/main.yml`
- Risk: Typo in Nginx config breaks site. Manual fix requires SSH access and `systemctl restart nginx`.
- Priority: **High** — easy to add, prevents downtime.

**Ansible playbooks are not linted or dry-run before apply:**
- What's not tested: Role tasks not checked for undefined variables, incorrect module names, or logic errors.
- Files: `ansible/playbooks/site.yml`, all role task files
- Risk: Typo in variable name (e.g., `{{ base_ddir }}` instead of `{{ base_dir }}`) causes deployment to silently create wrong directories.
- Priority: **Medium** — `ansible-playbook --check` would help, but not mandatory for portfolio.

**Docker Compose services have no health checks (except CatLink):**
- What's not tested: SERP containers lack health checks. If container starts but service is down, Docker considers it healthy.
- Files: `docker/serp/docker-compose.yml` (no `healthcheck`), `docker/catlink/docker-compose.yml` (has healthcheck, good)
- Risk: Nginx proxies to dead SERP backend; users see 502 errors. No automatic restart.
- Priority: **Medium** — add curl-based health checks to both demos.

**CV service PDF generation untested on deployment:**
- What's not tested: Ansible playbook doesn't verify PDF generation works after install. If WeasyPrint fails to load fonts or render, failure is silent.
- Files: `ansible/roles/deploy-cv/tasks/main.yml`, `web/cv-service/app.py`
- Risk: CV service starts (systemd says OK), but `/cv/preview` returns 500 error due to missing fonts or PDF library.
- Priority: **Medium** — add post-deploy check: `curl http://127.0.0.1:8001/ | grep 'visit'`.

**Terraform infrastructure changes not validated for AWS limits:**
- What's not tested: Terraform doesn't check if EC2 instance type is available in region, or if VPC CIDR overlaps with existing resources.
- Files: `terraform/ec2.tf`, `terraform/vpc.tf`
- Risk: `terraform apply` may fail mid-deployment, leaving partial infrastructure.
- Priority: **Low** — AWS pre-flight checks are decent. Could add `terraform validate` in CI.

**Security group rules not tested for internet exposure:**
- What's not tested: No verification that ports 80/443 accept traffic (intentional), but 8923/9091 should be closed to internet.
- Files: `terraform/security_groups.tf` (rules are correct, but no test)
- Risk: Manual change to security group (via AWS console) could accidentally expose Anubis metrics or internal Nginx to internet.
- Priority: **Low** — correct in code, but monitoring would help.

