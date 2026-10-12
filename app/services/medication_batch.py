"""All medicines in one slot are recorded/cancelled atomically, with an audit trail."""
from fastapi import HTTPException
from app.database import get_connection


def update_batch(request, *, undo=False):
    ids = list(dict.fromkeys(request.schedule_ids))
    conn = get_connection()
    try:
        conn.execute("BEGIN IMMEDIATE")
        records = []
        for schedule_id in ids:
            schedule = conn.execute("SELECT * FROM medication_schedules WHERE id=? AND user_id=?", (schedule_id, request.user_id)).fetchone()
            if not schedule:
                raise HTTPException(404, "복약 일정 정보를 확인할 수 없습니다.")
            if undo:
                conn.execute("UPDATE medication_logs SET status='CANCELLED', note='사용자가 완료 기록을 취소함' WHERE user_id=? AND schedule_id=? AND status='TAKEN'", (request.user_id, schedule_id))
                conn.execute("UPDATE medication_schedules SET status='PENDING' WHERE id=?", (schedule_id,))
            else:
                previous = conn.execute("SELECT * FROM medication_logs WHERE user_id=? AND schedule_id=? AND status='TAKEN' LIMIT 1", (request.user_id, schedule_id)).fetchone()
                if not previous:
                    conn.execute("INSERT INTO medication_logs(user_id,schedule_id,user_medicine_id,status) VALUES(?,?,?,'TAKEN')", (request.user_id, schedule_id, schedule["user_medicine_id"]))
                conn.execute("UPDATE medication_schedules SET status='TAKEN' WHERE id=?", (schedule_id,))
            records.append(schedule_id)
        conn.commit()
        return {"user_id": request.user_id, "schedule_ids": records, "status": "PENDING" if undo else "TAKEN"}
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()
