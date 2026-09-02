from fastapi import APIRouter

from app.models.schemas import PrescriptionConfirmRequest, PrescriptionOCRRequest
from app.services.prescription_service import (
    confirm_prescription,
    create_prescription_from_ocr,
    get_user_prescriptions,
)


router = APIRouter(prefix="/api/v1", tags=["Prescription"])


@router.post("/prescriptions/ocr")
def preview_prescription_ocr(request: PrescriptionOCRRequest):
    """읽기 미리보기만. 복용 등록은 /prescriptions/confirm."""
    return create_prescription_from_ocr(request)


@router.post("/prescriptions/confirm")
def register_prescription_confirm(request: PrescriptionConfirmRequest):
    return confirm_prescription(request)


@router.get("/users/{user_id}/prescriptions")
def list_user_prescriptions(user_id: str):
    return get_user_prescriptions(user_id)
