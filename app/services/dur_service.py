import json

from fastapi import HTTPException

from app.database import get_connection
from app.models.schemas import DurAnalyzeRequest


def _normalize(value: str) -> str:
    return "".join(value.lower().split())


def analyze_dur(request: DurAnalyzeRequest) -> dict:
    conn = get_connection()
    try:
        cursor = conn.cursor()
        if not cursor.execute(
            "SELECT 1 FROM users WHERE id = ?", (request.user_id,)
        ).fetchone():
            raise HTTPException(status_code=404, detail="사용자가 없습니다.")

        if request.medicine_codes:
            placeholders = ",".join("?" for _ in request.medicine_codes)
            medicines = cursor.execute(
                f"""
                SELECT medicine_code, product_name, ingredient
                FROM medicines WHERE medicine_code IN ({placeholders})
                """,
                request.medicine_codes,
            ).fetchall()
        else:
            medicines = cursor.execute(
                """
                SELECT DISTINCT m.medicine_code, m.product_name, m.ingredient
                FROM user_medicines um
                JOIN medicines m ON m.medicine_code = um.medicine_code
                WHERE um.user_id = ? AND um.is_active = 1
                """,
                (request.user_id,),
            ).fetchall()

        if not medicines:
            raise HTTPException(status_code=400, detail="분석할 복용 약이 없습니다.")

        ingredients = [row["ingredient"] for row in medicines]
        normalized = {_normalize(value): value for value in ingredients}
        matches = []
        for taboo in cursor.execute("SELECT * FROM dur_taboo").fetchall():
            ingredient_a = _normalize(taboo["ingredient_a"])
            ingredient_b = _normalize(taboo["ingredient_b"] or "")
            matched = ingredient_a in normalized and (
                not ingredient_b or ingredient_b in normalized
            )
            if not matched:
                continue
            cursor.execute(
                """
                INSERT INTO risk_results (
                    user_id, risk_level, taboo_id, ingredient_a, ingredient_b,
                    description, analyzed_ingredients
                ) VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    request.user_id,
                    taboo["severity"],
                    taboo["id"],
                    taboo["ingredient_a"],
                    taboo["ingredient_b"],
                    taboo["description"],
                    json.dumps(ingredients, ensure_ascii=False),
                ),
            )
            matches.append(
                {
                    "risk_result_id": cursor.lastrowid,
                    "risk_level": taboo["severity"],
                    "taboo_type": taboo["taboo_type"],
                    "ingredient_a": taboo["ingredient_a"],
                    "ingredient_b": taboo["ingredient_b"],
                    "description": taboo["description"],
                }
            )

        if not matches:
            cursor.execute(
                """
                INSERT INTO risk_results (
                    user_id, risk_level, description, analyzed_ingredients
                ) VALUES (?, 'LOW', ?, ?)
                """,
                (
                    request.user_id,
                    "현재 등록된 DUR 금기 기준에서 발견된 위험이 없습니다.",
                    json.dumps(ingredients, ensure_ascii=False),
                ),
            )

        conn.commit()
        return {
            "user_id": request.user_id,
            "risk_level": _highest_level(matches),
            "ingredients": ingredients,
            "matches": matches,
        }
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


def _highest_level(matches: list[dict]) -> str:
    if not matches:
        return "LOW"
    order = {"LOW": 0, "CAUTION": 1, "WARNING": 2, "HIGH": 3, "CRITICAL": 4}
    return max(matches, key=lambda item: order.get(item["risk_level"], 1))["risk_level"]


def get_latest_dur(user_id: str) -> dict:
    conn = get_connection()
    try:
        latest = conn.execute(
            """
            SELECT * FROM risk_results
            WHERE user_id = ?
            ORDER BY created_at DESC, id DESC
            LIMIT 1
            """,
            (user_id,),
        ).fetchone()
        if not latest:
            raise HTTPException(status_code=404, detail="DUR 분석 결과가 없습니다.")
        result = dict(latest)
        result["analyzed_ingredients"] = json.loads(result["analyzed_ingredients"])
        return result
    finally:
        conn.close()
