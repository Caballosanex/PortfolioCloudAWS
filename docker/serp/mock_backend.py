"""
Mock SERP backend - serves the API endpoints that the React frontend expects.
Replaces the real backend + PostgreSQL with in-memory data.
Deploy: copy this as backend/main.py before docker build.
"""

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import List, Optional
from datetime import datetime, timedelta
import uuid
import copy
import random

app = FastAPI(title="SERP Mock API")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# --- Data models ---

class Emergency(BaseModel):
    id: Optional[str] = None
    title: str = ""
    description: str = ""
    location: str = ""
    latitude: float = 0
    longitude: float = 0
    type: str = "other"
    status: str = "active"
    severity: str = "high"
    priority: int = 1
    assignedResources: List[str] = []
    createdAt: Optional[str] = None
    updatedAt: Optional[str] = None

class Resource(BaseModel):
    id: Optional[str] = None
    name: str = ""
    type: str = ""
    status: str = "disponible"
    latitude: float = 0
    longitude: float = 0
    location: str = ""
    lastUpdate: Optional[str] = None
    assignedEmergency: Optional[str] = None

class QosAlert(BaseModel):
    id: Optional[str] = None
    deviceId: str = ""
    deviceName: str = ""
    alertType: str = ""
    message: str = ""
    status: str = "active"
    createdAt: Optional[str] = None

# --- Seed data ---

SEED_EMERGENCIES = [
    Emergency(
        id="EMG-001", title="Incendi forestal a Collserola",
        description="Foc detectat a la carena de Collserola, zona de Can Coll. Tres dotacions de Bombers mobilitzades.",
        location="Parc de Collserola, Barcelona", latitude=41.4236, longitude=2.1123,
        type="fire", status="active", severity="critical", priority=1,
        createdAt=(datetime.now() - timedelta(hours=2)).isoformat(),
    ),
    Emergency(
        id="EMG-002", title="Accident multiple a la Ronda Litoral",
        description="Col.lisio de 4 vehicles a l'alçada de la sortida 21. Hi ha ferits lleus.",
        location="Ronda Litoral km 14, Barcelona", latitude=41.3751, longitude=2.1892,
        type="accident", status="active", severity="high", priority=2,
        assignedResources=["RES-001", "RES-005"],
        createdAt=(datetime.now() - timedelta(hours=1)).isoformat(),
    ),
    Emergency(
        id="EMG-003", title="Emergencia medica al Mercat de la Boqueria",
        description="Persona amb parada cardiorespiratoria al mercat. SEM activat.",
        location="La Boqueria, La Rambla, Barcelona", latitude=41.3816, longitude=2.1719,
        type="medical", status="pending", severity="critical", priority=1,
        assignedResources=["RES-003"],
        createdAt=(datetime.now() - timedelta(minutes=30)).isoformat(),
    ),
    Emergency(
        id="EMG-004", title="Fuita de gas al carrer Arago",
        description="Fuita de gas natural detectada. Bomberos i Policia al lloc.",
        location="Carrer Arago 285, Barcelona", latitude=41.3917, longitude=2.1649,
        type="hazmat", status="active", severity="medium", priority=3,
        assignedResources=["RES-002"],
        createdAt=(datetime.now() - timedelta(hours=3)).isoformat(),
    ),
    Emergency(
        id="EMG-005", title="Inundacio al barri de Sants",
        description="Acumulacio d'aigua per pluja intensa. Carrer tallat al transit.",
        location="Carrer de Sants 180, Barcelona", latitude=41.3744, longitude=2.1334,
        type="flood", status="resolved", severity="low", priority=4,
        createdAt=(datetime.now() - timedelta(hours=6)).isoformat(),
    ),
]

SEED_RESOURCES = [
    Resource(id="RES-001", name="Ambulancia SEM-B12", type="ambulancia", status="ocupado",
             latitude=41.3760, longitude=2.1880, location="Ronda Litoral",
             lastUpdate=datetime.now().isoformat(), assignedEmergency="EMG-002"),
    Resource(id="RES-002", name="Dotacio Bombers B-41", type="bombers", status="ocupado",
             latitude=41.3920, longitude=2.1650, location="Carrer Arago",
             lastUpdate=datetime.now().isoformat(), assignedEmergency="EMG-004"),
    Resource(id="RES-003", name="Ambulancia SEM-M07", type="ambulancia", status="ocupado",
             latitude=41.3818, longitude=2.1720, location="La Boqueria",
             lastUpdate=datetime.now().isoformat(), assignedEmergency="EMG-003"),
    Resource(id="RES-004", name="Patrulla Mossos TT-22", type="policia", status="disponible",
             latitude=41.3890, longitude=2.1590, location="Comissaria Eixample",
             lastUpdate=datetime.now().isoformat()),
    Resource(id="RES-005", name="Grua Municipal GM-08", type="grua", status="ocupado",
             latitude=41.3755, longitude=2.1895, location="Ronda Litoral",
             lastUpdate=datetime.now().isoformat(), assignedEmergency="EMG-002"),
    Resource(id="RES-006", name="Dotacio Bombers B-15", type="bombers", status="disponible",
             latitude=41.4100, longitude=2.1740, location="Parc Bombers Gracia",
             lastUpdate=datetime.now().isoformat()),
    Resource(id="RES-007", name="Ambulancia SEM-A03", type="ambulancia", status="disponible",
             latitude=41.4010, longitude=2.1530, location="Hospital Clinic",
             lastUpdate=datetime.now().isoformat()),
    Resource(id="RES-008", name="Patrulla GUB V-11", type="policia", status="mantenimiento",
             latitude=41.3850, longitude=2.1770, location="Base Central GUB",
             lastUpdate=datetime.now().isoformat()),
]

