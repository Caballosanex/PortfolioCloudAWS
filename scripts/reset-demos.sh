#!/bin/bash
# Reset SERP and CatLink demo data periodically
# Add to crontab: 0 */6 * * * /opt/portfolio/scripts/reset-demos.sh

set -euo pipefail

echo "[$(date)] Resetting demo data..."

# SERP uses in-memory mock data, restart resets it
docker restart serp-backend 2>/dev/null || true

# CatLink uses SQLite, delete DB and restart to re-seed
docker exec catlink-backend rm -f /app/catlink.db 2>/dev/null || true
docker restart catlink-backend 2>/dev/null || true

echo "[$(date)] Demo data reset complete."
