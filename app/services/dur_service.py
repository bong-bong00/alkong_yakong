import json
import uuid
from collections import defaultdict
from datetime import date

from fastapi import HTTPException

from app.database import get_connection
from app.models.schemas import DurAnalyzeRequest


HIGH_TYPES = {"병용금기", "중복성분", "효능군중복"}
MEDIUM_TYPES = {"연령금기", "임부금기"}


def _normalize(value: str | None) -> str:
    return "".join(str(value or "").lower().split())


def _risk_type(value: str | None) -> str:
    normalized = _normalize(value)
    mappings = {
        "병용금기": "병용금기",
        "combination": "병용금기",
        "contraindicatedcombination": "병용금기",
        "중복성분": "중복성분",
        "duplicate": "중복성분",
        "duplicateingredient": "중복성분",
        "효능군중복": "효능군중복",
        "efficacyduplicate": "효능군중복",
        "연령금기": "연령금기",
        "age": "연령금기",
        "agecontraindication": "연령금기",
        "임부금기": "임부금기",
        "pregnancy": "임부금기",
        "pregnancycontraindication": "임부금기",
    }
    return mappings.get(normalized, value or "성분주의")


def _age_from_birth_date(value: str | None) -> int | None:
    if not value:
        return None
    try:
        born = date.fromisoformat(value)
    except ValueError:
        return None
    today = date.today()
    return today.year - born.year - ((today.month, today.day) < (born.month, born.day))


