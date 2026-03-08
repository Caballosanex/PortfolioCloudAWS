"""CV Service - Generates PDF CVs in 3 languages with a visit counter."""

import sqlite3
from pathlib import Path
from fastapi import FastAPI, Request
from fastapi.responses import HTMLResponse, FileResponse
from jinja2 import Environment, FileSystemLoader
import yaml

BASE_DIR = Path(__file__).parent
GENERATED_DIR = BASE_DIR / "generated"
GENERATED_DIR.mkdir(exist_ok=True)
DATA_DIR = BASE_DIR / "data"
TEMPLATES_DIR = BASE_DIR / "templates"
DB_PATH = BASE_DIR / "visits.db"

app = FastAPI(title="CV Service")

jinja_env = Environment(loader=FileSystemLoader(str(TEMPLATES_DIR)))

LANGUAGES = {
    "es": {"label": "Spanish", "file_suffix": "ES"},
    "en": {"label": "English", "file_suffix": "EN"},
    "ca": {"label": "Catalan", "file_suffix": "CA"},
}


def get_db():
    db = sqlite3.connect(str(DB_PATH))
    db.execute(
        "CREATE TABLE IF NOT EXISTS visits (id INTEGER PRIMARY KEY, count INTEGER DEFAULT 0)"
    )
    db.execute("INSERT OR IGNORE INTO visits (id, count) VALUES (1, 0)")
    db.commit()
    return db


def increment_visits() -> int:
    db = get_db()
    db.execute("UPDATE visits SET count = count + 1 WHERE id = 1")
    db.commit()
    count = db.execute("SELECT count FROM visits WHERE id = 1").fetchone()[0]
    db.close()
    return count


def get_visits() -> int:
    db = get_db()
    count = db.execute("SELECT count FROM visits WHERE id = 1").fetchone()[0]
    db.close()
    return count


def load_cv_data(lang: str) -> dict:
    path = DATA_DIR / f"cv_{lang}.yml"
    with open(path, "r", encoding="utf-8") as f:
        return yaml.safe_load(f)


def generate_pdf(lang: str) -> Path:
    """Generate PDF from YAML data + HTML template using WeasyPrint."""
    from weasyprint import HTML

    data = load_cv_data(lang)
    template = jinja_env.get_template("cv.html")
    html_content = template.render(cv=data, lang=lang)

    suffix = LANGUAGES[lang]["file_suffix"]
    name = data["personal"]["name"].replace(" ", "_")
    filename = f"CV_{name}_{suffix}.pdf"
    output_path = GENERATED_DIR / filename

    HTML(string=html_content, base_url=str(BASE_DIR)).write_pdf(str(output_path))
    return output_path


@app.get("/", response_class=HTMLResponse)
async def cv_page(request: Request):
    """Main CV page with language selector, download buttons, and visit counter."""
    count = increment_visits()
    template = jinja_env.get_template("cv_page.html")
    return HTMLResponse(template.render(visit_count=count, languages=LANGUAGES))


@app.get("/preview/{lang}")
async def preview_cv(lang: str):
    """Serve CV PDF inline for browser preview."""
    if lang not in LANGUAGES:
        return {"error": "Language not supported. Use: es, en, ca"}

    pdf_path = generate_pdf(lang)
    return FileResponse(
        path=str(pdf_path),
        media_type="application/pdf",
        headers={"Content-Disposition": "inline"},
    )


@app.get("/download/{lang}")
async def download_cv(lang: str):
    """Download CV as PDF in the specified language."""
    if lang not in LANGUAGES:
        return {"error": "Language not supported. Use: es, en, ca"}

    pdf_path = generate_pdf(lang)
    return FileResponse(
        path=str(pdf_path),
        filename=pdf_path.name,
        media_type="application/pdf",
    )


@app.get("/api/visits")
async def api_visits():
    return {"visits": get_visits()}
