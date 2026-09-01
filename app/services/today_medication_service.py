"""Today's medicines for the patient home screen (from user_medicines)."""

from __future__ import annotations

import json
from datetime import date
from typing import Any

from fastapi import HTTPException

from app.database import get_connection
from app.services.pharmacist.easy_category import (
    derive_easy_category_from_medicine,
    format_display_name,
)


def get_today_medicines(user_id: str, target_date: str | None = None) -> dict[str, Any]:
    uid = (user_id or "").strip()
    if not uid:
        raise HTTPException(status_code=422, detail="user_id가 필요합니다.")
    day = target_date or date.today().isoformat()
    conn = get_connection()
    try:
        user = conn.execute("SELECT id, name FROM users WHERE id = ?", (uid,)).fetchone()
        if not user:
            raise HTTPException(status_code=404, detail="사용자가 없습니다.")

        # 오늘 스케줄이 있으면 스케줄 기준, 없으면 활성 user_medicines 로 슬롯 구성
        schedule_rows = conn.execute(
            """
            SELECT ms.time_slot, ms.scheduled_time, ms.status,
                   um.dosage, um.frequency_per_day,
                   m.medicine_code, m.product_name, m.ingredient, m.easy_category,
                   m.efficacy
            FROM medication_schedules ms
            JOIN user_medicines um ON um.id = ms.user_medicine_id
            JOIN medicines m ON m.medicine_code = um.medicine_code
            WHERE ms.user_id = ? AND ms.scheduled_date = ?
              AND COALESCE(um.is_active, 1) = 1
            ORDER BY ms.scheduled_time, ms.id
            """,
            (uid, day),
        ).fetchall()

        if schedule_rows:
            doses = _doses_from_schedules(schedule_rows)
        else:
            active = conn.execute(
                """
                SELECT um.dosage, um.frequency_per_day, um.administration_times,
                       m.medicine_code, m.product_name, m.ingredient, m.easy_category,
                       m.efficacy
                FROM user_medicines um
                JOIN medicines m ON m.medicine_code = um.medicine_code
                WHERE um.user_id = ? AND COALESCE(um.is_active, 1) = 1
                ORDER BY um.id
                """,
                (uid,),
            ).fetchall()
            doses = _doses_from_active_medicines(active)

        guardian = conn.execute(
            """
            SELECT guardian_name, relationship
            FROM guardians WHERE user_id = ?
            ORDER BY id LIMIT 1
            """,
            (uid,),
        ).fetchone()

        return {
            "user_id": uid,
            "date": day,
            "doses": doses,
            "guardian_relation": (
                (guardian["relationship"] if guardian else None) or "보호자"
            ),
            "guardian_name": (guardian["guardian_name"] if guardian else None) or "가족",
            "source": "server",
            "has_server_medicines": bool(doses),
        }
    finally:
        conn.close()


def _medicine_item(row) -> dict[str, Any]:
    data = dict(row)
    name = (
        str(data.get("ingredient") or "").strip()
        or str(data.get("product_name") or "").strip()
        or "약"
    )
    category = data.get("easy_category")
    if not category:
        category = derive_easy_category_from_medicine(data)
    dosage = str(data.get("dosage") or "").strip() or "1알"
    return {
        "medicine_code": data.get("medicine_code"),
        "ingredient": name,
        "amount": dosage,
        "easy_category": category,
        "display_name": format_display_name(name, category),
        "product_name": data.get("product_name"),
    }


def _slot_from_time(time_slot: str | None, scheduled_time: str | None) -> str:
    raw = str(time_slot or "").upper()
    if "MORNING" in raw or "아침" in raw:
        return "morning"
    if "LUNCH" in raw or "AFTERNOON" in raw or "점심" in raw:
        return "lunch"
    if "EVENING" in raw or "NIGHT" in raw or "저녁" in raw:
        return "dinner"
    hour = 8
    try:
        hour = int(str(scheduled_time or "08:00").split(":")[0])
    except ValueError:
        hour = 8
    if hour < 11:
        return "morning"
    if hour < 16:
        return "lunch"
    return "dinner"


def _doses_from_schedules(rows) -> list[dict[str, Any]]:
    buckets: dict[str, dict[str, Any]] = {}
    for row in rows:
        slot = _slot_from_time(row["time_slot"], row["scheduled_time"])
        bucket = buckets.setdefault(
            slot,
            {"slot": slot, "taken": True, "medicines": [], "_codes": set()},
        )
        status = str(row["status"] or "PENDING").upper()
        if status in {"PENDING", "MISSED", "SNOOZED"}:
            bucket["taken"] = False
        code = row["medicine_code"]
        if code in bucket["_codes"]:
            continue
        bucket["_codes"].add(code)
        bucket["medicines"].append(_medicine_item(row))
    order = ("morning", "lunch", "dinner")
    result = []
    for slot in order:
        if slot not in buckets:
            continue
        item = buckets[slot]
        item.pop("_codes", None)
        if item["medicines"]:
            result.append(item)
    return result


def _doses_from_active_medicines(rows) -> list[dict[str, Any]]:
    if not rows:
        return []
    # frequency 기준으로 슬롯에 나눠 담는다.
    buckets: dict[str, list[dict[str, Any]]] = {
        "morning": [],
        "lunch": [],
        "dinner": [],
    }
    for row in rows:
        med = _medicine_item(row)
        freq = int(row["frequency_per_day"] or 1)
        times = []
        raw_times = row["administration_times"]
        if isinstance(raw_times, str) and raw_times.strip():
            try:
                parsed = json.loads(raw_times)
                if isinstance(parsed, list):
                    times = [str(t) for t in parsed]
            except json.JSONDecodeError:
                times = []
        if times:
            for t in times:
                buckets[_slot_from_time(None, t)].append(med)
            continue
        if freq <= 1:
            buckets["morning"].append(med)
        elif freq == 2:
            buckets["morning"].append(med)
            buckets["dinner"].append(med)
        else:
            buckets["morning"].append(med)
            buckets["lunch"].append(med)
            buckets["dinner"].append(med)

    result = []
    for slot in ("morning", "lunch", "dinner"):
        meds = buckets[slot]
        if not meds:
            continue
        # 같은 약 중복 제거
        uniq = []
        seen = set()
        for med in meds:
            key = med.get("medicine_code") or med.get("ingredient")
            if key in seen:
                continue
            seen.add(key)
            uniq.append(med)
        result.append({"slot": slot, "taken": False, "medicines": uniq})
    return result
