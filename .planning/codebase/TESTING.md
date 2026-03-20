# Testing Patterns

**Analysis Date:** 2026-03-20

## Test Framework

**Status:** No testing framework detected in codebase

**What's present:**
- No pytest, unittest, Jest, Vitest, or other test runner configuration
- No `.test.py`, `.spec.js`, or test files in codebase
- No `pytest.ini`, `jest.config.js`, or equivalent configuration files

**Implication:**
Testing is not automated in this project. Validation occurs through:
1. Manual testing during development
2. Integration testing via Ansible playbook execution
3. Manual verification of deployed services

## Manual Testing Approach

**For Python services (CV Service, Mock APIs):**
- FastAPI provides automatic OpenAPI/Swagger docs at `/docs` endpoint
- Manual HTTP testing via curl or Postman against running service
- Pydantic model validation provides runtime type checking

Example FastAPI doc endpoint:
```python
@app.get("/")
async def root():
    return {"message": "SERP Mock API", "docs": "/docs"}
```

**For Ansible playbooks:**
- Full server provisioning tested via `ansible-playbook playbooks/site.yml`
- Idempotent execution verified (running twice should not error)
- Service status checked via `systemctl status` commands in handlers

**For Terraform:**
- Plan phase: `terraform plan` validates syntax and shows proposed changes
- Apply phase: `terraform apply` creates actual AWS resources
- Manual AWS console verification of created resources

**For Bash scripts:**
- `set -e` ensures script halts on first error
- Manual invocation and output inspection
- Docker image push success confirmed by Docker Hub registry check

**For Docker Compose services:**
- Manual testing via `docker-compose up`
- Service health verified via port accessibility and HTTP endpoint checks
- Container logs inspected for startup errors

## Test Data

**Mock backends use seed data for manual testing:**

CV Service (`app.py`):
- Pre-generates PDFs on startup for instant first requests
- SQLite database initialized on first access with default visit count
- YAML-based CV data files (`cv_es.yml`, `cv_en.yml`, `cv_ca.yml`) serve as fixtures

SERP Mock API (`mock_backend.py`):
```python
SEED_EMERGENCIES = [
    Emergency(id="EMG-001", title="Incendi forestal a Collserola", ...),
    Emergency(id="EMG-002", title="Accident multiple a la Ronda Litoral", ...),
    # ... 5 pre-populated emergencies
]

SEED_RESOURCES = [
    Resource(id="RES-001", name="Ambulancia SEM-B12", ...),
    # ... 8 pre-populated resources
]

SEED_QOS_ALERTS = [
    QosAlert(id="QOS-001", deviceId="RES-001", ...),
    # ... 2 pre-populated alerts
]
```

In-memory stores are reset-friendly:
```python
emergencies: List[dict] = [e.model_dump() for e in SEED_EMERGENCIES]
resources: List[dict] = [r.model_dump() for r in SEED_RESOURCES]
qos_alerts: List[dict] = [a.model_dump() for a in SEED_QOS_ALERTS]
```

CatLink Mock Agent (`mock_agent_patch.py`):
```python
FRAUD_PHONES = {"+3672123456", "+34666666666", "+34699999999"}

# Request to fraud phone triggers REJECT_FRAUD decision
# Other requests trigger APPROVE decision
# Deterministic responses allow manual verification of logic
```

## Fixtures and Test Data Organization

**Location:**
- CV data: `web/cv-service/data/` (YAML files)
- Mock API seed data: Hardcoded as module-level `SEED_*` constants
- Mock agent responses: Hardcoded in `MOCK_RESPONSES` dict

**Data file pattern (`web/cv-service/data/cv_es.yml`):**
Structured YAML with sections for personal, education, experience, projects, skills. Loaded and rendered via Jinja2 templates.

**Seed data pattern (SERP emergencies):**
```python
SEED_EMERGENCIES = [
    Emergency(
        id="EMG-001",
        title="Incendi forestal a Collserola",
        description="Foc detectat a la carena de Collserola...",
        location="Parc de Collserola, Barcelona",
        latitude=41.4236,
        longitude=2.1123,
        type="fire",
        status="active",
        severity="critical",
        priority=1,
        createdAt=(datetime.now() - timedelta(hours=2)).isoformat(),
    ),
]
```

**Mock response pattern (CatLink):**
```python
MOCK_RESPONSES = {
    "approve": {
        "decision": "APPROVE",
        "reason": "All security checks passed...",
        "user_message": "Your charging session has been approved!",
        "confidence": 0.95,
    },
    "reject_location": { ... },
    "reject_fraud": { ... },
}
```

## Mocking Strategy

**For Nokia APIs (removed from production mock):**
Mock implementations replace real API calls with deterministic responses.

Example from `mock_agent_patch.py`:
```python
async def evaluate_charge_request(
    self,
    charger: dict,
    user_phone: str,
    user_lat: float,
    user_lon: float,
) -> dict:
    # Simulates location verification without calling Nokia API
    R = 6371000  # Earth radius in meters
    lat1, lon1 = radians(user_lat), radians(user_lon)
    lat2, lon2 = radians(charger["lat"]), radians(charger["lon"])
    dlat, dlon = lat2 - lat1, lon2 - lon1
    a = sin(dlat/2)**2 + cos(lat1)*cos(lat2)*sin(dlon/2)**2
    distance = R * 2 * atan2(sqrt(a), sqrt(1-a))
    result = {"verified": distance <= 1500, "distance_m": round(distance, 2)}
```

**For Gemini AI (removed from production mock):**
Deterministic mock responses based on phone number.

