#!/usr/bin/env python3
"""
Seed demo data for the MatchCota portfolio demo.

Idempotent: safe to run on every container startup. Creates a single "demo"
tenant (Protectora Demo), an admin user, and a handful of adoptable animals.
"""
import sys
import uuid
from datetime import date

# Ensure the app package is importable
sys.path.insert(0, "/app")

# Import from the models package (not individual modules) so that ALL mappers
# — including Lead and Questionnaire referenced by Tenant.relationship() — are
# registered before SQLAlchemy configures the mappers. Importing only
# Tenant/User/Animal would raise "failed to locate a name 'Lead'" at query time.
from app.models import Tenant, User, Animal  # noqa: E402
from app.database import SessionLocal  # noqa: E402
from app.core.security import get_password_hash  # noqa: E402

DEMO_SLUG = "demo"
DEMO_EMAIL = "admin@matchcota.demo"
DEMO_PASSWORD = "demo123"


def seed(db):
    # --- Tenant ---
    tenant = db.query(Tenant).filter(Tenant.slug == DEMO_SLUG).first()
    if not tenant:
        tenant = Tenant(
            id=uuid.uuid4(),
            slug=DEMO_SLUG,
            name="Protectora Demo",
            city="Barcelona",
            email="info@matchcota.demo",
            phone="+34 600 000 000",
            website="https://asanchezbl.dev/demo/matchcota",
        )
        db.add(tenant)
        db.flush()
        print(f"[seed] Created tenant: {DEMO_SLUG}")
    else:
        print(f"[seed] Tenant {DEMO_SLUG} already exists, skipping")

    # --- Admin user ---
    existing_user = (
        db.query(User)
        .filter(User.tenant_id == tenant.id, User.email == DEMO_EMAIL)
        .first()
    )
    if not existing_user:
        db.add(
            User(
                id=uuid.uuid4(),
                tenant_id=tenant.id,
                username="admin",
                email=DEMO_EMAIL,
                password_hash=get_password_hash(DEMO_PASSWORD),
                name="Admin Demo",
            )
        )
        print(f"[seed] Created admin user: {DEMO_EMAIL} / {DEMO_PASSWORD}")
    else:
        print("[seed] Admin user already exists, skipping")

    # --- Animals ---
    existing_count = db.query(Animal).filter(Animal.tenant_id == tenant.id).count()
    if existing_count == 0:
        animals = [
            Animal(
                id=uuid.uuid4(), tenant_id=tenant.id,
                name="Luna", species="Gos", breed="Labrador Mix",
                sex="Femella", birth_date=date(2021, 3, 15), size="Gran", weight_kg=28.5,
                sociability=8.5, energy_level=7.0, attention_needs=5.0,
                good_with_children=9.0, good_with_dogs=8.0, good_with_cats=6.0,
                experience_required=2.0, maintenance_level=4.0,
                description="Luna és una gossa molt afectuosa i jugadora. Li encanta passejar i jugar a la pilota. Molt bona amb nens.",
                photo_urls=[],
            ),
            Animal(
                id=uuid.uuid4(), tenant_id=tenant.id,
                name="Mochi", species="Gat", breed="Europeu comú",
                sex="Mascle", birth_date=date(2022, 7, 20), size="Mitjà", weight_kg=4.2,
                sociability=6.0, energy_level=5.5, attention_needs=3.0,
                good_with_children=7.0, good_with_dogs=4.0, good_with_cats=9.0,
                experience_required=1.0, maintenance_level=2.0,
                description="Mochi és un gat tranquil i afectuós. Li agraden les migdiades i el sol de la finestra.",
                photo_urls=[],
            ),
            Animal(
                id=uuid.uuid4(), tenant_id=tenant.id,
                name="Rex", species="Gos", breed="Pastor Alemany",
                sex="Mascle", birth_date=date(2020, 11, 5), size="Gran", weight_kg=34.0,
                sociability=7.0, energy_level=9.0, attention_needs=7.0,
                good_with_children=6.0, good_with_dogs=5.0, good_with_cats=3.0,
                experience_required=7.0, maintenance_level=6.0,
                description="Rex és un gos molt intel·ligent i lleial. Necessita un adoptant amb experiència i molt d'espai.",
                photo_urls=[],
            ),
            Animal(
                id=uuid.uuid4(), tenant_id=tenant.id,
                name="Nala", species="Gos", breed="Beagle",
                sex="Femella", birth_date=date(2023, 2, 10), size="Petit", weight_kg=10.5,
                sociability=9.5, energy_level=8.0, attention_needs=6.0,
                good_with_children=9.5, good_with_dogs=9.0, good_with_cats=7.0,
                experience_required=2.0, maintenance_level=3.0,
                description="Nala és una gosseta molt sociable i alegre. Perfecta per a famílies amb nens.",
                photo_urls=[],
            ),
            Animal(
                id=uuid.uuid4(), tenant_id=tenant.id,
                name="Oliver", species="Gat", breed="Siamès",
                sex="Mascle", birth_date=date(2021, 9, 1), size="Petit", weight_kg=3.8,
                sociability=5.0, energy_level=6.0, attention_needs=8.0,
                good_with_children=5.0, good_with_dogs=3.0, good_with_cats=7.0,
                experience_required=3.0, maintenance_level=3.0,
                description="Oliver és un gat molt vocal i afectuós. Busca una llar tranquil·la on sigui el centre d'atenció.",
                photo_urls=[],
            ),
        ]
        db.add_all(animals)
        print(f"[seed] Created {len(animals)} demo animals")
    else:
        print(f"[seed] {existing_count} animals already present, skipping")

    db.commit()
    print("[seed] Done.")


if __name__ == "__main__":
    db = SessionLocal()
    try:
        seed(db)
    finally:
        db.close()
