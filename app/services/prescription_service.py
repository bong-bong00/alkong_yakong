import base64
import binascii
import json
import uuid
from datetime import date, timedelta

from fastapi import HTTPException

from app.database import get_connection, purge_ocr_placeholder_rows
from app.models.schemas import (
    OCRMedicineItem,
    PrescriptionConfirmRequest,
    PrescriptionOCRRequest,
)
from app.services.matching.name_matcher import compare_key
from app.services.ocr.parser import (
    _clean_drug_label,
    _is_plausible_drug_candidate,
    looks_truncated_ocr_name,
)
from app.services.ocr.pipeline import run_ocr_pipeline, run_ocr_text_pipeline
from app.services.pharmacist.easy_category import derive_easy_category_from_medicine
from app.services.pharmacist.ingredient import (
    clean_ingredient_text,
    is_usable_ingredient,
)
from app.services.pharmacist.retrieve import retrieve_official


RECOGNITION_MEANING = (
    "이 숫자는 사진 글자를 얼마나 읽었는지가 아니라, "
    "공식 약 이름과 성분에 얼마나 맞췄는지예요."
)

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
                ocr_drug_name_raw=item.get("ocr_drug_name_raw"),
                dosage=item.get("dosage"),
                unit=item.get("unit"),
                frequency_per_day=item.get("frequency_per_day"),
                times_per_take=item.get("times_per_take"),
                duration_days=item.get("duration_days"),
                easy_explanation=item.get("easy_explanation"),
                warning_note=item.get("warning_note"),
            )
        )
    return results


def _raise_ocr_fail(result) -> None:
    error = result.error or "unknown"
    payload = {"message": "처방전을 읽지 못했습니다.", "error": error}
    if error == "missing_api_key":
        raise HTTPException(status_code=503, detail=payload)
    if error == "quota_exceeded":
        raise HTTPException(status_code=503, detail=payload)
    if error in {"timeout", "DeadlineExceeded"}:
        raise HTTPException(status_code=504, detail=payload)
    if error in {"auth_error", "unavailable"} or (
        result.trace.get("stage") == "engine"
        and error not in {"empty_image", "empty_raw_text"}
    ):
        raise HTTPException(status_code=502, detail=payload)
    raise HTTPException(status_code=422, detail=payload)


def _extract_items(
    request: PrescriptionOCRRequest,
) -> tuple[list[OCRMedicineItem], str, dict, dict]:
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
        _raise_ocr_fail(result)
    items = _structured_items(result.structured)
    if not items:
        raise HTTPException(status_code=422, detail="처방전에서 약품을 찾지 못했습니다.")
    trace = dict(result.trace or {})
    coverage = result.structured.get("field_coverage")
    if coverage:
        trace["field_coverage"] = coverage
    discarded = result.structured.get("discarded_names")
    if discarded:
        trace["discarded_names"] = discarded
    return items, result.raw_text, trace, result.structured


