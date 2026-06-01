#!/bin/bash
set -e

# Configuration
DOCKER_USERNAME="caballosanex"
TARGET_ARCH="linux/arm64" # EC2 is t4g.small (ARM64)

# Paths
PORTFOLIO_DIR="/Users/alex/Documents/GITs/PortfolioCloudAWS"
SERP_SRC="/Users/alex/Documents/GITs/SERP"
CATLINK_SRC="/Users/alex/Documents/GITs/CatLink"
MATCHCOTA_SRC="/Users/alex/Documents/GITs/MatchCota"

# Create a temporary workspace to avoid touching the real repos
WORK_DIR=$(mktemp -d)
echo "Working directory: $WORK_DIR"
cd "$WORK_DIR"

echo "=== 1. Copying source code ==="
rsync -a --exclude=.git --exclude=__pycache__ --exclude=node_modules "$SERP_SRC/" ./SERP/
rsync -a --exclude=.git --exclude=__pycache__ --exclude=node_modules "$CATLINK_SRC/" ./CatLink/
rsync -a --exclude=.git --exclude=__pycache__ --exclude=node_modules \
      --exclude=.venv --exclude=.planning --exclude=.pytest_cache --exclude=uploads \
      "$MATCHCOTA_SRC/" ./MatchCota/

echo "=== 2. Applying SERP Patches ==="
# SERP Backend
cp "$PORTFOLIO_DIR/docker/serp/mock_backend.py" ./SERP/backend/main.py
cp "$PORTFOLIO_DIR/docker/serp/mock_requirements.txt" ./SERP/backend/requirements.txt
sed -i '' 's/python:3.11-rc-slim/python:3.11-slim/' ./SERP/backend/Dockerfile
sed -i '' 's/apt-get update/apt-get update --fix-missing/' ./SERP/backend/Dockerfile

