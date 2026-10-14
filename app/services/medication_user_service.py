"""Bootstrap the medication-service user without registering any medicines."""

from app.database import get_connection
from app.core.auth import auth_enforced
from fastapi import HTTPException


def sync_medication_health(user_id: str, profile: dict) -> None:
    """Mirror only authoritative main-server fields needed for medication checks."""
    import json
    fields = ("name", "birth_date", "gender", "is_pregnant", "pregnancy_status", "allergies", "diseases", "past_illnesses", "smoking", "drinking")
    updates = {key: json.dumps(profile[key], ensure_ascii=False) if isinstance(profile[key], list) else profile[key]
               for key in fields if key in profile}
    ensure_medication_user(user_id)
    if not updates:
        return
    conn = get_connection()
    try:
        existing = dict(conn.execute("SELECT * FROM users WHERE id=?", (user_id,)).fetchone())
        updates = {key: value for key, value in updates.items() if existing.get(key) != value}
        if not updates:
            return
        conn.execute("UPDATE users SET " + ",".join(key + "=?" for key in updates) + " WHERE id=?", (*updates.values(), user_id))
        conn.commit()
    finally:
        conn.close()


def ensure_medication_user(user_id: str) -> None:
    # Authentication lives on the team service; only the shared ID is needed here.
    # Never seed prescriptions, user_medicines or schedules during a read.
    conn = get_connection()
    try:
        if auth_enforced():
            if not conn.execute("SELECT 1 FROM users WHERE id = ?", (user_id,)).fetchone():
                raise HTTPException(status_code=403, detail="인증된 사용자 준비가 필요해요.")
            return
        conn.execute(
            "INSERT OR IGNORE INTO users (id, name, role) VALUES (?, '사용자', 'PATIENT')",
            (user_id,),
        )
        conn.commit()
    finally:
        conn.close()