def _upsert_official_medicine(cursor, official: dict) -> tuple[str, str]:
    med = official.get("medicine") or {}
    code = str(med.get("medicine_code") or "").strip()
    name = str(med.get("product_name") or med.get("medicine_name") or "").strip()
    if not code or not name:
        raise HTTPException(
            status_code=422,
            detail="공식 약품 코드가 없습니다.",
        )
    precautions = med.get("precautions") or med.get("cautions") or ""
    easy_category = derive_easy_category_from_medicine(
        {
            **med,
            "product_name": name,
            "source_text": official.get("source_text"),
        }
    )
    # 성분이 없거나 제품명과 같으면 DUR이 제품명으로 오탐하지 않게 빈 값/기존값 유지
    incoming_ingredient = clean_ingredient_text(med.get("ingredient"))
    if incoming_ingredient == name:
        incoming_ingredient = ""
    if not incoming_ingredient:
        prev = cursor.execute(
            "SELECT ingredient, product_name FROM medicines WHERE medicine_code = ?",
            (code,),
        ).fetchone()
        if (
            prev
            and prev["ingredient"]
            and clean_ingredient_text(prev["ingredient"])
            and clean_ingredient_text(prev["ingredient"])
            != clean_ingredient_text(prev["product_name"])
        ):
            ingredient = clean_ingredient_text(prev["ingredient"])
        else:
            ingredient = ""
    else:
        ingredient = incoming_ingredient

    cursor.execute(
        """
        INSERT INTO medicines (
            medicine_code, product_name, ingredient, manufacturer,
            efficacy, usage, precautions, image_url, easy_category
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(medicine_code) DO UPDATE SET
            product_name = excluded.product_name,
            ingredient = CASE
                WHEN excluded.ingredient IS NOT NULL
                     AND trim(excluded.ingredient) != ''
                     AND excluded.ingredient != excluded.product_name
                THEN excluded.ingredient
                ELSE medicines.ingredient
            END,
            manufacturer = excluded.manufacturer,
            efficacy = excluded.efficacy,
            usage = excluded.usage,
            precautions = excluded.precautions,
            image_url = excluded.image_url,
            easy_category = COALESCE(excluded.easy_category, medicines.easy_category),
            updated_at = CURRENT_TIMESTAMP
        """,
        (
            code,
            name,
            ingredient,
            med.get("manufacturer"),
            med.get("efficacy"),
            med.get("usage"),
            precautions if isinstance(precautions, str) else str(precautions or ""),
            med.get("image_url"),
            easy_category,
        ),
    )
    status = "MATCHED" if official.get("source") == "local" else "MFDS"
    return code, status


def _official_display_name(medicine: dict, fallback: str) -> str:
    return (
        str(medicine.get("product_name") or medicine.get("medicine_name") or "").strip()
        or (fallback or "").strip()
    )


def _resolve_medicine(cursor, item: OCRMedicineItem) -> tuple[str, str, str] | None:
    """공식 허가/로컬 약만 반환. 못 찾으면 None (OCR 원문은 약으로 쓰지 않음)."""
    medicine = None
    if item.medicine_code and not str(item.medicine_code).upper().startswith("OCR-"):
        medicine = cursor.execute(
            """
            SELECT * FROM medicines
            WHERE medicine_code = ? AND medicine_code NOT LIKE 'OCR-%'
            """,
            (item.medicine_code,),
        ).fetchone()
    if medicine:
        row = dict(medicine)
        _ensure_easy_category(cursor, row)
        return (
            row["medicine_code"],
            "MATCHED",
            _official_display_name(row, item.drug_name),
        )

    official = retrieve_official(
        item.drug_name,
        dosage_hint=item.dosage,
    )
    if official:
        code, status = _upsert_official_medicine(cursor, official)
        name = _official_display_name(official.get("medicine") or {}, item.drug_name)
        return code, status, name

    return None


