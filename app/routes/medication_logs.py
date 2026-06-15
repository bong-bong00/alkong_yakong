from fastapi import APIRouter

from app.models.schemas import MedicationLogCreate
from app.services.medication_service import mark_medication_taken


router = APIRouter(prefix="/api/v1", tags=["Medication Logs"])


@router.post("/medication-logs")
def create_medication_log(request: MedicationLogCreate):
    return mark_medication_taken(request)
