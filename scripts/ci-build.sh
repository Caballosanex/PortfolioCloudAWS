#!/bin/bash
set -euo pipefail

# CI-compatible build script for GitHub Actions (x86 runner + QEMU for ARM64).
# Env vars expected: ECR_REGISTRY, S3_BUCKET, BUILD_SERP, BUILD_CATLINK, BUILD_MATCHCOTA, BUILD_FRONTENDS
# Source repos expected at /tmp/SERP, /tmp/CatLink, /tmp/MatchCota

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

echo "=== 1. Applying SERP Patches ==="
if [[ "${BUILD_SERP:-false}" == "true" ]]; then
  cp "$SCRIPT_DIR/docker/serp/mock_backend.py" /tmp/SERP/backend/main.py
  cp "$SCRIPT_DIR/docker/serp/mock_requirements.txt" /tmp/SERP/backend/requirements.txt
  sed -i 's/python:3.11-rc-slim/python:3.11-slim/' /tmp/SERP/backend/Dockerfile
  sed -i 's/apt-get update/apt-get update --fix-missing/' /tmp/SERP/backend/Dockerfile

  sed -i 's|"version": "0.1.0",|"version": "0.1.0",\n  "homepage": "/demo/serp/",|' /tmp/SERP/frontend/package.json
  sed -i 's|<BrowserRouter>|<BrowserRouter basename="/demo/serp">|' /tmp/SERP/frontend/src/index.jsx
  perl -i -pe 'if (!$done1 && /email: '\'''\''/) { s|email: '\'''\''|email: '\''admin\@serp.cat'\''|; $done1=1 }' /tmp/SERP/frontend/src/pages/auth/Login.jsx
  perl -i -pe 'if (!$done2 && /password: '\'''\''/) { s|password: '\'''\''|password: '\''admin123'\''|; $done2=1 }' /tmp/SERP/frontend/src/pages/auth/Login.jsx

  cat << 'EOF' > /tmp/SERP/frontend/Dockerfile
FROM public.ecr.aws/docker/library/node:20-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm install && npm cache clean --force
COPY . .
ARG REACT_APP_API_URL
ARG PUBLIC_URL
ARG WDS_SOCKET_PATH
ENV REACT_APP_API_URL=$REACT_APP_API_URL
ENV PUBLIC_URL=$PUBLIC_URL
ENV WDS_SOCKET_PATH=$WDS_SOCKET_PATH
RUN npm run build

FROM public.ecr.aws/docker/library/node:20-alpine
WORKDIR /app
RUN npm install -g serve
COPY --from=builder /app/build ./build
EXPOSE 3000
CMD ["serve", "-s", "build", "-l", "3000", "--no-compression"]
EOF

  echo "Building SERP backend image..."
  docker buildx build --platform linux/arm64 \
    -t "$ECR_REGISTRY/asanchezbl-portfolio/serp-backend:latest" \
    --push /tmp/SERP/backend
  echo "SERP backend pushed."
fi

echo "=== 2. Applying CatLink Patches ==="
if [[ "${BUILD_CATLINK:-false}" == "true" ]]; then
  cp "$SCRIPT_DIR/docker/catlink/mock_agent_patch.py" /tmp/CatLink/backend/src/agent/agent.py
  cp "$SCRIPT_DIR/docker/catlink/mock_tools_patch.py" /tmp/CatLink/backend/src/agent/tools.py
  cp "$SCRIPT_DIR/docker/catlink/mock_agent_init_patch.py" /tmp/CatLink/backend/src/agent/__init__.py

  sed -i "s|^const API_BASE =.*|const API_BASE = '/demo/catlink/api';|" /tmp/CatLink/frontend/src/services/api.js
  sed -i 's|const url = `\${proto}//\${window\.location\.host}/ws`|const url = `${proto}//${window.location.host}/demo/catlink/ws`|' /tmp/CatLink/frontend/src/hooks/useWebSocket.js
  sed -i 's|server: {|server: {\n    allowedHosts: true,|' /tmp/CatLink/frontend/vite.config.js
  sed -i "s|plugins: \[react()\],|plugins: [react()],\n  base: '/demo/catlink/',|" /tmp/CatLink/frontend/vite.config.js

  cat << 'EOF' > /tmp/CatLink/frontend/Dockerfile
FROM public.ecr.aws/docker/library/node:20-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
RUN npm run build

FROM public.ecr.aws/docker/library/node:20-alpine
WORKDIR /app
RUN npm install -g serve
COPY --from=builder /app/dist ./dist
EXPOSE 3000
CMD ["serve", "-s", "dist", "-l", "3000", "--no-compression"]
EOF

  echo "Building CatLink backend image..."
  docker buildx build --platform linux/arm64 \
    -t "$ECR_REGISTRY/asanchezbl-portfolio/catlink-backend:latest" \
    --push /tmp/CatLink/backend
  echo "CatLink backend pushed."
fi

echo "=== 3. Applying MatchCota Patches ==="
if [[ "${BUILD_MATCHCOTA:-false}" == "true" ]]; then
  cp "$SCRIPT_DIR/docker/matchcota/backend/Dockerfile" /tmp/MatchCota/backend/Dockerfile
  cp "$SCRIPT_DIR/docker/matchcota/backend/entrypoint.sh" /tmp/MatchCota/backend/entrypoint.sh
  cp "$SCRIPT_DIR/docker/matchcota/backend/seed_demo.py" /tmp/MatchCota/backend/seed_demo.py
  chmod +x /tmp/MatchCota/backend/entrypoint.sh

  cp "$SCRIPT_DIR/docker/matchcota/frontend/Dockerfile" /tmp/MatchCota/frontend/Dockerfile
  sed -i "s|plugins: \[react()\],|plugins: [react()],\n  base: '/demo/matchcota/',|" /tmp/MatchCota/frontend/vite.config.js
  sed -i 's|<BrowserRouter>|<BrowserRouter basename="/demo/matchcota">|' /tmp/MatchCota/frontend/src/App.jsx

  python3 << 'PYEOF'
path = '/tmp/MatchCota/frontend/src/routing/hostRouting.js'
with open(path) as f:
    src = f.read()

inject = """export function resolveHostContext() {
  const demoSlug = (import.meta.env.VITE_DEMO_TENANT || '').trim();
  if (demoSlug) {
    return {
      hostname: normalizeHostname(window.location.hostname),
      baseDomain: getBaseDomain(),
      isProduction: false,
      isApexHost: false,
      isTenantHost: true,
      tenantSlug: demoSlug,
      invalidHost: false,
    };
  }
"""

marker = 'export function resolveHostContext() {'
assert src.count(marker) == 1, "expected exactly one resolveHostContext definition"
src = src.replace(marker, inject, 1)

with open(path, 'w') as f:
    f.write(src)
print("Patched hostRouting.js (VITE_DEMO_TENANT shortcut)")
PYEOF

  echo "Building MatchCota backend image..."
  docker buildx build --platform linux/arm64 \
    -t "$ECR_REGISTRY/asanchezbl-portfolio/matchcota-backend:latest" \
    --push /tmp/MatchCota/backend
  echo "MatchCota backend pushed."
fi

echo "=== 4. Building Frontend SPAs ==="
if [[ "${BUILD_FRONTENDS:-false}" == "true" ]]; then
  # SERP Frontend
  if [[ "${BUILD_SERP:-false}" == "true" ]]; then
    echo "Building SERP Frontend..."
    docker build -t serp-frontend-build \
      --build-arg REACT_APP_API_URL=/demo/serp/api \
      --build-arg PUBLIC_URL=/demo/serp \
      --build-arg WDS_SOCKET_PATH=/demo/serp/ws \
      /tmp/SERP/frontend
    docker create --name tmp-serp serp-frontend-build
    docker cp tmp-serp:/app/build ./serp-build
    docker rm tmp-serp
  fi

  # CatLink Frontend
  if [[ "${BUILD_CATLINK:-false}" == "true" ]]; then
    echo "Building CatLink Frontend..."
    docker build -t catlink-frontend-build /tmp/CatLink/frontend
    docker create --name tmp-catlink catlink-frontend-build
    docker cp tmp-catlink:/app/dist ./catlink-build
    docker rm tmp-catlink
  fi

  # MatchCota Frontend
  if [[ "${BUILD_MATCHCOTA:-false}" == "true" ]]; then
    echo "Building MatchCota Frontend..."
    docker build -t matchcota-frontend-build \
      --build-arg VITE_DEMO_TENANT=demo \
      --build-arg VITE_API_URL=/demo/matchcota/api/v1 \
      --build-arg VITE_ENVIRONMENT=development \
      --build-arg VITE_BASE_DOMAIN=matchcota.local \
      /tmp/MatchCota/frontend
    docker create --name tmp-matchcota matchcota-frontend-build
    docker cp tmp-matchcota:/app/dist ./matchcota-build
    docker rm tmp-matchcota
  fi

  # Inject demo banners
  echo "Injecting demo banners..."
  python3 << 'PYEOF'
import os
banners = {
    'serp-build/index.html': '<div id="demo-banner" style="position:fixed;top:0;left:0;right:0;z-index:99999;background:#12121a;border-bottom:2px solid #6366f1;padding:8px 16px;display:flex;align-items:center;justify-content:space-between;font-family:Inter,sans-serif;font-size:13px;color:#e4e4e7"><div style="display:flex;align-items:center;gap:10px"><span style="background:#22c55e;color:#fff;padding:2px 8px;border-radius:4px;font-weight:600;font-size:11px">LIVE DEMO</span><span style="font-weight:500">SERP - Emergency Response System</span><span style="color:#8b8b9e;font-size:11px">ECS Fargate on AWS</span></div><div><a href="/portfolio#projects" style="color:#6366f1;text-decoration:none;font-size:12px">&larr; Back to Portfolio</a></div></div><style>body{padding-top:40px !important}.MuiAppBar-root{top:40px !important}.MuiDrawer-root .MuiDrawer-paper{top:40px !important;height:calc(100% - 40px) !important}</style>',
    'catlink-build/index.html': '<div id="demo-banner" style="position:fixed;top:0;left:0;right:0;z-index:99999;background:#12121a;border-bottom:2px solid #6366f1;padding:8px 16px;display:flex;align-items:center;justify-content:space-between;font-family:Inter,sans-serif;font-size:13px;color:#e4e4e7"><div style="display:flex;align-items:center;gap:10px"><span style="background:#22c55e;color:#fff;padding:2px 8px;border-radius:4px;font-weight:600;font-size:11px">LIVE DEMO</span><span style="font-weight:500">CatLink - AI EV Charger Agent</span><span style="color:#8b8b9e;font-size:11px">ECS Fargate on AWS</span></div><div><a href="/portfolio#projects" style="color:#6366f1;text-decoration:none;font-size:12px">&larr; Back to Portfolio</a></div></div><style>body{padding-top:40px !important}</style>',
    'matchcota-build/index.html': '<div id="demo-banner" style="position:fixed;top:0;left:0;right:0;z-index:99999;background:#12121a;border-bottom:2px solid #6366f1;padding:8px 16px;display:flex;align-items:center;justify-content:space-between;font-family:Inter,sans-serif;font-size:13px;color:#e4e4e7"><div style="display:flex;align-items:center;gap:10px"><span style="background:#22c55e;color:#fff;padding:2px 8px;border-radius:4px;font-weight:600;font-size:11px">LIVE DEMO</span><span style="font-weight:500">MatchCota - Pet Adoption Platform</span><span style="color:#8b8b9e;font-size:11px">ECS Fargate + PostgreSQL on AWS</span></div><div style="display:flex;gap:12px;align-items:center"><a href="/portfolio#projects" style="color:#6366f1;text-decoration:none;font-size:12px">&larr; Back to Portfolio</a><span style="color:#8b8b9e;font-size:11px">admin@matchcota.demo / demo123</span></div></div><style>body{padding-top:40px !important}</style>',
}
for path, banner in banners.items():
    if not os.path.exists(path):
        print(f"Skipping {path} (not built)")
        continue
    with open(path) as f:
        html = f.read()
    html = html.replace('</body>', banner + '</body>')
    with open(path, 'w') as f:
        f.write(html)
    print(f"Banner injected: {path}")
PYEOF

  # Upload SPA builds to S3
  echo "Uploading SPAs to S3..."
  [[ -d ./serp-build ]] && aws s3 sync ./serp-build/ "s3://$S3_BUCKET/demo/serp/" --delete
  [[ -d ./catlink-build ]] && aws s3 sync ./catlink-build/ "s3://$S3_BUCKET/demo/catlink/" --delete
  [[ -d ./matchcota-build ]] && aws s3 sync ./matchcota-build/ "s3://$S3_BUCKET/demo/matchcota/" --delete
fi

echo "=== CI build complete ==="
