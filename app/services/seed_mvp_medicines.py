"""Seed a demo patient so the home screen can load from server medicines."""

from __future__ import annotations

from app.database import get_connection
from app.services.pharmacist.easy_category import derive_easy_category


MVP_USER_ID = "mvp-user"

_SEED_MEDS = (
    {
        "medicine_code": "MVP-AMLO",
        "product_name": "암로디핀정5밀리그램",
        "ingredient": "암로디핀 5mg",
        "dosage": "1알",
        "frequency_per_day": 2,
        "efficacy": "고혈압, 혈압을 낮추는 데 사용",
    },
    {
        "medicine_code": "MVP-ASP",
        "product_name": "아스피린장용정100밀리그램",
        "ingredient": "아스피린 100mg",
        "dosage": "1알",
        "frequency_per_day": 1,
        "efficacy": "혈전 생성 억제, 항혈소판",
    },
    {
        "medicine_code": "MVP-MET",
        "product_name": "메트포르민정500밀리그램",
        "ingredient": "메트포르민 500mg",
        "dosage": "1알",
        "frequency_per_day": 2,
        "efficacy": "당뇨, 혈당 조절",
    },
)


def ensure_mvp_demo_medicines() -> str:
    """Create mvp-user and active medicines if missing. Returns user_id."""
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
                ON CONFLICT(medicine_code) DO UPDATE SET
                    product_name = excluded.product_name,
                    ingredient = excluded.ingredient,
                    efficacy = excluded.efficacy,
                    easy_category = COALESCE(excluded.easy_category, medicines.easy_category),
                    updated_at = CURRENT_TIMESTAMP
                """,
                (
                    med["medicine_code"],
                    med["product_name"],
                    med["ingredient"],
                    med["efficacy"],
                    category,
                ),
            )
            existing = conn.execute(
                """
                SELECT id FROM user_medicines
                WHERE user_id = ? AND medicine_code = ? AND COALESCE(is_active, 1) = 1
                """,
                (MVP_USER_ID, med["medicine_code"]),
            ).fetchone()
            if existing:
                continue
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
        return MVP_USER_ID
    finally:
        conn.close()
