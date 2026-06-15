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
        if not baseline:
            min_bpm = max(40, request.bpm - 20)
            max_bpm = request.bpm + 20
            cursor.execute(
                """
                INSERT INTO baseline_heart_rate (
                    user_id, resting_bpm, min_normal_bpm, max_normal_bpm
                ) VALUES (?, ?, ?, ?)
                """,
                (request.user_id, request.bpm, min_bpm, max_bpm),
            )
            baseline = cursor.execute(
                "SELECT * FROM baseline_heart_rate WHERE user_id = ?",
                (request.user_id,),
            ).fetchone()

        event = None
        if request.bpm < baseline["min_normal_bpm"] or request.bpm > baseline["max_normal_bpm"]:
            event_type = "LOW_HEART_RATE" if request.bpm < baseline["min_normal_bpm"] else "HIGH_HEART_RATE"
            difference = abs(request.bpm - baseline["resting_bpm"])
            severity = "HIGH" if difference >= 40 else "WARNING"
            cursor.execute(
                """
                INSERT INTO abnormal_events (
                    user_id, heart_rate_log_id, event_type, bpm,
                    baseline_bpm, severity, occurred_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    request.user_id,
                    log_id,
                    event_type,
                    request.bpm,
                    baseline["resting_bpm"],
                    severity,
                    measured_at,
                ),
            )
            event_id = cursor.lastrowid
            event = {
                "id": event_id,
                "event_type": event_type,
                "severity": severity,
            }
            guardians = cursor.execute(
                """
                SELECT id FROM guardians
                WHERE user_id = ? AND notification_enabled = 1
                """,
                (request.user_id,),
            ).fetchall()
            for guardian in guardians:
                cursor.execute(
                    """
                    INSERT INTO notifications (
                        user_id, guardian_id, abnormal_event_id,
                        notification_type, title, message
                    ) VALUES (?, ?, ?, 'ABNORMAL_HEART_RATE', ?, ?)
                    """,
                    (
                        request.user_id,
                        guardian["id"],
                        event_id,
                        "심박 이상 감지",
                        f"사용자의 심박수가 {request.bpm} BPM으로 측정되었습니다.",
                    ),
                )

        conn.commit()
        return {
            "heart_rate_log_id": log_id,
            "bpm": request.bpm,
            "measured_at": measured_at,
            "baseline": dict(baseline),
            "abnormal_event": event,
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
