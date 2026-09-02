import json
import re
import uuid
from collections import defaultdict
from datetime import date

from fastapi import HTTPException

from app.database import get_connection
from app.models.schemas import DurAnalyzeRequest


HIGH_TYPES = {"병용금기", "중복성분", "효능군중복"}
MEDIUM_TYPES = {"연령금기", "임부금기"}


def _normalize(value: str | None) -> str:
    """DUR 매칭용: 공백·용량(mg 등)을 걷어 성분 핵심만 남긴다."""
    text = str(value or "").casefold()
    text = re.sub(
        r"\d+(?:\.\d+)?\s*(?:mg|ml|g|㎎|밀리그램|밀리그람|마이크로그램|%|정|캡슐)",
        "",
        text,
    )
    text = re.sub(r"[^0-9a-z가-힣]", "", text)
    return text


def _is_usable_ingredient(medicine) -> bool:
    """제품명을 성분란에 넣은 임시/OCR 행은 DUR 성분 매칭에서 뺀다."""
    ingredient = str(medicine["ingredient"] or "").strip()
    if not ingredient:
        return False
    product = str(medicine["product_name"] or "").strip()
    if product and _normalize(ingredient) == _normalize(product):
        return False
    return bool(_normalize(ingredient))


def _grouped_hit(grouped: dict, needle: str | None) -> bool:
    """용량 정규화 후 정확 일치만. (암로디핀⊂에스암로디핀 같은 포함 오탐 방지)"""
    key = _normalize(needle)
    if not key or len(key) < 2:
        return False
    return key in grouped


def _grouped_rows(grouped: dict, needle: str | None) -> list:
    key = _normalize(needle)
    if not key or key not in grouped:
        return []
    return list(grouped[key])


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
            "SELECT id, birth_date, gender, is_pregnant FROM users WHERE id = ?",
            (request.user_id,),
        ).fetchone()
        if not user:
            raise HTTPException(status_code=404, detail="사용자가 없습니다.")

        medicines = _load_medicines(cursor, request)
        if not medicines:
            empty_by_type = _group_by_type([])
            return {
                "risk_result_id": None,
                "analysis_id": None,
                "user_id": request.user_id,
                "risk_level": "LOW",
                "has_risk": False,
                "total_matches": 0,
                "total_count": 0,
                "representative_type": None,
                "message": "살펴볼 등록 약이 아직 없어요.",
                "by_type": empty_by_type,
                "ingredients": [],
                "medicine_names": [],
                "matches": [],
            }

        ingredients = [
            row["ingredient"]
            for row in medicines
            if _is_usable_ingredient(row)
        ]
        normalized_ingredients = defaultdict(list)
        for medicine in medicines:
            if not _is_usable_ingredient(medicine):
                continue
            key = _normalize(medicine["ingredient"])
            if not key:
                continue
            normalized_ingredients[key].append(medicine)

        age = _age_from_birth_date(user["birth_date"])
        # 요청값 우선, 없으면 회원 프로필 is_pregnant
        is_pregnant = request.is_pregnant
        if is_pregnant is None:
            try:
                is_pregnant = bool(user["is_pregnant"])
            except (KeyError, IndexError, TypeError):
                is_pregnant = None
        matches = _duplicate_matches(normalized_ingredients)
        taboo_rows = [
            row
            for row in cursor.execute("SELECT * FROM dur_taboo").fetchall()
            if not _is_deleted_taboo(row)
        ]
        official_matches = _taboo_matches(
            taboo_rows,
            normalized_ingredients,
            age=age,
            is_pregnant=is_pregnant,
        )
        matches.extend(official_matches)
        matches.extend(
            _efficacy_duplicate_matches(taboo_rows, normalized_ingredients)
        )

        # Legacy ingredient rows remain usable when no structured DUR type matched.
        if not official_matches:
            matches.extend(
                _legacy_matches(taboo_rows, normalized_ingredients)
            )

        matches = _deduplicate_matches(matches)
        risk_level = _risk_level(matches)
        by_type = _group_by_type(matches)
        has_risk = len(matches) > 0
        analysis_id = str(uuid.uuid4())
        description = (
            f"함께 먹을 때 주의가 {len(matches)}건 있어요."
            if has_risk
            else "지금 등록된 약끼리, 특별한 함께먹기 주의는 없어요."
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
            "has_risk": has_risk,
            "total_matches": len(matches),
            "total_count": len(matches),
            "representative_type": matches[0]["type"] if matches else None,
            "message": description,
            "by_type": by_type,
            "ingredients": ingredients,
            "medicine_names": [row["product_name"] for row in medicines],
            "matches": matches,
        }
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


