from fastapi import APIRouter

from app.models.schemas import MedicationReminderRequest
from app.services.notification_service import (
    generate_medication_reminders,
    get_user_notifications,
)


router = APIRouter(prefix="/api/v1", tags=["Notifications"])


@router.post("/notifications/generate-medication-reminders")
def generate_reminders(request: MedicationReminderRequest):
    return generate_medication_reminders(request)


@router.get("/users/{user_id}/notifications")
def list_notifications(user_id: str):
    return get_user_notifications(user_id)
