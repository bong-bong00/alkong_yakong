from fastapi import APIRouter

from app.models.schemas import MedicationReminderRequest
from app.models.response_schemas import (
    NotificationResponse,
    PrescriptionHelpRequestResponse,
    ReminderGenerationResponse,
)
from app.services.notification_service import (
    generate_medication_reminders,
    get_user_notifications,
    request_prescription_help,
)


router = APIRouter(prefix="/api/v1", tags=["Notifications"])


@router.post(
    "/notifications/generate-medication-reminders",
    response_model=ReminderGenerationResponse,
)
def generate_reminders(request: MedicationReminderRequest):
    return generate_medication_reminders(request)


@router.get("/users/{user_id}/notifications", response_model=list[NotificationResponse])
def list_notifications(user_id: str):
    return get_user_notifications(user_id)


@router.post(
    "/users/{user_id}/prescription-help-requests",
    response_model=PrescriptionHelpRequestResponse,
)
def request_help_with_prescription(user_id: str):
    """어르신이 가족에게 처방전 넣기를 부탁한다."""
    return request_prescription_help(user_id)
