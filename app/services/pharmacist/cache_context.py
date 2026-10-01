"""Read-only cache invalidation token; never return raw health information."""
import hashlib
import json
import sqlite3
from datetime import date

from app.database import get_connection


def health_cache_context(user_id: str) -> dict:
    conn = None
    try:
        conn = get_connection()
        row = conn.execute("SELECT * FROM users WHERE id = ?", (user_id,)).fetchone()
        if row is None:
            return {"verified": False}
        data = dict(row)
        fields = ("birth_date", "gender", "height_cm", "weight_kg", "blood_type",
                  "diseases", "past_illnesses", "allergies", "family_illnesses",
                  "past_history", "family_history", "smoking", "drinking",
                  "is_pregnant", "pregnancy_status")
        snapshot = {field: data.get(field) for field in fields}
        snapshot["day"] = date.today().isoformat()
        token = hashlib.sha256(json.dumps(snapshot, sort_keys=True,
                                         ensure_ascii=False).encode()).hexdigest()
        return {"verified": True, "fingerprint": token}
    except sqlite3.Error:
        return {"verified": False}
    finally:
        if conn is not None:
            conn.close()
