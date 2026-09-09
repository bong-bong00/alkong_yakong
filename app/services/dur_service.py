import json
import logging
import uuid
from collections import defaultdict
from datetime import date

from fastapi import HTTPException

from app.database import get_connection
from app.models.schemas import DurAnalyzeRequest
from app.services.pharmacist.ingredient import (
    ingredient_keys,
    is_usable_ingredient,
    normalize_ingredient,
    primary_ingredient_keys,
)


logger = logging.getLogger(__name__)


HIGH_TYPES = {"병용금기", "중복성분", "효능군중복"}
MEDIUM_TYPES = {"연령금기", "임부금기"}


def _normalize(value: str | None) -> str:
    return normalize_ingredient(value)


def _is_usable_ingredient(medicine) -> bool:
    return is_usable_ingredient(medicine["ingredient"], medicine["product_name"])


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
                "incomplete": True,
                "incomplete_reasons": ["살펴볼 등록 약이 아직 없어요."],
                "skipped_medicine_names": [],
                "taboo_row_count": 0,
            }

        ingredients = [
            row["ingredient"]
            for row in medicines
            if _is_usable_ingredient(row)
        ]
        dur_sync_status = "skipped"
        dur_sync_upserted = 0
        dur_sync_fetched = 0
        if ingredients:
            from app.services.dur_sync_service import refresh_dur_for_ingredients

            dur_sync = refresh_dur_for_ingredients(ingredients)
            dur_sync_status = str(dur_sync.get("status") or "failed")
            dur_sync_upserted = int(dur_sync.get("upserted") or 0)
            dur_sync_fetched = int(dur_sync.get("fetched") or 0)

        lookup_grouped = defaultdict(list)
        primary_grouped = defaultdict(list)
        for medicine in medicines:
            if not _is_usable_ingredient(medicine):
                continue
            keys = ingredient_keys(medicine["ingredient"])
            if not keys:
                continue
            for primary in primary_ingredient_keys(medicine["ingredient"]):
                primary_grouped[primary].append(medicine)
            for key in keys:
                lookup_grouped[key].append(medicine)

        age = _age_from_birth_date(user["birth_date"])
        # 요청값 우선, 없으면 회원 프로필 is_pregnant
        is_pregnant = request.is_pregnant
        if is_pregnant is None:
            try:
                is_pregnant = bool(user["is_pregnant"])
            except (KeyError, IndexError, TypeError):
                is_pregnant = None
        matches = _duplicate_matches(primary_grouped)
        taboo_rows = [
            row
            for row in cursor.execute("SELECT * FROM dur_taboo").fetchall()
            if not _is_deleted_taboo(row)
        ]
        official_matches = _taboo_matches(
            taboo_rows,
            lookup_grouped,
            age=age,
            is_pregnant=is_pregnant,
        )
        matches.extend(official_matches)
        matches.extend(
            _efficacy_duplicate_matches(taboo_rows, lookup_grouped)
        )

        # Legacy ingredient rows remain usable when no structured DUR type matched.
        if not official_matches:
            matches.extend(
                _legacy_matches(taboo_rows, lookup_grouped)
            )

        matches = _deduplicate_matches(matches)
        matches = [_without_internal_match_fields(match) for match in matches]
        risk_level = _risk_level(matches)
        by_type = _group_by_type(matches)
        has_risk = len(matches) > 0
        analysis_id = str(uuid.uuid4())
        skipped_ingredient = [
            str(row["product_name"] or row["medicine_code"])
            for row in medicines
            if not _is_usable_ingredient(row)
        ]
        checkable_n = len(medicines) - len(skipped_ingredient)
        taboo_n = len(taboo_rows)
        incomplete_reasons = []
        if checkable_n == 0:
            incomplete_reasons.append("등록 약의 성분 정보가 없어 함께먹기 검사를 할 수 없어요.")
        elif skipped_ingredient:
            incomplete_reasons.append(
                f"{len(skipped_ingredient)}개 약은 성분을 몰라 검사에서 빠졌어요."
            )
        if taboo_n == 0 and checkable_n > 0:
            if dur_sync_status == "skipped_missing_key":
                incomplete_reasons.append(
                    "식약처 함께먹기 조회 키가 없어 병용·금기 검사는 하지 못했어요."
                )
            elif dur_sync_status == "failed":
                incomplete_reasons.append(
                    "식약처 함께먹기 기준을 받아오지 못했어요. 잠시 후 다시 살펴봐 주세요."
                )
            elif dur_sync_fetched > 0 and dur_sync_upserted == 0:
                incomplete_reasons.append(
                    "식약처에서 이 약 성분에 맞는 함께먹기 기준을 찾지 못했어요."
                )
        if age is None:
            incomplete_reasons.append("생년월일이 없어 나이 관련 주의는 살펴보지 못했어요.")
        incomplete = bool(incomplete_reasons)
        if has_risk:
            description = f"함께 먹을 때 주의가 {len(matches)}건 있어요."
        elif incomplete:
            description = " ".join(incomplete_reasons)
        else:
            description = "지금 등록된 약끼리, 특별한 함께먹기 주의는 없어요."
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
            "incomplete": incomplete,
            "incomplete_reasons": incomplete_reasons,
            "skipped_medicine_names": skipped_ingredient,
            "taboo_row_count": taboo_n,
            "dur_sync_status": dur_sync_status,
        }
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


