from fastapi import APIRouter, HTTPException
from app.database import get_connection
from app.models.schemas import PrescriptionDrugCreate

router = APIRouter(prefix="/prescription-drugs", tags=["Prescription Drugs"])

@router.post("/")
def create_prescription_drug(drug: PrescriptionDrugCreate):
    conn = get_connection()
    cursor = conn.cursor()

    # prescription 존재 여부 확인
    cursor.execute("SELECT id FROM prescriptions WHERE id = ?", (drug.prescription_id,))
    prescription = cursor.fetchone()

    if not prescription:
        conn.close()
        raise HTTPException(status_code=404, detail="해당 prescription_id의 처방전이 없습니다.")

    cursor.execute("""
        INSERT INTO prescription_drugs (
            prescription_id, drug_name, ingredient_name, dosage, unit,
            frequency_per_day, times_per_take,
            morning, lunch, dinner, bedtime,
            duration_days, warning_note
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    """, (
        drug.prescription_id,
        drug.drug_name,
        drug.ingredient_name,
        drug.dosage,
        drug.unit,
        drug.frequency_per_day,
        drug.times_per_take,
        drug.morning,
        drug.lunch,
        drug.dinner,
        drug.bedtime,
        drug.duration_days,
        drug.warning_note
    ))

    conn.commit()
    drug_id = cursor.lastrowid
    conn.close()

    return {
        "message": "처방 약 등록 완료",
        "prescription_drug_id": drug_id,
        "drug_name": drug.drug_name
    }

@router.get("/{prescription_id}")
def get_prescription_drugs(prescription_id: int):
    conn = get_connection()
    cursor = conn.cursor()

    cursor.execute("""
        SELECT * FROM prescription_drugs
        WHERE prescription_id = ?
        ORDER BY id ASC
    """, (prescription_id,))

    rows = cursor.fetchall()
    conn.close()

    return [dict(row) for row in rows]