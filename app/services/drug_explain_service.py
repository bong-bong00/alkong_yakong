import json
import logging
from typing import Any

from fastapi import HTTPException

from app.core.config import GEMINI_MODEL
from app.database import get_connection
from app.services.external_api_service import fetch_e_drug_info
from app.services.pharmacist.easy_category import derive_easy_category_from_medicine
from app.services.pharmacist.generate import generate_card_from_source


logger = logging.getLogger(__name__)
CACHE_MAX_AGE = "-1 day"
MISSING_OFFICIAL_TEXT = "공식 정보에 명시되어 있지 않습니다."


def get_drug_explanation(
    medicine_code: str,
    *,
    force_refresh: bool = False,
) -> dict[str, Any]:
    conn = get_connection()
    try:
        cursor = conn.cursor()
        medicine = _get_medicine(cursor, medicine_code)
        cached = _get_latest_card(
            cursor,
            medicine_code,
            fresh_only=not force_refresh,
        )
        if medicine and cached and not force_refresh:
            return _response(medicine, cached, generated_by="local-cache")

        official_info = fetch_e_drug_info(
            medicine_code=medicine_code,
            medicine_name=medicine.get("product_name") if medicine else None,
        )
        if official_info:
            official_info["ingredient"] = (
                official_info.get("ingredient")
                or (medicine.get("ingredient") if medicine else None)
            )
            _upsert_medicine(cursor, medicine_code, medicine, official_info)
            document_id = _save_official_document(
                cursor,
                medicine_code,
                official_info,
            )
            medicine = _get_medicine(cursor, medicine_code)

            generated = None
            try:
                generated = generate_card_from_source(official_info)
            except Exception:
                generated = None
            if generated and generated.get("source_based") is not False:
                card_data = {
                    **generated,
                    "model_name": GEMINI_MODEL,
                    "generated_by": "e약은요+gemini",
                    "source": "e약은요",
                    "is_verified": 0,
                    "source_based": True,
                }
            else:
                card_data = {
                    **_official_fallback(official_info),
                    "model_name": "official-fallback",
                    "generated_by": "e약은요-fallback",
                    "source": "e약은요",
                    "is_verified": 1,
                }

            card_data["official_raw_summary"] = _official_raw_summary(
                official_info
            )
            card = _save_card(
                cursor,
                medicine_code,
                card_data,
                [document_id],
            )
            conn.commit()
            return _response(medicine, card)

        if not medicine:
            raise HTTPException(status_code=404, detail="의약품이 없습니다.")

        stale_cache = _get_latest_card(cursor, medicine_code)
        if stale_cache and stale_cache.get("source_based"):
            return _response(medicine, stale_cache, generated_by="local-cache")

        raise HTTPException(
            status_code=404,
            detail="공식 자료에서 이 약을 찾지 못했습니다.",
        )
    except HTTPException:
        raise
    except Exception as error:
        conn.rollback()
        logger.warning(
            "Drug explanation pipeline failed for %s: %s",
            medicine_code,
            error,
            exc_info=True,
        )
        raise HTTPException(
            status_code=502,
            detail="공식 약 설명을 만들지 못했습니다.",
        ) from error
    finally:
        conn.close()


def _get_medicine(cursor, medicine_code: str) -> dict[str, Any] | None:
    row = cursor.execute(
        "SELECT * FROM medicines WHERE medicine_code = ?",
        (medicine_code,),
    ).fetchone()
    return dict(row) if row else None


def _get_latest_card(
    cursor,
    medicine_code: str,
    *,
    fresh_only: bool = False,
) -> dict[str, Any] | None:
    freshness = (
        "AND datetime(created_at) >= datetime('now', ?)" if fresh_only else ""
    )
    params: tuple[Any, ...] = (
        (medicine_code, CACHE_MAX_AGE)
        if fresh_only
        else (medicine_code,)
    )
    row = cursor.execute(
        f"""
        SELECT * FROM ai_explanation_cards
        WHERE medicine_code = ?
        {freshness}
        ORDER BY created_at DESC, id DESC
        LIMIT 1
        """,
        params,
    ).fetchone()
    return dict(row) if row else None


def _save_official_document(
    cursor,
    medicine_code: str,
    official_info: dict[str, Any],
) -> int:
    content = json.dumps(official_info, ensure_ascii=False)
    existing = cursor.execute(
        """
        SELECT id FROM medicine_documents
        WHERE medicine_code = ? AND document_type = 'E_DRUG'
          AND content = ?
        ORDER BY id DESC LIMIT 1
        """,
        (medicine_code, content),
    ).fetchone()
    if existing:
        return existing["id"]

    cursor.execute(
        """
        INSERT INTO medicine_documents (
            medicine_code, document_type, title, content, source_url
        ) VALUES (?, 'E_DRUG', ?, ?, ?)
        """,
        (
            medicine_code,
            official_info.get("product_name") or medicine_code,
            content,
            "https://www.data.go.kr/data/15075057/openapi.do",
        ),
    )
    return cursor.lastrowid