def _load_medicines(cursor, request: DurAnalyzeRequest):
    if request.medicine_codes:
        # 요청 코드도 중복 제거 (같은 약 여러 번 넣어도 한 번만)
        codes = list(dict.fromkeys(request.medicine_codes))
        placeholders = ",".join("?" for _ in codes)
        return cursor.execute(
            f"""
            SELECT medicine_code, product_name, ingredient
            FROM medicines WHERE medicine_code IN ({placeholders})
            """,
            codes,
        ).fetchall()
    # OCR을 여러 번 하면 같은 약이 user_medicines에 중복 쌓일 수 있음.
    # 충돌 검사에서는 약 코드당 1개만 본다 (가짜 '중복성분' 방지).
    return cursor.execute(
        """
        SELECT m.medicine_code, m.product_name, m.ingredient
        FROM medicines m
        WHERE m.medicine_code IN (
            SELECT DISTINCT um.medicine_code
            FROM user_medicines um
            WHERE um.user_id = ? AND um.is_active = 1
        )
        ORDER BY m.product_name
        """,
        (request.user_id,),
    ).fetchall()


def _duplicate_matches(grouped) -> list[dict]:
    matches = []
    for key, rows in grouped.items():
        if not key or len(rows) < 2:
            continue
        # 서로 다른 약 코드가 2개 이상일 때만 (같은 약 중복 등록은 제외)
        codes = {row["medicine_code"] for row in rows}
        if len(codes) < 2:
            continue
        ingredient = rows[0]["ingredient"]
        names = ", ".join(row["product_name"] for row in rows)
        matches.append(
            {
                "type": "중복성분",
                "ingredient_a": ingredient,
                "ingredient_b": ingredient,
                "reason": (
                    f"같은 성분({ingredient})이 여러 약에 들어 있어요: {names}. "
                    "중복으로 드시는지 약국에 확인해 주세요."
                ),
                "source": "활성 복용약 성분 비교",
            }
        )
    return matches


def _is_deleted_taboo(row) -> bool:
    """식약처 DEL_YN=삭제/Y 행은 검사에서 제외."""
    raw = row["raw_json"] if "raw_json" in row.keys() else None
    if not raw:
        return False
    try:
        data = json.loads(raw) if isinstance(raw, str) else raw
    except (TypeError, json.JSONDecodeError):
        return False
    if not isinstance(data, dict):
        return False
    value = str(data.get("DEL_YN") or "").strip()
    upper = value.upper()
    return upper in {"Y", "삭제", "DELETE", "DELETED"} or value == "삭제"


def _effect_group_key(row) -> str | None:
    """효능군중복 그룹 키: ingredient_b(동기화 시 EFFECT_CODE) 또는 raw_json."""
    stored = row["ingredient_b"] if "ingredient_b" in row.keys() else None
    if stored and str(stored).strip():
        # 병용금기 ingredient_b 와 구분: 효능군만 이 함수를 씀
        return str(stored).strip()
    raw = row["raw_json"] if "raw_json" in row.keys() else None
    if not raw:
        return None
    try:
        data = json.loads(raw) if isinstance(raw, str) else raw
    except (TypeError, json.JSONDecodeError):
        return None
    if not isinstance(data, dict):
        return None
    for key in ("EFFECT_CODE", "SERS_NAME", "CLASS_NAME"):
        value = data.get(key)
        if value is not None and str(value).strip():
            return str(value).strip()
    return None


