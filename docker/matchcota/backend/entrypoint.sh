#!/bin/sh
set -e

cd /app

echo "[matchcota] Running Alembic migrations..."
alembic upgrade head

echo "[matchcota] Seeding demo data..."
python seed_demo.py

echo "[matchcota] Starting uvicorn..."
exec uvicorn app.main:app --host 0.0.0.0 --port 8000 --workers 1
