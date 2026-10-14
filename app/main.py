from contextlib import asynccontextmanager
from pathlib import Path
import sqlite3

from fastapi import Depends, FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from app.core.config import (
    APP_ENV,
    APP_VERSION,
    CLOVA_OCR_API_URL,
    CLOVA_OCR_ENABLED,
    CLOVA_OCR_SECRET_KEY,
    DEMO_SEED_ENABLED,
)
from app.database import DB_PATH, database_backend
from app.core.auth import auth_enforced, require_authorized_request, validate_auth_configuration
from app.routes import (
    auth,
    biosignal,
    biosignal_test,
    dashboard,
    drug_explain,
    dur_analysis,
    guardians,
    internal,
    medication_logs,
    notifications,
    prescription,
    users,
)
from init_db import initialize_database
from app.services.pharmacist.easy_category_db import initialize_easy_category_map_db
from app.services.seed_mvp_medicines import ensure_mvp_demo_medicines
from app.services.pharmacist.retrieve import start_background_medicine_detail_refresh
from app.services.dur_sync_service import start_background_dur_sync


@asynccontextmanager
async def lifespan(_: FastAPI):
    validate_auth_configuration()
    initialize_database(preserve_records=auth_enforced())
    from app.services.mfds_drug_permission.db import initialize_permission_db
    initialize_permission_db()
    initialize_easy_category_map_db()
    if DEMO_SEED_ENABLED:
        ensure_mvp_demo_medicines()
    start_background_medicine_detail_refresh()
    start_background_dur_sync()
    yield


app = FastAPI(
    title="알콩약콩 MVP API",
    version=APP_VERSION,
    lifespan=lifespan,
)


@app.exception_handler(sqlite3.OperationalError)
async def storage_unavailable(request, error):
    # Neither SQL values nor connection credentials belong in an API response.
    return JSONResponse(status_code=503, content={"detail": "저장소에 연결하지 못했어요. 잠시 후 다시 시도해 주세요."})

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

for router in (
    auth.router,
    users.router,
    internal.router,
    guardians.router,
    prescription.router,
    dur_analysis.router,
    drug_explain.router,
    biosignal.router,
    biosignal_test.router,
    medication_logs.router,
    notifications.router,
    dashboard.router,
):
    app.include_router(router, dependencies=[Depends(require_authorized_request)])


@app.get("/")
def root():
    return {"message": "알콩약콩 MVP 서버 실행 중", "docs": "/docs"}


@app.get("/health")
def health():
    from app.postgres import schema_for_role
    return {
        "status": "ok",
        "version": APP_VERSION,
        "environment": APP_ENV,
        "database": f"postgresql:{schema_for_role()}" if database_backend() == "postgresql" else f"sqlite:{Path(DB_PATH).name}",
        "demo_seed_enabled": DEMO_SEED_ENABLED,
        "ocr_engine": "clova-ocr-v2",
        "ocr_configured": bool(
            CLOVA_OCR_ENABLED and CLOVA_OCR_API_URL and CLOVA_OCR_SECRET_KEY
        ),
    }
