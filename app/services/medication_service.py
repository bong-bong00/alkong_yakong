from datetime import datetime, timedelta

from fastapi import HTTPException

from app.database import get_connection
from app.models.schemas import MarkMissedRequest, MedicationLogCreate


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


def mark_missed_medications(request: MarkMissedRequest) -> dict:
    current_time = _parse_datetime(request.current_time)
    cutoff = current_time - timedelta(hours=request.grace_hours)
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
            SELECT ms.id, ms.user_medicine_id, ms.scheduled_date,
                   ms.scheduled_time, m.product_name
            FROM medication_schedules ms
            JOIN user_medicines um ON um.id = ms.user_medicine_id
            JOIN medicines m ON m.medicine_code = um.medicine_code
            WHERE ms.user_id = ?
              AND datetime(ms.scheduled_date || ' ' || ms.scheduled_time)
                  <= datetime(?)
            ORDER BY ms.scheduled_date, ms.scheduled_time, ms.id
            """,
            (
                request.user_id,
                cutoff.strftime("%Y-%m-%d %H:%M:%S"),
            ),
        ).fetchall()

        missed = []
        skipped_taken = 0
        skipped_duplicate = 0
        for schedule in schedules:
            taken = cursor.execute(
                """
                SELECT 1 FROM medication_logs
                WHERE user_id = ? AND schedule_id = ? AND status = 'TAKEN'
                LIMIT 1
                """,
                (request.user_id, schedule["id"]),
            ).fetchone()
            if taken:
                skipped_taken += 1
                continue

            existing = cursor.execute(
                """
                SELECT id, taken_at FROM medication_logs
                WHERE user_id = ? AND schedule_id = ? AND status = 'MISSED'
                ORDER BY id DESC LIMIT 1
                """,
                (request.user_id, schedule["id"]),
            ).fetchone()
            if existing:
                skipped_duplicate += 1
                continue

            cursor.execute(
                """
                INSERT INTO medication_logs (
                    user_id, schedule_id, user_medicine_id,
                    taken_at, status, note
                ) VALUES (?, ?, ?, ?, 'MISSED', ?)
                """,
                (
                    request.user_id,
                    schedule["id"],
                    schedule["user_medicine_id"],
                    current_time.isoformat(timespec="seconds"),
                    f"예정 시각 후 {request.grace_hours}시간 동안 "
                    "복약 완료 기록이 없습니다.",
                ),
            )
            log_id = cursor.lastrowid
            cursor.execute(
                "UPDATE medication_schedules SET status = 'MISSED' WHERE id = ?",
                (schedule["id"],),
            )
            guardian_notifications = _store_guardian_missed_notifications(
                cursor,
                user_id=request.user_id,
                schedule_id=schedule["id"],
                medication_log_id=log_id,
                product_name=schedule["product_name"],
                scheduled_time=schedule["scheduled_time"],
            )
            missed.append(
                {
                    "medication_log_id": log_id,
                    "schedule_id": schedule["id"],
                    "status": "MISSED",
                    "scheduled_date": schedule["scheduled_date"],
                    "scheduled_time": schedule["scheduled_time"],
                    "drug_name": schedule["product_name"],
                    "guardian_notification_count": guardian_notifications,
                }
            )

        conn.commit()
        return {
            "user_id": request.user_id,
            "current_time": current_time.isoformat(timespec="seconds"),
            "grace_hours": request.grace_hours,
            "eligible_schedule_count": len(schedules),
            "missed_count": len(missed),
            "skipped_taken_count": skipped_taken,
            "skipped_duplicate_count": skipped_duplicate,
            "missed": missed,
        }
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


def _store_guardian_missed_notifications(
    cursor,
    *,
    user_id: str,
    schedule_id: int,
    medication_log_id: int,
    product_name: str,
    scheduled_time: str,
) -> int:
    guardians = cursor.execute(
        """
        SELECT id FROM guardians
        WHERE user_id = ? AND notification_enabled = 1
        """,
        (user_id,),
    ).fetchall()
    created = 0
    for guardian in guardians:
        existing = cursor.execute(
            """
            SELECT 1 FROM notifications
            WHERE user_id = ? AND guardian_id = ? AND schedule_id = ?
              AND notification_type = 'MEDICATION_MISSED'
            LIMIT 1
            """,
            (user_id, guardian["id"], schedule_id),
        ).fetchone()
        if existing:
            continue
        cursor.execute(
            """
            INSERT INTO notifications (
                user_id, guardian_id, schedule_id, medication_log_id,
                notification_type, title, message, status
            ) VALUES (?, ?, ?, ?, 'MEDICATION_MISSED', ?, ?, 'STORED')
            """,
            (
                user_id,
                guardian["id"],
                schedule_id,
                medication_log_id,
                "복약 미완료 알림",
                f"{scheduled_time} {product_name} 복약이 확인되지 않았습니다.",
            ),
        )
        created += 1
    return created


def _parse_datetime(value: str | None) -> datetime:
    if not value:
        return datetime.now()
    try:
        return datetime.fromisoformat(value)
    except ValueError as error:
        raise HTTPException(
            status_code=400,
            detail="current_time은 ISO 날짜/시간 형식이어야 합니다.",
        ) from error
