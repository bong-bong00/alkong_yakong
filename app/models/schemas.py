from typing import Optional
from pydantic import BaseModel

class UserCreate(BaseModel):
    name: str
    birth_date: Optional[str] = None
    gender: Optional[str] = None
    phone: Optional[str] = None

class PrescriptionCreate(BaseModel):
    user_id: int
    source_type: str
    hospital_name: Optional[str] = None
    pharmacy_name: Optional[str] = None
    prescribed_date: Optional[str] = None
    expire_date: Optional[str] = None
    original_image_path: Optional[str] = None
    ocr_text: Optional[str] = None

class PrescriptionDrugCreate(BaseModel):
    prescription_id: int
    drug_name: str
    ingredient_name: Optional[str] = None
    dosage: Optional[str] = None
    unit: Optional[str] = None
    frequency_per_day: Optional[int] = None
    times_per_take: Optional[int] = None
    morning: int = 0
    lunch: int = 0
    dinner: int = 0
    bedtime: int = 0
    duration_days: Optional[int] = None
    warning_note: Optional[str] = None

class ScheduleGenerateRequest(BaseModel):
    user_id: int
    prescription_id: int
    start_date: str
    end_date: str

class MedicationLogCreate(BaseModel):
    user_id: int
    schedule_id: int
    image_path: Optional[str] = None
    verification_result: str
    confidence_score: Optional[float] = None
    predicted_drugs_json: Optional[str] = None
    missing_drugs_json: Optional[str] = None
    extra_drugs_json: Optional[str] = None
    note: Optional[str] = None