import json
import re
import uuid
from datetime import date, timedelta
from hashlib import sha1

from fastapi import HTTPException

from app.database import get_connection
from app.models.schemas import OCRMedicineItem, PrescriptionOCRRequest


DEFAULT_SCHEDULE_TIMES = {
    1: [("08:00", "MORNING")],
    2: [("08:00", "MORNING"), ("20:00", "EVENING")],
    3: [
        ("08:00", "MORNING"),
        ("13:00", "AFTERNOON"),
        ("20:00", "EVENING"),
    ],
}


def _extract_items(request: PrescriptionOCRRequest) -> list[OCRMedicineItem]:
    if request.mock_items:
        return request.mock_items

    if request.ocr_text:
        from app.services.gemini_service import parse_ocr_text_to_medicines
        parsed_data = parse_ocr_text_to_medicines(request.ocr_text)
        if parsed_data:
            items = []
            for item in parsed_data:
                # 단위 포함 문자열 변환
                dosage_str = str(item.get("dosage", "")) if item.get("dosage") is not None else None
                items.append(
                    OCRMedicineItem(
                        drug_name=item.get("drug_name"),
                        dosage=dosage_str,
                        frequency_per_day=item.get("frequency_per_day"),
                        duration_days=item.get("duration_days"),
                        warning_note=item.get("warning_note")
                    )
                )
            return items

    names = [
        value.strip()
        for value in re.split(r"[\n,]", request.ocr_text or "")
        if value.strip()
    ]
    if not names:
        names = ["아스피린 100mg"]
    return [OCRMedicineItem(drug_name=name) for name in names]


def _resolve_medicine(cursor, item: OCRMedicineItem) -> tuple[str, str]:
    medicine = None
    if item.medicine_code:
        medicine = cursor.execute(
            "SELECT * FROM medicines WHERE medicine_code = ?",
            (item.medicine_code,),
        ).fetchone()
    if not medicine:
        medicine = cursor.execute(
            "SELECT * FROM medicines WHERE product_name = ?",
            (item.drug_name,),
        ).fetchone()
        
    if not medicine:
        # Fuzzy Matching 로직 추가 (유사도 70점 이상 매핑)
        all_medicines = cursor.execute("SELECT medicine_code, product_name FROM medicines").fetchall()
        if all_medicines:
            medicine_dict = {med["product_name"]: med["medicine_code"] for med in all_medicines}
            medicine_names = list(medicine_dict.keys())
            
            from thefuzz import process
            best_match = process.extractOne(item.drug_name, medicine_names)
            if best_match and best_match[1] >= 70:
                return medicine_dict[best_match[0]], "FUZZY_MATCHED"

    if medicine:
        return medicine["medicine_code"], "MATCHED"

    code = item.medicine_code or f"MOCK-{sha1(item.drug_name.encode('utf-8')).hexdigest()[:10].upper()}"
    cursor.execute(
        """
        INSERT OR IGNORE INTO medicines (
            medicine_code, product_name, ingredient, efficacy, usage, precautions
        ) VALUES (?, ?, ?, ?, ?, ?)
        """,
        (
            code,
            item.drug_name,
            item.ingredient or item.drug_name,
            "등록된 효능 정보가 없습니다.",
            "처방 지시에 따라 복용하세요.",
            "이상 반응이 있으면 전문가와 상담하세요.",
        ),
    )
    return code, "MOCK_CREATED"


def _parse_date(value: str | None, fallback: date) -> date:
    if not value:
        return fallback
    try:
        return date.fromisoformat(value)
    except ValueError:
        return fallback


def _schedule_dates(
    prescribed_date: str | None,
    expire_date: str | None,
    duration_days: int | None,
) -> list[date]:
    start_date = _parse_date(prescribed_date, date.today())
    if expire_date:
        end_date = _parse_date(expire_date, start_date)
    else:
        end_date = start_date + timedelta(days=max(duration_days or 1, 1) - 1)

    if end_date < start_date:
        end_date = start_date

    day_count = min((end_date - start_date).days + 1, 365)
    return [start_date + timedelta(days=offset) for offset in range(day_count)]


