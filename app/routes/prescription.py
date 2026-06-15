from fastapi import APIRouter

from app.models.schemas import PrescriptionOCRRequest
from app.services.prescription_service import (
    create_prescription_from_ocr,
    get_user_prescriptions,
)


router = APIRouter(prefix="/api/v1", tags=["Prescription"])


@router.post("/prescriptions/ocr")
def register_prescription_ocr(request: PrescriptionOCRRequest):
    return create_prescription_from_ocr(request)


@router.get("/users/{user_id}/prescriptions")
def list_user_prescriptions(user_id: str):
    return get_user_prescriptions(user_id)