def _ensure_easy_category(cursor, medicine: dict) -> None:
    if medicine.get("easy_category"):
        return
    category = derive_easy_category_from_medicine(medicine)
    if not category:
        return
    cursor.execute(
        """
        UPDATE medicines
        SET easy_category = ?, updated_at = CURRENT_TIMESTAMP
        WHERE medicine_code = ?
        """,
        (category, medicine["medicine_code"]),
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


def _same_drug_name(left: str, right: str) -> bool:
    a, b = compare_key(left), compare_key(right)
    if not a or not b:
        return False
    return a == b or a in b or b in a


def _druglike_misses(names: list[str], already: list[str]) -> list[str]:
    misses: list[str] = []
    for name in names or []:
        cleaned = _clean_drug_label(name) or str(name or "").strip()
        if not cleaned:
            continue
        if not (
            _is_plausible_drug_candidate(name, cleaned)
            or _is_plausible_drug_candidate(cleaned)
        ):
            continue
        if any(_same_drug_name(cleaned, other) for other in already + misses):
            continue
        misses.append(cleaned)
    return misses
    seen: set[str] = set()
    names: list[str] = []
    for value in values or []:
        name = str(value or "").strip()
        if not name or name in seen:
            continue
        seen.add(name)
        names.append(name)
    return names


def _should_retake(
    pct: int,
    unrecognized_names: list[str],
    discarded_names: list[str],
) -> bool:
    if pct < 60:
        return True
    if unrecognized_names:
        return True
    return any(looks_truncated_ocr_name(name) for name in discarded_names)


def _user_readiness(items: list[dict], ocr_trace: dict | None = None) -> dict:
    """사용자용 공식 약 확인률(%). 약품명·성분 매칭만 반영한다.

    병원명·약국명·처방일·횟수·일수는 점수에 넣지 않는다.
    field_coverage / 엔진 confidence도 섞지 않는다.
    """
    _ = ocr_trace
    if not items:
        return {
            "pct": 0,
            "label": "poor",
            "summary": "공식 약으로 맞춘 약이 거의 없어요. 흔들리지 않게 다시 찍어 주세요.",
            "meaning": RECOGNITION_MEANING,
            "missing_hints": ["약 이름"],
            "metric": "name_ingredient",
        }

    scores: list[float] = []
    hints: list[str] = []
    weak_n = 0
    for item in items:
        name = str(item.get("drug_name") or "").strip()
        status = str(item.get("match_status") or "").upper()
        uncertain = item.get("uncertain") is True or status == "UNMATCHED"
        product = str(item.get("product_name") or name).strip()
        ingredient_ok = is_usable_ingredient(item.get("ingredient"), product)

        if not name:
            name_score = 0.0
            hints.append("약 이름")
            weak_n += 1
        elif uncertain:
            name_score = 0.35
            hints.append("약 이름 확인")
            weak_n += 1
        else:
            name_score = 1.0

        if not ingredient_ok:
            hints.append("성분")
            weak_n += 1
            ingredient_score = 0.0
        else:
            ingredient_score = 1.0

        scores.append(0.7 * name_score + 0.3 * ingredient_score)

    pct = int(max(0, min(100, round(100.0 * (sum(scores) / len(scores))))))

    if pct >= 85:
        label = "good"
        summary = f"약 {len(items)}개를 공식 이름과 성분에 맞췄어요."
    elif pct >= 60:
        label = "fair"
        summary = (
            f"약 {len(items)}개 중 일부는 공식 목록에 아직 못 맞췄어요."
            if weak_n
            else f"약 {len(items)}개 공식 약 확인이 보통이에요."
        )
    else:
        label = "poor"
        summary = "공식 약으로 맞춘 비율이 낮아요. 흔들리지 않게 다시 찍어 주세요."

    unique_hints: list[str] = []
    for hint in hints:
        if hint not in unique_hints:
            unique_hints.append(hint)

    return {
        "pct": pct,
        "label": label,
        "summary": summary,
        "meaning": RECOGNITION_MEANING,
        "missing_hints": unique_hints[:4],
        "metric": "name_ingredient",
    }


def create_prescription_from_ocr(request: PrescriptionOCRRequest) -> dict:
    """OCR 미리보기만. user_medicines/스케줄은 넣지 않는다 (확정 API에서 등록)."""
    conn = get_connection()
    try:
        cursor = conn.cursor()
        purge_ocr_placeholder_rows(conn)
        items, raw_text, ocr_trace, structured = _extract_items(request)
        user = cursor.execute(
            "SELECT id FROM users WHERE id = ?", (request.user_id,)
        ).fetchone()
        if not user:
            cursor.execute(
                "INSERT INTO users (id, name, role) VALUES (?, ?, ?)",
                (request.user_id, "테스트유저", "PATIENT"),
            )

        preview_items = []
        unrecognized_names: list[str] = []
        readiness_seed: list[dict] = []
        for item in items:
            resolved = _resolve_medicine(cursor, item)
            if not resolved:
                unrecognized_names.append(item.drug_name)
                readiness_seed.append(
                    {
                        "drug_name": item.drug_name,
                        "ingredient": "",
                        "uncertain": True,
                        "match_status": "UNMATCHED",
                    }
                )
                continue
            medicine_code, match_status, official_name = resolved
            ocr_raw = (item.ocr_drug_name_raw or item.drug_name or "").strip()
            med_row = cursor.execute(
                "SELECT * FROM medicines WHERE medicine_code = ?",
                (medicine_code,),
            ).fetchone()
            easy_label = None
            if med_row:
                easy_label = derive_easy_category_from_medicine(dict(med_row))
            easy_explanation = easy_label or None
            ingredient = ""
            if med_row:
                ingredient = dict(med_row).get("ingredient") or ""
            readiness_seed.append(
                {
                    "drug_name": official_name,
                    "product_name": official_name,
                    "ingredient": ingredient,
                    "uncertain": False,
                    "match_status": match_status,
                }
            )
            item_pct = _user_readiness([readiness_seed[-1]])["pct"]
            preview_items.append(
                {
                    "medicine_code": medicine_code,
                    "drug_name": official_name,
                    "ocr_drug_name_raw": ocr_raw if ocr_raw != official_name else None,
                    "match_status": match_status,
                    "dosage": item.dosage,
                    "unit": item.unit,
                    "frequency_per_day": item.frequency_per_day,
                    "times_per_take": item.times_per_take,
                    "duration_days": item.duration_days,
                    "administration_times": list(item.administration_times or []),
                    "easy_explanation": easy_explanation,
                    "easy_category": easy_label,
                    "warning_note": item.warning_note,
                    "uncertain": False,
                    "recognition_pct": item_pct,
                    "schedules": [],
                }
            )

        discarded_names = _unique_names(
            (structured or {}).get("discarded_names")
            or (ocr_trace or {}).get("discarded_names")
        )
        already = (
            unrecognized_names
            + [str(row.get("drug_name") or "") for row in preview_items]
            + [str(item.drug_name or "") for item in items]
        )
        for miss in _druglike_misses(discarded_names, already):
            unrecognized_names.append(miss)
            readiness_seed.append(
                {
                    "drug_name": miss,
                    "ingredient": "",
                    "uncertain": True,
                    "match_status": "UNMATCHED",
                }
            )

        if not preview_items and not unrecognized_names:
            raise HTTPException(
                status_code=422,
                detail="처방전에서 확인할 수 있는 약을 찾지 못했습니다.",
            )

        # 약 사전(medicines) upsert 만 커밋. 복용 등록은 confirm 에서.
        conn.commit()
        readiness = _user_readiness(readiness_seed, ocr_trace)
        retake_recommended = _should_retake(
            readiness["pct"],
            unrecognized_names,
            discarded_names,
        )
        return {
            "prescription_id": None,
            "preview": True,
            "registered": False,
            "user_id": request.user_id,
            "ocr_status": "COMPLETED",
            "ocr_text": raw_text,
            "ocr_trace": ocr_trace,
            "unrecognized_names": unrecognized_names,
            "discarded_names": discarded_names,
            "items": preview_items,
            "hospital_name": request.hospital_name or structured.get("hospital_name"),
            "pharmacy_name": request.pharmacy_name or structured.get("pharmacy_name"),
            "prescribed_date": request.prescribed_date
            or structured.get("prescribed_date"),
            "user_readiness_pct": readiness["pct"],
            "readiness_label": readiness["label"],
            "readiness_summary": readiness["summary"],
            "missing_hints": readiness["missing_hints"],
            "recognition_pct": readiness["pct"],
            "recognition_label": readiness["label"],
            "recognition_summary": readiness["summary"],
            "recognition_meaning": readiness.get("meaning") or RECOGNITION_MEANING,
            "recognition_metric": readiness.get("metric") or "name_ingredient",
            "retake_recommended": retake_recommended,
        }
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


def confirm_prescription(request: PrescriptionConfirmRequest) -> dict:
    """확인 화면에서 「이대로 등록하기」 할 때 실제 복용약·스케줄을 넣는다."""
    if not request.items:
        raise HTTPException(status_code=422, detail="등록할 약이 없습니다.")

    conn = get_connection()
    try:
        cursor = conn.cursor()
        purge_ocr_placeholder_rows(conn)
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
                None,
                None,
            ),
        )

        created_items = []
        for item in request.items:
            code = (item.medicine_code or "").strip()
            if not code:
                raise HTTPException(status_code=422, detail="medicine_code가 없습니다.")
            if code.upper().startswith("OCR-") or (
                item.match_status or ""
            ).upper() == "UNMATCHED":
                raise HTTPException(
                    status_code=422,
                    detail="공식 목록에서 확인된 약만 등록할 수 있습니다.",
                )
            exists = cursor.execute(
                """
                SELECT medicine_code, product_name FROM medicines
                WHERE medicine_code = ? AND medicine_code NOT LIKE 'OCR-%'
                """,
                (code,),
            ).fetchone()
            if not exists:
                raise HTTPException(
                    status_code=422,
                    detail=f"알 수 없는 약 코드입니다: {code}",
                )
            official_name = str(exists["product_name"] or item.drug_name).strip()

            cursor.execute(
                """
                INSERT INTO prescription_items (
                    prescription_id, medicine_code, ocr_drug_name, dosage, unit,
                    frequency_per_day, times_per_take, duration_days,
                    administration_times, match_status, easy_explanation,
                    warning_note
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    prescription_id,
                    code,
                    official_name,
                    item.dosage,
                    item.unit,
                    item.frequency_per_day,
                    item.times_per_take,
                    item.duration_days,
                    json.dumps(item.administration_times, ensure_ascii=False),
                    item.match_status or "MATCHED",
                    item.easy_explanation,
                    item.warning_note,
                ),
            )
            item_id = cursor.lastrowid
            cursor.execute(
                """
                INSERT INTO user_medicines (
                    user_id, medicine_code, prescription_item_id, start_date,
                    end_date, dosage, frequency_per_day, administration_times,
                    is_active
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1)
                """,
                (
                    request.user_id,
                    code,
                    item_id,
                    request.prescribed_date,
                    request.expire_date,
                    item.dosage,
                    item.frequency_per_day,
                    json.dumps(item.administration_times, ensure_ascii=False),
                ),
            )
            user_medicine_id = cursor.lastrowid
            ocr_item = OCRMedicineItem(
                drug_name=official_name,
                medicine_code=code,
                dosage=item.dosage,
                unit=item.unit,
                frequency_per_day=item.frequency_per_day,
                times_per_take=item.times_per_take,
                duration_days=item.duration_days,
                administration_times=list(item.administration_times or []),
                easy_explanation=item.easy_explanation,
                warning_note=item.warning_note,
            )
            schedules = _create_medication_schedules(
                cursor,
                user_id=request.user_id,
                user_medicine_id=user_medicine_id,
                prescribed_date=request.prescribed_date,
                expire_date=request.expire_date,
                item=ocr_item,
            )
            created_items.append(
                {
                    "id": item_id,
                    "user_medicine_id": user_medicine_id,
                    "medicine_code": code,
                    "drug_name": official_name,
                    "match_status": item.match_status or "MATCHED",
                    "frequency_per_day": item.frequency_per_day,
                    "duration_days": item.duration_days,
                    "schedules": schedules,
                }
            )

        conn.commit()
        return {
            "prescription_id": prescription_id,
            "user_id": request.user_id,
            "registered": True,
            "items": created_items,
        }
    except HTTPException:
        conn.rollback()
        raise
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
