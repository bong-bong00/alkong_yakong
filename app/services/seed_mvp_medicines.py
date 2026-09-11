"""Seed a demo patient so the home screen can load from server medicines."""

from __future__ import annotations

from app.database import get_connection
from app.services.pharmacist.easy_category import derive_easy_category


MVP_USER_ID = "mvp-user"

# 허가 미러에 있는 제품. 프리마란·아디팜·휴온스시메티딘·프레벨액은 넣지 않는다.
# 코다론정과 레시프람정은 아디팜(히드록시진) OCR 등록 뒤
# 공식 DUR 병용금기 화면을 확인하기 위한 개발용 충돌 시나리오다.
_SEED_MEDS = (
    {
        "medicine_code": "200701021",
        "product_name": "코다론정(아미오다론염산염)",
        "ingredient": "아미오다론염산염",
        "dosage": "1알",
        "frequency_per_day": 3,
        "administration_times": '["08:00", "13:00", "20:00"]',
        "efficacy": (
            "심방성부정맥, 심실성부정맥, 기타 다른 부정맥용제로 치료되지 않는 "
            "재발성중증 부정맥\n협심증 등 기초심질환을 수반하는 부정맥"
        ),
        "precautions": "간장애 환자에게 신중히 투여한다. 임부에 투여하지 않는다.",
    },
    {
        "medicine_code": "197700120",
        "product_name": "부루펜정200밀리그램(이부프로펜)",
        "ingredient": "이부프로펜",
        "dosage": "1알",
        "frequency_per_day": 3,
        "administration_times": '["08:00", "13:00", "20:00"]',
        "efficacy": (
            "류마티양 관절염, 연소성 류마티양 관절염, 골관절염(퇴행성 관절질환), "
            "감기로 인한 발열 및 동통, 요통, 월경통"
        ),
        "precautions": "임부에 투여하지 않는다. 음주 시 주의. 졸음이 올 수 있으며 운전 및 기계조작을 피한다.",
    },
    {
        "medicine_code": "196400046",
        "product_name": "게루삼정",
        "ingredient": "탄산마그네슘|침강탄산칼슘|탄산수소나트륨|건조수산화알루미늄 겔",
        "dosage": "1알",
        "frequency_per_day": 3,
        "administration_times": '["08:00", "13:00", "20:00"]',
        "efficacy": "위산과다, 속쓰림, 위부불쾌감, 위부팽만감, 체함, 구역, 구토, 위통, 신트림.",
        "precautions": "신장애 환자에게 신중투여한다.",
    },
    {
        "medicine_code": "200809813",
        "product_name": "레시프람정(에스시탈로프람옥살산염)",
        "ingredient": "에스시탈로프람옥살산염",
        "dosage": "1알",
        "frequency_per_day": 1,
        "administration_times": '["08:00"]',
        "efficacy": "주요우울장애, 광장공포증을 수반하거나 수반하지 않는 공황장애, 사회불안장애, 범불안장애, 강박장애의 치료",
        "short_explanation": "불안이나 우울 증상을 치료할 목적으로 처방될 수 있어요.",
        "precautions": "다른 약을 복용 중이면 의사나 약사에게 알려야 한다.",
    },
)


