"""Explicit, idempotent synthetic history for a dedicated presentation account.

Never invoked by app startup. Requires existing SQLite databases and a user whose
name contains '시연' or 'DEMO'. Dry-run is the default; --apply is opt-in.
"""
import argparse
import json
import sqlite3
from datetime import date, timedelta
from pathlib import Path

DEMO_SOURCE = "DEMO_SYNTHETIC_20261006"
DEMO_MEDICINE = "DEMO-PRESENTATION-20261006"
DEMO_PHONE = "010-1234-5678"
DEMO_HEALTH_PROFILE = {
    "smoking": "폈어요",
    "drinking": "자주 마셔요",
    "diseases": ["고혈압", "당뇨", "고지혈증", "콩팥병", "간 질환"],
    "past_history": True,
    "past_illnesses": ["천식", "위궤양", "뇌졸중"],
    "family_history": True,
    "family_illnesses": ["고혈압", "당뇨"],
    "allergies": ["페니실린 (항생제)", "아스피린", "소염진통제 (이부프로펜 등)"],
}


def configure_demo_health(conn, user_id):
    """Set only synthetic health fields; preserve phone, password and real records."""
    check_demo_user(conn, user_id)
    phone = conn.execute("SELECT phone FROM users WHERE id=?", (user_id,)).fetchone()[0]
    if "".join(char for char in str(phone or "") if char.isdigit()) != "01012345678":
        raise ValueError("요청한 010-1234-5678 계정이 아닙니다.")
    values = {
        key: json.dumps(value, ensure_ascii=False) if isinstance(value, list) else value
        for key, value in DEMO_HEALTH_PROFILE.items()
    }
    conn.execute("UPDATE users SET " + ",".join(f"{key}=?" for key in values) + " WHERE id=?",
                 (*values.values(), user_id))


def check_demo_user(conn, user_id):
    row = conn.execute("SELECT name FROM users WHERE id=?", (user_id,)).fetchone()
    if not row or not ("시연" in row[0] or "DEMO" in row[0].upper()):
        raise ValueError("시연 또는 DEMO가 이름에 들어간 전용 계정만 허용합니다.")


def seed_hearts(conn, user_id):
    check_demo_user(conn, user_id)
    inserted = 0
    start = date(2026, 9, 21)
    for offset in range(15):
        day = start + timedelta(days=offset)
        before = (76, 79, 74, 82, 77, 80, 75)[offset % 7]
        after = before + (-2, 3, 1, -3, 4)[offset % 5]
        for clock, bpm, context in (
            ("08:00:00+09:00", before, "before_medication"),
            ("08:45:00+09:00", after, "after_medication"),
        ):
            at = f"{day.isoformat()}T{clock}"
            if not conn.execute(
                "SELECT 1 FROM heart_rate_logs WHERE user_id=? AND measured_at=? AND source=?",
                (user_id, at, DEMO_SOURCE),
            ).fetchone():
                conn.execute(
                    "INSERT INTO heart_rate_logs(user_id,bpm,measured_at,device_id,source,measurement_context) "
                    "VALUES(?,?,?,?,?,?)",
                    (user_id, bpm, at, "DEMO-NOT-A-REAL-SENSOR", DEMO_SOURCE, context),
                )
                inserted += 1
    return inserted


