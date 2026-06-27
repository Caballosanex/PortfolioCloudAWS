#!/bin/bash
set -e

# Configuration
AWS_ACCOUNT="649966626787"
AWS_REGION="eu-west-1"
AWS_PROFILE="personal"
ECR_PREFIX="$AWS_ACCOUNT.dkr.ecr.$AWS_REGION.amazonaws.com/asanchezbl-portfolio"
S3_BUCKET="asanchezbl-static"
TARGET_ARCH="linux/arm64"

# Paths
PORTFOLIO_DIR="/Users/alex/Documents/GITs/PortfolioCloudAWS"
SERP_SRC="/Users/alex/Documents/GITs/SERP"
CATLINK_SRC="/Users/alex/Documents/GITs/CatLink"
MATCHCOTA_SRC="/Users/alex/Documents/GITs/MatchCota"

# ECR Login
echo "=== Logging in to ECR ==="
aws ecr get-login-password --region $AWS_REGION --profile $AWS_PROFILE | \
  docker login --username AWS --password-stdin "$AWS_ACCOUNT.dkr.ecr.$AWS_REGION.amazonaws.com"

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
cp "$PORTFOLIO_DIR/docker/serp/mock_backend.py" ./SERP/backend/main.py
cp "$PORTFOLIO_DIR/docker/serp/mock_requirements.txt" ./SERP/backend/requirements.txt
sed -i '' 's/python:3.11-rc-slim/python:3.11-slim/' ./SERP/backend/Dockerfile
sed -i '' 's/apt-get update/apt-get update --fix-missing/' ./SERP/backend/Dockerfile

