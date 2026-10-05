import sqlite3

import pytest

from init_db import TABLE_DEFINITIONS
from scripts.seed_presentation_history import seed_hearts, seed_medications, DEMO_SOURCE
from scripts.seed_presentation_history import configure_demo_health, DEMO_HEALTH_PROFILE
import json


def database():
    conn = sqlite3.connect(":memory:")
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys=ON")
    for definition in TABLE_DEFINITIONS.values():
        conn.execute(definition)
    conn.execute("INSERT INTO users(id,name,role) VALUES('demo','시연 전용','PATIENT')")
    conn.execute("INSERT INTO users(id,name,role) VALUES('real','실제 사용자','PATIENT')")
    return conn


def test_synthetic_history_is_past_labelled_and_idempotent():
    with database() as conn:
        assert seed_hearts(conn, "demo") == 30
        assert seed_medications(conn, "demo") == 21
        assert seed_hearts(conn, "demo") == 0
        assert seed_medications(conn, "demo") == 0
        assert conn.execute("SELECT COUNT(*) FROM medication_logs").fetchone()[0] == 19
        assert conn.execute("SELECT COUNT(*) FROM heart_rate_logs WHERE source=?", (DEMO_SOURCE,)).fetchone()[0] == 30
        assert conn.execute("SELECT MAX(measured_at) FROM heart_rate_logs").fetchone()[0].startswith("2026-10-05")
        assert conn.execute("SELECT COUNT(*) FROM user_medicines WHERE is_active=1").fetchone()[0] == 0


def test_real_account_is_rejected_without_writes():
    with database() as conn:
        for seed in (seed_hearts, seed_medications):
            with pytest.raises(ValueError):
                seed(conn, "real")
        assert conn.execute("SELECT COUNT(*) FROM heart_rate_logs").fetchone()[0] == 0
        assert conn.execute("SELECT COUNT(*) FROM prescriptions").fetchone()[0] == 0


def test_demo_health_requires_exact_phone_and_preserves_password():
    with database() as conn:
        with pytest.raises(ValueError):
            configure_demo_health(conn, "demo")
        conn.execute("UPDATE users SET phone='010-1234-5678',password_hash='preserved' WHERE id='demo'")
        configure_demo_health(conn, "demo")
        configure_demo_health(conn, "demo")
        row = conn.execute("SELECT * FROM users WHERE id='demo'").fetchone()
        assert row["password_hash"] == "preserved"
        assert row["phone"] == "010-1234-5678"
        assert row["smoking"] == "폈어요"
        assert row["drinking"] == "자주 마셔요"
        assert json.loads(row["diseases"]) == DEMO_HEALTH_PROFILE["diseases"]
        assert json.loads(row["allergies"]) == DEMO_HEALTH_PROFILE["allergies"]
