"""Compatibility entry point; all completion/undo paths share one atomic implementation."""
from app.services.medication_service import mark_medications_taken, cancel_medications_taken


def update_batch(request, *, undo=False):
    result = cancel_medications_taken(request) if undo else mark_medications_taken(request)
    return {**result, "status": "PENDING" if undo else "TAKEN"}