# SERP Frontend Base Path and Demo Patches
sed -i '' 's|"version": "0.1.0",|"version": "0.1.0",\n  "homepage": "/demo/serp/",|' ./SERP/frontend/package.json
sed -i '' 's|<BrowserRouter>|<BrowserRouter basename="/demo/serp">|' ./SERP/frontend/src/index.jsx
# Only replace in formData useState, not in formErrors (which also has email/password keys)
perl -i -pe 'if (!$done1 && /email: '\'''\''/) { s|email: '\'''\''|email: '\''admin\@serp.cat'\''|; $done1=1 }' ./SERP/frontend/src/pages/auth/Login.jsx
perl -i -pe 'if (!$done2 && /password: '\'''\''/) { s|password: '\'''\''|password: '\''admin123'\''|; $done2=1 }' ./SERP/frontend/src/pages/auth/Login.jsx

# Rewrite SERP Frontend Dockerfile for Production
cat << 'EOF' > ./SERP/frontend/Dockerfile
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

echo "=== 3. Applying CatLink Patches ==="
# CatLink Backend Agent Mocks
cp "$PORTFOLIO_DIR/docker/catlink/mock_agent_patch.py" ./CatLink/backend/src/agent/agent.py
cp "$PORTFOLIO_DIR/docker/catlink/mock_tools_patch.py" ./CatLink/backend/src/agent/tools.py
cp "$PORTFOLIO_DIR/docker/catlink/mock_agent_init_patch.py" ./CatLink/backend/src/agent/__init__.py

# CatLink Frontend URLs
sed -i '' "s|^const API_BASE =.*|const API_BASE = '/demo/catlink/api';|" ./CatLink/frontend/src/services/api.js
sed -i '' 's|const url = `\${proto}//\${window\.location\.host}/ws`|const url = `${proto}//${window.location.host}/demo/catlink/ws`|' ./CatLink/frontend/src/hooks/useWebSocket.js
sed -i '' 's|server: {|server: {\n    allowedHosts: true,|' ./CatLink/frontend/vite.config.js
sed -i '' "s|plugins: \[react()\],|plugins: [react()],\n  base: '/demo/catlink/',|" ./CatLink/frontend/vite.config.js

# Rewrite CatLink Frontend Dockerfile for Production
cat << 'EOF' > ./CatLink/frontend/Dockerfile
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


echo "=== 3b. Applying MatchCota Patches ==="
# Backend: drop in the production Dockerfile + entrypoint + idempotent demo seed.
# (requirements.txt is reused from the repo as-is.)
cp "$PORTFOLIO_DIR/docker/matchcota/backend/Dockerfile"     ./MatchCota/backend/Dockerfile
cp "$PORTFOLIO_DIR/docker/matchcota/backend/entrypoint.sh"  ./MatchCota/backend/entrypoint.sh
cp "$PORTFOLIO_DIR/docker/matchcota/backend/seed_demo.py"   ./MatchCota/backend/seed_demo.py
chmod +x ./MatchCota/backend/entrypoint.sh

# Frontend: production Dockerfile (multi-stage Vite build + serve)
cp "$PORTFOLIO_DIR/docker/matchcota/frontend/Dockerfile"    ./MatchCota/frontend/Dockerfile

# Frontend patch 1: serve the SPA under the /demo/matchcota/ base path (asset URLs)
sed -i '' "s|plugins: \[react()\],|plugins: [react()],\n  base: '/demo/matchcota/',|" ./MatchCota/frontend/vite.config.js

# Frontend patch 2: React Router must route against the base path too — Vite's
# `base` only rewrites assets. Without basename, every route 404s under the subpath.
# (Same pattern SERP uses: basename="/demo/serp".)
sed -i '' 's|<BrowserRouter>|<BrowserRouter basename="/demo/matchcota">|' ./MatchCota/frontend/src/App.jsx

# Frontend patch 3: bypass subdomain-based tenant detection. When VITE_DEMO_TENANT
# is baked at build time, resolveHostContext() returns a fixed tenant context so
# the app renders the tenant Home (not the registration Landing) under any path.
# The injected block is self-contained (does not reference the later `const hostname`).
python3 << 'PYEOF'
path = './MatchCota/frontend/src/routing/hostRouting.js'
with open(path) as f:
    src = f.read()

inject = """export function resolveHostContext() {
  // Demo mode: fixed tenant context when VITE_DEMO_TENANT is baked at build time.
  // Bypasses subdomain detection so the app works under /demo/matchcota/.
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


echo "=== 4. Building and Pushing SERP Images ==="
# SERP Backend
echo "Building SERP Backend..."
docker buildx build --platform $TARGET_ARCH -t $DOCKER_USERNAME/serp-backend:latest --push ./SERP/backend

# SERP Frontend
echo "Building SERP Frontend..."
docker buildx build --platform $TARGET_ARCH -t $DOCKER_USERNAME/serp-frontend:latest \
  --build-arg REACT_APP_API_URL=/demo/serp/api \
  --build-arg PUBLIC_URL=/demo/serp \
  --build-arg WDS_SOCKET_PATH=/demo/serp/ws \
  --push ./SERP/frontend


echo "=== 5. Building and Pushing CatLink Images ==="
# CatLink Backend
echo "Building CatLink Backend..."
docker buildx build --platform $TARGET_ARCH -t $DOCKER_USERNAME/catlink-backend:latest --push ./CatLink/backend

# CatLink Frontend
echo "Building CatLink Frontend..."
docker buildx build --platform $TARGET_ARCH -t $DOCKER_USERNAME/catlink-frontend:latest --push ./CatLink/frontend


echo "=== 6. Building and Pushing MatchCota Images ==="
# MatchCota Backend
echo "Building MatchCota Backend..."
docker buildx build --platform $TARGET_ARCH -t $DOCKER_USERNAME/matchcota-backend:latest --push ./MatchCota/backend

# MatchCota Frontend
echo "Building MatchCota Frontend..."
docker buildx build --platform $TARGET_ARCH -t $DOCKER_USERNAME/matchcota-frontend:latest \
  --build-arg VITE_DEMO_TENANT=demo \
  --build-arg VITE_API_URL=/demo/matchcota/api/v1 \
  --build-arg VITE_ENVIRONMENT=development \
  --build-arg VITE_BASE_DOMAIN=matchcota.local \
  --push ./MatchCota/frontend


echo "=== Done! Cleaning up... ==="
rm -rf "$WORK_DIR"
echo "All images built for $TARGET_ARCH and pushed to Docker Hub."
