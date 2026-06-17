from datetime import date

from fastapi import HTTPException

from app.database import get_connection
from app.models.schemas import MedicationReminderRequest
from app.services.fcm_service import send_push_notification


def generate_medication_reminders(
    request: MedicationReminderRequest,
) -> dict:
    target_date = request.target_date or date.today().isoformat()
    conn = get_connection()
    try:
        cursor = conn.cursor()
        user = cursor.execute(
            "SELECT id FROM users WHERE id = ?",
            (request.user_id,),
        ).fetchone()
        if not user:
            raise HTTPException(status_code=404, detail="사용자가 없습니다.")

        # Try to get FCM token (ignore if column doesn't exist)
        try:
            fcm_token = cursor.execute("SELECT fcm_token FROM users WHERE id = ?", (request.user_id,)).fetchone()
            user_fcm_token = fcm_token["fcm_token"] if fcm_token else None
        except Exception:
            user_fcm_token = None

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
            title = "복약 예정 알림"
            message_body = f"{schedule['scheduled_time']} {schedule['product_name']} 복약 예정입니다."
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
                    title,
                    message_body,
                ),
            )
            if user_fcm_token:
                send_push_notification(user_fcm_token, title, message_body, data={"schedule_id": str(schedule["id"])})
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
