"""Derive a short senior-friendly medicine category for UI parentheses."""

from __future__ import annotations

import re
import sqlite3
from typing import Any

from app.services.pharmacist.easy_category_db import (
    FALLBACK_SPOKEN,
    lookup_easy_label,
    lookup_easy_matches,
    lookup_spoken_sentence,
)

_EXPORT_NAME = re.compile(r"\(수출명\s*[:：][^)]*\)", re.I)

_PATCH = ("붙이", "첩부", "파스", "플라스타", "플라스터", "패취", "반창고")
_APPLY = ("바르", "도포", "외용", "연고", "크림", "로션")
_EYE = ("점안", "안연고")
_EAT = ("경구", "복용", "정제", "캡슐", "시럽", "현탁")

PURPOSE_NOTICE = (
    "허가된 쓰임을 쉽게 설명한 내용이에요. 내가 처방받은 이유는 의사나 약사에게 확인해 주세요."
)

# 긴 효능 문장에서 독립적으로 확인해도 의미가 흐려지지 않는 문구만 둔다.
# 단순 단어 나열로 모든 효능을 추측하지 않고, 검토된 규칙을 조금씩 늘린다.
_CONTEXT_PURPOSE_RULES: tuple[dict[str, Any], ...] = (
    {
        "purpose_code": "ITCH_RELIEF",
        "easy_label": "가려움 완화",
        "sentence": "가려움을 줄이는 데 쓰이는 약이에요.",
        "phrases": ("수반하는 가려움", "가려움증", "두드러기"),
    },
    {
        "purpose_code": "ANXIETY_TENSION_RELIEF",
        "easy_label": "불안·긴장 완화",
        "sentence": "불안이나 긴장을 줄이는 데 쓰이는 약이에요.",
        "phrases": (
            "신경증에서의 불안",
            "불안, 긴장, 초조",
            "불안ㆍ긴장ㆍ초조",
            "불안장애의 치료",
            "불안증상",
            "공황장애",
        ),
    },
)


def infer_use_route(
    *,
    product_name: str | None = None,
    usage: str | None = None,
    efficacy: str | None = None,
) -> str:
    name = str(product_name or "")
    usage_text = str(usage or "")
    efficacy_text = str(efficacy or "")
    blob = f"{name} {usage_text}"
    if any(token in blob for token in _PATCH):
        return "patch"
    if any(token in blob for token in _EYE):
        return "eye"
    if any(token in blob for token in _APPLY):
        return "apply"
    if "액" in name and any(
        token in efficacy_text for token in ("피부", "습진", "피부염", "가려움", "건선")
    ):
        return "apply"
    if any(token in blob for token in _EAT):
        return "eat"
    return "eat"


def display_product_name(name: str | None) -> str:
    """수출명·군더더기 괄호를 떼고 카드에 쓸 제품명."""
    text = str(name or "").strip()
    if not text:
        return ""
    text = _EXPORT_NAME.sub("", text)
    return re.sub(r"\s+", " ", text).strip(" /") or str(name or "").strip()


def derive_easy_category(
    *,
    product_name: str | None = None,
    ingredient: str | None = None,
    efficacy: str | None = None,
    usage: str | None = None,
    source_text: str | None = None,
) -> str | None:
    """Look up easy_category_map.db using official name/efficacy text."""
    name_blob = " ".join(str(part or "") for part in (product_name, ingredient))
    # 복용법·주의는 분류에 쓰지 않는다. 주의의 '알레르기'가 약 효능처럼 붙는 것을 막는다.
    efficacy_blob = str(efficacy or "")
    if not name_blob.strip() and not efficacy_blob.strip():
        return None
    return lookup_easy_label(name_text=name_blob, efficacy_text=efficacy_blob)


