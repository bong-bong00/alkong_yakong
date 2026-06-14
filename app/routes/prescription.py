from fastapi import APIRouter, HTTPException
from app.database import get_connection
from app.models.schemas import PrescriptionCreate

router = APIRouter(prefix="/prescriptions", tags=["Prescriptions"])

@router.post("/")
def create_prescription(prescription: PrescriptionCreate):
    conn = get_connection()
    cursor = conn.cursor()

    # user 존재 여부 확인
    cursor.execute("SELECT id FROM users WHERE id = ?", (prescription.user_id,))
    user = cursor.fetchone()

    if not user:
        conn.close()
        raise HTTPException(status_code=404, detail="해당 user_id의 사용자가 없습니다.")

    cursor.execute("""
        INSERT INTO prescriptions (
            user_id, source_type, hospital_name, pharmacy_name,
            prescribed_date, expire_date, original_image_path, ocr_text
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    """, (
        prescription.user_id,
        prescription.source_type,
        prescription.hospital_name,
        prescription.pharmacy_name,
        prescription.prescribed_date,
        prescription.expire_date,
        prescription.original_image_path,
        prescription.ocr_text
    ))

    conn.commit()
    prescription_id = cursor.lastrowid
    conn.close()

    return {
        "message": "처방전 등록 완료",
        "prescription_id": prescription_id,
        "user_id": prescription.user_id
    }

@router.get("/{user_id}")
def get_prescriptions_by_user(user_id: int):
    conn = get_connection()
    cursor = conn.cursor()

    cursor.execute("""
        SELECT * FROM prescriptions
        WHERE user_id = ?
        ORDER BY id DESC
    """, (user_id,))

    rows = cursor.fetchall()
    conn.close()

    return [dict(row) for row in rows]