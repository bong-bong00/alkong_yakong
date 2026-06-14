from datetime import date

from fastapi import HTTPException

from app.database import get_connection


def get_dashboard(user_id: str, target_date: str | None = None) -> dict:
    selected_date = target_date or date.today().isoformat()
    conn = get_connection()
    try:
        if not conn.execute(
            "SELECT 1 FROM users WHERE id = ?", (user_id,)
        ).fetchone():
            raise HTTPException(status_code=404, detail="사용자가 없습니다.")
        schedules = conn.execute(
            """
            SELECT ms.id, ms.scheduled_date, ms.scheduled_time, ms.time_slot,
                   ms.status, um.medicine_code, m.product_name, m.ingredient
            FROM medication_schedules ms
            JOIN user_medicines um ON um.id = ms.user_medicine_id
            JOIN medicines m ON m.medicine_code = um.medicine_code
            WHERE ms.user_id = ? AND ms.scheduled_date = ?
            ORDER BY ms.scheduled_time, ms.id
            """,
            (user_id, selected_date),
        ).fetchall()
        latest_risk = conn.execute(
            """
            SELECT * FROM risk_results WHERE user_id = ?
            ORDER BY created_at DESC, id DESC LIMIT 1
            """,
            (user_id,),
        ).fetchone()
        latest_event = conn.execute(
            """
            SELECT * FROM abnormal_events WHERE user_id = ?
            ORDER BY occurred_at DESC, id DESC LIMIT 1
            """,
            (user_id,),
        ).fetchone()
        latest_prescription = conn.execute(
            """
            SELECT id, hospital_name, pharmacy_name, prescribed_date,
                   status, created_at
            FROM prescriptions
            WHERE user_id = ?
            ORDER BY created_at DESC
            LIMIT 1
            """,
            (user_id,),
        ).fetchone()
        unread_notifications = conn.execute(
            """
            SELECT COUNT(*) FROM notifications
            WHERE user_id = ? AND status = 'RECORDED'
            """,
            (user_id,),
        ).fetchone()[0]
        schedule_data = [dict(row) for row in schedules]
        return {
            "user_id": user_id,
            "date": selected_date,
            "medication_summary": {
                "total": len(schedule_data),
                "completed": sum(row["status"] == "TAKEN" for row in schedule_data),
                "schedules": schedule_data,
            },
            "latest_risk": dict(latest_risk) if latest_risk else None,
            "latest_prescription": (
                dict(latest_prescription) if latest_prescription else None
            ),
            "latest_abnormal_event": dict(latest_event) if latest_event else None,
            "notification_count": unread_notifications,
        }
    finally:
        conn.close()
