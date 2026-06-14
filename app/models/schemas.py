from typing import List, Optional

from pydantic import BaseModel, Field


class UserCreate(BaseModel):
    name: str
    birth_date: Optional[str] = None
    gender: Optional[str] = None
    phone: Optional[str] = None
    role: str = "PATIENT"


class GuardianCreate(BaseModel):
    user_id: str
    guardian_name: str
    relationship: Optional[str] = None
    phone: Optional[str] = None
    fcm_token: Optional[str] = None
    notification_enabled: bool = True


class OCRMedicineItem(BaseModel):
    drug_name: str
    medicine_code: Optional[str] = None
    ingredient: Optional[str] = None
    dosage: Optional[str] = None
    unit: Optional[str] = None
    frequency_per_day: Optional[int] = None
    times_per_take: Optional[int] = None
    duration_days: Optional[int] = None
    administration_times: List[str] = Field(default_factory=list)


class PrescriptionOCRRequest(BaseModel):
    user_id: str
    image_path: Optional[str] = None
    ocr_text: Optional[str] = None
    hospital_name: Optional[str] = None
    pharmacy_name: Optional[str] = None
    prescribed_date: Optional[str] = None
    expire_date: Optional[str] = None
    mock_items: List[OCRMedicineItem] = Field(default_factory=list)


class DurAnalyzeRequest(BaseModel):
    user_id: str
    medicine_codes: List[str] = Field(default_factory=list)


class HeartRateCreate(BaseModel):
    user_id: str
    bpm: int = Field(gt=0)
    measured_at: Optional[str] = None
    device_id: Optional[str] = None
    source: str = "POLAR"
