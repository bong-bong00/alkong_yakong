from fastapi import APIRouter

from app.models.schemas import MarkMissedRequest, MedicationLogCreate, MedicationBatchRequest
from app.services.medication_batch import update_batch
from app.models.response_schemas import MarkMissedResponse, MedicationLogResponse
from app.services.medication_service import (
    mark_medication_taken,
    mark_missed_medications,
)


router = APIRouter(prefix="/api/v1", tags=["Medication Logs"])


@router.post("/medication-logs/batch")
def complete_batch(request: MedicationBatchRequest):
    return update_batch(request)


@router.post("/medication-logs/undo")
def cancel_batch(request: MedicationBatchRequest):
    return update_batch(request, undo=True)


@router.post("/medication-logs", response_model=MedicationLogResponse)
def create_medication_log(request: MedicationLogCreate):
    return mark_medication_taken(request)


@router.post("/medication-logs/mark-missed", response_model=MarkMissedResponse)
def mark_missed(request: MarkMissedRequest):
    return mark_missed_medications(request)
