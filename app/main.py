from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.routes import (
    biosignal,
    dashboard,
    drug_explain,
    dur_analysis,
    guardians,
    medication_logs,
    notifications,
    prescription,
    users,
)
from init_db import initialize_database
from app.services.pharmacist.easy_category_db import initialize_easy_category_map_db
from app.services.seed_mvp_medicines import ensure_mvp_demo_medicines
from app.services.dur_sync_service import start_background_dur_sync


@asynccontextmanager
async def lifespan(_: FastAPI):
    initialize_database()
    initialize_easy_category_map_db()
    ensure_mvp_demo_medicines()
    start_background_dur_sync()
    yield


app = FastAPI(
    title="알콩약콩 MVP API",
    version="1.1.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

for router in (
    users.router,
    guardians.router,
    prescription.router,
    dur_analysis.router,
    drug_explain.router,
    biosignal.router,
    medication_logs.router,
    notifications.router,
    dashboard.router,
):
    app.include_router(router)


@app.get("/")
def root():
    return {"message": "알콩약콩 MVP 서버 실행 중", "docs": "/docs"}


@app.get("/health")
def health():
    return {"status": "ok"}