def _create_medication_schedules(
    cursor,
    *,
    user_id: str,
    user_medicine_id: int,
    prescribed_date: str | None,
    expire_date: str | None,
    item: OCRMedicineItem,
) -> list[dict]:
    frequency = min(max(item.frequency_per_day or 1, 1), 3)
    created_schedules = []

    for scheduled_date in _schedule_dates(
        prescribed_date,
        expire_date,
        item.duration_days,
    ):
        for scheduled_time, time_slot in DEFAULT_SCHEDULE_TIMES[frequency]:
            cursor.execute(
                """
                INSERT OR IGNORE INTO medication_schedules (
                    user_id, user_medicine_id, scheduled_date,
                    scheduled_time, time_slot, status
                ) VALUES (?, ?, ?, ?, ?, 'PENDING')
                """,
                (
                    user_id,
                    user_medicine_id,
                    scheduled_date.isoformat(),
                    scheduled_time,
                    time_slot,
                ),
            )
            if cursor.rowcount:
                created_schedules.append(
                    {
                        "scheduled_date": scheduled_date.isoformat(),
                        "scheduled_time": scheduled_time,
                        "time_slot": time_slot,
                        "status": "PENDING",
                    }
                )

    return created_schedules


def create_prescription_from_ocr(request: PrescriptionOCRRequest) -> dict:
    conn = get_connection()
    try:
        cursor = conn.cursor()
        user = cursor.execute(
            "SELECT id FROM users WHERE id = ?", (request.user_id,)
        ).fetchone()
        if not user:
            raise HTTPException(status_code=404, detail="사용자가 없습니다.")

        prescription_id = str(uuid.uuid4())
        cursor.execute(
            """
            INSERT INTO prescriptions (
                id, user_id, source_type, hospital_name, pharmacy_name,
                prescribed_date, expire_date, original_image_path, ocr_text
            ) VALUES (?, ?, 'OCR', ?, ?, ?, ?, ?, ?)
            """,
            (
                prescription_id,
                request.user_id,
                request.hospital_name,
                request.pharmacy_name,
                request.prescribed_date,
                request.expire_date,
                request.image_path,
                request.ocr_text,
            ),
        )

        created_items = []
        for item in _extract_items(request):
            medicine_code, match_status = _resolve_medicine(cursor, item)
            cursor.execute(
                """
                INSERT INTO prescription_items (
                    prescription_id, medicine_code, ocr_drug_name, dosage, unit,
                    frequency_per_day, times_per_take, duration_days,
                    administration_times, warning_note, match_status
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    prescription_id,
                    medicine_code,
                    item.drug_name,
                    item.dosage,
                    item.unit,
                    item.frequency_per_day,
                    item.times_per_take,
                    item.duration_days,
                    json.dumps(item.administration_times, ensure_ascii=False),
                    item.warning_note,
                    match_status,
                ),
            )
            item_id = cursor.lastrowid
            cursor.execute(
                """
                INSERT INTO user_medicines (
                    user_id, medicine_code, prescription_item_id, start_date,
                    end_date, dosage, frequency_per_day, administration_times
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    request.user_id,
                    medicine_code,
                    item_id,
                    request.prescribed_date,
                    request.expire_date,
                    item.dosage,
                    item.frequency_per_day,
                    json.dumps(item.administration_times, ensure_ascii=False),
                ),
            )
            user_medicine_id = cursor.lastrowid
            schedules = _create_medication_schedules(
                cursor,
                user_id=request.user_id,
                user_medicine_id=user_medicine_id,
                prescribed_date=request.prescribed_date,
                expire_date=request.expire_date,
                item=item,
            )
            created_items.append(
                {
                    "id": item_id,
                    "user_medicine_id": user_medicine_id,
                    "medicine_code": medicine_code,
                    "drug_name": item.drug_name,
                    "match_status": match_status,
                    "frequency_per_day": item.frequency_per_day or 1,
                    "schedules": schedules,
                }
            )

        conn.commit()
        return {
            "prescription_id": prescription_id,
            "user_id": request.user_id,
            "ocr_status": "COMPLETED",
            "items": created_items,
        }
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


def get_user_prescriptions(user_id: str) -> list[dict]:
    conn = get_connection()
    try:
        prescriptions = conn.execute(
            """
            SELECT * FROM prescriptions
            WHERE user_id = ?
            ORDER BY created_at DESC
            """,
            (user_id,),
        ).fetchall()
        result = []
        for prescription in prescriptions:
            data = dict(prescription)
            items = conn.execute(
                """
                SELECT pi.*, m.product_name, m.ingredient
                FROM prescription_items pi
                LEFT JOIN medicines m ON m.medicine_code = pi.medicine_code
                WHERE pi.prescription_id = ?
                ORDER BY pi.id
                """,
                (prescription["id"],),
            ).fetchall()
            data["items"] = [dict(item) for item in items]
            result.append(data)
        return result
    finally:
        conn.close()
