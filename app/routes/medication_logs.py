from fastapi import APIRouter

from app.models.schemas import MarkMissedRequest, MedicationBatchRequest, MedicationLogCreate
from app.models.response_schemas import MarkMissedResponse, MedicationLogResponse
from app.services.medication_service import (
    cancel_medication_taken,
    cancel_medications_taken,
    mark_medication_taken,
    mark_medications_taken,
    mark_missed_medications,
)


router = APIRouter(prefix="/api/v1", tags=["Medication Logs"])


@router.post("/medication-logs", response_model=MedicationLogResponse)
def create_medication_log(request: MedicationLogCreate):
    return mark_medication_taken(request)


@router.post("/medication-logs/cancel", response_model=MedicationLogResponse)
def cancel_medication_log(request: MedicationLogCreate):
    return cancel_medication_taken(request)


@router.post("/medication-logs/batch")
def create_medication_logs_batch(request: MedicationBatchRequest):
    return mark_medications_taken(request)


@router.post("/medication-logs/batch/cancel")
@router.post("/medication-logs/undo", include_in_schema=False)
def cancel_medication_logs_batch(request: MedicationBatchRequest):
    return cancel_medications_taken(request)


@router.post("/medication-logs/mark-missed", response_model=MarkMissedResponse)
def mark_missed(request: MarkMissedRequest):
    return mark_missed_medications(request)
