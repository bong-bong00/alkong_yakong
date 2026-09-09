"""Seed a demo patient so the home screen can load from server medicines."""

from __future__ import annotations

from app.database import get_connection
from app.services.pharmacist.easy_category import derive_easy_category
from app.services.pharmacist.retrieve import refresh_app_medicines_from_permission


MVP_USER_ID = "mvp-user"

# 허가 미러에 있는 제품. 프리마란·아디팜·휴온스시메티딘·프레벨액은 넣지 않는다.
# 코다론정은 아디팜(히드록시진)과 병용금기.
_SEED_MEDS = (
    {
        "medicine_code": "200701021",
        "product_name": "코다론정(아미오다론염산염)",
        "ingredient": "아미오다론염산염",
        "dosage": "1알",
        "frequency_per_day": 3,
        "efficacy": (
            "심방성부정맥, 심실성부정맥, 기타 다른 부정맥용제로 치료되지 않는 "
            "재발성중증 부정맥\n협심증 등 기초심질환을 수반하는 부정맥"
        ),
    },
    {
        "medicine_code": "197700120",
        "product_name": "부루펜정200밀리그램(이부프로펜)",
        "ingredient": "이부프로펜",
        "dosage": "1알",
        "frequency_per_day": 3,
        "efficacy": (
            "류마티양 관절염, 연소성 류마티양 관절염, 골관절염(퇴행성 관절질환), "
            "감기로 인한 발열 및 동통, 요통, 월경통"
        ),
    },
    {
        "medicine_code": "196400046",
        "product_name": "게루삼정",
        "ingredient": "탄산마그네슘|침강탄산칼슘|탄산수소나트륨|건조수산화알루미늄 겔",
        "dosage": "1알",
        "frequency_per_day": 3,
        "efficacy": "위산과다, 속쓰림, 위부불쾌감, 위부팽만감, 체함, 구역, 구토, 위통, 신트림.",
    },
)


def ensure_mvp_demo_medicines() -> str:
    """Create mvp-user and replace active medicines with the demo trio."""
    conn = get_connection()
    try:
        conn.execute(
            """
            INSERT OR IGNORE INTO users (id, name, role)
            VALUES (?, '체험환자', 'PATIENT')
            """,
            (MVP_USER_ID,),
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
                    medicine_code, product_name, ingredient, efficacy, easy_category
                ) VALUES (?, ?, ?, ?, ?)
                """,
                (
                    med["medicine_code"],
                    med["product_name"],
                    med["ingredient"],
                    med["efficacy"],
                    category,
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
                        user_id, medicine_code, dosage, frequency_per_day, is_active
                    ) VALUES (?, ?, ?, ?, 1)
                    """,
                    (
                        MVP_USER_ID,
                        med["medicine_code"],
                        med["dosage"],
                        med["frequency_per_day"],
                    ),
                )
        conn.commit()
        try:
            refresh_app_medicines_from_permission()
        except Exception:
            pass
        return MVP_USER_ID
    finally:
        conn.close()