def seed_medications(conn, user_id):
    check_demo_user(conn, user_id)
    prescription_id = f"DEMO-20261006-{user_id}"
    conn.execute(
        "INSERT OR IGNORE INTO medicines(medicine_code,product_name,ingredient) VALUES(?,?,?)",
        (DEMO_MEDICINE, "시연용 가상약(실제 약 아님)", "시연용 가상 성분"),
    )
    conn.execute(
        "INSERT OR IGNORE INTO prescriptions(id,user_id,source_type,hospital_name,prescribed_date,expire_date) "
        "VALUES(?,?,'MANUAL','시연용 가상 처방전','2026-09-21','2026-09-27')",
        (prescription_id, user_id),
    )
    item = conn.execute(
        "SELECT id FROM prescription_items WHERE prescription_id=? AND medicine_code=?",
        (prescription_id, DEMO_MEDICINE),
    ).fetchone()
    if not item:
        item_id = conn.execute(
            "INSERT INTO prescription_items(prescription_id,medicine_code,ocr_drug_name,duration_days,"
            "frequency_per_day,administration_times,match_status,warning_note) "
            "VALUES(?,?,?,7,3,?,'UNMATCHED',?)",
            (prescription_id, DEMO_MEDICINE, "시연용 가상약(실제 약 아님)",
             json.dumps(["08:00", "12:00", "20:00"]), DEMO_SOURCE),
        ).lastrowid
    else:
        item_id = item[0]
    medicine = conn.execute(
        "SELECT id FROM user_medicines WHERE user_id=? AND prescription_item_id=?",
        (user_id, item_id),
    ).fetchone()
    if not medicine:
        medicine_id = conn.execute(
            "INSERT INTO user_medicines(user_id,medicine_code,prescription_item_id,start_date,end_date,"
            "frequency_per_day,administration_times,is_active,status) "
            "VALUES(?,?,?,'2026-09-21','2026-09-27',3,?,0,'INACTIVE')",
            (user_id, DEMO_MEDICINE, item_id, json.dumps(["08:00", "12:00", "20:00"])),
        ).lastrowid
    else:
        medicine_id = medicine[0]
    inserted = 0
    for offset in range(7):
        day = date(2026, 9, 21) + timedelta(days=offset)
        for slot, clock in (("morning", "08:00"), ("lunch", "12:00"), ("dinner", "20:00")):
            # Two missed slots demonstrate the calendar's distinction, not 100% adherence.
            taken = (offset, slot) not in ((2, "lunch"), (5, "dinner"))
            cursor = conn.execute(
                "INSERT OR IGNORE INTO medication_schedules(user_id,user_medicine_id,scheduled_date,"
                "scheduled_time,time_slot,status) VALUES(?,?,?,?,?,?)",
                (user_id, medicine_id, day.isoformat(), clock, slot, "TAKEN" if taken else "MISSED"),
            )
            inserted += cursor.rowcount
            schedule_id = conn.execute(
                "SELECT id FROM medication_schedules WHERE user_medicine_id=? AND scheduled_date=? AND scheduled_time=?",
                (medicine_id, day.isoformat(), clock),
            ).fetchone()[0]
            if taken and not conn.execute(
                "SELECT 1 FROM medication_logs WHERE schedule_id=?", (schedule_id,)
            ).fetchone():
                conn.execute(
                    "INSERT INTO medication_logs(user_id,schedule_id,user_medicine_id,taken_at,status,note) "
                    "VALUES(?,?,?,?,'TAKEN',?)",
                    (user_id, schedule_id, medicine_id, f"{day}T{clock}:00+09:00", DEMO_SOURCE),
                )
    return inserted


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--heart-db", required=True)
    parser.add_argument("--medication-db", required=True)
    parser.add_argument("--user-id", required=True)
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--health-profile", action="store_true",
                        help="010-1234-5678 시연 전용 계정의 가상 건강정보도 설정")
    args = parser.parse_args()
    targets = [(Path(args.heart_db).resolve(), seed_hearts),
               (Path(args.medication_db).resolve(), seed_medications)]
    # Validate both before writing either. A failed second write is safe to retry.
    for path, _ in targets:
        with sqlite3.connect(path.as_uri() + "?mode=ro", uri=True) as conn:
            check_demo_user(conn, args.user_id)
    if not args.apply:
        print("DRY RUN: 9/21~10/5 심박 30건, 9/21~9/27 복약 일정 21건. 쓰기 없음.")
        return
    for path, seed in targets:
        with sqlite3.connect(path.as_uri() + "?mode=rw", uri=True) as conn:
            conn.execute("PRAGMA foreign_keys=ON")
            if args.health_profile:
                configure_demo_health(conn, args.user_id)
            count = seed(conn, args.user_id)
        print(f"{seed.__name__}: inserted={count} db={path}")


if __name__ == "__main__":
    main()