def analyze_dur_consultation(
    *,
    user_id: str,
    selected_medicine: dict,
    risk_types: set[str],
) -> dict:
    """Run an official DUR check without persisting user medication or results."""
    conn = get_connection()
    try:
        cursor = conn.cursor()
        user = cursor.execute(
            "SELECT id, birth_date, gender, is_pregnant FROM users WHERE id = ?",
            (user_id,),
        ).fetchone()
        if not user:
            raise HTTPException(status_code=404, detail="사용자가 없습니다.")

        medicine_code = str(selected_medicine.get("medicine_code") or "").strip()
        product_name = str(selected_medicine.get("product_name") or "").strip()
        ingredient = selected_medicine.get("ingredient")
        consultation_medicine = {
            "medicine_code": medicine_code,
            "product_name": product_name,
            "ingredient": ingredient,
        }
        if not medicine_code or not product_name or not _is_usable_ingredient(
            consultation_medicine
        ):
            return {
                "status": "missing",
                "items": [],
                "scope": "consultation",
                "reason": "official_medicine_unavailable",
            }

        pairwise_types = {"병용금기", "효능군중복", "중복성분"}
        medicines = []
        if risk_types & pairwise_types:
            medicines.extend(
                dict(row)
                for row in _load_medicines(
                    cursor,
                    DurAnalyzeRequest(user_id=user_id, medicine_codes=[]),
                )
            )
        medicines.append(consultation_medicine)
        medicines = list(
            {
                medicine["medicine_code"]: medicine
                for medicine in medicines
                if medicine.get("medicine_code")
            }.values()
        )

        age = _age_from_birth_date(user["birth_date"])
        if "연령금기" in risk_types and age is None:
            return {
                "status": "missing",
                "items": [],
                "scope": "consultation",
                "reason": "missing_birth_date",
            }
        try:
            pregnancy_value = user["is_pregnant"]
            if pregnancy_value is None and "임부금기" in risk_types:
                return {
                    "status": "missing",
                    "items": [],
                    "scope": "consultation",
                    "reason": "missing_pregnancy_status",
                }
            is_pregnant = bool(pregnancy_value)
        except (KeyError, IndexError, TypeError):
            if "임부금기" in risk_types:
                return {
                    "status": "missing",
                    "items": [],
                    "scope": "consultation",
                    "reason": "missing_pregnancy_status",
                }
            is_pregnant = None

        ingredients = [
            medicine["ingredient"]
            for medicine in medicines
            if _is_usable_ingredient(medicine)
        ]
        from app.services.dur_sync_service import refresh_dur_for_ingredients

        official_risk_types = risk_types & {
            "병용금기",
            "연령금기",
            "임부금기",
            "효능군중복",
        }
        sync_result = (
            refresh_dur_for_ingredients(
                ingredients,
                risk_types=official_risk_types,
                force_refresh=True,
            )
            if official_risk_types
            else {"status": "ok", "fetched": 0, "upserted": 0}
        )
        taboo_rows = [
            row
            for row in cursor.execute("SELECT * FROM dur_taboo").fetchall()
            if not _is_deleted_taboo(row)
        ]
        if official_risk_types and sync_result.get("status") != "ok":
            return {
                "status": "missing",
                "items": [],
                "scope": "consultation",
                "reason": "dur_data_unavailable",
            }

        lookup_grouped = defaultdict(list)
        primary_grouped = defaultdict(list)
        for medicine in medicines:
            if not _is_usable_ingredient(medicine):
                continue
            keys = ingredient_keys(medicine["ingredient"])
            if not keys:
                continue
            for primary in primary_ingredient_keys(medicine["ingredient"]):
                primary_grouped[primary].append(medicine)
            for key in keys:
                lookup_grouped[key].append(medicine)

        matches = _duplicate_matches(primary_grouped)
        official_matches = _taboo_matches(
            taboo_rows,
            lookup_grouped,
            age=age,
            is_pregnant=is_pregnant,
        )
        matches.extend(official_matches)
        matches.extend(_efficacy_duplicate_matches(taboo_rows, lookup_grouped))
        if not official_matches:
            matches.extend(_legacy_matches(taboo_rows, lookup_grouped))
        matches = _deduplicate_matches(matches)
        matches = [
            match
            for match in matches
            if match.get("type") in risk_types
            and _match_involves_consultation_medicine(match, consultation_medicine)
        ]
        matches = [_without_internal_match_fields(match) for match in matches]
        return {
            "status": "current",
            "items": matches,
            "scope": "consultation",
            "reason": None,
        }
    finally:
        conn.close()


