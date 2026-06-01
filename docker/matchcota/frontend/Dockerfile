# MatchCota frontend — production multi-stage Vite build for ARM64
# Built with base path /demo/matchcota/ and a fixed demo tenant baked in.
FROM public.ecr.aws/docker/library/node:20-alpine AS builder

WORKDIR /app

COPY package*.json ./
RUN npm install

COPY . .

# Build-time configuration (see scripts/build-and-push.sh for the values passed).
# VITE_DEMO_TENANT bypasses subdomain detection in the patched hostRouting.js.
ARG VITE_DEMO_TENANT=demo
ARG VITE_API_URL=/demo/matchcota/api/v1
ARG VITE_ENVIRONMENT=development
ARG VITE_BASE_DOMAIN=matchcota.local
ENV VITE_DEMO_TENANT=$VITE_DEMO_TENANT
ENV VITE_API_URL=$VITE_API_URL
ENV VITE_ENVIRONMENT=$VITE_ENVIRONMENT
ENV VITE_BASE_DOMAIN=$VITE_BASE_DOMAIN

RUN npm run build

# ---- Runtime stage: static file server ----
FROM public.ecr.aws/docker/library/node:20-alpine
WORKDIR /app
RUN npm install -g serve
COPY --from=builder /app/dist ./dist
EXPOSE 3000
CMD ["serve", "-s", "dist", "-l", "3000", "--no-compression"]
