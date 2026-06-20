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
    easy_explanation: Optional[str] = None

    administration_times: List[str] = Field(default_factory=list)


class PrescriptionOCRRequest(BaseModel):
    user_id: str
    image_path: Optional[str] = None
    image_data: Optional[str] = None  # Base64 encoded image string
    ocr_text: Optional[str] = None
    hospital_name: Optional[str] = None
    pharmacy_name: Optional[str] = None
    prescribed_date: Optional[str] = None
    expire_date: Optional[str] = None
    mock_items: List[OCRMedicineItem] = Field(default_factory=list)


class DurAnalyzeRequest(BaseModel):
    user_id: str
    medicine_codes: List[str] = Field(default_factory=list)
    is_pregnant: Optional[bool] = None


class DurSyncRequest(BaseModel):
    types: List[str] = Field(
        default_factory=lambda: [
            "병용금기",
            "연령금기",
            "임부금기",
            "효능군중복",
        ]
    )
    page_size: int = Field(default=100, ge=1, le=1000)
    max_pages: Optional[int] = Field(default=None, ge=1)


class MedicationLogCreate(BaseModel):
    user_id: str
    schedule_id: int = Field(gt=0)


class MedicationReminderRequest(BaseModel):
    user_id: str
    target_date: Optional[str] = None


class MarkMissedRequest(BaseModel):
    user_id: str
    grace_hours: int = Field(default=2, ge=0, le=24)
    current_time: Optional[str] = None


class HeartRateCreate(BaseModel):
    user_id: str
    bpm: int = Field(gt=0)
    measured_at: Optional[str] = None
    device_id: Optional[str] = None
    source: str = "POLAR"


class DrugExplainChatRequest(BaseModel):
    user_id: str
    message: str
