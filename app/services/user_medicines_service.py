"""Active user medicines for list and detail screens (one row per medicine code)."""

from __future__ import annotations

import json
from datetime import date
from typing import Any

from fastapi import HTTPException

from app.database import get_connection
from app.services.today_medication_service import _visible_medicine_item


def _parse_administration_times(raw: Any) -> list[str]:
    if isinstance(raw, list):
        return [str(t) for t in raw]
    if isinstance(raw, str) and raw.strip():
        try:
            parsed = json.loads(raw)
            if isinstance(parsed, list):
                return [str(t) for t in parsed]
        except json.JSONDecodeError:
            return []
    return []


def _latest_interaction_result(conn, user_id: str) -> dict[str, Any] | None:
    row = conn.execute(
        """
        SELECT assessment_status, risk_level, description, matches_json, created_at
        FROM risk_results
        WHERE user_id = ?
        ORDER BY created_at DESC, id DESC
        LIMIT 1
        """,
        (user_id,),
    ).fetchone()
    if not row:
        return None
    result = dict(row)
    try:
        matches = json.loads(result.get("matches_json") or "[]")
    except (TypeError, json.JSONDecodeError):
        matches = []
    result["matches"] = matches if isinstance(matches, list) else []
    return result


def _interaction_for_medicine(
    row: dict[str, Any],
    latest: dict[str, Any] | None,
) -> dict[str, Any]:
    if latest is None:
        return {
            "interaction_status": "not_checked",
            "interaction_summary": "아직 함께먹기 검사를 하지 않았어요.",
            "interaction_matches": [],
        }
    last_prescribed = str(
        row.get("last_prescribed_at") or row.get("start_date") or row.get("created_at") or ""
    )
    if last_prescribed and last_prescribed > str(latest.get("created_at") or ""):
        return {
            "interaction_status": "check_needed",
            "interaction_summary": "이 약을 등록한 뒤 함께먹기 검사가 필요해요.",
            "interaction_matches": [],
        }
    assessment = str(latest.get("assessment_status") or "").upper()
    if not assessment:
        assessment = (
            "RISK_FOUND"
            if latest.get("matches")
            else "INCOMPLETE"
            if str(latest.get("risk_level") or "").upper() == "UNKNOWN"
            else "SAFE"
        )
    if assessment == "INCOMPLETE":
        return {
            "interaction_status": "check_needed",
            "interaction_summary": str(latest.get("description") or "함께먹기 검사를 끝내지 못했어요."),
            "interaction_matches": [],
        }

    product = str(row.get("product_name") or "").strip()
    ingredient = str(row.get("ingredient") or "").strip()
    relevant: list[dict[str, Any]] = []
    for raw in latest.get("matches") or []:
        if not isinstance(raw, dict):
            continue
        names = [
            *[str(value) for value in raw.get("medicine_names_a") or []],
            *[str(value) for value in raw.get("medicine_names_b") or []],
        ]
        ingredients = [
            str(raw.get("ingredient_a") or ""),
            str(raw.get("ingredient_b") or ""),
        ]
        if (product and product in names) or any(
            ingredient and value and (value in ingredient or ingredient in value)
            for value in ingredients
        ):
            relevant.append(raw)
    if relevant:
        conflict_names: list[str] = []
        for match in relevant:
            for value in [
                *(match.get("medicine_names_a") or []),
                *(match.get("medicine_names_b") or []),
            ]:
                name = str(value or "").strip()
                if name and name != product and name not in conflict_names:
                    conflict_names.append(name)
        return {
            "interaction_status": "risk_found",
            "interaction_risk_level": str(latest.get("risk_level") or "UNKNOWN"),
            "interaction_conflict_names": conflict_names,
            "interaction_summary": str(
                relevant[0].get("reason") or "함께 먹을 때 주의가 필요해요."
            ),
            "interaction_matches": relevant,
        }
    return {
        "interaction_status": "none",
        "interaction_risk_level": str(latest.get("risk_level") or "LOW"),
        "interaction_conflict_names": [],
        "interaction_summary": "최근 검사에서 이 약과 관련된 함께먹기 주의를 찾지 못했어요.",
        "interaction_matches": [],
    }


def _usage_select(conn) -> str:
    medicine_cols = {row[1] for row in conn.execute("PRAGMA table_info(medicines)")}
    return ", m.usage" if "usage" in medicine_cols else ""


