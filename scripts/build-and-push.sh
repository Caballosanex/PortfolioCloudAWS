#!/bin/bash
set -e

# Configuration
DOCKER_USERNAME="caballosanex"
TARGET_ARCH="linux/arm64" # EC2 is t4g.small (ARM64)

# Paths
PORTFOLIO_DIR="/Users/alex/Documents/GITs/PortfolioCloudAWS"
SERP_SRC="/Users/alex/Documents/GITs/SERP"
CATLINK_SRC="/Users/alex/Documents/GITs/CatLink"

# Create a temporary workspace to avoid touching the real repos
WORK_DIR=$(mktemp -d)
echo "Working directory: $WORK_DIR"
cd "$WORK_DIR"

echo "=== 1. Copying source code ==="
rsync -a --exclude=.git --exclude=__pycache__ --exclude=node_modules "$SERP_SRC/" ./SERP/
rsync -a --exclude=.git --exclude=__pycache__ --exclude=node_modules "$CATLINK_SRC/" ./CatLink/

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


echo "=== Done! Cleaning up... ==="
rm -rf "$WORK_DIR"
echo "All images built for $TARGET_ARCH and pushed to Docker Hub."
