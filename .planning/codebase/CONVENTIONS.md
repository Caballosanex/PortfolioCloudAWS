# Coding Conventions

**Analysis Date:** 2026-03-20

## Naming Patterns

**Files:**
- Python modules: `snake_case` (e.g., `mock_backend.py`, `mock_agent_patch.py`)
- Terraform files: `snake_case` with semantic naming (e.g., `ec2.tf`, `security_groups.tf`, `vpc.tf`)
- Ansible playbooks/roles: `snake_case` (e.g., `deploy-landing`, `deploy-cv`, `base`, `security`)
- Shell scripts: `snake_case.sh` (e.g., `build-and-push.sh`, `reset-demos.sh`)
- Static HTML: lowercase (e.g., `index.html`, `cv.js`)

**Functions:**
- Python: `snake_case` for function names (e.g., `generate_pdf()`, `get_db()`, `increment_visits()`, `load_cv_data()`)
- Bash: `snake_case` with descriptive verbs (e.g., `DOCKER_USERNAME`, `TARGET_ARCH`)
- JavaScript: `camelCase` for functions (e.g., `renderPDF()`, `isMobile`, `downloadLink`)

**Variables:**
- Python: `snake_case` for local variables and module-level constants (e.g., `LANGUAGES`, `BASE_DIR`, `DB_PATH`, `GENERATED_DIR`)
- Terraform: `snake_case` for variable names, `var.` prefix for references
- Ansible: `snake_case` in task names, `{{ var_name }}` for variable interpolation
- JavaScript: `camelCase` for variables (e.g., `pdfjsLib`, `isMobile`, `downloadLink`)

**Types/Classes:**
- Python: `PascalCase` for Pydantic models (e.g., `Emergency`, `Resource`, `QosAlert`)
- Terraform: Resources use provider convention, variables use `snake_case`
- Ansible: Task names use clear English descriptors

## Code Style

**Formatting:**
- Python: Follows implicit PEP 8 style (4-space indentation, docstrings present)
- Terraform: 2-space indentation, clear resource organization by file
- Ansible: YAML indentation (2 spaces), clear task descriptions
- Bash: 2-space indentation where applicable, `set -e` for error handling
- JavaScript: Vanilla JS, readable formatting with clear variable names

**Linting:**
- No explicit linting configuration detected in codebase
- No ESLint, Prettier, or Python Black configs present
- Code is manually formatted with consistency emphasis

## Import Organization

**Python (CV Service - `app.py`):**
```python
1. Standard library imports (sqlite3, pathlib, datetime)
2. Third-party imports (fastapi, jinja2, yaml, weasyprint)
3. Local imports (none in this service)
```

Example from `app.py`:
```python
import sqlite3
from pathlib import Path
from fastapi import FastAPI, Request
from fastapi.responses import HTMLResponse, FileResponse
from fastapi.staticfiles import StaticFiles
from jinja2 import Environment, FileSystemLoader
import yaml
```

**Python (Mock APIs - `mock_backend.py`):**
```python
1. Standard library imports (datetime, uuid, copy, random)
2. Third-party imports (fastapi, pydantic)
3. Model definitions (Pydantic BaseModel classes)
4. Constants/seed data
5. Utility functions
6. Route handlers
```

**JavaScript (vanilla):**
- Conditional imports via `typeof` checks (e.g., `if (typeof pdfjsLib !== 'undefined')`)
- Global variable declarations at top level
- Event listener attachment at module level

**Terraform:**
- Provider configuration separate (`providers.tf`)
- Data sources, resources, and outputs in logical groupings
- No explicit import statements (uses implicit module composition)

**Ansible:**
- Task organization by role
- Implicit variable inclusion via `group_vars` and role defaults
- Handler definitions within role structure

## Error Handling

**Python FastAPI patterns:**
- HTTPException with status codes for API errors: `raise HTTPException(404)`
- Try-except blocks for system-level operations (PDF generation, database)
- Graceful fallback on startup tasks: `try/except` with logging in `warmup()` function

Example from `app.py` (warmup function):
```python
def _gen(lang):
    try:
        generate_pdf(lang, force=False)
    except Exception as e:
        print(f"[warmup] Failed to pre-generate {lang}: {e}")
```

**Python error handling in mock backends:**
- `HTTPException(404)` for missing resources
- Dictionary `.get()` with defaults for safe field access
- Optional type hints with `Optional[str]` for nullable fields

**Bash error handling:**
- `set -e` to exit on any error
- Directory existence verification before operations
- No explicit try-catch equivalent; failures halt script

**Ansible error handling:**
- Conditional execution: `when: not ssl_cert.stat.exists`
- `notify` handlers for service restarts on configuration changes
- `args: creates:` for idempotent task guards

