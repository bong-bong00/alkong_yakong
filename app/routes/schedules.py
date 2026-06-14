from datetime import datetime, timedelta
from fastapi import APIRouter, HTTPException
from app.database import get_connection
from app.models.schemas import ScheduleGenerateRequest

router = APIRouter(prefix="/schedules", tags=["Schedules"])

@router.post("/generate")
def generate_schedules(request: ScheduleGenerateRequest):
    conn = get_connection()
    cursor = conn.cursor()

    # 사용자 확인
    cursor.execute("SELECT id FROM users WHERE id = ?", (request.user_id,))
    user = cursor.fetchone()
    if not user:
        conn.close()
        raise HTTPException(status_code=404, detail="사용자가 없습니다.")

    # 처방전 확인
    cursor.execute("SELECT id FROM prescriptions WHERE id = ?", (request.prescription_id,))
    prescription = cursor.fetchone()
    if not prescription:
        conn.close()
        raise HTTPException(status_code=404, detail="처방전이 없습니다.")

    # 처방 약 목록 불러오기
    cursor.execute("""
        SELECT * FROM prescription_drugs
        WHERE prescription_id = ?
    """, (request.prescription_id,))
    drugs = cursor.fetchall()

    if not drugs:
        conn.close()
        raise HTTPException(status_code=404, detail="처방 약 목록이 없습니다.")

    start_date = datetime.strptime(request.start_date, "%Y-%m-%d")
    end_date = datetime.strptime(request.end_date, "%Y-%m-%d")

    if end_date < start_date:
        conn.close()
        raise HTTPException(status_code=400, detail="end_date는 start_date보다 같거나 뒤여야 합니다.")

    created_count = 0
    current_date = start_date

    while current_date <= end_date:
        date_str = current_date.strftime("%Y-%m-%d")

        for drug in drugs:
            time_slots = []

            if drug["morning"] == 1:
                time_slots.append(("MORNING", "08:00"))
            if drug["lunch"] == 1:
                time_slots.append(("LUNCH", "13:00"))
            if drug["dinner"] == 1:
                time_slots.append(("DINNER", "19:00"))
            if drug["bedtime"] == 1:
                time_slots.append(("BEDTIME", "22:00"))

            for time_slot, scheduled_time in time_slots:
                cursor.execute("""
                    INSERT INTO medication_schedules (
                        user_id, prescription_drug_id, scheduled_date,
                        time_slot, scheduled_time, status
                    )
                    VALUES (?, ?, ?, ?, ?, ?)
                """, (
                    request.user_id,
                    drug["id"],
                    date_str,
                    time_slot,
                    scheduled_time,
                    "PENDING"
                ))
                created_count += 1

        current_date += timedelta(days=1)

    conn.commit()
    conn.close()

    return {
        "message": "복약 스케줄 생성 완료",
        "created_count": created_count,
        "user_id": request.user_id,
        "prescription_id": request.prescription_id
    }

@router.get("/{user_id}")
def get_schedules_by_user(user_id: int):
    conn = get_connection()
    cursor = conn.cursor()

    cursor.execute("""
        SELECT 
            ms.id,
            ms.user_id,
            ms.prescription_drug_id,
            ms.scheduled_date,
            ms.time_slot,
            ms.scheduled_time,
            ms.status,
            pd.drug_name
        FROM medication_schedules ms
        JOIN prescription_drugs pd
            ON ms.prescription_drug_id = pd.id
        WHERE ms.user_id = ?
        ORDER BY ms.scheduled_date ASC, ms.scheduled_time ASC
    """, (user_id,))

    rows = cursor.fetchall()
    conn.close()

    return [dict(row) for row in rows]