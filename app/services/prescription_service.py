import base64
import binascii
import json
import uuid
from datetime import date, timedelta

from fastapi import HTTPException

from app.database import get_connection
from app.models.schemas import OCRMedicineItem, PrescriptionOCRRequest
from app.services.matching.name_matcher import match_medicine_name
from app.services.ocr.pipeline import run_ocr_pipeline, run_ocr_text_pipeline


DEFAULT_SCHEDULE_TIMES = {
    1: [("08:00", "MORNING")],
    2: [("08:00", "MORNING"), ("20:00", "EVENING")],
    3: [
        ("08:00", "MORNING"),
        ("13:00", "AFTERNOON"),
        ("20:00", "EVENING"),
    ],
}


def _structured_items(structured: dict) -> list[OCRMedicineItem]:
    results = []
    for item in structured.get("items", []):
        if not item.get("drug_name"):
            continue
        results.append(
            OCRMedicineItem(
                drug_name=item["drug_name"],
                dosage=item.get("dosage"),
                unit=item.get("unit"),
                frequency_per_day=item.get("frequency_per_day"),
                times_per_take=item.get("times_per_take"),
                duration_days=item.get("duration_days"),
                easy_explanation=item.get("easy_explanation"),
            )
        )
    return results


def _extract_items(request: PrescriptionOCRRequest) -> tuple[list[OCRMedicineItem], str]:
    if request.image_data:
        try:
            encoded = request.image_data.split(",", 1)[-1]
            image_bytes = base64.b64decode(encoded, validate=True)
        except (binascii.Error, ValueError, TypeError) as error:
            raise HTTPException(
                status_code=422,
                detail="이미지 데이터가 올바르지 않습니다.",
            ) from error
        result = run_ocr_pipeline(image_bytes)
    elif request.ocr_text:
        result = run_ocr_text_pipeline(request.ocr_text)
    else:
        raise HTTPException(status_code=422, detail="처방전 이미지 또는 원문이 필요합니다.")

    if not result.ok or not result.structured:
        raise HTTPException(
            status_code=422,
            detail={"message": "처방전을 읽지 못했습니다.", "error": result.error},
        )
    items = _structured_items(result.structured)
    if not items:
        raise HTTPException(status_code=422, detail="처방전에서 약품을 찾지 못했습니다.")
    return items, result.raw_text


def _resolve_medicine(cursor, item: OCRMedicineItem) -> tuple[str, str]:
    medicine = None
    if item.medicine_code:
        medicine = cursor.execute(
            "SELECT * FROM medicines WHERE medicine_code = ?",
            (item.medicine_code,),
        ).fetchone()
    if not medicine:
        rows = cursor.execute(
            "SELECT * FROM medicines WHERE product_name IS NOT NULL"
        ).fetchall()
        match = match_medicine_name(
            item.drug_name,
            [row["product_name"] for row in rows],
        )
        if match.matched_name:
            medicine = next(
                row for row in rows
                if row["product_name"] == match.matched_name
            )
    if medicine:
        return medicine["medicine_code"], "MATCHED"
    raise HTTPException(
        status_code=422,
        detail=f"등록된 공식 약품에서 확인하지 못했습니다: {item.drug_name}",
    )


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
        items, raw_text = _extract_items(request)
        user = cursor.execute(
            "SELECT id FROM users WHERE id = ?", (request.user_id,)
        ).fetchone()
        if not user:
            cursor.execute(
                "INSERT INTO users (id, name, role) VALUES (?, ?, ?)",
                (request.user_id, "테스트유저", "PATIENT")
            )

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
                raw_text,
            ),
        )

        created_items = []
        for item in items:
            medicine_code, match_status = _resolve_medicine(cursor, item)
            cursor.execute(
                """
                INSERT INTO prescription_items (
                    prescription_id, medicine_code, ocr_drug_name, dosage, unit,
                    frequency_per_day, times_per_take, duration_days,
                    administration_times, match_status, easy_explanation
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
                    match_status,
                    item.easy_explanation,
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
                    "easy_explanation": item.easy_explanation,
                    "schedules": schedules,
                }
            )

        conn.commit()
        return {
            "prescription_id": prescription_id,
            "user_id": request.user_id,
            "ocr_status": "COMPLETED",
            "ocr_text": raw_text,
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