## Logging

**Framework:** No external logging framework; uses `print()` for Python and native Ansible logging

**Patterns:**

Python logging:
```python
# Simple print statements for startup/errors
print(f"[warmup] Failed to pre-generate {lang}: {e}")
```

Mock API logging:
- Models include `createdAt`, `updatedAt`, `lastUpdate` timestamp fields
- Pydantic models define audit fields explicitly

Ansible logging:
- Task descriptions serve as log output (no explicit logging statements)
- Handler names indicate actions: `restart cv-service`, `reload nginx`

Bash logging:
- Echo statements with section headers: `echo "=== 1. Copying source code ==="`
- No structured logging; informational progress output

## Comments

**When to Comment:**
- Docstrings on all public functions (Python modules)
- Inline comments for non-obvious logic (particularly in mock implementations)
- Docker Compose and Ansible task names serve as documentation

**JSDoc/TSDoc:**
- Not used (codebase is Python/Terraform/Ansible/Bash focused)

**Example docstring pattern (Python):**
```python
def generate_pdf(lang: str, force: bool = False) -> Path:
    """Generate PDF from YAML data + HTML template using WeasyPrint.
    If the PDF already exists and force=False, return the cached file."""
```

**Example comment pattern (mock backend):**
```python
# --- Data models ---
# --- In-memory stores (reset-friendly) ---
# --- Emergency routes ---
```

## Function Design

**Size:**
- Small, focused functions (10-40 lines typical)
- Single responsibility principle observed
- Utility functions like `_find()` are minimal (5 lines)

**Parameters:**
- Python: Type hints present (e.g., `lang: str`, `force: bool = False`)
- Pydantic models use `BaseModel` for parameter validation
- Optional fields use `Optional[type]` annotation

Example parameter pattern:
```python
async def preview_cv(lang: str):
async def create_emergency(data: Emergency):
async def assign_resources(eid: str, body: dict):
```

**Return Values:**
- FastAPI endpoints return `FileResponse`, `HTMLResponse`, or JSON dict
- PDF generation returns `Path` object
- API endpoints return Pydantic model dumps or dict

Example return patterns:
```python
# File download
return FileResponse(path=str(pdf_path), filename=pdf_path.name, media_type="application/pdf")

# JSON response
return {"visits": get_visits()}

# HTML response
return HTMLResponse(template.render(visit_count=count, languages=LANGUAGES))
```

## Module Design

**Exports:**
- Python FastAPI app: Single `app = FastAPI()` instance exported as module
- Pydantic models: Exported at module level for type annotations
- Mock backends: Provide `app` instance (FastAPI) for integration

**Barrel Files:**
- Not used in this codebase
- Ansible roles use `tasks/main.yml` as single entry point per role
- Terraform files are standalone (no barrel patterns)

## Infrastructure-as-Code Conventions

**Terraform:**
- Variable definitions centralized in `variables.tf`
- Outputs defined in `outputs.tf`
- Sensitive variables marked with `sensitive = true`
- Resources grouped by type (VPC in `vpc.tf`, EC2 in `ec2.tf`, etc.)
- Comments use `#` for inline documentation

Example variable pattern:
```hcl
variable "domain" {
  description = "Domain name"
  type        = string
  default     = "asanchezbl.dev"
}
```

**Ansible:**
- Playbooks reference roles with tags for selective execution
- Variables stored in `group_vars/all.yml` and role `defaults/main.yml`
- Handlers for service restarts isolated in `handlers/main.yml`
- Task names are descriptive (e.g., "Install Nginx", "Enable Nginx site")

Example Ansible task pattern:
```yaml
- name: Create CV service directory
  file:
    path: "{{ base_dir }}/cv-service"
    state: directory
    owner: www-data
    group: www-data
    mode: '0755'
```

## Deployment Patterns

**Docker Compose:**
- Services defined with explicit container names
- Port bindings specify `127.0.0.1` for internal services (e.g., `127.0.0.1:5001:5001`)
- Environment variables passed as list under `environment:`
- Networks defined for service isolation

Example Docker Compose pattern:
```yaml
services:
  backend:
    image: docker.io/caballosanex/serp-backend:latest
    container_name: serp-backend
    restart: unless-stopped
    command: ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "5001"]
    ports:
      - "127.0.0.1:5001:5001"
```

**Shell Scripts:**
- Configuration section at top with `DOCKER_USERNAME`, `TARGET_ARCH`, path variables
- Temporary workspace creation: `WORK_DIR=$(mktemp -d)`
- Explicit cleanup: `rm -rf "$WORK_DIR"`
- Modular section headers: `echo "=== 1. Copying source code ==="`

---

*Convention analysis: 2026-03-20*