def _active_medicine_rows(conn, user_id: str) -> list[dict[str, Any]]:
    """현재약과 과거약을 합쳐 약 코드당 최신 등록 1건을 반환한다."""
    usage_select = _usage_select(conn)
    rows = conn.execute(
        f"""
        SELECT um.id AS user_medicine_id, um.dosage, um.dose_amount,
               um.dose_unit, um.frequency_per_day, um.administration_times,
               um.start_date, um.end_date, um.is_active, um.status,
               um.created_at, um.last_prescribed_at,
               (SELECT MAX(ml.taken_at)
                  FROM medication_logs ml
                  JOIN medication_schedules ms ON ms.id = ml.schedule_id
                 WHERE ms.user_medicine_id = um.id) AS last_taken_at,
               m.medicine_code, m.product_name, m.ingredient, m.easy_category,
               m.efficacy, m.precautions, m.short_explanation,
               m.explanation_review_status, m.ingredient_strength,
               m.dosage_form, m.administration_route{usage_select}
        FROM user_medicines um
        JOIN medicines m ON m.medicine_code = um.medicine_code
        WHERE um.user_id = ? AND um.medicine_code NOT LIKE 'MVP-%'
        ORDER BY um.id DESC
        """,
        (user_id,),
    ).fetchall()
    deduped: list[dict[str, Any]] = []
    seen_codes: set[str] = set()
    for row in rows:
        code = row["medicine_code"]
        if code in seen_codes:
            continue
        seen_codes.add(code)
        deduped.append(dict(row))
    deduped.reverse()
    return deduped


def _enrich_medicine_row(
    row: dict[str, Any],
    *,
    guidance_cursor,
    latest_interaction: dict[str, Any] | None = None,
) -> dict[str, Any] | None:
    item = _visible_medicine_item(row, guidance_cursor=guidance_cursor)
    if item is None:
        return None
    item["dosage"] = row.get("dosage")
    item["frequency_per_day"] = row.get("frequency_per_day")
    item["administration_times"] = _parse_administration_times(
        row.get("administration_times")
    )
    end_date = str(row.get("end_date") or "").strip()
    explicitly_active = bool(row.get("is_active", 1))
    item["status"] = (
        "active"
        if explicitly_active and (not end_date or end_date >= date.today().isoformat())
        else "past"
    )
    item["registered_at"] = row.get("created_at")
    item["last_prescribed_at"] = (
        row.get("last_prescribed_at") or row.get("start_date") or row.get("created_at")
    )
    item["last_taken_at"] = row.get("last_taken_at")
    item.update(_interaction_for_medicine(row, latest_interaction))
    user_medicine_id = row.get("user_medicine_id")
    if user_medicine_id is not None:
        try:
            item["user_medicine_id"] = int(user_medicine_id)
        except (TypeError, ValueError):
            pass
    return item


def get_user_medicines(user_id: str) -> dict[str, Any]:
    uid = (user_id or "").strip()
    if not uid:
        raise HTTPException(status_code=422, detail="user_id가 필요합니다.")

    conn = get_connection()
    try:
        user = conn.execute("SELECT id FROM users WHERE id = ?", (uid,)).fetchone()
        if not user:
            raise HTTPException(status_code=404, detail="사용자가 없습니다.")

        latest_interaction = _latest_interaction_result(conn, uid)
        medicines = [
            item
            for row in _active_medicine_rows(conn, uid)
            if (
                item := _enrich_medicine_row(
                    row,
                    guidance_cursor=conn,
                    latest_interaction=latest_interaction,
                )
            )
            is not None
        ]
        return {
            "user_id": uid,
            "medicines": medicines,
            "has_medicines": bool(medicines),
            "source": "server",
        }
    finally:
        conn.close()


def get_user_medicine(user_id: str, medicine_code: str) -> dict[str, Any]:
    uid = (user_id or "").strip()
    code = (medicine_code or "").strip()
    if not uid:
        raise HTTPException(status_code=422, detail="user_id가 필요합니다.")
    if not code:
        raise HTTPException(status_code=422, detail="medicine_code가 필요합니다.")

    conn = get_connection()
    try:
        user = conn.execute("SELECT id FROM users WHERE id = ?", (uid,)).fetchone()
        if not user:
            raise HTTPException(status_code=404, detail="사용자가 없습니다.")

        usage_select = _usage_select(conn)
        row = conn.execute(
            f"""
            SELECT um.id AS user_medicine_id, um.dosage, um.dose_amount,
                   um.dose_unit, um.frequency_per_day, um.administration_times,
                   um.start_date, um.end_date, um.is_active, um.status,
                   um.created_at, um.last_prescribed_at,
                   (SELECT MAX(ml.taken_at)
                      FROM medication_logs ml
                      JOIN medication_schedules ms ON ms.id = ml.schedule_id
                     WHERE ms.user_medicine_id = um.id) AS last_taken_at,
                   m.medicine_code, m.product_name, m.ingredient, m.easy_category,
                   m.efficacy, m.precautions, m.short_explanation,
                   m.explanation_review_status, m.ingredient_strength,
                   m.dosage_form, m.administration_route{usage_select}
            FROM user_medicines um
            JOIN medicines m ON m.medicine_code = um.medicine_code
            WHERE um.user_id = ? AND um.medicine_code = ?
              AND um.medicine_code NOT LIKE 'MVP-%'
            ORDER BY um.id DESC
            LIMIT 1
            """,
            (uid, code),
        ).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="해당 약을 찾을 수 없습니다.")

        medicine = _enrich_medicine_row(
            dict(row),
            guidance_cursor=conn,
            latest_interaction=_latest_interaction_result(conn, uid),
        )
        if medicine is None:
            raise HTTPException(status_code=404, detail="해당 약을 찾을 수 없습니다.")

        return {
            "user_id": uid,
            "medicine": medicine,
            "source": "server",
        }
    finally:
        conn.close()
