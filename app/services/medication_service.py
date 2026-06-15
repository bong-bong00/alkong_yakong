from fastapi import HTTPException

from app.database import get_connection
from app.models.schemas import MedicationLogCreate


def mark_medication_taken(request: MedicationLogCreate) -> dict:
    conn = get_connection()
    try:
        cursor = conn.cursor()
        schedule = cursor.execute(
            """
            SELECT id, user_id, user_medicine_id, scheduled_date, scheduled_time
            FROM medication_schedules
            WHERE id = ? AND user_id = ?
            """,
            (request.schedule_id, request.user_id),
        ).fetchone()
        if not schedule:
            raise HTTPException(status_code=404, detail="복약 일정이 없습니다.")

        existing = cursor.execute(
            """
            SELECT id, status, taken_at FROM medication_logs
            WHERE schedule_id = ? AND user_id = ? AND status = 'TAKEN'
            ORDER BY id DESC LIMIT 1
            """,
            (request.schedule_id, request.user_id),
        ).fetchone()
        if existing:
            return {
                "id": existing["id"],
                "schedule_id": request.schedule_id,
                "status": existing["status"],
                "taken_at": existing["taken_at"],
                "duplicate": True,
            }

        cursor.execute(
            """
            INSERT INTO medication_logs (
                user_id, schedule_id, user_medicine_id, status
            ) VALUES (?, ?, ?, 'TAKEN')
            """,
            (
                request.user_id,
                request.schedule_id,
                schedule["user_medicine_id"],
            ),
        )
        log_id = cursor.lastrowid
        cursor.execute(
            "UPDATE medication_schedules SET status = 'TAKEN' WHERE id = ?",
            (request.schedule_id,),
        )
        log = cursor.execute(
            "SELECT id, schedule_id, status, taken_at FROM medication_logs WHERE id = ?",
            (log_id,),
        ).fetchone()
        conn.commit()
        return {**dict(log), "duplicate": False}
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()
