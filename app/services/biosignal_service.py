from datetime import datetime, timedelta
from typing import List

from fastapi import HTTPException

from app.database import get_connection
from app.models.schemas import HeartRateCreate
from app.services.fcm_service import send_push_notification


def save_heart_rate_bulk(requests: List[HeartRateCreate]) -> dict:
    if not requests:
        return {"message": "No logs provided."}
        
    conn = get_connection()
    try:
        cursor = conn.cursor()
        user_id = requests[0].user_id
        if not cursor.execute(
            "SELECT 1 FROM users WHERE id = ?", (user_id,)
        ).fetchone():
            raise HTTPException(status_code=404, detail="사용자가 없습니다.")

        # 1. Bulk Insert
        log_ids = []
        for req in requests:
            measured_at = req.measured_at or datetime.now().isoformat(timespec="seconds")
            cursor.execute(
                """
                INSERT INTO heart_rate_logs (
                    user_id, bpm, measured_at, device_id, source
                ) VALUES (?, ?, ?, ?, ?)
                """,
                (
                    req.user_id,
                    req.bpm,
                    measured_at,
                    req.device_id,
                    req.source,
                ),
            )
            log_ids.append(cursor.lastrowid)
            
        # 2. 통계 기반 임계치 판정 (μ + 2σ)
        baseline = cursor.execute(
            "SELECT * FROM baseline_heart_rate WHERE user_id = ?",
            (user_id,),
        ).fetchone()
        
        # 만약 baseline이 없다면 최초 1회 생성 (임시로 μ = 평균, σ = 10 이라 가정)
        if not baseline:
            avg_bpm = int(sum(r.bpm for r in requests) / len(requests))
            std_dev = 10.0
            cursor.execute(
                """
                INSERT INTO baseline_heart_rate (
                    user_id, resting_bpm, min_normal_bpm, max_normal_bpm
                ) VALUES (?, ?, ?, ?)
                """,
                (user_id, avg_bpm, avg_bpm - (2*std_dev), avg_bpm + (2*std_dev)),
            )
            baseline = cursor.execute(
                "SELECT * FROM baseline_heart_rate WHERE user_id = ?",
                (user_id,),
            ).fetchone()

        # threshold = μ + 2σ 에 해당하는 상한선
        threshold = baseline["max_normal_bpm"]
        
        # 3. 5분 시계열 윈도우 기반 빈도 판정
        abnormal_count = sum(1 for r in requests if r.bpm > threshold)
        total_count = len(requests)
        
        event = None
        if total_count > 0 and (abnormal_count / total_count) >= 0.5:
            # 50% 이상 초과 시 이상 징후 확정
            avg_trigger_bpm = int(sum(r.bpm for r in requests if r.bpm > threshold) / abnormal_count)
            event_type = "HIGH_HEART_RATE_ANOMALY"
            severity = "HIGH"
            
            cursor.execute(
                """
                INSERT INTO abnormal_events (
                    user_id, heart_rate_log_id, event_type, bpm,
                    baseline_bpm, severity, occurred_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    user_id,
                    log_ids[-1],
                    event_type,
                    avg_trigger_bpm,
                    baseline["resting_bpm"],
                    severity,
                    datetime.now().isoformat(timespec="seconds"),
                ),
            )
            event_id = cursor.lastrowid
            event = {
                "id": event_id,
                "event_type": event_type,
                "severity": severity,
            }
            
            # 보호자 알림 발송 (웅건님 기존 로직 유지)
            guardians = cursor.execute(
                """
                SELECT id, fcm_token FROM guardians
                WHERE user_id = ? AND notification_enabled = 1
                """,
                (user_id,),
            ).fetchall()
            for guardian in guardians:
                title = "심박 이상 감지 (통계적)"
                message = f"사용자의 심박수가 평균 범위를 지속적으로 초과했습니다. ({avg_trigger_bpm} BPM)"
                cursor.execute(
                    """
                    INSERT INTO notifications (
                        user_id, guardian_id, abnormal_event_id,
                        notification_type, title, message
                    ) VALUES (?, ?, ?, 'ABNORMAL_HEART_RATE', ?, ?)
                    """,
                    (
                        user_id,
                        guardian["id"],
                        event_id,
                        title,
                        message,
                    ),
                )
                if guardian.get("fcm_token"):
                    send_push_notification(guardian["fcm_token"], title, message, data={"event_id": str(event_id)})

        conn.commit()
        return {
            "inserted_logs": len(log_ids),
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