def _upsert_medicine(
    cursor,
    medicine_code: str,
    local: dict[str, Any] | None,
    official: dict[str, Any],
) -> None:
    local = local or {}
    merged = {
        **local,
        **{key: value for key, value in official.items() if value},
        "product_name": official.get("product_name")
        or local.get("product_name")
        or medicine_code,
    }
    easy_category = derive_easy_category_from_medicine(merged) or local.get(
        "easy_category"
    )
    cursor.execute(
        """
        INSERT INTO medicines (
            medicine_code, product_name, ingredient, manufacturer,
            efficacy, usage, precautions, image_url, easy_category
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(medicine_code) DO UPDATE SET
            product_name = excluded.product_name,
            ingredient = excluded.ingredient,
            manufacturer = excluded.manufacturer,
            efficacy = excluded.efficacy,
            usage = excluded.usage,
            precautions = excluded.precautions,
            image_url = excluded.image_url,
            easy_category = COALESCE(excluded.easy_category, medicines.easy_category),
            updated_at = CURRENT_TIMESTAMP
        """,
        (
            medicine_code,
            merged["product_name"],
            official.get("ingredient")
            or local.get("ingredient")
            or None,
            official.get("manufacturer") or local.get("manufacturer"),
            official.get("efficacy") or local.get("efficacy"),
            official.get("usage") or local.get("usage"),
            official.get("cautions") or local.get("precautions"),
            official.get("image_url") or local.get("image_url"),
            easy_category,
        ),
    )


