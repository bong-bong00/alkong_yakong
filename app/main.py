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


@asynccontextmanager
async def lifespan(_: FastAPI):
    initialize_database()
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