sed -i '' 's|"version": "0.1.0",|"version": "0.1.0",\n  "homepage": "/demo/serp/",|' ./SERP/frontend/package.json
sed -i '' 's|<BrowserRouter>|<BrowserRouter basename="/demo/serp">|' ./SERP/frontend/src/index.jsx
perl -i -pe 'if (!$done1 && /email: '\'''\''/) { s|email: '\'''\''|email: '\''admin\@serp.cat'\''|; $done1=1 }' ./SERP/frontend/src/pages/auth/Login.jsx
perl -i -pe 'if (!$done2 && /password: '\'''\''/) { s|password: '\'''\''|password: '\''admin123'\''|; $done2=1 }' ./SERP/frontend/src/pages/auth/Login.jsx

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
cp "$PORTFOLIO_DIR/docker/catlink/mock_agent_patch.py" ./CatLink/backend/src/agent/agent.py
cp "$PORTFOLIO_DIR/docker/catlink/mock_tools_patch.py" ./CatLink/backend/src/agent/tools.py
cp "$PORTFOLIO_DIR/docker/catlink/mock_agent_init_patch.py" ./CatLink/backend/src/agent/__init__.py

sed -i '' "s|^const API_BASE =.*|const API_BASE = '/demo/catlink/api';|" ./CatLink/frontend/src/services/api.js
sed -i '' 's|const url = `\${proto}//\${window\.location\.host}/ws`|const url = `${proto}//${window.location.host}/demo/catlink/ws`|' ./CatLink/frontend/src/hooks/useWebSocket.js
sed -i '' 's|server: {|server: {\n    allowedHosts: true,|' ./CatLink/frontend/vite.config.js
sed -i '' "s|plugins: \[react()\],|plugins: [react()],\n  base: '/demo/catlink/',|" ./CatLink/frontend/vite.config.js

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
cp "$PORTFOLIO_DIR/docker/matchcota/backend/Dockerfile"     ./MatchCota/backend/Dockerfile
cp "$PORTFOLIO_DIR/docker/matchcota/backend/entrypoint.sh"  ./MatchCota/backend/entrypoint.sh
cp "$PORTFOLIO_DIR/docker/matchcota/backend/seed_demo.py"   ./MatchCota/backend/seed_demo.py
chmod +x ./MatchCota/backend/entrypoint.sh

cp "$PORTFOLIO_DIR/docker/matchcota/frontend/Dockerfile"    ./MatchCota/frontend/Dockerfile
sed -i '' "s|plugins: \[react()\],|plugins: [react()],\n  base: '/demo/matchcota/',|" ./MatchCota/frontend/vite.config.js
sed -i '' 's|<BrowserRouter>|<BrowserRouter basename="/demo/matchcota">|' ./MatchCota/frontend/src/App.jsx

python3 << 'PYEOF'
path = './MatchCota/frontend/src/routing/hostRouting.js'
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

echo "=== 4. Building and Pushing Backend Images to ECR ==="
docker buildx build --platform $TARGET_ARCH -t $ECR_PREFIX/serp-backend:latest --push ./SERP/backend
docker buildx build --platform $TARGET_ARCH -t $ECR_PREFIX/catlink-backend:latest --push ./CatLink/backend
docker buildx build --platform $TARGET_ARCH -t $ECR_PREFIX/matchcota-backend:latest --push ./MatchCota/backend

echo "=== 5. Building Frontend SPAs and Uploading to S3 ==="

# SERP Frontend
echo "Building SERP Frontend..."
docker buildx build --platform $TARGET_ARCH -t serp-frontend-build \
  --build-arg REACT_APP_API_URL=/demo/serp/api \
  --build-arg PUBLIC_URL=/demo/serp \
  --build-arg WDS_SOCKET_PATH=/demo/serp/ws \
  --load ./SERP/frontend
docker create --name tmp-serp serp-frontend-build
docker cp tmp-serp:/app/build ./serp-build
docker rm tmp-serp

# CatLink Frontend
echo "Building CatLink Frontend..."
docker buildx build --platform $TARGET_ARCH -t catlink-frontend-build --load ./CatLink/frontend
docker create --name tmp-catlink catlink-frontend-build
docker cp tmp-catlink:/app/dist ./catlink-build
docker rm tmp-catlink

# MatchCota Frontend
echo "Building MatchCota Frontend..."
docker buildx build --platform $TARGET_ARCH -t matchcota-frontend-build \
  --build-arg VITE_DEMO_TENANT=demo \
  --build-arg VITE_API_URL=/demo/matchcota/api/v1 \
  --build-arg VITE_ENVIRONMENT=development \
  --build-arg VITE_BASE_DOMAIN=matchcota.local \
  --load ./MatchCota/frontend
docker create --name tmp-matchcota matchcota-frontend-build
docker cp tmp-matchcota:/app/dist ./matchcota-build
docker rm tmp-matchcota

# Inject demo banners
python3 << 'PYEOF'
banners = {
    'serp-build/index.html': '<div id="demo-banner" style="position:fixed;top:0;left:0;right:0;z-index:99999;background:#12121a;border-bottom:2px solid #6366f1;padding:8px 16px;display:flex;align-items:center;justify-content:space-between;font-family:Inter,sans-serif;font-size:13px;color:#e4e4e7"><div style="display:flex;align-items:center;gap:10px"><span style="background:#22c55e;color:#fff;padding:2px 8px;border-radius:4px;font-weight:600;font-size:11px">LIVE DEMO</span><span style="font-weight:500">SERP - Emergency Response System</span><span style="color:#8b8b9e;font-size:11px">ECS Fargate on AWS</span></div><div><a href="/portfolio#projects" style="color:#6366f1;text-decoration:none;font-size:12px">&larr; Back to Portfolio</a></div></div><style>body{padding-top:40px !important}.MuiAppBar-root{top:40px !important}.MuiDrawer-root .MuiDrawer-paper{top:40px !important;height:calc(100% - 40px) !important}</style>',
    'catlink-build/index.html': '<div id="demo-banner" style="position:fixed;top:0;left:0;right:0;z-index:99999;background:#12121a;border-bottom:2px solid #6366f1;padding:8px 16px;display:flex;align-items:center;justify-content:space-between;font-family:Inter,sans-serif;font-size:13px;color:#e4e4e7"><div style="display:flex;align-items:center;gap:10px"><span style="background:#22c55e;color:#fff;padding:2px 8px;border-radius:4px;font-weight:600;font-size:11px">LIVE DEMO</span><span style="font-weight:500">CatLink - AI EV Charger Agent</span><span style="color:#8b8b9e;font-size:11px">ECS Fargate on AWS</span></div><div><a href="/portfolio#projects" style="color:#6366f1;text-decoration:none;font-size:12px">&larr; Back to Portfolio</a></div></div><style>body{padding-top:40px !important}</style>',
    'matchcota-build/index.html': '<div id="demo-banner" style="position:fixed;top:0;left:0;right:0;z-index:99999;background:#12121a;border-bottom:2px solid #6366f1;padding:8px 16px;display:flex;align-items:center;justify-content:space-between;font-family:Inter,sans-serif;font-size:13px;color:#e4e4e7"><div style="display:flex;align-items:center;gap:10px"><span style="background:#22c55e;color:#fff;padding:2px 8px;border-radius:4px;font-weight:600;font-size:11px">LIVE DEMO</span><span style="font-weight:500">MatchCota - Pet Adoption Platform</span><span style="color:#8b8b9e;font-size:11px">ECS Fargate + PostgreSQL on AWS</span></div><div style="display:flex;gap:12px;align-items:center"><a href="/portfolio#projects" style="color:#6366f1;text-decoration:none;font-size:12px">&larr; Back to Portfolio</a><span style="color:#8b8b9e;font-size:11px">admin@matchcota.demo / demo123</span></div></div><style>body{padding-top:40px !important}</style>',
}
for path, banner in banners.items():
    with open(path) as f:
        html = f.read()
    html = html.replace('</body>', banner + '</body>')
    with open(path, 'w') as f:
        f.write(html)
    print(f"Banner injected: {path}")
PYEOF

# Upload SPA builds to S3
echo "Uploading SPAs to S3..."
aws s3 sync ./serp-build/ "s3://$S3_BUCKET/demo/serp/" --delete --exclude ".DS_Store" --profile $AWS_PROFILE
aws s3 sync ./catlink-build/ "s3://$S3_BUCKET/demo/catlink/" --delete --exclude ".DS_Store" --profile $AWS_PROFILE
aws s3 sync ./matchcota-build/ "s3://$S3_BUCKET/demo/matchcota/" --delete --exclude ".DS_Store" --profile $AWS_PROFILE

echo "=== 6. Force ECS Service Redeployment ==="
aws ecs update-service --cluster asanchezbl-portfolio --service serp-backend --force-new-deployment --profile $AWS_PROFILE --region $AWS_REGION --query 'service.serviceName' --output text
aws ecs update-service --cluster asanchezbl-portfolio --service catlink-backend --force-new-deployment --profile $AWS_PROFILE --region $AWS_REGION --query 'service.serviceName' --output text
aws ecs update-service --cluster asanchezbl-portfolio --service matchcota --force-new-deployment --profile $AWS_PROFILE --region $AWS_REGION --query 'service.serviceName' --output text

echo "=== Done! Cleaning up... ==="
rm -rf "$WORK_DIR"
echo "All backend images pushed to ECR, frontend SPAs uploaded to S3."
