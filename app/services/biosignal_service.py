from datetime import datetime

from fastapi import HTTPException

from app.database import get_connection
from app.models.schemas import HeartRateCreate


def save_heart_rate(request: HeartRateCreate) -> dict:
    conn = get_connection()
    try:
        cursor = conn.cursor()
        if not cursor.execute(
            "SELECT 1 FROM users WHERE id = ?", (request.user_id,)
        ).fetchone():
            raise HTTPException(status_code=404, detail="사용자가 없습니다.")

        measured_at = request.measured_at or datetime.now().isoformat(timespec="seconds")
        cursor.execute(
            """
            INSERT INTO heart_rate_logs (
                user_id, bpm, measured_at, device_id, source
            ) VALUES (?, ?, ?, ?, ?)
            """,
            (
                request.user_id,
                request.bpm,
                measured_at,
                request.device_id,
                request.source,
            ),
        )
        log_id = cursor.lastrowid
        baseline = cursor.execute(
            "SELECT * FROM baseline_heart_rate WHERE user_id = ?",
            (request.user_id,),
        ).fetchone()

        conn.commit()
        return {
            "heart_rate_log_id": log_id,
            "bpm": request.bpm,
            "measured_at": measured_at,
            "baseline": dict(baseline) if baseline else None,
            "abnormal_event": None,
        }
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


def get_abnormal_events(user_id: str) -> list[dict]:
    conn = get_connection()
    try:
        rows = conn.execute(
            """
            SELECT * FROM abnormal_events
            WHERE user_id = ?
            ORDER BY occurred_at DESC, id DESC
            """,
            (user_id,),
        ).fetchall()
        return [dict(row) for row in rows]
    finally:
        conn.close()