def derive_easy_spoken(
    *,
    product_name: str | None = None,
    ingredient: str | None = None,
    efficacy: str | None = None,
    usage: str | None = None,
) -> str:
    """홈·OCR 카드용 B 문장. 허가 원문을 다시 쓰지 않는다."""
    label = derive_easy_category(
        product_name=product_name,
        ingredient=ingredient,
        efficacy=efficacy,
        usage=usage,
    )
    route = infer_use_route(
        product_name=product_name,
        usage=usage,
        efficacy=efficacy,
    )
    if not label:
        return FALLBACK_SPOKEN
    return lookup_spoken_sentence(label, route)


def derive_easy_category_from_medicine(med: dict[str, Any]) -> str | None:
    return derive_easy_category(
        product_name=med.get("product_name") or med.get("medicine_name"),
        ingredient=med.get("ingredient"),
        efficacy=med.get("efficacy") or med.get("efficacy_text"),
    )


def derive_easy_spoken_from_medicine(med: dict[str, Any]) -> str:
    return derive_easy_spoken(
        product_name=med.get("product_name") or med.get("medicine_name"),
        ingredient=med.get("ingredient"),
        efficacy=med.get("efficacy") or med.get("efficacy_text"),
        usage=med.get("usage") or med.get("usage_text"),
    )


def _purpose_from_legacy_label(
    label: str,
    *,
    route: str,
    evidence_type: str,
    evidence_text: str,
) -> dict[str, str]:
    return {
        "purpose_code": label,
        "easy_label": label,
        "sentence": lookup_spoken_sentence(label, route),
        "evidence_type": evidence_type,
        "evidence_text": evidence_text,
        "source": "식약처 허가정보 기반 분류 사전",
        "confidence": "HIGH" if evidence_type == "NAME_OR_INGREDIENT" else "MEDIUM",
        "review_status": "DERIVED",
    }


def derive_easy_purposes_from_medicine(med: dict[str, Any]) -> list[dict[str, str]]:
    """Return patient-friendly purposes without claiming the patient's diagnosis."""
    product_name = med.get("product_name") or med.get("medicine_name")
    ingredient = med.get("ingredient")
    efficacy = str(med.get("efficacy") or med.get("efficacy_text") or "")
    usage = med.get("usage") or med.get("usage_text")
    name_blob = " ".join(str(part or "") for part in (product_name, ingredient))
    route = infer_use_route(
        product_name=str(product_name or ""),
        usage=str(usage or ""),
        efficacy=efficacy,
    )

    mapped = lookup_easy_matches(name_text=name_blob, efficacy_text=efficacy)
    name_matches = [row for row in mapped if row["match_scope"] == "name"]
    if name_matches:
        row = name_matches[0]
        return [
            _purpose_from_legacy_label(
                row["easy_label"],
                route=route,
                evidence_type="NAME_OR_INGREDIENT",
                evidence_text=row["official_phrase"],
            )
        ]

    purposes: list[dict[str, str]] = []
    for rule in _CONTEXT_PURPOSE_RULES:
        evidence = next(
            (phrase for phrase in rule["phrases"] if phrase in efficacy),
            None,
        )
        if not evidence:
            continue
        purposes.append(
            {
                "purpose_code": str(rule["purpose_code"]),
                "easy_label": str(rule["easy_label"]),
                "sentence": str(rule["sentence"]),
                "evidence_type": "OFFICIAL_EFFICACY",
                "evidence_text": evidence,
                "source": "식약처 허가 효능",
                "confidence": "HIGH",
                "review_status": "DERIVED",
            }
        )
    if purposes:
        return purposes

    efficacy_matches = [row for row in mapped if row["match_scope"] == "efficacy"]
    if efficacy_matches:
        row = efficacy_matches[0]
        return [
            _purpose_from_legacy_label(
                row["easy_label"],
                route=route,
                evidence_type="OFFICIAL_EFFICACY",
                evidence_text=row["official_phrase"],
            )
        ]
    return []


