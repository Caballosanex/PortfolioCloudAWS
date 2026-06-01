# MatchCota backend — production multi-stage build for ARM64 (t4g.small)
# Mirrors the repo's Alpine approach but adds an entrypoint that runs
# Alembic migrations + demo seed before launching uvicorn.
FROM public.ecr.aws/docker/library/python:3.11-alpine AS builder

WORKDIR /app

# Build deps for psycopg2 + bcrypt (musl wheels often compile from source)
RUN apk add --no-cache gcc musl-dev postgresql-dev linux-headers

COPY requirements.txt .
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt

# ---- Runtime stage ----
FROM public.ecr.aws/docker/library/python:3.11-alpine

WORKDIR /app

# Runtime libs: libpq for psycopg2, curl for the healthcheck
RUN apk add --no-cache libpq curl

COPY --from=builder /usr/local/lib/python3.11/site-packages /usr/local/lib/python3.11/site-packages
COPY --from=builder /usr/local/bin /usr/local/bin

# Application source (seed_demo.py + entrypoint.sh are copied into the build
# context by scripts/build-and-push.sh before this build runs)
COPY . .

RUN chmod +x /app/entrypoint.sh

EXPOSE 8000
ENTRYPOINT ["/app/entrypoint.sh"]
