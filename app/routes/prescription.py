from fastapi import APIRouter

from app.models.schemas import PrescriptionOCRRequest
from app.models.response_schemas import PrescriptionOcrResponse, PrescriptionResponse
from app.services.prescription_service import (
    create_prescription_from_ocr,
    get_user_prescriptions,
)


router = APIRouter(prefix="/api/v1", tags=["Prescription"])


@router.post("/prescriptions/ocr", response_model=PrescriptionOcrResponse)
def register_prescription_ocr(request: PrescriptionOCRRequest):
    return create_prescription_from_ocr(request)


@router.get("/users/{user_id}/prescriptions", response_model=list[PrescriptionResponse])
def list_user_prescriptions(user_id: str):
    return get_user_prescriptions(user_id)