Example from `mock_agent_patch.py`:
```python
is_fraud = user_phone in FRAUD_PHONES

if is_fraud:
    decision = "REJECT_FRAUD"
    reason = ("SIM swap detected within the last 24 hours. "
              "This is a strong indicator of potential fraud.")
    confidence = 0.92
else:
    decision = "APPROVE"
    reason = "All security checks passed..."
    confidence = 0.95
```

**What NOT to mock:**
- Database operations (CV service uses SQLite directly)
- File system operations (PDF generation uses WeasyPrint on real files)
- HTTP server functionality (FastAPI handles this natively)

**What to mock:**
- External service APIs (Nokia APIs, Gemini AI)
- Expensive operations (replaced with simulated delays: `await asyncio.sleep(0.5)`)

## Common Testing Patterns

**Async testing pattern (CatLink mock agent):**
```python
async def evaluate_charge_request(...) -> dict:
    # Async function with nested awaits
    for tool_name, tool_input in tools_sequence:
        await asyncio.sleep(0.5)  # Simulate processing time
        # Tool execution
        log_entry = {...}
        logs.append(log_entry)
        await manager.broadcast({"type": "agent_log", "data": log_entry})
```

**Error testing pattern (not present but inferred from code):**
FastAPI uses `HTTPException` for error cases:
```python
@app.get("/emergencies/{eid}")
async def get_emergency(eid: str):
    e = _find(emergencies, eid)
    if not e:
        raise HTTPException(404)  # Implicit error response
    return e
```

**Type validation pattern (Pydantic models):**
```python
class Emergency(BaseModel):
    id: Optional[str] = None
    title: str = ""
    description: str = ""
    latitude: float = 0
    longitude: float = 0
    type: str = "other"
    status: str = "active"
    severity: str = "high"
    priority: int = 1
    assignedResources: List[str] = []
    createdAt: Optional[str] = None
    updatedAt: Optional[str] = None
```

Pydantic automatically validates incoming data:
```python
@app.post("/emergencies", status_code=201)
async def create_emergency(data: Emergency):
    # data is guaranteed to match Emergency schema or 422 error returned
    data.id = data.id or f"EMG-{uuid.uuid4().hex[:6].upper()}"
    emergencies.append(data.model_dump())
    return data.model_dump()
```

## Test Coverage

**Requirements:** None enforced

**Current coverage:** Not measured (no test framework)

**Recommendations for future:**
If testing is added, prioritize:
1. API endpoint contract testing (mock SERP/CatLink endpoints)
2. PDF generation correctness (CV service template rendering)
3. Ansible playbook idempotence (provisioning stability)
4. Mock response determinism (fraud phone detection, distance calculations)

## Integration Testing (via Ansible)

**Location:** `ansible/playbooks/site.yml`

**Approach:**
Full system is tested via Ansible playbook execution:
```yaml
- name: Base system setup
  hosts: portfolio
  become: true
  roles:
    - role: base          # System packages
    - role: security      # SSH, firewall, fail2ban
    - role: docker        # Docker + Docker Compose
    - role: nginx         # Reverse proxy
    - role: certbot       # SSL certificates

- name: Deploy applications
  hosts: portfolio
  become: true
  roles:
    - role: deploy-landing      # Static landing page
    - role: deploy-cv           # CV service (Python venv)
    - role: deploy-portfolio    # Portfolio web
    - role: deploy-serp         # SERP Docker Compose
    - role: deploy-catlink      # CatLink Docker Compose
    - role: demo-reset          # Cron job for data reset
    - role: anubis              # WAF setup
```

**Validation:**
- Playbook runs sequentially without error (implies correct provisioning)
- Services start successfully (systemd service units validate)
- Ports are accessible (Nginx proxying validates connectivity)

## Manual Verification Checklist

**For CV Service:**
- [ ] `/cv` page loads with language selector
- [ ] Visit counter increments on page refresh
- [ ] PDF download works for each language (ES, EN, CA)
- [ ] PDF preview loads inline in browser
- [ ] Mobile rendering uses PDF.js canvas rendering
- [ ] Desktop rendering uses iframe preview

**For SERP Demo:**
- [ ] `/demo/serp` loads React frontend
- [ ] Emergency list displays with mock data
- [ ] Emergency creation endpoint returns 201
- [ ] Resource assignment works
- [ ] QoS alerts display
- [ ] API docs accessible at `/demo/serp/api/docs`

**For CatLink Demo:**
- [ ] `/demo/catlink` loads React frontend
- [ ] Charger map displays with mock locations
- [ ] Charging request evaluation works
- [ ] Fraud detection triggers on known fraud phones
- [ ] WebSocket agent logs display in real-time

**For Infrastructure:**
- [ ] SSH on custom port 2222 works
- [ ] HTTPS certificates installed and valid
- [ ] Nginx proxying routes requests correctly
- [ ] fail2ban bans after 3 SSH failures
- [ ] UFW allows only ports 80, 443, 2222

## Build and Deployment Testing

**Docker image building (`scripts/build-and-push.sh`):**
- Multi-stage builds for frontend (builder + serve)
- ARM64 architecture targeting for t4g.small instance
- Images pushed to Docker Hub registry

**Production Dockerfile pattern:**
```dockerfile
FROM public.ecr.aws/docker/library/node:20-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm install && npm cache clean --force
COPY . .
RUN npm run build

FROM public.ecr.aws/docker/library/node:20-alpine
WORKDIR /app
RUN npm install -g serve
COPY --from=builder /app/build ./build
EXPOSE 3000
CMD ["serve", "-s", "build", "-l", "3000", "--no-compression"]
```

**Testing approach:**
1. Build succeeds with no errors
2. Image can be pushed to Docker Hub
3. `docker-compose up` starts all services
4. Services are accessible on configured ports

---

*Testing analysis: 2026-03-20*
