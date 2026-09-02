from typing import Any

from pydantic import BaseModel, ConfigDict


class ApiResponse(BaseModel):
    model_config = ConfigDict(extra="allow")


class UserCreateResponse(ApiResponse):
    id: str
    name: str
    birth_date: str | None = None
    gender: str | None = None
    phone: str | None = None
    role: str


class UserResponse(UserCreateResponse):
    created_at: str
    updated_at: str


class GuardianCreateResponse(ApiResponse):
    id: str
    user_id: str
    guardian_name: str
    relationship: str | None = None
    phone: str | None = None
    fcm_token: str | None = None
    notification_enabled: bool


class GuardianResponse(GuardianCreateResponse):
    notification_enabled: bool | int
    created_at: str


class ScheduleResponse(ApiResponse):
    scheduled_date: str
    scheduled_time: str
    time_slot: str | None = None
    status: str


class PrescriptionCreatedItemResponse(ApiResponse):
    id: int
    user_medicine_id: int
    medicine_code: str
    drug_name: str
    match_status: str
    frequency_per_day: int
    easy_explanation: str | None = None
    schedules: list[ScheduleResponse]


class PrescriptionOcrResponse(ApiResponse):
    prescription_id: str
    user_id: str
    ocr_status: str
    items: list[PrescriptionCreatedItemResponse]


class PrescriptionItemResponse(ApiResponse):
    id: int
    prescription_id: str
    medicine_code: str | None = None
    ocr_drug_name: str
    dosage: str | None = None
    unit: str | None = None
    frequency_per_day: int | None = None
    times_per_take: int | None = None
    duration_days: int | None = None
    administration_times: str | None = None
    warning_note: str | None = None
    easy_explanation: str | None = None
    match_status: str
    created_at: str
    product_name: str | None = None
    ingredient: str | None = None


class PrescriptionResponse(ApiResponse):
    id: str
    user_id: str
    source_type: str
    hospital_name: str | None = None
    pharmacy_name: str | None = None
    prescribed_date: str | None = None
    expire_date: str | None = None
    original_image_path: str | None = None
    ocr_text: str | None = None
    ocr_status: str
    status: str
    created_at: str
    items: list[PrescriptionItemResponse]


class DurMatchResponse(ApiResponse):
    type: str
    ingredient_a: str | None = None
    ingredient_b: str | None = None
    reason: str | None = None
    source: str | None = None
    external_id: str | None = None


class DurAnalyzeResponse(ApiResponse):
    risk_result_id: int
    analysis_id: str
    user_id: str
    risk_level: str
    total_matches: int
    representative_type: str | None = None
    ingredients: list[str]
    matches: list[DurMatchResponse]


class DurLatestResponse(ApiResponse):
    id: int
    user_id: str
    risk_level: str
    taboo_id: int | None = None
    ingredient_a: str | None = None
    ingredient_b: str | None = None
    description: str | None = None
    analyzed_ingredients: list[str]
    analysis_id: str | None = None
    risk_type: str | None = None
    total_matches: int
    matches_json: str | None = None
    created_at: str
    matches: list[DurMatchResponse]
    representative_type: str | None = None


class DurSyncStatsResponse(ApiResponse):
    status: str | None = None
    total_fetched: int
    inserted: int
    updated: int
    skipped: int
    skipped_missing_key: int


class DurSyncResponse(ApiResponse):
    source: str
    types: dict[str, DurSyncStatsResponse]
    total_fetched: int
    inserted: int
    updated: int
    skipped: int
    skipped_missing_key: int


class DurDiagnoseResponse(ApiResponse):
    key_loaded: bool
    risk_type: str
    endpoint: str
    results: list[dict[str, Any]]


class ChatResponse(ApiResponse):
    reply: str


class MedicineResponse(ApiResponse):
    id: int
    medicine_code: str
    product_name: str
    ingredient: str
    manufacturer: str | None = None
    efficacy: str | None = None
    usage: str | None = None
    precautions: str | None = None
    image_url: str | None = None
    created_at: str
    updated_at: str