def _save_card(
    cursor,
    medicine_code: str,
    card: dict[str, Any],
    document_ids: list[int],
) -> dict[str, Any]:
    cautions = _ensure_consultation(_string_list(card.get("cautions")))
    ask_doctor_when = _ensure_consultation(
        _string_list(card.get("ask_doctor_when"))
    )
    side_effects = _string_list(card.get("possible_side_effects"))
    cursor.execute(
        """
        INSERT INTO ai_explanation_cards (
            medicine_code, summary, what_it_does, how_to_take,
            warnings, cautions, side_effects, storage, ask_doctor_when,
            source_based, official_raw_summary, source_document_ids,
            model_name, generated_by, source, is_verified
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            medicine_code,
            card.get("easy_summary") or MISSING_OFFICIAL_TEXT,
            card.get("what_it_does") or MISSING_OFFICIAL_TEXT,
            card.get("how_to_take") or MISSING_OFFICIAL_TEXT,
            json.dumps(cautions, ensure_ascii=False),
            json.dumps(cautions, ensure_ascii=False),
            json.dumps(side_effects, ensure_ascii=False),
            card.get("storage") or MISSING_OFFICIAL_TEXT,
            json.dumps(ask_doctor_when, ensure_ascii=False),
            int(bool(card.get("source_based"))),
            card.get("official_raw_summary") or "",
            json.dumps(document_ids),
            card.get("model_name") or "mock",
            card.get("generated_by") or "mock",
            card.get("source") or "local",
            int(bool(card.get("is_verified"))),
        ),
    )
    return dict(
        cursor.execute(
            "SELECT * FROM ai_explanation_cards WHERE id = ?",
            (cursor.lastrowid,),
        ).fetchone()
    )


def _official_fallback(info: dict[str, Any]) -> dict[str, Any]:
    cautions = _string_list(info.get("cautions"))
    if interaction := info.get("interaction"):
        cautions.append(f"상호작용: {interaction}")
    return {
        "easy_summary": (
            f"{info.get('product_name') or '이 약'}의 e약은요 공식 정보를 "
            "쉬운 항목으로 정리했습니다."
        ),
        "what_it_does": info.get("efficacy") or MISSING_OFFICIAL_TEXT,
        "how_to_take": info.get("usage") or MISSING_OFFICIAL_TEXT,
        "cautions": cautions or [MISSING_OFFICIAL_TEXT],
        "possible_side_effects": _string_list(info.get("side_effects"))
        or [MISSING_OFFICIAL_TEXT],
        "storage": info.get("storage") or MISSING_OFFICIAL_TEXT,
        "ask_doctor_when": [
            "복용 중 이상 증상이 있거나 복용 방법이 걱정되면 의사/약사와 상담하세요."
        ],
        "source_based": True,
    }


def _local_fallback(medicine: dict[str, Any]) -> dict[str, Any]:
    product_name = medicine.get("product_name") or "이 약"
    ingredient = medicine.get("ingredient") or "확인되지 않은"
    return {
        "easy_summary": f"{product_name}은(는) {ingredient} 성분의 약입니다.",
        "what_it_does": medicine.get("efficacy") or "효능 정보는 확인 중입니다.",
        "how_to_take": medicine.get("usage") or "처방 지시에 따라 복용하세요.",
        "cautions": _string_list(medicine.get("precautions"))
        or ["이상 반응이 있으면 복용을 중단하고 상담하세요."],
        "possible_side_effects": ["공식 부작용 정보가 없습니다."],
        "storage": "공식 보관 정보가 없습니다.",
        "ask_doctor_when": [
            "궁금하거나 이상 반응이 있으면 의사/약사와 상담하세요."
        ],
        "source_based": False,
    }


def _official_raw_summary(info: dict[str, Any]) -> str:
    labels = (
        ("제품명", "product_name"),
        ("성분명", "ingredient"),
        ("효능/효과", "efficacy"),
        ("복용법", "usage"),
        ("주의사항", "cautions"),
        ("상호작용", "interaction"),
        ("부작용", "side_effects"),
        ("보관법", "storage"),
    )
    return "\n".join(
        f"{label}: {info.get(key) or MISSING_OFFICIAL_TEXT}"
        for label, key in labels
    )


def _response(
    medicine: dict[str, Any],
    card: dict[str, Any],
    *,
    generated_by: str | None = None,
) -> dict[str, Any]:
    cautions = _json_list(card.get("cautions") or card.get("warnings"))
    side_effects = _json_list(card.get("side_effects"))
    ask_doctor_when = _json_list(card.get("ask_doctor_when"))
    response = {
        "medicine_code": medicine.get("medicine_code"),
        "drug_name": medicine.get("product_name"),
        "ingredient": medicine.get("ingredient"),
        "easy_summary": card.get("summary") or MISSING_OFFICIAL_TEXT,
        "what_it_does": card.get("what_it_does") or MISSING_OFFICIAL_TEXT,
        "how_to_take": card.get("how_to_take") or MISSING_OFFICIAL_TEXT,
        "cautions": cautions,
        "possible_side_effects": side_effects,
        "storage": card.get("storage") or MISSING_OFFICIAL_TEXT,
        "ask_doctor_when": ask_doctor_when,
        "generated_by": generated_by
        or card.get("generated_by")
        or card.get("model_name")
        or "mock",
        "source": card.get("source") or "local",
        "is_verified": bool(card.get("is_verified")),
        "source_based": bool(card.get("source_based")),
        "official_raw_summary": card.get("official_raw_summary") or "",
    }
    response["medicine"] = medicine
    response["explanation"] = {
        **response,
        "summary": response["easy_summary"],
        "side_effects": response["possible_side_effects"],
        "warnings": response["cautions"],
    }
    return response


def _safe_existing_or_fallback(conn, medicine_code: str) -> dict[str, Any]:
    cursor = conn.cursor()
    medicine = _get_medicine(cursor, medicine_code)
    if not medicine:
        raise HTTPException(status_code=404, detail="의약품이 없습니다.")
    cached = _get_latest_card(cursor, medicine_code)
    if cached:
        return _response(medicine, cached, generated_by="local-cache")
    return _response(
        medicine,
        {
            "summary": _local_fallback(medicine)["easy_summary"],
            "what_it_does": medicine.get("efficacy"),
            "how_to_take": medicine.get("usage"),
            "cautions": json.dumps(
                _local_fallback(medicine)["cautions"], ensure_ascii=False
            ),
            "side_effects": json.dumps(
                _local_fallback(medicine)["possible_side_effects"],
                ensure_ascii=False,
            ),
            "storage": "공식 보관 정보가 없습니다.",
            "ask_doctor_when": json.dumps(
                _local_fallback(medicine)["ask_doctor_when"],
                ensure_ascii=False,
            ),
            "generated_by": "mock",
            "source": "local",
            "is_verified": 0,
            "source_based": 0,
        },
    )


def _ensure_consultation(values: list[str]) -> list[str]:
    if not any("의사/약사와 상담하세요" in value for value in values):
        values.append("궁금하거나 이상 반응이 있으면 의사/약사와 상담하세요.")
    return values


def _string_list(value: Any) -> list[str]:
    if isinstance(value, list):
        return [str(item).strip() for item in value if str(item).strip()]
    text = str(value or "").strip()
    if not text:
        return []
    return [line.strip(" -•") for line in text.splitlines() if line.strip(" -•")]


def _json_list(value: Any) -> list[str]:
    if isinstance(value, list):
        return _string_list(value)
    if isinstance(value, str):
        try:
            parsed = json.loads(value)
            if isinstance(parsed, list):
                return _string_list(parsed)
        except json.JSONDecodeError:
            pass
    return _string_list(value)