def analyze_dur(request: DurAnalyzeRequest) -> dict:
    conn = get_connection()
    try:
        cursor = conn.cursor()
        user = cursor.execute(
            "SELECT id, birth_date, gender FROM users WHERE id = ?",
            (request.user_id,),
        ).fetchone()
        if not user:
            raise HTTPException(status_code=404, detail="사용자가 없습니다.")

        medicines = _load_medicines(cursor, request)
        if not medicines:
            raise HTTPException(status_code=400, detail="분석할 복용 약이 없습니다.")

        ingredients = [row["ingredient"] for row in medicines if row["ingredient"]]
        normalized_ingredients = defaultdict(list)
        for medicine in medicines:
            normalized_ingredients[_normalize(medicine["ingredient"])].append(medicine)

        age = _age_from_birth_date(user["birth_date"])
        matches = _duplicate_matches(normalized_ingredients)
        taboo_rows = cursor.execute("SELECT * FROM dur_taboo").fetchall()
        official_matches = _taboo_matches(
            taboo_rows,
            normalized_ingredients,
            age=age,
            is_pregnant=request.is_pregnant,
        )
        matches.extend(official_matches)

        # Legacy ingredient rows remain usable when no structured DUR type matched.
        if not official_matches:
            matches.extend(
                _legacy_matches(taboo_rows, normalized_ingredients)
            )

        matches = _deduplicate_matches(matches)
        risk_level = _risk_level(matches)
        analysis_id = str(uuid.uuid4())
        description = (
            f"DUR 위험 {len(matches)}건이 확인되었습니다."
            if matches
            else "현재 등록된 DUR 기준에서 발견된 위험이 없습니다."
        )
        cursor.execute(
            """
            INSERT INTO risk_results (
                user_id, risk_level, description, analyzed_ingredients,
                analysis_id, risk_type, total_matches, matches_json
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                request.user_id,
                risk_level,
                description,
                json.dumps(ingredients, ensure_ascii=False),
                analysis_id,
                matches[0]["type"] if matches else None,
                len(matches),
                json.dumps(matches, ensure_ascii=False),
            ),
        )
        risk_result_id = cursor.lastrowid
        conn.commit()
        return {
            "risk_result_id": risk_result_id,
            "analysis_id": analysis_id,
            "user_id": request.user_id,
            "risk_level": risk_level,
            "total_matches": len(matches),
            "representative_type": matches[0]["type"] if matches else None,
            "ingredients": ingredients,
            "matches": matches,
        }
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


def _load_medicines(cursor, request: DurAnalyzeRequest):
    if request.medicine_codes:
        placeholders = ",".join("?" for _ in request.medicine_codes)
        return cursor.execute(
            f"""
            SELECT medicine_code, product_name, ingredient
            FROM medicines WHERE medicine_code IN ({placeholders})
            """,
            request.medicine_codes,
        ).fetchall()
    return cursor.execute(
        """
        SELECT m.medicine_code, m.product_name, m.ingredient
        FROM user_medicines um
        JOIN medicines m ON m.medicine_code = um.medicine_code
        WHERE um.user_id = ? AND um.is_active = 1
        ORDER BY um.id
        """,
        (request.user_id,),
    ).fetchall()


def _duplicate_matches(grouped) -> list[dict]:
    matches = []
    for rows in grouped.values():
        if len(rows) < 2:
            continue
        ingredient = rows[0]["ingredient"]
        matches.append(
            {
                "type": "중복성분",
                "ingredient_a": ingredient,
                "ingredient_b": ingredient,
                "reason": (
                    "같은 성분이 여러 복용약에 포함되어 있습니다: "
                    + ", ".join(row["product_name"] for row in rows)
                ),
                "source": "활성 복용약 성분 비교",
            }
        )
    return matches


def _taboo_matches(
    rows,
    grouped,
    *,
    age: int | None,
    is_pregnant: bool | None,
) -> list[dict]:
    matches = []
    for row in rows:
        risk_type = _risk_type(row["taboo_type"])
        if risk_type not in HIGH_TYPES | MEDIUM_TYPES:
            continue
        ingredient_a = _normalize(row["ingredient_a"])
        ingredient_b = _normalize(row["ingredient_b"])
        if ingredient_a not in grouped:
            continue
        if risk_type == "병용금기" and (
            not ingredient_b or ingredient_b not in grouped
        ):
            continue
        if risk_type == "연령금기":
            if age is None or not _age_is_restricted(
                age,
                row["min_age"],
                row["max_age"],
            ):
                continue
        if risk_type == "임부금기" and is_pregnant is not True:
            continue
        matches.append(
            {
                "type": risk_type,
                "ingredient_a": row["ingredient_a"],
                "ingredient_b": row["ingredient_b"],
                "reason": row["description"],
                "source": row["source"] or "식약처 DUR",
                "external_id": row["external_id"],
            }
        )
    return matches


def _age_is_restricted(
    age: int,
    min_age: int | None,
    max_age: int | None,
) -> bool:
    if min_age is None and max_age is None:
        return True
    if min_age is not None and age < min_age:
        return False
    if max_age is not None and age > max_age:
        return False
    return True


def _legacy_matches(rows, grouped) -> list[dict]:
    matches = []
    for row in rows:
        if _risk_type(row["taboo_type"]) in HIGH_TYPES | MEDIUM_TYPES:
            continue
        ingredient_a = _normalize(row["ingredient_a"])
        ingredient_b = _normalize(row["ingredient_b"])
        if ingredient_a not in grouped:
            continue
        if ingredient_b and ingredient_b not in grouped:
            continue
        matches.append(
            {
                "type": _risk_type(row["taboo_type"]),
                "ingredient_a": row["ingredient_a"],
                "ingredient_b": row["ingredient_b"],
                "reason": row["description"],
                "source": row["source"] or "기존 ingredient DUR",
            }
        )
    return matches


def _deduplicate_matches(matches: list[dict]) -> list[dict]:
    result = []
    seen = set()
    for match in matches:
        key = (
            match["type"],
            _normalize(match.get("ingredient_a")),
            _normalize(match.get("ingredient_b")),
            match.get("reason"),
        )
        if key not in seen:
            seen.add(key)
            result.append(match)
    result.sort(key=lambda item: 0 if item["type"] in HIGH_TYPES else 1)
    return result


def _risk_level(matches: list[dict]) -> str:
    types = {match["type"] for match in matches}
    if types & HIGH_TYPES:
        return "HIGH"
    if types & MEDIUM_TYPES:
        return "MEDIUM"
    return "LOW"


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
        result["analyzed_ingredients"] = _json_value(
            result.get("analyzed_ingredients"),
            [],
        )
        result["matches"] = _json_value(result.get("matches_json"), [])
        result["total_matches"] = result.get("total_matches") or len(
            result["matches"]
        )
        result["representative_type"] = (
            result.get("risk_type")
            or (result["matches"][0]["type"] if result["matches"] else None)
        )
        return result
    finally:
        conn.close()


def _json_value(value: str | None, fallback):
    if not value:
        return fallback
    try:
        return json.loads(value)
    except json.JSONDecodeError:
        return fallback
