from fastapi import APIRouter, HTTPException
from app.database import get_connection
from app.models.schemas import MedicationLogCreate

router = APIRouter(prefix="/medication-logs", tags=["Medication Logs"])

@router.post("/verify")
def create_medication_log(log: MedicationLogCreate):
    conn = get_connection()
    cursor = conn.cursor()

    # schedule 존재 확인
    cursor.execute("SELECT id FROM medication_schedules WHERE id = ?", (log.schedule_id,))
    schedule = cursor.fetchone()

    if not schedule:
        conn.close()
        raise HTTPException(status_code=404, detail="해당 스케줄이 없습니다.")

    cursor.execute("""
        INSERT INTO medication_logs (
            user_id, schedule_id, image_path,
            verification_result, confidence_score,
            predicted_drugs_json, missing_drugs_json, extra_drugs_json,
            note
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    """, (
        log.user_id,
        log.schedule_id,
        log.image_path,
        log.verification_result,
        log.confidence_score,
        log.predicted_drugs_json,
        log.missing_drugs_json,
        log.extra_drugs_json,
        log.note
    ))

    # 스케줄 상태 업데이트 (복약 완료)
    cursor.execute("""
        UPDATE medication_schedules
        SET status = 'TAKEN'
        WHERE id = ?
    """, (log.schedule_id,))

    conn.commit()
    log_id = cursor.lastrowid
    conn.close()

    return {
        "message": "복약 기록 저장 완료",
        "log_id": log_id,
        "status": log.verification_result
    }

@router.get("/{user_id}")
def get_logs(user_id: int):
    conn = get_connection()
    cursor = conn.cursor()

    cursor.execute("""
        SELECT 
            ml.id,
            ml.user_id,
            ml.schedule_id,
            ml.taken_at,
            ml.verification_result,
            ml.confidence_score,
            pd.drug_name,
            ms.scheduled_date,
            ms.time_slot
        FROM medication_logs ml
        JOIN medication_schedules ms ON ml.schedule_id = ms.id
        JOIN prescription_drugs pd ON ms.prescription_drug_id = pd.id
        WHERE ml.user_id = ?
        ORDER BY ml.taken_at DESC
    """, (user_id,))

    rows = cursor.fetchall()
    conn.close()

    return [dict(row) for row in rows]