def derive_key_cautions_from_medicine(med: dict[str, Any]) -> list[dict[str, str]]:
    """Short, evidence-linked cautions. Rules stay deliberately conservative."""
    name_blob = " ".join(
        str(part or "")
        for part in (
            med.get("product_name") or med.get("medicine_name"),
            med.get("ingredient"),
        )
    )
    precautions = str(med.get("precautions") or med.get("cautions") or "")
    if "히드록시진" in name_blob and any(
        phrase in precautions for phrase in ("졸음", "운전", "기계조작")
    ):
        return [
            {
                "caution_code": "DROWSINESS_DRIVING",
                "short_sentence": "졸리거나 어지러울 수 있어요. 운전이나 위험한 기계 조작은 피하세요.",
                "evidence_text": "졸음 및 운전·기계조작 주의",
                "source": "식약처 허가 주의사항",
                "severity": "CAUTION",
                "review_status": "DERIVED",
            }
        ]
    return []


def _compose_guidance(
    purposes: list[dict[str, str]], cautions: list[dict[str, str]]
) -> dict[str, Any]:
    codes = {item["purpose_code"] for item in purposes}
    if {"ITCH_RELIEF", "ANXIETY_TENSION_RELIEF"}.issubset(codes):
        short_explanation = "가려움이나 불안·긴장을 줄이는 데 쓰이는 약이에요."
    elif purposes:
        short_explanation = purposes[0]["sentence"]
    else:
        short_explanation = FALLBACK_SPOKEN
    return {
        "easy_purposes": purposes,
        "purpose_label": " · ".join(item["easy_label"] for item in purposes),
        "short_explanation": short_explanation,
        "key_cautions": cautions,
        "key_caution": cautions[0]["short_sentence"] if cautions else None,
        "purpose_notice": PURPOSE_NOTICE,
    }


def medicine_guidance_from_medicine(med: dict[str, Any]) -> dict[str, Any]:
    return _compose_guidance(
        derive_easy_purposes_from_medicine(med),
        derive_key_cautions_from_medicine(med),
    )


def load_medicine_guidance(cursor: Any, med: dict[str, Any]) -> dict[str, Any]:
    """Prefer pharmacist-reviewed persisted guidance, then derived persisted rows."""
    medicine_code = str(med.get("medicine_code") or "").strip()
    if not medicine_code:
        return medicine_guidance_from_medicine(med)
    try:
        purpose_result = cursor.execute(
            """
                SELECT purpose_code, easy_label, easy_sentence AS sentence,
                       evidence_type, evidence_text, source, confidence, review_status
                FROM medicine_purposes
                WHERE medicine_code = ?
                ORDER BY CASE review_status WHEN 'REVIEWED' THEN 0 ELSE 1 END,
                         priority, id
            """,
            (medicine_code,),
        )
        purpose_columns = [item[0] for item in purpose_result.description or []]
        purpose_rows = [
            dict(row)
            if hasattr(row, "keys")
            else dict(zip(purpose_columns, row))
            for row in purpose_result.fetchall()
        ]
        caution_result = cursor.execute(
            """
                SELECT caution_code, short_sentence, evidence_text, source,
                       severity, review_status
                FROM medicine_key_cautions
                WHERE medicine_code = ?
                ORDER BY CASE review_status WHEN 'REVIEWED' THEN 0 ELSE 1 END, id
            """,
            (medicine_code,),
        )
        caution_columns = [item[0] for item in caution_result.description or []]
        caution_rows = [
            dict(row)
            if hasattr(row, "keys")
            else dict(zip(caution_columns, row))
            for row in caution_result.fetchall()
        ]
    except sqlite3.OperationalError:
        return medicine_guidance_from_medicine(med)

    reviewed_purposes = [
        row for row in purpose_rows if row.get("review_status") == "REVIEWED"
    ]
    reviewed_cautions = [
        row for row in caution_rows if row.get("review_status") == "REVIEWED"
    ]
    purposes = reviewed_purposes or purpose_rows
    cautions = reviewed_cautions or caution_rows
    if not purposes and not cautions:
        return medicine_guidance_from_medicine(med)
    return _compose_guidance(purposes, cautions)