def _match_involves_consultation_medicine(
    match: dict,
    medicine: dict,
) -> bool:
    medicine_code = str(medicine.get("medicine_code") or "")
    related_codes = {str(code) for code in match.get("_medicine_codes") or []}
    if related_codes:
        return medicine_code in related_codes

    product_name = str(medicine.get("product_name") or "")
    names = [
        str(name)
        for key in ("medicine_names_a", "medicine_names_b")
        for name in (match.get(key) or [])
    ]
    if product_name and product_name in names:
        return True
    consultation_keys = set(ingredient_keys(medicine.get("ingredient")))
    match_keys = set(match.get("_ingredient_keys") or [])
    if consultation_keys and match_keys:
        return bool(consultation_keys & match_keys)
    return bool(product_name and product_name in str(match.get("reason") or ""))


def _without_internal_match_fields(match: dict) -> dict:
    return {key: value for key, value in match.items() if not key.startswith("_")}


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
        names = [row["product_name"] for row in rows]
        matches.append(
            {
                "type": "중복성분",
                "ingredient_a": ingredient,
                "ingredient_b": ingredient,
                "medicine_names_a": names,
                "medicine_names_b": names,
                "_medicine_codes": sorted(codes),
                "_ingredient_keys": [key],
                "reason": (
                    f"같은 성분({ingredient})이 여러 약에 들어 있어요: {', '.join(names)}. "
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
                "_medicine_codes": [med["medicine_code"] for med in hit_meds],
                "_ingredient_keys": sorted(
                    {
                        key
                        for med in hit_meds
                        for key in ingredient_keys(med["ingredient"])
                    }
                ),
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
        products_a = [r["product_name"] for r in _grouped_rows(grouped, row["ingredient_a"])]
        products_b = [r["product_name"] for r in _grouped_rows(grouped, row["ingredient_b"])]
        medicine_codes = {
            r["medicine_code"]
            for r in (
                _grouped_rows(grouped, row["ingredient_a"])
                + _grouped_rows(grouped, row["ingredient_b"])
            )
        }
        reason = row["description"] or "함께 먹을 때 주의가 필요해요."
        if products_a:
            reason = f"{', '.join(products_a)}" + (
                f" ↔ {', '.join(products_b)}" if products_b else ""
            ) + f" — {reason}"
        matches.append(
            {
                "type": risk_type,
                "ingredient_a": row["ingredient_a"],
                "ingredient_b": row["ingredient_b"],
                "medicine_names_a": products_a,
                "medicine_names_b": products_b,
                "reason": reason,
                "source": row["source"] or "식약처 DUR",
                "external_id": row["external_id"],
                "_medicine_codes": sorted(medicine_codes),
                "_ingredient_keys": sorted(
                    set(ingredient_keys(row["ingredient_a"]))
                    | set(ingredient_keys(row["ingredient_b"]))
                ),
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
        type_name = match["type"]
        a = _normalize(match.get("ingredient_a"))
        b = _normalize(match.get("ingredient_b"))
        if type_name == "병용금기" and a and b:
            pair = tuple(sorted((a, b)))
            key = (type_name, pair)
        else:
            key = (type_name, a, b, match.get("reason"))
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
        row_id = result.get("id")
        required_invalid = (
            not isinstance(row_id, int)
            or isinstance(row_id, bool)
            or not isinstance(result.get("user_id"), str)
            or not result.get("user_id", "").strip()
            or not isinstance(result.get("risk_level"), str)
            or not result.get("risk_level", "").strip()
            or not isinstance(result.get("created_at"), str)
            or not result.get("created_at", "").strip()
        )
        if required_invalid:
            logger.warning(
                "DUR latest required_field_invalid row_id=%s created_at_null=%s",
                row_id,
                result.get("created_at") is None,
            )
            raise HTTPException(
                status_code=503,
                detail="저장된 DUR 분석 결과를 해석할 수 없습니다. DUR 분석을 다시 실행해주세요.",
            )

        ingredients, ingredients_meta = _normalized_json_list(
            result.get("analyzed_ingredients"),
            item_kind="ingredient",
        )
        matches, matches_meta = _normalized_json_list(
            result.get("matches_json"),
            item_kind="match",
        )
        total_matches_value = result.get("total_matches")
        total_matches_invalid = (
            not isinstance(total_matches_value, int)
            or isinstance(total_matches_value, bool)
            or total_matches_value < 0
        )
        malformed = (
            ingredients_meta["malformed"]
            or matches_meta["malformed"]
            or total_matches_invalid
        )

        result["analyzed_ingredients"] = ingredients
        result["matches"] = matches
        result["total_matches"] = (
            len(matches)
            if total_matches_invalid
            else (total_matches_value or len(matches))
        )
        result["total_count"] = result["total_matches"]
        result["by_type"] = _group_by_type(matches)
        result["representative_type"] = (
            result.get("risk_type")
            or (matches[0]["type"] if matches else None)
        )
        if malformed:
            reasons = []
            if ingredients_meta["malformed"]:
                reasons.append("analyzed_ingredients")
            if matches_meta["malformed"]:
                reasons.append("matches_json")
            if total_matches_invalid:
                reasons.append("total_matches")
            logger.warning(
                "DUR latest malformed row_id=%s ingredients_type=%s matches_type=%s "
                "invalid_ingredients=%s invalid_matches=%s invalid_total_matches=%s",
                row_id,
                ingredients_meta["decoded_type"],
                matches_meta["decoded_type"],
                ingredients_meta["invalid_count"],
                matches_meta["invalid_count"],
                total_matches_invalid,
            )
            result["matches_json"] = None
            result["data_status"] = "malformed"
            result["incomplete"] = True
            result["incomplete_reasons"] = reasons
            result["has_risk"] = True if matches else None
            result["message"] = (
                "저장된 DUR 분석 데이터를 완전히 해석할 수 없어 위험 여부를 "
                "확인할 수 없습니다. DUR 분석을 다시 실행해주세요."
            )
        else:
            result["has_risk"] = bool(matches)
            result["message"] = result.get("description") or (
                f"함께 먹을 때 주의가 {len(matches)}건 있어요."
                if matches
                else "지금 등록된 약끼리, 특별한 함께먹기 주의는 없어요."
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


def _normalized_json_list(value, *, item_kind: str) -> tuple[list, dict]:
    """Decode legacy JSON lists while retaining an explicit malformed signal."""
    try:
        decoded = json.loads(value) if isinstance(value, str) else value
    except (json.JSONDecodeError, TypeError):
        return [], {"malformed": True, "decoded_type": "decode_error", "invalid_count": 0}

    decoded_type = type(decoded).__name__
    if not isinstance(decoded, list):
        return [], {"malformed": True, "decoded_type": decoded_type, "invalid_count": 0}

    normalized = []
    invalid_count = 0
    for item in decoded:
        if item_kind == "ingredient":
            valid = isinstance(item, str) and bool(item.strip())
        else:
            valid = (
                isinstance(item, dict)
                and isinstance(item.get("type"), str)
                and bool(item["type"].strip())
            )
        if valid:
            normalized.append(item)
        else:
            invalid_count += 1

    return normalized, {
        "malformed": invalid_count > 0,
        "decoded_type": decoded_type,
        "invalid_count": invalid_count,
    }
