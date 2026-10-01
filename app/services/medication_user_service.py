"""Bootstrap the medication-service user without registering any medicines."""

from app.database import get_connection


def ensure_medication_user(user_id: str) -> None:
    # Authentication lives on the team service; only the shared ID is needed here.
    # Never seed prescriptions, user_medicines or schedules during a read.
    conn = get_connection()
    try:
        conn.execute(
            "INSERT OR IGNORE INTO users (id, name, role) VALUES (?, '사용자', 'PATIENT')",
            (user_id,),
        )
        conn.commit()
    finally:
        conn.close()