def sync_medicine_guidance(cursor: Any, med: dict[str, Any]) -> dict[str, Any]:
    """Persist derived guidance while preserving pharmacist-reviewed rows."""
    guidance = medicine_guidance_from_medicine(med)
    medicine_code = str(med.get("medicine_code") or "").strip()
    if not medicine_code:
        return guidance

    purpose_codes: list[str] = []
    for priority, purpose in enumerate(guidance["easy_purposes"], start=1):
        purpose_code = str(purpose["purpose_code"])
        purpose_codes.append(purpose_code)
        cursor.execute(
            """
            INSERT INTO medicine_purposes (
                medicine_code, purpose_code, easy_label, easy_sentence,
                evidence_type, evidence_text, source, confidence,
                review_status, classifier_version, priority
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, '2.0', ?)
            ON CONFLICT(medicine_code, purpose_code) DO UPDATE SET
                easy_label = excluded.easy_label,
                easy_sentence = excluded.easy_sentence,
                evidence_type = excluded.evidence_type,
                evidence_text = excluded.evidence_text,
                source = excluded.source,
                confidence = excluded.confidence,
                classifier_version = excluded.classifier_version,
                priority = excluded.priority,
                updated_at = CURRENT_TIMESTAMP
            WHERE medicine_purposes.review_status != 'REVIEWED'
            """,
            (
                medicine_code,
                purpose_code,
                purpose["easy_label"],
                purpose["sentence"],
                purpose["evidence_type"],
                purpose.get("evidence_text"),
                purpose["source"],
                purpose["confidence"],
                purpose["review_status"],
                priority,
            ),
        )
    if purpose_codes:
        placeholders = ", ".join("?" for _ in purpose_codes)
        cursor.execute(
            f"""
            DELETE FROM medicine_purposes
            WHERE medicine_code = ? AND review_status = 'DERIVED'
              AND purpose_code NOT IN ({placeholders})
            """,
            (medicine_code, *purpose_codes),
        )
    else:
        cursor.execute(
            "DELETE FROM medicine_purposes WHERE medicine_code = ? AND review_status = 'DERIVED'",
            (medicine_code,),
        )

    caution_codes: list[str] = []
    for caution in guidance["key_cautions"]:
        caution_code = str(caution["caution_code"])
        caution_codes.append(caution_code)
        cursor.execute(
            """
            INSERT INTO medicine_key_cautions (
                medicine_code, caution_code, short_sentence, evidence_text,
                source, severity, review_status, classifier_version
            ) VALUES (?, ?, ?, ?, ?, ?, ?, '2.0')
            ON CONFLICT(medicine_code, caution_code) DO UPDATE SET
                short_sentence = excluded.short_sentence,
                evidence_text = excluded.evidence_text,
                source = excluded.source,
                severity = excluded.severity,
                classifier_version = excluded.classifier_version,
                updated_at = CURRENT_TIMESTAMP
            WHERE medicine_key_cautions.review_status != 'REVIEWED'
            """,
            (
                medicine_code,
                caution_code,
                caution["short_sentence"],
                caution.get("evidence_text"),
                caution["source"],
                caution["severity"],
                caution["review_status"],
            ),
        )
    if caution_codes:
        placeholders = ", ".join("?" for _ in caution_codes)
        cursor.execute(
            f"""
            DELETE FROM medicine_key_cautions
            WHERE medicine_code = ? AND review_status = 'DERIVED'
              AND caution_code NOT IN ({placeholders})
            """,
            (medicine_code, *caution_codes),
        )
    else:
        cursor.execute(
            "DELETE FROM medicine_key_cautions WHERE medicine_code = ? AND review_status = 'DERIVED'",
            (medicine_code,),
        )
    return load_medicine_guidance(cursor, med)


def format_display_name(name: str, easy_category: str | None) -> str:
    base = (name or "").strip()
    category = (easy_category or "").strip()
    if not base:
        return category
    if not category:
        return base
    return f"{base} ({category})"