def ensure_mvp_demo_medicines() -> str:
    """Create mvp-user and replace active medicines with development demo data."""
    conn = get_connection()
    try:
        conn.execute(
            """
            INSERT OR IGNORE INTO users (id, name, role, birth_date)
            VALUES (?, '체험환자', 'PATIENT', '1958-01-01')
            """,
            (MVP_USER_ID,),
        )
        conn.execute(
            """
            UPDATE users
            SET name = COALESCE(NULLIF(trim(name), ''), '체험환자'),
                birth_date = COALESCE(NULLIF(trim(birth_date), ''), '1958-01-01')
            WHERE id = ?
            """,
            (MVP_USER_ID,),
        )
        guardian = conn.execute(
            "SELECT id FROM guardians WHERE user_id = ? LIMIT 1",
            (MVP_USER_ID,),
        ).fetchone()
        if not guardian:
            conn.execute(
                """
                INSERT INTO guardians (id, user_id, guardian_name, relationship)
                VALUES (?, ?, '지안', '딸')
                """,
                (f"{MVP_USER_ID}-guardian", MVP_USER_ID),
            )
        for med in _SEED_MEDS:
            exists = conn.execute(
                "SELECT 1 FROM medicines WHERE medicine_code = ?",
                (med["medicine_code"],),
            ).fetchone()
            if exists:
                continue
            category = derive_easy_category(
                product_name=med["product_name"],
                ingredient=med["ingredient"],
                efficacy=med["efficacy"],
            )
            conn.execute(
                """
                INSERT INTO medicines (
                    medicine_code, product_name, ingredient, efficacy,
                    precautions, easy_category, short_explanation,
                    explanation_review_status
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    med["medicine_code"],
                    med["product_name"],
                    med["ingredient"],
                    med["efficacy"],
                    med.get("precautions"),
                    category,
                    med.get("short_explanation"),
                    "REVIEWED" if med.get("short_explanation") else None,
                ),
            )
        for med in _SEED_MEDS:
            conn.execute(
                """
                UPDATE medicines
                SET precautions = COALESCE(NULLIF(trim(precautions), ''), ?),
                    short_explanation = CASE
                        WHEN ? IS NOT NULL THEN ?
                        ELSE short_explanation
                    END,
                    explanation_review_status = CASE
                        WHEN ? IS NOT NULL THEN 'REVIEWED'
                        ELSE explanation_review_status
                    END
                WHERE medicine_code = ?
                """,
                (
                    med.get("precautions"),
                    med.get("short_explanation"),
                    med.get("short_explanation"),
                    med.get("short_explanation"),
                    med["medicine_code"],
                ),
            )

        desired = [med["medicine_code"] for med in _SEED_MEDS]
        active_rows = conn.execute(
            """
            SELECT medicine_code FROM user_medicines
            WHERE user_id = ? AND COALESCE(is_active, 1) = 1
            ORDER BY id
            """,
            (MVP_USER_ID,),
        ).fetchall()
        active_codes = [row["medicine_code"] for row in active_rows]
        if active_codes != desired:
            conn.execute(
                "UPDATE user_medicines SET is_active = 0 WHERE user_id = ?",
                (MVP_USER_ID,),
            )
            conn.execute(
                "DELETE FROM medication_schedules WHERE user_id = ?",
                (MVP_USER_ID,),
            )
            for med in _SEED_MEDS:
                conn.execute(
                    """
                    INSERT INTO user_medicines (
                        user_id, medicine_code, dosage, frequency_per_day,
                        administration_times, is_active
                    ) VALUES (?, ?, ?, ?, ?, 1)
                    """,
                    (
                        MVP_USER_ID,
                        med["medicine_code"],
                        med["dosage"],
                        med["frequency_per_day"],
                        med["administration_times"],
                    ),
                )
        conn.commit()
        try:
            from app.services.pharmacist.easy_category import (
                backfill_all_medicine_guidance,
                derive_key_cautions_from_medicine,
            )

            backfill_all_medicine_guidance()
            conn2 = get_connection()
            try:
                for med in _SEED_MEDS:
                    row = conn2.execute(
                        "SELECT * FROM medicines WHERE medicine_code = ?",
                        (med["medicine_code"],),
                    ).fetchone()
                    if not row:
                        continue
                    if derive_key_cautions_from_medicine(dict(row)):
                        continue
                    extra = (med.get("precautions") or "").strip()
                    if not extra:
                        continue
                    current = str(row["precautions"] or "")
                    conn2.execute(
                        "UPDATE medicines SET precautions = ? WHERE medicine_code = ?",
                        ((current + "\n" + extra).strip(), med["medicine_code"]),
                    )
                conn2.commit()
            finally:
                conn2.close()
            backfill_all_medicine_guidance()
        except Exception:
            pass
        return MVP_USER_ID
    finally:
        conn.close()