def _efficacy_duplicate_matches(rows, grouped) -> list[dict]:
    """
    효능군중복: 같은 EFFECT_CODE 에 유저 약이 2개 이상 걸릴 때만 주의.
    (성분 목록 1건만 있어도 뜨던 오탐 방지)
    """
    by_group: dict[str, list] = defaultdict(list)
    for row in rows:
        if _risk_type(row["taboo_type"]) != "효능군중복":
            continue
        group = _effect_group_key(row)
        if not group:
            continue
        by_group[group].append(row)

    matches = []
    for group, taboo_rows in by_group.items():
        hit_meds = []
        seen_codes: set[str] = set()
        for taboo in taboo_rows:
            for medicine in _grouped_rows(grouped, taboo["ingredient_a"]):
                code = medicine["medicine_code"]
                if code in seen_codes:
                    continue
                seen_codes.add(code)
                hit_meds.append(medicine)
        if len(seen_codes) < 2:
            continue
        names = ", ".join(med["product_name"] for med in hit_meds)
        ingredient_names = [
            med["ingredient"] for med in hit_meds if med["ingredient"]
        ]
        reason = (
            f"{names} — 비슷한 효과({group}) 약이 겹쳐요. "
            "약국·병원에 확인해 주세요."
        )
        matches.append(
            {
                "type": "효능군중복",
                "ingredient_a": ingredient_names[0] if ingredient_names else group,
                "ingredient_b": (
                    ingredient_names[1] if len(ingredient_names) > 1 else None
                ),
                "reason": reason,
                "source": taboo_rows[0]["source"] or "식약처 DUR",
                "external_id": taboo_rows[0]["external_id"],
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
        # 효능군중복은 _efficacy_duplicate_matches 에서 그룹 단위로 처리
        if risk_type == "효능군중복":
            continue
        if risk_type not in HIGH_TYPES | MEDIUM_TYPES:
            continue
        if not _grouped_hit(grouped, row["ingredient_a"]):
            continue
        if risk_type == "병용금기":
            if not row["ingredient_b"] or not _grouped_hit(grouped, row["ingredient_b"]):
                continue
            # 한 알(복합제) 안 성분 두 개만으로 병용 오탐 나지 않게, 서로 다른 약 필요
            rows_a = _grouped_rows(grouped, row["ingredient_a"])
            rows_b = _grouped_rows(grouped, row["ingredient_b"])
            if not any(
                a["medicine_code"] != b["medicine_code"]
                for a in rows_a
                for b in rows_b
            ):
                continue
        if risk_type == "연령금기":
            min_age, max_age = _age_bounds_for_row(row)
            if age is None or not _age_is_restricted(age, min_age, max_age):
                continue
        if risk_type == "임부금기" and is_pregnant is not True:
            continue
        # 사용자 약 이름을 이유에 붙여 화면에서 이해하기 쉽게
        products_a = ", ".join(
            r["product_name"] for r in _grouped_rows(grouped, row["ingredient_a"])
        )
        products_b = ", ".join(
            r["product_name"] for r in _grouped_rows(grouped, row["ingredient_b"])
        )
        reason = row["description"] or "함께 먹을 때 주의가 필요해요."
        if products_a:
            reason = f"{products_a}" + (
                f" ↔ {products_b}" if products_b else ""
            ) + f" — {reason}"
        matches.append(
            {
                "type": risk_type,
                "ingredient_a": row["ingredient_a"],
                "ingredient_b": row["ingredient_b"],
                "reason": reason,
                "source": row["source"] or "식약처 DUR",
                "external_id": row["external_id"],
            }
        )
    return matches


def _age_bounds_for_row(row) -> tuple[int | None, int | None]:
    """저장된 min/max 우선, 없으면 raw_json AGE_BASE 재파싱 (개월/주 포함)."""
    min_age = row["min_age"] if "min_age" in row.keys() else None
    max_age = row["max_age"] if "max_age" in row.keys() else None
    if min_age is not None or max_age is not None:
        return min_age, max_age
    raw = row["raw_json"] if "raw_json" in row.keys() else None
    if not raw:
        return None, None
    try:
        data = json.loads(raw) if isinstance(raw, str) else raw
    except (TypeError, json.JSONDecodeError):
        return None, None
    if not isinstance(data, dict):
        return None, None
    from app.services.dur_sync_service import _parse_age_base

    return _parse_age_base(data.get("AGE_BASE"))


def _age_is_restricted(
    age: int,
    min_age: int | None,
    max_age: int | None,
) -> bool:
    # 파싱 실패(둘 다 None)면 금기로 치지 않음 — 성인 전원 오탐 방지
    if min_age is None and max_age is None:
        return False
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
        if not _grouped_hit(grouped, row["ingredient_a"]):
            continue
        if row["ingredient_b"] and not _grouped_hit(grouped, row["ingredient_b"]):
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


# 화면에 고정으로 보여주는 유형 (설계 4종 + 같은성분 중복)
DISPLAY_TYPES = ("병용금기", "연령금기", "임부금기", "효능군중복", "중복성분")


def _group_by_type(matches: list[dict]) -> dict:
    """타입별 건수·목록. 표시용 5종 키는 항상 둔다."""
    grouped: dict[str, list] = {name: [] for name in DISPLAY_TYPES}
    for match in matches:
        risk_type = match.get("type") or "성분주의"
        # 효능군중복·중복성분은 화면에 각각 집계
        grouped.setdefault(risk_type, []).append(match)
    return {
        name: {"count": len(items), "items": items}
        for name, items in grouped.items()
    }


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
        matches = _json_value(result.get("matches_json"), [])
        result["matches"] = matches
        result["total_matches"] = result.get("total_matches") or len(matches)
        result["total_count"] = result["total_matches"]
        result["has_risk"] = bool(matches)
        result["by_type"] = _group_by_type(matches)
        result["message"] = result.get("description") or (
            f"함께 먹을 때 주의가 {len(matches)}건 있어요."
            if matches
            else "지금 등록된 약끼리, 특별한 함께먹기 주의는 없어요."
        )
        result["representative_type"] = (
            result.get("risk_type")
            or (matches[0]["type"] if matches else None)
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