class DrugExplanationDetailResponse(ApiResponse):
    medicine_code: str | None = None
    drug_name: str | None = None
    ingredient: str | None = None
    easy_summary: str
    what_it_does: str
    how_to_take: str
    cautions: list[str]
    possible_side_effects: list[str]
    storage: str
    ask_doctor_when: list[str]
    generated_by: str
    source: str
    is_verified: bool
    source_based: bool
    official_raw_summary: str


class DrugExplanationResponse(DrugExplanationDetailResponse):
    medicine: MedicineResponse
    explanation: DrugExplanationDetailResponse


class BaselineResponse(ApiResponse):
    id: int
    user_id: str
    resting_bpm: float
    min_normal_bpm: int
    max_normal_bpm: int
    sample_count: int
    calculated_at: str


class AbnormalEventSummaryResponse(ApiResponse):
    id: int
    event_type: str
    severity: str


class HeartRateResponse(ApiResponse):
    heart_rate_log_id: int
    bpm: int
    measured_at: str
    baseline: BaselineResponse
    abnormal_event: AbnormalEventSummaryResponse | None = None


class AbnormalEventResponse(ApiResponse):
    id: int
    user_id: str
    heart_rate_log_id: int | None = None
    event_type: str
    bpm: int
    baseline_bpm: float | None = None
    severity: str
    status: str
    occurred_at: str
    created_at: str


class BiosignalTestSessionStartResponse(ApiResponse):
    session_id: str
    participant_id: str
    scenario: str
    started_at: str
    is_synthetic: bool


class BiosignalTestSessionResponse(BiosignalTestSessionStartResponse):
    ended_at: str | None = None
    note: str | None = None


class BiosignalTestSampleBaseResponse(ApiResponse):
    session_id: str
    participant_id: str
    scenario: str
    bpm: int
    measured_at: str
    device_id: str | None = None
    source: str
    is_synthetic: bool


class BiosignalTestSampleCreateResponse(BiosignalTestSampleBaseResponse):
    sample_id: int


class BiosignalTestSampleResponse(BiosignalTestSampleBaseResponse):
    id: int


class MedicationLogResponse(ApiResponse):
    id: int
    schedule_id: int
    status: str
    taken_at: str
    duplicate: bool


class MissedMedicationResponse(ApiResponse):
    medication_log_id: int
    schedule_id: int
    status: str
    scheduled_date: str
    scheduled_time: str
    drug_name: str
    guardian_notification_count: int


class MarkMissedResponse(ApiResponse):
    user_id: str
    current_time: str
    grace_hours: int
    eligible_schedule_count: int
    missed_count: int
    skipped_taken_count: int
    skipped_duplicate_count: int
    missed: list[MissedMedicationResponse]


class StoredNotificationResponse(ApiResponse):
    id: int
    user_id: str
    guardian_id: str | None = None
    abnormal_event_id: int | None = None
    schedule_id: int | None = None
    medication_log_id: int | None = None
    notification_type: str
    title: str
    message: str
    status: str
    sent_at: str | None = None
    created_at: str


class NotificationResponse(StoredNotificationResponse):
    guardian_name: str | None = None
    relationship: str | None = None


class ReminderGenerationResponse(ApiResponse):
    user_id: str
    target_date: str
    schedule_count: int
    created_count: int
    skipped_duplicate_count: int
    notifications: list[StoredNotificationResponse]


class DashboardResponse(ApiResponse):
    user_id: str
    date: str
    today_medications: list[dict[str, Any]]
    medication_summary: dict[str, Any]
    latest_risk: dict[str, Any] | None = None
    latest_prescription: dict[str, Any] | None = None
    latest_abnormal_event: AbnormalEventResponse | None = None
    notification_count: int
    recent_notifications: list[dict[str, Any]]


class RootResponse(ApiResponse):
    message: str
    docs: str


class HealthResponse(ApiResponse):
    status: str