SEED_QOS_ALERTS = [
    QosAlert(id="QOS-001", deviceId="RES-001", deviceName="Ambulancia SEM-B12",
             alertType="priority_activated", message="QoS prioritari activat per vehicle d'emergencia",
             status="active", createdAt=(datetime.now() - timedelta(minutes=45)).isoformat()),
    QosAlert(id="QOS-002", deviceId="RES-002", deviceName="Dotacio Bombers B-41",
             alertType="priority_activated", message="Prioritzacio de xarxa activa per emergencia de gas",
             status="active", createdAt=(datetime.now() - timedelta(hours=2)).isoformat()),
]

# --- In-memory stores (reset-friendly) ---

emergencies: List[dict] = [e.model_dump() for e in SEED_EMERGENCIES]
resources: List[dict] = [r.model_dump() for r in SEED_RESOURCES]
qos_alerts: List[dict] = [a.model_dump() for a in SEED_QOS_ALERTS]


def _find(collection, item_id):
    for item in collection:
        if item["id"] == item_id:
            return item
    return None


# --- Emergency routes ---

@app.get("/emergencies")
async def list_emergencies():
    return emergencies

@app.post("/emergencies", status_code=201)
async def create_emergency(data: Emergency):
    data.id = data.id or f"EMG-{uuid.uuid4().hex[:6].upper()}"
    data.createdAt = datetime.now().isoformat()
    data.updatedAt = data.createdAt
    emergencies.append(data.model_dump())
    return data.model_dump()

@app.get("/emergencies/{eid}")
async def get_emergency(eid: str):
    e = _find(emergencies, eid)
    if not e:
        raise HTTPException(404)
    return e

@app.put("/emergencies/{eid}")
async def update_emergency(eid: str, data: Emergency):
    e = _find(emergencies, eid)
    if not e:
        raise HTTPException(404)
    update = data.model_dump(exclude_unset=True)
    update["id"] = eid
    update["updatedAt"] = datetime.now().isoformat()
    e.update(update)
    return e

@app.delete("/emergencies/{eid}")
async def delete_emergency(eid: str):
    global emergencies
    emergencies = [e for e in emergencies if e["id"] != eid]
    return {"ok": True}

@app.put("/emergencies/{eid}/resolve")
async def resolve_emergency(eid: str):
    e = _find(emergencies, eid)
    if not e:
        raise HTTPException(404)
    e["status"] = "resolved"
    e["updatedAt"] = datetime.now().isoformat()
    for r in resources:
        if r.get("assignedEmergency") == eid:
            r["status"] = "disponible"
            r["assignedEmergency"] = None
            r["lastUpdate"] = datetime.now().isoformat()
    return e

@app.post("/emergencies/{eid}/assign-resources")
async def assign_resources(eid: str, body: dict):
    e = _find(emergencies, eid)
    if not e:
        raise HTTPException(404)
    resource_ids = body.get("resourceIds", [])
    e["assignedResources"] = list(set(e.get("assignedResources", []) + resource_ids))
    for rid in resource_ids:
        r = _find(resources, rid)
        if r:
            r["status"] = "ocupado"
            r["assignedEmergency"] = eid
            r["lastUpdate"] = datetime.now().isoformat()
    return e


# --- Resource routes ---

@app.get("/resources")
async def list_resources():
    return resources

@app.post("/resources/{rid}/assign")
async def assign_resource(rid: str, body: dict):
    r = _find(resources, rid)
    if not r:
        raise HTTPException(404)
    eid = body.get("emergencyId")
    r["status"] = "ocupado"
    r["assignedEmergency"] = eid
    r["lastUpdate"] = datetime.now().isoformat()
    if eid:
        e = _find(emergencies, eid)
        if e:
            if rid not in e.get("assignedResources", []):
                e.setdefault("assignedResources", []).append(rid)
    return r

@app.post("/resources/{rid}/unassign")
async def unassign_resource(rid: str):
    r = _find(resources, rid)
    if not r:
        raise HTTPException(404)
    eid = r.get("assignedEmergency")
    r["status"] = "disponible"
    r["assignedEmergency"] = None
    r["lastUpdate"] = datetime.now().isoformat()
    if eid:
        e = _find(emergencies, eid)
        if e and rid in e.get("assignedResources", []):
            e["assignedResources"].remove(rid)
    return r


# --- QoS alert routes ---

@app.get("/qosod/alerts")
async def list_qos_alerts():
    return qos_alerts

@app.put("/qosod/alerts/{aid}/resolve")
async def resolve_qos_alert(aid: str):
    a = _find(qos_alerts, aid)
    if not a:
        raise HTTPException(404)
    a["status"] = "resolved"
    return a


# --- Health ---

@app.get("/health")
async def health():
    return {"status": "ok", "service": "serp-mock-api"}

@app.get("/")
async def root():
    return {"message": "SERP Mock API", "docs": "/docs"}
