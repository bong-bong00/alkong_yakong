from datetime import date

from fastapi import HTTPException

from app.database import get_connection
from app.models.schemas import MedicationReminderRequest


def generate_medication_reminders(
    request: MedicationReminderRequest,
) -> dict:
    target_date = request.target_date or date.today().isoformat()
    conn = get_connection()
    try:
        cursor = conn.cursor()
        if not cursor.execute(
            "SELECT 1 FROM users WHERE id = ?",
            (request.user_id,),
        ).fetchone():
            raise HTTPException(status_code=404, detail="사용자가 없습니다.")

        schedules = cursor.execute(
            """
            SELECT ms.id, ms.scheduled_time, m.product_name
            FROM medication_schedules ms
            JOIN user_medicines um ON um.id = ms.user_medicine_id
            JOIN medicines m ON m.medicine_code = um.medicine_code
            WHERE ms.user_id = ? AND ms.scheduled_date = ?
            ORDER BY ms.scheduled_time, ms.id
            """,
            (request.user_id, target_date),
        ).fetchall()

        created = []
        skipped = 0
        for schedule in schedules:
            existing = cursor.execute(
                """
                SELECT id FROM notifications
                WHERE user_id = ? AND schedule_id = ?
                  AND notification_type = 'MEDICATION_REMINDER'
                  AND guardian_id IS NULL
                LIMIT 1
                """,
                (request.user_id, schedule["id"]),
            ).fetchone()
            if existing:
                skipped += 1
                continue
            cursor.execute(
                """
                INSERT INTO notifications (
                    user_id, schedule_id, notification_type,
                    title, message, status
                ) VALUES (?, ?, 'MEDICATION_REMINDER', ?, ?, 'PENDING')
                """,
                (
                    request.user_id,
                    schedule["id"],
                    "복약 예정 알림",
                    f"{schedule['scheduled_time']} "
                    f"{schedule['product_name']} 복약 예정입니다.",
                ),
            )
            created.append(
                dict(
                    cursor.execute(
                        "SELECT * FROM notifications WHERE id = ?",
                        (cursor.lastrowid,),
                    ).fetchone()
                )
            )
        conn.commit()
        return {
            "user_id": request.user_id,
            "target_date": target_date,
            "schedule_count": len(schedules),
            "created_count": len(created),
            "skipped_duplicate_count": skipped,
            "notifications": created,
        }
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


def get_user_notifications(user_id: str) -> list[dict]:
    conn = get_connection()
    try:
        if not conn.execute(
            "SELECT 1 FROM users WHERE id = ?",
            (user_id,),
        ).fetchone():
            raise HTTPException(status_code=404, detail="사용자가 없습니다.")
        rows = conn.execute(
            """
            SELECT n.*, g.guardian_name, g.relationship
            FROM notifications n
            LEFT JOIN guardians g ON g.id = n.guardian_id
            WHERE n.user_id = ?
            ORDER BY n.created_at DESC, n.id DESC
            """,
            (user_id,),
        ).fetchall()
        return [dict(row) for row in rows]
    finally:
        conn.close()
