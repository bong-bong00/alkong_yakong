import json
from datetime import date

from fastapi import HTTPException

from app.database import get_connection


def _is_aspirin_fallback_name(*values: object) -> bool:
    combined = " ".join(str(value or "") for value in values)
    compact = combined.replace(" ", "").lower()
    return "아스피린" in compact or "aspirin" in compact


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
                   COALESCE(
                       (
                           SELECT ml.status
                           FROM medication_logs ml
                           WHERE ml.schedule_id = ms.id
                           ORDER BY ml.taken_at DESC, ml.id DESC
                           LIMIT 1
                       ),
                       ms.status,
                       'PENDING'
                   ) AS status,
                   um.id AS user_medicine_id, um.medicine_code,
                   m.product_name, m.ingredient
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
            SELECT id, source_type, hospital_name, pharmacy_name,
                   prescribed_date, ocr_status, status, created_at
            FROM prescriptions
            WHERE user_id = ?
            ORDER BY created_at DESC, rowid DESC
            LIMIT 1
            """,
            (user_id,),
        ).fetchone()
        prescription_data = dict(latest_prescription) if latest_prescription else None
        if prescription_data:
            items = conn.execute(
                """
                SELECT pi.id, pi.medicine_code, pi.ocr_drug_name,
                       pi.dosage, pi.unit, pi.match_status,
                       COALESCE(m.product_name, pi.ocr_drug_name) AS medicine_name
                FROM prescription_items pi
                LEFT JOIN medicines m ON m.medicine_code = pi.medicine_code
                WHERE pi.prescription_id = ?
                ORDER BY pi.id
                """,
                (prescription_data["id"],),
            ).fetchall()
            prescription_items = [
                dict(item)
                for item in items
                if not _is_aspirin_fallback_name(
                    item["ocr_drug_name"],
                    item["medicine_name"],
                )
            ]
            if not prescription_items:
                prescription_data = None
            else:
                prescription_data["items"] = prescription_items
                prescription_data["medicine_names"] = [
                    item["medicine_name"] for item in prescription_items
                ]
                prescription_data["display_name"] = (
                    prescription_data["hospital_name"]
                    or prescription_data["pharmacy_name"]
                    or "OCR 처방전"
                )
                prescription_data["registered_at"] = prescription_data["created_at"]
        unread_notifications = conn.execute(
            """
            SELECT COUNT(*) FROM notifications
            WHERE user_id = ? AND status IN ('PENDING', 'STORED', 'RECORDED')
            """,
            (user_id,),
        ).fetchone()[0]
        recent_notifications = conn.execute(
            """
            SELECT n.id, n.guardian_id, n.schedule_id,
                   n.notification_type, n.title, n.message,
                   n.status, n.created_at, g.guardian_name
            FROM notifications n
            LEFT JOIN guardians g ON g.id = n.guardian_id
            WHERE n.user_id = ?
            ORDER BY n.created_at DESC, n.id DESC
            LIMIT 5
            """,
            (user_id,),
        ).fetchall()
        schedule_data = []
        for row in schedules:
            if _is_aspirin_fallback_name(row["product_name"], row["ingredient"]):
                continue
            item = dict(row)
            item["schedule_id"] = item["id"]
            item["drug_name"] = item["product_name"]
            item["time"] = item["scheduled_time"]
            schedule_data.append(item)
        completed_count = sum(
            row["status"].upper() == "TAKEN" for row in schedule_data
        )
        risk_data = dict(latest_risk) if latest_risk else None
        if risk_data:
            risk_data["matches"] = _json_list(risk_data.get("matches_json"))
            risk_data["total_matches"] = (
                risk_data.get("total_matches") or len(risk_data["matches"])
            )
            risk_data["representative_type"] = (
                risk_data.get("risk_type")
                or (
                    risk_data["matches"][0].get("type")
                    if risk_data["matches"]
                    else None
                )
            )
        return {
            "user_id": user_id,
            "date": selected_date,
            "today_medications": schedule_data,
            "medication_summary": {
                "total": len(schedule_data),
                "completed": completed_count,
                "pending": sum(
                    row["status"].upper() == "PENDING" for row in schedule_data
                ),
                "missed": sum(
                    row["status"].upper() == "MISSED" for row in schedule_data
                ),
                "schedules": schedule_data,
            },
            "latest_risk": risk_data,
            "latest_prescription": prescription_data,
            "latest_abnormal_event": dict(latest_event) if latest_event else None,
            "notification_count": unread_notifications,
            "recent_notifications": [
                dict(notification) for notification in recent_notifications
            ],
        }
    finally:
        conn.close()


def _json_list(value: str | None) -> list:
    if not value:
        return []
    try:
        parsed = json.loads(value)
        return parsed if isinstance(parsed, list) else []
    except json.JSONDecodeError:
        return []
