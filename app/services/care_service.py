"""보호자가 돌보는 어르신 목록과 한 분씩의 오늘 현황."""

from __future__ import annotations

import sqlite3
from datetime import date, datetime, timedelta, timezone
from typing import Any

from fastapi import HTTPException

from app.database import get_connection
from app.core.auth import auth_enforced, service_role
from app.core.kst import today_kst
from app.services.heart_reading import latest_heart_reading
from app.services.medication_history_service import get_medication_history
from app.services.today_medication_service import _slot_from_time, get_today_medicines

_KST = timezone(timedelta(hours=9))
_SLOT_LABELS = {"morning": "아침", "lunch": "점심", "dinner": "저녁"}
_MAX_ACTIVITIES = 6


def linked_rows(conn: sqlite3.Connection, guardian) -> list:
    """Return only links explicitly bound to this guardian account.

    A matching phone number alone is not evidence of patient consent.
    """
    return conn.execute(
        """
        SELECT g.*, u.name AS patient_name, u.phone AS patient_phone,
               u.birth_date AS patient_birth_date
        FROM guardians g
        JOIN users u ON u.id = g.user_id
        WHERE g.user_id != ? AND g.guardian_user_id = ?
        ORDER BY g.created_at, g.id
        """,
        (guardian["id"], guardian["id"]),
    ).fetchall()


def get_care_overview(guardian_user_id: str) -> dict[str, Any]:
    conn = get_connection()
    try:
        guardian = conn.execute(
            "SELECT * FROM users WHERE id = ?", (guardian_user_id,)
        ).fetchone()
        if not guardian:
            raise HTTPException(status_code=404, detail="사용자가 없습니다.")
        rows = linked_rows(conn, guardian)
    finally:
        conn.close()

    patients: list[dict[str, Any]] = []
    pending: list[dict[str, Any]] = []
    for row in rows:
        if (
            str(row["status"] or "").upper() != "ACCEPTED"
            or not row["consent_verified_at"]
        ):
            pending.append(
                {
                    "id": row["id"],
                    "patient_name": row["patient_name"],
                    "patient_phone": row["patient_phone"],
                    "patient_relation": row["patient_relation"],
                }
            )
        else:
            patients.append(_patient_summary(row))
    return {"guardian_user_id": guardian_user_id, "patients": patients, "pending": pending}


def _patient_summary(row) -> dict[str, Any]:
    patient_id = row["user_id"]
    today = today_kst()
    remote = None
    if auth_enforced() and service_role() == "main":
        from app.services.medication_feature_dur_client import load_remote_patient_overview
        remote = load_remote_patient_overview(
            user_id=patient_id, day=today.isoformat(),
            start=(today - timedelta(days=6)).isoformat(),
        )
    doses = (remote["today"] if remote else get_today_medicines(patient_id)).get("doses") or []
    slots = [
        {"label": _SLOT_LABELS.get(dose["slot"], dose["slot"]), "taken": bool(dose.get("taken"))}
        for dose in doses
    ]
    next_slot = next((slot["label"] for slot in slots if not slot["taken"]), None)

    week = (remote["history"] if remote else get_medication_history(
        patient_id, (today - timedelta(days=6)).isoformat(), today.isoformat()
    ))["days"]
    week_total = sum(day["total"] for day in week)
    week_taken = sum(day["taken"] for day in week)

    conn = get_connection()
    try:
        heart = latest_heart_reading(conn, patient_id)
        activities = _activities(conn, patient_id, today.isoformat(), include_medication=remote is None)
    finally:
        conn.close()
    if remote:
        activities += [
            {"text": f"{_SLOT_LABELS[item['slot']]} 약 드셨어요",
             "time": _clock(item.get("taken_at"), stored_in_utc=True)}
            for item in remote["activities"] if item.get("slot") in _SLOT_LABELS
        ]
        activities.sort(key=lambda item: item["time"], reverse=True)
        activities = activities[:_MAX_ACTIVITIES]

    return {
        "link_id": row["id"],
        "patient_id": patient_id,
        "name": row["patient_name"],
        "phone": row["patient_phone"],
        "relation": row["patient_relation"] or "",
        "age": _age(row["patient_birth_date"], today),
        "taken_count": sum(1 for slot in slots if slot["taken"]),
        "total_count": len(slots),
        "next_dose_label": f"{next_slot} 약" if next_slot else None,
        "slots": slots,
        "heart_rate": heart["bpm"] if heart else None,
        "heart_rate_normal": heart["normal"] if heart else None,
        "heart_rate_at": heart["measured_at"] if heart else None,
        "week_rate": round(week_taken * 100 / week_total) if week_total else None,
        "activities": activities,
    }


def _age(birth_date: str | None, today: date) -> int | None:
    try:
        birth = date.fromisoformat(str(birth_date or "")[:10])
    except ValueError:
        return None
    return today.year - birth.year - ((today.month, today.day) < (birth.month, birth.day))


def _clock(value: str | None, *, stored_in_utc: bool) -> str:
    try:
        moment = datetime.fromisoformat(str(value or "").replace(" ", "T"))
    except ValueError:
        return ""
    if moment.tzinfo is None and stored_in_utc:
        moment = moment.replace(tzinfo=timezone.utc)
    if moment.tzinfo is not None:
        moment = moment.astimezone(_KST)
    return moment.strftime("%H:%M")


def _activities(conn: sqlite3.Connection, patient_id: str, day: str, *, include_medication: bool = True) -> list[dict[str, str]]:
    """오늘 있었던 일. 어르신이 직접 누른 복약과 잰 심박수만 적는다."""
    taken_by_slot: dict[str, str] = {}
    for row in conn.execute(
        """
        SELECT ms.time_slot, ms.scheduled_time, ml.taken_at
        FROM medication_logs ml
        JOIN medication_schedules ms ON ms.id = ml.schedule_id
        WHERE ml.user_id = ? AND ms.scheduled_date = ?
          AND ml.status = 'TAKEN' AND ms.status = 'TAKEN'
        """,
        (patient_id, day if include_medication else ""),
    ):
        slot = _slot_from_time(row["time_slot"], row["scheduled_time"])
        taken_by_slot[slot] = max(taken_by_slot.get(slot, ""), str(row["taken_at"] or ""))

    items = [
        # medication_logs.taken_at 은 SQLite CURRENT_TIMESTAMP(UTC)로 쌓인다.
        {"text": f"{_SLOT_LABELS[slot]} 약 드셨어요", "time": _clock(at, stored_in_utc=True)}
        for slot, at in taken_by_slot.items()
    ]
    for row in conn.execute(
        """
        SELECT bpm, measured_at FROM heart_rate_logs
        WHERE user_id = ? AND measured_at LIKE ?
        ORDER BY measured_at DESC LIMIT 3
        """,
        (patient_id, f"{day}%"),
    ):
        items.append(
            {
                "text": f"심장 박동 {row['bpm']}",
                "time": _clock(row["measured_at"], stored_in_utc=False),
            }
        )
    items.sort(key=lambda item: item["time"], reverse=True)
    return items[:_MAX_ACTIVITIES]
