"""Deterministic medicine-detail preparation shared by DB and OCR medicines.

This module never calls Gemini or an external API. It turns already stored MFDS
fields into a safe OFFICIAL_ONLY profile and overlays reviewed human content when
available. External enrichment can therefore run separately without blocking a
prescription registration or a detail-screen request.
"""

from __future__ import annotations

import hashlib
import html
import json
import logging
import re
from typing import Any

from app.services.medicine_display import split_ingredients
from app.services.medicine_detail_providers import (
    clean_ingredient_explanation,
    find_reviewed_ingredient_explanations,
    is_displayable_ingredient_explanation,
)


logger = logging.getLogger(__name__)


PROFILE_STATUSES = frozenset(
    {"READY", "OFFICIAL_ONLY", "NEEDS_REVIEW", "PENDING", "FAILED", "OUTDATED"}
)
JOB_STATUSES = frozenset(
    {"PENDING", "FETCHING", "DRAFT", "READY", "FAILED", "OUTDATED"}
)
_STRENGTH = re.compile(
    r"\b\d+(?:\.\d+)?\s*(?:mg|mcg|μg|g|ml|mL|밀리그램|밀리그람|마이크로그램|밀리리터|%)\b",
    re.I,
)
_SPACE = re.compile(r"\s+")
_HTML = re.compile(r"<\s*/?\s*[A-Za-z][^>]*>")
_LEADING_MARK = re.compile(r"^(?:\d+[.)]|[가-하][.)]|[-•·※]+)\s*")
# 허가정보 "사용상의 주의사항"의 목차 제목. 내용이 아니라 칸 이름이다.
_SECTION_HEADING = re.compile(
    r"^(?:"
    r".*사용상\s*의\s*주의.*"
    # "다음 환자에는 투여하지 말 것.", "이 약을 복용하는 동안 다음의 약을
    # 복용하지 말 것." — 아래 목록을 가리키는 머리말이라 홀로 두면 빈말이다.
    r"|.*다음(?:의|과\s*같은)?\s.*것"
    # "상담 시 가능한 한 이 첨부문서를 소지할 것." — 종이 설명서 안내다.
    r"|.*첨부\s*문서.*"
    r"|.*에\s*(?:대한|의)\s*(?:투여|영향)"
    r"|과량\s*투여\s*시?의?\s*처치"
    r"|(?:적용|저장|보관(?:\s*및\s*취급)?)\s*상의?\s*주의(?:사항)?"
    r"|일반적\s*주의|이상\s*반응|상호\s*작용"
    r"|기타(?:\s.*(?:주의(?:사항)?|주의할\s*사항))?"
    # "적용상의 주의(주사제에 한함.)"처럼 뒤에 붙는 단서와, "…말 것 2."처럼
    # 다음 항 번호가 끌려 붙은 것까지 목차다.
    r")(?:\s*\([^)]*\))?\.?(?:\s*\d+[.)]?)?$"
)
# 내용 앞에 붙어 온 목차 이름. 뒤에 내용이 이어질 때만 뗀다.
_HEADING_PREFIX = re.compile(
    r"^(?:기타|[가-힣 ]{1,20}에\s*대한\s*투여(?:\s*\([^)]*\))?)\s*[:：]?\s+(?=\S)"
)
# 목차 밑에 늘어선 "○○ 환자" 같은 조각. 목차("투여하지 말 것" 등)를 떼고
# 홀로 두면 먹으면 안 된다는 건지 조심하라는 건지 알 수 없다.
_PATIENT_GROUP = re.compile(
    r"(?:(?:환자|영아|유아|소아|고령자|임부|수유부|사람)(?:\s*\([^)]*\))?|\s등)$"
)
PARSER_VERSION = "3.0"
_BOILERPLATE_PURPOSES = (
    "다음 질환에도 사용할 수 있다",
    "다음 질환에 사용할 수 있다",
    "다음의 질환 및 증상",
    "주효능 효과",
    "효능 효과",
)
# (찾는 말, 쓰임 한 마디, 설명 한 문장, 파랗게 짚을 낱말)
_PURPOSE_GROUPS: tuple[tuple[re.Pattern[str], str, str, str], ...] = (
    (
        re.compile(r"발열|해열|감기.*(?:열|통증)"),
        "열·감기 통증",
        "열을 내리고 감기로 인한 통증을 줄이는 데 사용해요.",
        "열·감기 통증",
    ),
    (
        re.compile(r"두통|치통|월경곤란|생리통|요통|근육통|신경통|수술\s*후\s*통증"),
        "여러 통증",
        "두통·치통·생리통 등 여러 통증을 줄이는 데 사용해요.",
        "통증",
    ),
    (
        re.compile(r"관절염|류마티|통풍|염좌|좌상|건염|건초염|활액낭염|소염"),
        "관절·근육의 염증과 통증",
        "관절이나 근육의 염증과 통증을 줄이는 데 사용해요.",
        "염증과 통증",
    ),
    (
        re.compile(r"피부염|습진|건선|피부\s*질환"),
        "피부 염증·습진",
        "습진이나 피부염 같은 피부 염증을 가라앉히는 데 사용해요.",
        "피부 염증",
    ),
    (
        re.compile(r"가려움|두드러기|알레르기|알러지"),
        "알레르기로 인한 가려움",
        "알레르기로 인한 가려움 같은 증상을 줄이는 데 사용해요.",
        "가려움",
    ),
    (
        # "우울증에 수반하는 불안"은 불안에 쓰는 약이다.
        re.compile(r"우울(?!증?에\s*수반)"),
        "우울한 기분",
        "우울한 기분을 나아지게 하는 데 사용해요.",
        "우울",
    ),
    (
        # "불안정형 협심증"의 "불안", "월경전긴장증"의 "긴장"은 불안 증상이
        # 아니다.
        re.compile(r"불안(?!정)|긴장(?!증)|초조|신경증"),
        "불안·긴장",
        "불안하거나 긴장된 증상을 완화할 목적으로 사용될 수 있어요.",
        "불안·긴장",
    ),
    (
        re.compile(r"위산|속쓰림|역류|위궤양|십이지장궤양"),
        "속쓰림·위 불편감",
        "위산과 관련된 속쓰림이나 위 불편감을 줄이는 데 사용해요.",
        "속쓰림",
    ),
    (
        # "심부전이 없거나"는 심부전에 쓰는 말이 아니다.
        re.compile(r"심부전(?!이?\s*없)"),
        "약해진 심장(심부전)",
        "심장이 피를 내보내는 힘이 약해졌을 때 심장을 돕는 데 사용해요.",
        "심부전",
    ),
    (
        re.compile(r"부정맥|심실세동|심방세동|빈맥"),
        "빠르거나 불규칙한 심장 박동",
        "불규칙하거나 지나치게 빠른 심장 박동을 조절하는 데 사용해요.",
        "심장 박동",
    ),
    (
        re.compile(r"고혈압|혈압"),
        "높은 혈압",
        "높은 혈압을 조절하는 데 사용해요.",
        "혈압",
    ),
    (
        re.compile(r"당뇨|혈당"),
        "높은 혈당",
        "혈당을 조절하는 데 사용해요.",
        "혈당",
    ),
    (
        re.compile(r"혈전|항혈소판|색전|재경색|심근경색|뇌졸중|혈소판응집"),
        "혈전 예방",
        "혈관을 막는 혈전이 생기지 않게 하는 데 사용해요.",
        "혈전",
    ),
    (
        re.compile(r"고지혈|이상지질|콜레스테롤|중성지방|LDL"),
        "높은 콜레스테롤",
        "콜레스테롤과 중성지방 수치를 낮추는 데 사용해요.",
        "콜레스테롤",
    ),
    (
        re.compile(r"갑상선|갑상샘"),
        "갑상선 호르몬 조절",
        "갑상선 호르몬이 모자라거나 넘칠 때 조절하는 데 사용해요.",
        "갑상선",
    ),
    (
        re.compile(r"세균|감염|항생|폐렴|요로감염|중이염|인두염|방광염"),
        "세균 감염 치료",
        "세균으로 생긴 감염을 치료하는 데 사용해요.",
        "세균 감염",
    ),
    (
        re.compile(r"천식|만성폐쇄성|COPD|기관지확장|호흡곤란"),
        "숨찬 증상",
        "기관지를 넓혀 숨쉬기 편하게 하는 데 사용해요.",
        "숨찬",
    ),
    (
        re.compile(r"전립선|배뇨장애|빈뇨|야간뇨|잔뇨"),
        "전립선으로 인한 소변 불편",
        "전립선이 커져 생기는 소변 불편을 줄이는 데 사용해요.",
        "전립선",
    ),
    (
        re.compile(r"골다공|골밀도|골절\s*예방"),
        "약해진 뼈(골다공증)",
        "뼈가 약해지는 것을 늦추는 데 사용해요.",
        "골다공증",
    ),
    (
        re.compile(r"소화불량|위장관\s*운동|구역|구토|복부팽만|메스꺼"),
        "소화 불편",
        "소화가 안 되거나 속이 메스꺼울 때 쓰는 약이에요.",
        "소화",
    ),
    (
        re.compile(r"치매|알츠하이머|기억력\s*저하"),
        "기억력 저하(치매)",
        "기억력과 생각하는 힘이 떨어지는 것을 늦추는 데 사용해요.",
        "기억력",
    ),
    (
        re.compile(r"비타민|자양강장|영양\s*보급"),
        "비타민 보충",
        "모자란 비타민을 채워 피로를 푸는 데 사용해요.",
        "비타민",
    ),
    (
        re.compile(r"변비"),
        "변비",
        "변비로 굳은 변을 무르게 해 배변을 돕는 데 사용해요.",
        "변비",
    ),
    (
        re.compile(r"불면|수면장애|입면"),
        "잠들기 어려움",
        "잠들기 어렵거나 자주 깨실 때 쓰는 약이에요.",
        "잠들기",
    ),
)
# 쓰임을 찾을 때 걷어낼 부분. 괄호 속은 대개 "고위험군 환자(고혈압, 당뇨
# 등)"처럼 누구에게 쓰는지를 덧붙인 말이라, 거기 든 병 이름을 쓰임으로 읽으면
# 아스피린이 혈압·혈당 약이 된다. 닫는 괄호가 잘려 나간 원문도 있어 줄 끝까지
# 걷는다.
_PURPOSE_ASIDE = re.compile(r"[(\[（][^)\]）]*(?:[)\]）]|$)")
# "울혈성심부전 : 판막질환, 고혈압 … 에 의한 것."처럼 콜론 뒤에 원인을
# 늘어놓은 말. 원인으로 적힌 병은 이 약의 쓰임이 아니다.
_PURPOSE_CAUSE = re.compile(r"[:：][^\n:：]*에\s*의한\s*것\.?")


def _purpose_search_text(items: list[str]) -> str:
    """Text to match purpose keywords against, without asides or causes.

    "기타 …"로 시작하는 줄은 덧붙인 쓰임이라 대표 쓰임을 고를 때 읽지 않는다.
    긴 줄은 첫 문장까지만 읽는다. 뒤따르는 설명문은 증상을 늘어놓는 일이
    많아(“유방통증, 두통, 관절통…”) 우울증 약이 통증 약으로 읽힌다.
    """
    lines = []
    for item in items:
        for line in str(item or "").splitlines():
            line = line.strip()
            if not line or line.startswith("기타"):
                continue
            if len(line) > 120:
                line = re.split(r"(?<=다)\.\s", line, maxsplit=1)[0]
            line = _PURPOSE_CAUSE.sub(" ", line)
            lines.append(_PURPOSE_ASIDE.sub(" ", line))
    return " ".join(lines)


def _matched_purpose_groups(
    text: str,
) -> list[tuple[re.Pattern[str], str, str, str]]:
    """Purpose groups found in [text], in the order the text mentions them.

    목록 순서대로 고르면 원문 맨 끝에 덧붙은 쓰임이 앞에 온 주된 쓰임을
    밀어낸다. 원문에 먼저 나온 쓰임이 대개 그 약의 주된 쓰임이다.
    """
    found = []
    for index, group in enumerate(_PURPOSE_GROUPS):
        match = group[0].search(text)
        if match:
            found.append((match.start(), index, group))
    return [group for _, _, group in sorted(found)]


def normalize_ingredient_key(value: str | None) -> str:
    """Make a stable reuse key without changing the official display value."""
    text = _HTML.sub(" ", str(value or ""))
    text = _STRENGTH.sub(" ", text)
    text = re.sub(r"\([^)]*(?:함량|역가)[^)]*\)", " ", text)
    text = _SPACE.sub(" ", text).strip(" ,;|/·").casefold()
    return text


def _topic_particle(value: str) -> str:
    last = str(value or "").strip()[-1:]
    if last and "가" <= last <= "힣":
        return "은" if (ord(last) - ord("가")) % 28 else "는"
    return "은"


def ingredient_entries(raw: str | None) -> list[dict[str, str]]:
    entries: list[dict[str, str]] = []
    seen: set[str] = set()
    for name in split_ingredients(raw):
        key = normalize_ingredient_key(name)
        if not key or key in seen:
            continue
        seen.add(key)
        entries.append({"key": key, "name": name.strip()})
    return entries


def _profile_quality(profile: dict[str, Any] | None) -> int:
    if not profile:
        return -1
    score = 0
    if clean_ingredient_explanation(profile.get("ingredient_explanation")):
        score += 6
    if str(profile.get("approved_use_summary") or "").strip():
        score += 4
    score += min(len(_load_list(profile.get("approved_uses"))), 3)
    score += min(len(_load_list(profile.get("all_approved_uses"))), 5)
    if str(profile.get("official_usage") or "").strip():
        score += 2
    if bool(profile.get("source_verified")):
        score += 1
    if str(profile.get("review_status") or "").upper() == "REVIEWED":
        score += 4
    score -= len(_load_list(profile.get("quality_flags")))
    return score


def _merge_profile_content(
    existing: dict[str, Any] | None,
    candidate: dict[str, Any],
) -> dict[str, Any]:
    """Keep non-empty/reviewed detail fields while accepting richer updates."""
    merged = dict(candidate)
    merged["ingredient_explanation"] = clean_ingredient_explanation(
        merged.get("ingredient_explanation")
    )
    if not existing:
        return merged

    string_fields = (
        "ingredient_explanation",
        "approved_use_summary",
        "official_usage",
        "source_name",
        "source_url",
        "generated_by",
    )
    list_fields = (
        "ingredient_keys",
        "approved_uses",
        "all_approved_uses",
        "key_cautions",
        "possible_side_effects",
        "ask_doctor_when",
    )
    for field in string_fields:
        if not str(merged.get(field) or "").strip():
            merged[field] = existing.get(field) or ""
    for field in list_fields:
        if not _load_list(merged.get(field)):
            merged[field] = _load_list(existing.get(field))

    old_reviewed = str(existing.get("review_status") or "").upper() == "REVIEWED"
    new_reviewed = str(merged.get("review_status") or "").upper() == "REVIEWED"
    if old_reviewed and not new_reviewed:
        for field in (
            "ingredient_explanation",
            "approved_use_summary",
            "approved_uses",
            "all_approved_uses",
        ):
            old_value = existing.get(field)
            if old_value:
                merged[field] = old_value
        merged["review_status"] = "REVIEWED"
        merged["status"] = "READY"
        merged["generated_by"] = existing.get("generated_by") or merged.get(
            "generated_by"
        )

    flags = _load_list(merged.get("quality_flags"))
    if str(merged.get("ingredient_explanation") or "").strip():
        flags = [item for item in flags if item != "missing_reviewed_ingredient_explanation"]
    if (
        str(merged.get("approved_use_summary") or "").strip()
        or _load_list(merged.get("approved_uses"))
        or _load_list(merged.get("all_approved_uses"))
    ):
        flags = [item for item in flags if item != "missing_purpose"]
    merged["quality_flags"] = flags
    if str(merged.get("status") or "").upper() in {"PENDING", "FAILED"} and (
        str(merged.get("ingredient_explanation") or "").strip()
        or str(merged.get("approved_use_summary") or "").strip()
        or _load_list(merged.get("all_approved_uses"))
    ):
        merged["status"] = "READY" if merged.get("review_status") == "REVIEWED" else "OFFICIAL_ONLY"
    merged["source_verified"] = bool(
        merged.get("source_verified") or existing.get("source_verified")
    )
    return merged


def enqueue_medicine_detail(cursor, medicine_code: str) -> None:
    """Idempotently enqueue one official medicine for local/background preparation."""
    code = str(medicine_code or "").strip()
    if not code or code.upper().startswith("OCR-"):
        return
    cursor.execute(
        """
        INSERT INTO medicine_detail_jobs (medicine_code, status)
        VALUES (?, 'PENDING')
        ON CONFLICT(medicine_code) DO UPDATE SET
            status = CASE
                WHEN medicine_detail_jobs.status IN ('FETCHING', 'DRAFT')
                THEN medicine_detail_jobs.status
                ELSE 'PENDING'
            END,
            requested_at = CURRENT_TIMESTAMP,
            updated_at = CURRENT_TIMESTAMP,
            last_error = NULL
        """,
        (code,),
    )


def ensure_medicine_detail(cursor, medicine_code: str) -> dict[str, Any] | None:
    """Prepare one profile using local official data and reviewed content only."""
    code = str(medicine_code or "").strip()
    medicine_row = cursor.execute(
        "SELECT * FROM medicines WHERE medicine_code = ? AND medicine_code NOT LIKE 'OCR-%'",
        (code,),
    ).fetchone()
    if not medicine_row:
        return None
    medicine = dict(medicine_row)
    medicine = _hydrate_from_local_permission(cursor, medicine)
    enqueue_medicine_detail(cursor, code)
    cursor.execute(
        """
        UPDATE medicine_detail_jobs
        SET status='FETCHING', attempts=attempts+1, started_at=CURRENT_TIMESTAMP,
            updated_at=CURRENT_TIMESTAMP
        WHERE medicine_code=?
        """,
        (code,),
    )

    try:
        existing_profile = get_medicine_detail_profile(cursor, code)
        if not existing_profile or existing_profile.get("source_hash") != official_source_hash(medicine):
            # Keep the old snapshot stored, but never merge its reviewed copy
            # into a different official product snapshot.
            cursor.execute("UPDATE ai_explanation_cards SET review_status='OUTDATED' WHERE medicine_code=? AND review_status='REVIEWED'", (code,))
            cursor.execute("UPDATE medicines SET explanation_review_status='UNREVIEWED' WHERE medicine_code=?", (code,))
            existing_profile = None
        profile = _build_profile(cursor, medicine)
        candidate_quality = _profile_quality(profile)
        existing_quality = _profile_quality(existing_profile)
        # OUTDATED 프로필은 과거 원문 기준이므로 품질 점수가 더 높아도
        # 보존하지 않는다. 현재 공식 정보와 현재 성분 설명으로 다시 만든다.
        if (
            existing_profile
            and str(existing_profile.get("status") or "").upper() != "OUTDATED"
            and candidate_quality < existing_quality
        ):
            logger.info(
                "MEDICINE_DETAIL_PRESERVED code=%s existing_quality=%s candidate_quality=%s",
                code,
                existing_quality,
                candidate_quality,
            )
            cursor.execute(
                """
                UPDATE medicine_detail_jobs
                SET status='READY', last_error=NULL, finished_at=CURRENT_TIMESTAMP,
                    updated_at=CURRENT_TIMESTAMP
                WHERE medicine_code=?
                """,
                (code,),
            )
            return existing_profile
        merged_profile = _merge_profile_content(existing_profile, profile)
        changed_fields = [
            field
            for field in (
                "status",
                "ingredient_keys",
                "ingredient_explanation",
                "approved_use_summary",
                "approved_uses",
                "all_approved_uses",
                "official_usage",
                "key_cautions",
                "ask_doctor_when",
                "review_status",
                "quality_flags",
            )
            if (existing_profile or {}).get(field) != merged_profile.get(field)
        ]
        profile = merged_profile
        logger.info(
            "MEDICINE_DETAIL_MERGED code=%s existing_quality=%s candidate_quality=%s "
            "final_quality=%s changed_fields=%s",
            code,
            existing_quality,
            candidate_quality,
            _profile_quality(profile),
            ",".join(changed_fields) or "none",
        )
        existing = cursor.execute(
            "SELECT source_hash, content_version FROM medicine_detail_profiles WHERE medicine_code=?",
            (code,),
        ).fetchone()
        if (
            existing
            and str(existing["source_hash"] or "")
            and existing["source_hash"] != profile["source_hash"]
        ):
            cursor.execute(
                "UPDATE medicine_detail_profiles SET status='OUTDATED', updated_at=CURRENT_TIMESTAMP WHERE medicine_code=?",
                (code,),
            )
            cursor.execute(
                "UPDATE medicine_detail_jobs SET status='OUTDATED', updated_at=CURRENT_TIMESTAMP WHERE medicine_code=?",
                (code,),
            )
        if existing and existing["source_hash"] == profile["source_hash"]:
            version = int(existing["content_version"] or 1)
        else:
            version = int(existing["content_version"] or 0) + 1 if existing else 1

        cursor.execute(
            """
            INSERT INTO medicine_detail_profiles (
                medicine_code, status, ingredient_keys, ingredient_explanation,
                approved_use_summary, approved_uses, all_approved_uses, official_usage,
                key_cautions, possible_side_effects, ask_doctor_when,
                source_name, source_url, source_verified, review_status,
                generated_by, source_hash, quality_flags, parser_version,
                content_version, prepared_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
            ON CONFLICT(medicine_code) DO UPDATE SET
                status=excluded.status,
                ingredient_keys=excluded.ingredient_keys,
                ingredient_explanation=excluded.ingredient_explanation,
                approved_use_summary=excluded.approved_use_summary,
                approved_uses=excluded.approved_uses,
                all_approved_uses=excluded.all_approved_uses,
                official_usage=excluded.official_usage,
                key_cautions=excluded.key_cautions,
                possible_side_effects=excluded.possible_side_effects,
                ask_doctor_when=excluded.ask_doctor_when,
                source_name=excluded.source_name,
                source_url=excluded.source_url,
                source_verified=excluded.source_verified,
                review_status=excluded.review_status,
                generated_by=excluded.generated_by,
                source_hash=excluded.source_hash,
                quality_flags=excluded.quality_flags,
                parser_version=excluded.parser_version,
                content_version=excluded.content_version,
                prepared_at=CURRENT_TIMESTAMP,
                updated_at=CURRENT_TIMESTAMP
            """,
            (
                code,
                profile["status"],
                _dump(profile["ingredient_keys"]),
                profile["ingredient_explanation"],
                profile["approved_use_summary"],
                _dump(profile["approved_uses"]),
                _dump(profile["all_approved_uses"]),
                profile["official_usage"],
                _dump(profile["key_cautions"]),
                _dump(profile["possible_side_effects"]),
                _dump(profile["ask_doctor_when"]),
                profile["source_name"],
                profile["source_url"],
                int(profile["source_verified"]),
                profile["review_status"],
                profile["generated_by"],
                profile["source_hash"],
                _dump(profile["quality_flags"]),
                PARSER_VERSION,
                version,
            ),
        )
        cursor.execute(
            """
            UPDATE medicine_detail_jobs
            SET status=?, source_hash=?, last_error=NULL,
                finished_at=CURRENT_TIMESTAMP, updated_at=CURRENT_TIMESTAMP
            WHERE medicine_code=?
            """,
            (
                "READY"
                if profile["status"] in {"READY", "OFFICIAL_ONLY", "NEEDS_REVIEW"}
                else "PENDING",
                profile["source_hash"],
                code,
            ),
        )
        return get_medicine_detail_profile(cursor, code)
    except Exception as error:
        cursor.execute(
            """
            UPDATE medicine_detail_jobs
            SET status='FAILED', last_error=?, finished_at=CURRENT_TIMESTAMP,
                updated_at=CURRENT_TIMESTAMP
            WHERE medicine_code=?
            """,
            (str(error)[:500], code),
        )
        raise


def prepare_all_medicine_details(cursor) -> dict[str, int]:
    """Backfill every real app medicine without network access."""
    codes = [
        str(row[0])
        for row in cursor.execute(
            """
            SELECT medicine_code FROM medicines
            WHERE medicine_code NOT LIKE 'OCR-%'
            ORDER BY CASE WHEN medicine_code IN (
                SELECT DISTINCT medicine_code FROM user_medicines WHERE is_active=1
            ) THEN 0 ELSE 1 END, medicine_code
            """
        ).fetchall()
    ]
    result = {
        "total": len(codes),
        "ready": 0,
        "official_only": 0,
        "needs_review": 0,
        "pending": 0,
        "failed": 0,
    }
    for code in codes:
        try:
            profile = ensure_medicine_detail(cursor, code)
            status = str((profile or {}).get("status") or "PENDING").lower()
            result[status if status in result else "pending"] += 1
        except Exception:
            result["failed"] += 1
    return result


def get_medicine_detail_profile(cursor, medicine_code: str) -> dict[str, Any] | None:
    row = cursor.execute(
        "SELECT * FROM medicine_detail_profiles WHERE medicine_code=?",
        (medicine_code,),
    ).fetchone()
    if not row:
        return None
    profile = dict(row)
    for key in (
        "ingredient_keys",
        "approved_uses",
        "all_approved_uses",
        "key_cautions",
        "possible_side_effects",
        "ask_doctor_when",
        "quality_flags",
    ):
        profile[key] = _load_list(profile.get(key))
    return profile


def _build_profile(cursor, medicine: dict[str, Any]) -> dict[str, Any]:
    code = str(medicine["medicine_code"])
    ingredients = ingredient_entries(medicine.get("ingredient"))
    reviewed_card_row = cursor.execute(
        """
        SELECT * FROM ai_explanation_cards
        WHERE medicine_code=? AND review_status='REVIEWED'
        ORDER BY content_version DESC, reviewed_at DESC, id DESC LIMIT 1
        """,
        (code,),
    ).fetchone()
    card = dict(reviewed_card_row) if reviewed_card_row else None

    ingredient_explanation = ""
    reviewed_by_key = find_reviewed_ingredient_explanations(cursor, ingredients)
    ingredient_provider_names: set[str] = set()
    for ingredient in ingredients:
        row = reviewed_by_key.get(ingredient["key"])
        if row:
            ingredient_provider_names.add(str(row.get("provider") or ""))
    if ingredients and len(reviewed_by_key) == len(ingredients):
        ingredient_explanation = _compose_reviewed_ingredient_explanation(
            ingredients,
            reviewed_by_key,
        )

    if card and ingredients and is_displayable_ingredient_explanation(card.get("ingredient_explanation")):
        ingredient_explanation = clean_ingredient_explanation(card["ingredient_explanation"])

    quality_flags: list[str] = []
    if card:
        all_approved_uses = _deduplicate_items(_load_list(card.get("approved_uses")))
        approved_uses = all_approved_uses[:3]
        approved_summary = str(card.get("approved_use_summary") or "").strip()
        approved_uses = _without_summary_duplicate(approved_uses, approved_summary)
    else:
        parsed_purposes = _parse_official_purposes(medicine.get("efficacy"))
        approved_uses = parsed_purposes["representative"]
        all_approved_uses = parsed_purposes["all"]
        quality_flags.extend(parsed_purposes["flags"])
        approved_summary = (
            "공식 허가정보에서 확인한 대표 사용 목적이에요."
            if len(approved_uses) > 1
            else (approved_uses[0] if approved_uses else "")
        )
        if len(approved_uses) == 1:
            approved_uses = []

    purpose_for_ingredient = approved_summary
    if purpose_for_ingredient == "공식 허가정보에서 확인한 대표 사용 목적이에요.":
        purpose_for_ingredient = next(
            iter(approved_uses or all_approved_uses),
            "",
        )
    # 쓰임이 다듬은 문장("~요.")일 때만 이어 붙인다. 허가 원문 조각("주요
    # 우울증", "변비 - 만성변비 …")을 붙이면 "…주성분이에요. 주요 우울증"처럼
    # 말이 끊긴 채로 화면에 나간다. 그럴 바엔 비워 두고 검토를 기다린다.
    if (
        len(ingredients) == 1
        and not ingredient_explanation
        and purpose_for_ingredient.rstrip().endswith("요.")
    ):
        ingredient_name = ingredients[0]["name"]
        ingredient_explanation = clean_ingredient_explanation(
            f"{ingredient_name}{_topic_particle(ingredient_name)} 이 약의 주성분이에요. "
            f"{purpose_for_ingredient}"
        )

    if ingredients and not ingredient_explanation:
        quality_flags.append("missing_reviewed_ingredient_explanation")

    key_cautions = _load_list(card.get("cautions")) if card else []
    if not key_cautions:
        key_cautions = _official_items(medicine.get("precautions"), limit=3)
    side_effects = _load_list(card.get("side_effects")) if card else []
    side_effects = [item for item in side_effects if _complete_user_text(item)][:4]
    ask_doctor_when = _load_list(card.get("ask_doctor_when")) if card else []
    if not ask_doctor_when and key_cautions:
        # 바르는 약·붙이는 약에도 붙는 말이라 "복용"이라 하지 않는다.
        ask_doctor_when = ["약을 쓰는 동안 불편한 증상이 생기거나 사용 방법이 걱정될 때 의사나 약사에게 알려주세요."]

    has_official = any(
        str(medicine.get(key) or "").strip()
        for key in ("efficacy", "usage", "precautions", "ingredient")
    )
    fully_reviewed = bool(card)
    if fully_reviewed:
        status = "READY"
    elif quality_flags:
        status = "NEEDS_REVIEW"
    else:
        status = "OFFICIAL_ONLY" if has_official else "PENDING"
    review_status = "REVIEWED" if fully_reviewed else "UNREVIEWED"
    return {
        "status": status,
        "ingredient_keys": [item["key"] for item in ingredients],
        "ingredient_explanation": ingredient_explanation,
        "approved_use_summary": approved_summary,
        "approved_uses": approved_uses,
        "all_approved_uses": all_approved_uses,
        "official_usage": str((card or {}).get("how_to_take") or medicine.get("usage") or "").strip(),
        "key_cautions": key_cautions,
        "possible_side_effects": side_effects,
        "ask_doctor_when": ask_doctor_when,
        "source_name": str(
            (card or {}).get("source")
            or (
                "식약처 의약품 허가정보 · 검토된 성분 설명 사전"
                if ingredient_provider_names
                else "식약처 의약품 허가정보"
            )
        ),
        "source_url": str((card or {}).get("source_url") or "https://nedrug.mfds.go.kr"),
        "source_verified": has_official or bool(card),
        "review_status": review_status,
        "generated_by": str(
            (card or {}).get("content_generated_by")
            or ("ingredient-provider" if ingredient_provider_names else "official-parser")
        ),
        "quality_flags": quality_flags,
        "source_hash": official_source_hash(medicine),
    }


def _hydrate_from_local_permission(cursor, medicine: dict[str, Any]) -> dict[str, Any]:
    """Fill missing official fields from the local MFDS mirror only."""
    try:
        from app.services.mfds_drug_permission.db import (
            find_permission_product_by_item_seq,
            product_to_medicine,
        )

        row = find_permission_product_by_item_seq(str(medicine.get("medicine_code") or ""))
        official = product_to_medicine(row) if row else {}
    except Exception:
        official = {}
    if not official or str(official.get("medicine_code") or "") != str(medicine.get("medicine_code") or ""):
        return medicine

    merged = dict(medicine)
    field_map = {
        "ingredient": "ingredient",
        "manufacturer": "manufacturer",
        "efficacy": "efficacy",
        "usage": "usage",
        "precautions": "precautions",
        "image_url": "image_url",
    }
    updates: dict[str, str] = {}
    for target, source in field_map.items():
        current = str(merged.get(target) or "").strip()
        incoming = str(official.get(source) or "").strip()
        if not current and incoming:
            merged[target] = incoming
            updates[target] = incoming
    if updates:
        assignments = ", ".join(f"{name}=?" for name in updates)
        cursor.execute(
            f"UPDATE medicines SET {assignments}, updated_at=CURRENT_TIMESTAMP WHERE medicine_code=?",
            (*updates.values(), medicine["medicine_code"]),
        )
    return merged


def _store_reviewed_ingredient(
    cursor,
    ingredient: dict[str, str],
    explanation: str,
    *,
    source: str,
    generated_by: str,
) -> None:
    explanation = clean_ingredient_explanation(explanation)
    if not is_displayable_ingredient_explanation(explanation):
        return
    cursor.execute(
        """
        INSERT INTO ingredient_explanations (
            normalized_key, ingredient_name, explanation, review_status,
            source, source_verified, generated_by, reviewed_at
        ) VALUES (?, ?, ?, 'REVIEWED', ?, 1, ?, CURRENT_TIMESTAMP)
        ON CONFLICT(normalized_key) DO UPDATE SET
            ingredient_name=excluded.ingredient_name,
            explanation=CASE
                WHEN ingredient_explanations.review_status='REVIEWED'
                THEN ingredient_explanations.explanation
                ELSE excluded.explanation
            END,
            review_status='REVIEWED', source_verified=1,
            updated_at=CURRENT_TIMESTAMP,
            reviewed_at=COALESCE(ingredient_explanations.reviewed_at, CURRENT_TIMESTAMP)
        """,
        (
            ingredient["key"],
            ingredient["name"],
            explanation,
            source,
            generated_by,
        ),
    )


def _official_items(value: Any, *, limit: int) -> list[str]:
    # 허가 원문에는 "&nbsp;" 같은 HTML 기호가 그대로 들어 있기도 하다.
    text = html.unescape(_HTML.sub(" ", str(value or ""))).replace("\xa0", " ")
    text = text.replace("\r", "\n")
    candidates = re.split(r"(?:\n+|(?<=[.!?다요])\s+|\s+[※•])", text)
    result: list[str] = []
    for candidate in candidates:
        item = _LEADING_MARK.sub("", _SPACE.sub(" ", candidate)).strip(" -•·")
        # "기타 이 약은 …", "고령자에 대한 투여(캡슐제에 한함.) 고령자에게는 …"
        # 처럼 목차 이름이 내용 앞에 붙어 온 것은 이름만 뗀다.
        item = _HEADING_PREFIX.sub("", item)
        if not _complete_user_text(item) or len(item) > 240 or item in result:
            continue
        if _SECTION_HEADING.match(item) or _PATIENT_GROUP.search(item):
            continue
        # "다음 의약품의 작용이 …"은 아래 목록을 가리키는 말이라 홀로 서지 못한다.
        if item.startswith("다음"):
            continue
        # 끝맺지 않은 조각("…투여 시보다", "피부염, 상처부위")은 줄바꿈에서
        # 잘린 문장이거나 목록의 한 칸이라 홀로 두면 뜻이 서지 않는다.
        # "보다"는 "다"로 끝나도 비교하는 말이라 문장이 끝난 게 아니다.
        if not re.search(r"[.!?다요]\)?$", item) or re.search(
            r"(?:보다|처럼|만큼)$", item
        ):
            continue
        result.append(item)
        if len(result) >= limit:
            break
    return result


def _parse_official_purposes(value: Any) -> dict[str, list[str]]:
    """Separate concise representative purposes from the preserved official list."""
    raw = _HTML.sub(" ", str(value or "")).replace("\r", "\n")
    cleaned = re.sub(r"[ \t\f\v]+", " ", raw).strip()
    if not cleaned:
        return {"representative": [], "all": [], "flags": ["missing_purpose"]}

    for phrase in _BOILERPLATE_PURPOSES:
        cleaned = re.sub(
            rf"(?:^|\n|[.!?]\s*){re.escape(phrase)}\s*[.:：]?",
            "\n",
            cleaned,
            flags=re.I,
        )

    chunks: list[str] = []
    # 글머리표(●○■)가 줄바꿈 없이 한 줄에 이어 붙은 원문도 있다.
    for block in re.split(r"\n+|[;；]|\s*[●○■]\s*", cleaned):
        for item in _split_top_level_commas(block):
            text = _clean_purpose_item(item)
            if text:
                chunks.append(text)
    all_items = _deduplicate_items(chunks)
    flags: list[str] = []
    if not all_items:
        flags.append("unparsed_purpose")
    if any(len(item) > 160 for item in all_items):
        flags.append("long_purpose_item")
    if len(all_items) == 1 and len(all_items[0]) > 120:
        flags.append("unparsed_long_text")

    representative: list[str] = []
    for _pattern, _title, sentence, _highlight in _matched_purpose_groups(
        _purpose_search_text([cleaned])
    ):
        if sentence not in representative:
            representative.append(sentence)
        if len(representative) == 3:
            break

    if not representative:
        representative = [
            item
            for item in all_items
            if len(item) <= 80 and not _looks_like_heading(item)
        ][:3]
    if not representative and all_items:
        flags.append("no_representative_purpose")
    return {
        "representative": representative[:3],
        "all": all_items,
        "flags": list(dict.fromkeys(flags)),
    }


_PERSON_TAIL = re.compile(
    r"(?:\s*(?:환자|분|사람|성인|소아))\s*$"
)


def use_phrase(value: str) -> str:
    """Say what the medicine is for, not who takes it.

    허가 문구는 "혈전이 생기기 쉬운 분"처럼 사람을 가리키는 말로 끝나는 일이
    많다. "쓰임" 줄에 그대로 올리면 약이 무엇에 쓰이는지가 아니라 누가 먹는지가
    적힐다. 사람을 가리키는 꼬리를 떼고 상황으로 바꾼다.
    """
    text = _SPACE.sub(" ", str(value or "")).strip()
    if not text:
        return ""
    if not _PERSON_TAIL.search(text):
        return text
    stem = _PERSON_TAIL.sub("", text).strip()
    if not stem:
        return text
    if stem.endswith("운"):  # 쉬운 → 쉬울 때
        return stem[:-1] + "울 때"
    if stem.endswith("는"):  # 생기는 → 생길 때, 먹는 → 먹을 때
        head = stem[:-1]
        last = head[-1:]
        if last and "가" <= last <= "훣":
            code = ord(last) - 0xAC00
            if code % 28 == 0:
                return head[:-1] + chr(0xAC00 + code + 8) + " 때"
            return head + "을 때"
        return head + " 때"
    if stem.endswith("한"):  # 필요한 → 필요할 때
        return stem[:-1] + "할 때"
    if stem.endswith("인"):  # 고혈압인 → 고혈압일 때
        return stem[:-1] + "일 때"
    return stem + "일 때"


def treatment_use_items(
    approved_summary: str,
    approved_uses: list[str],
    all_approved_uses: list[str],
) -> list[dict[str, str]]:
    """Return at most three user-facing treatment titles and descriptions."""
    source_items = _deduplicate_items(
        [
            *all_approved_uses,
            *approved_uses,
            approved_summary,
        ]
    )
    result: list[dict[str, str]] = []
    # 대표 쓰임을 이미 골라 두었으면 그 결과를 그대로 따른다. 다시 찾으면
    # 대표 쓰임 문장 속 낱말과 원문 조각이 섞여 쓰임 줄이 따로 논다.
    by_sentence = {group[2]: group for group in _PURPOSE_GROUPS}
    chosen = [
        by_sentence[item]
        for item in [*approved_uses, approved_summary]
        if item in by_sentence
    ]
    groups = list(dict.fromkeys(chosen)) or _matched_purpose_groups(
        _purpose_search_text(source_items)
    )
    for _pattern, title, description, highlight in groups:
        result.append(
            {
                "title": title,
                "description": description,
                "highlight": highlight,
            }
        )
        if len(result) == 3:
            return result

    if result:
        return result

    for item in [*approved_uses, approved_summary, *all_approved_uses]:
        text = str(item or "").strip()
        if (
            not text
            or text == "공식 허가정보에서 확인한 대표 사용 목적이에요."
            or any(entry["title"] == text for entry in result)
        ):
            continue
        result.append(
            {"title": use_phrase(text), "description": "", "highlight": ""}
        )
        if len(result) == 3:
            break
    return result


def _compose_reviewed_ingredient_explanation(
    ingredients: list[dict[str, str]],
    reviewed_by_key: dict[str, dict[str, Any]],
) -> str:
    """Compose only complete, verified copy; never splice approved-use text."""
    rows = [reviewed_by_key[item["key"]] for item in ingredients]
    group_keys = {str(row.get("role_group") or "").strip() for row in rows}
    group_texts = {
        clean_ingredient_explanation(row.get("group_explanation")) for row in rows
    }
    group_keys.discard("")
    group_texts.discard("")
    if (
        len(ingredients) > 1
        and len(group_keys) == 1
        and len(group_texts) == 1
    ):
        common_roles = {
            clean_ingredient_explanation(row.get("role_explanation")) for row in rows
        }
        common_uses = {
            clean_ingredient_explanation(row.get("use_help")) for row in rows
        }
        common_roles.discard("")
        common_uses.discard("")
        if len(common_roles) == 1 and len(common_uses) == 1:
            return f"이 약의 여러 주성분은 {next(iter(common_roles))} {next(iter(common_uses))}"
        grouped = next(iter(group_texts))
        if is_displayable_ingredient_explanation(grouped):
            return grouped

    if len(ingredients) == 1:
        row = rows[0]
        role = clean_ingredient_explanation(row.get("role_explanation"))
        use_help = clean_ingredient_explanation(row.get("use_help"))
        if role and use_help:
            ingredient_name = ingredients[0]["name"]
            return (
                f"{ingredient_name}{_topic_particle(ingredient_name)} 이 약의 주성분으로, "
                f"{role} {use_help}"
            )

    explanations: list[str] = []
    for ingredient, row in zip(ingredients, rows):
        text = clean_ingredient_explanation(row.get("explanation"))
        if not is_displayable_ingredient_explanation(text):
            return ""
        explanations.append(text if len(ingredients) == 1 else f"{ingredient['name']}: {text}")
    return "\n".join(explanations)


def _split_top_level_commas(value: str) -> list[str]:
    """Split a permission list without breaking commas inside parentheses."""
    result: list[str] = []
    current: list[str] = []
    depth = 0
    for char in str(value or ""):
        if char in "([（":
            depth += 1
        elif char in ")]）" and depth:
            depth -= 1
        if char in ",，" and depth == 0:
            piece = "".join(current).strip()
            if piece:
                result.append(piece)
            current = []
        else:
            current.append(char)
    piece = "".join(current).strip()
    if piece:
        result.append(piece)
    return result


def _clean_purpose_item(value: str) -> str:
    text = _LEADING_MARK.sub("", _SPACE.sub(" ", str(value or ""))).strip(
        " -•·,.;:："
    )
    for phrase in _BOILERPLATE_PURPOSES:
        if _purpose_key(text) == _purpose_key(phrase):
            return ""
        text = re.sub(rf"^{re.escape(phrase)}\s*[.:：]?\s*", "", text, flags=re.I)
    if not text or _looks_like_heading(text):
        return ""
    # "1", "2" 같은 항 번호만 남은 조각이나 한글이 하나도 없는 영문 균주명
    # 목록은 쓰임이 아니다.
    if not re.search(r"[가-힣]", text):
        return ""
    return text


def _looks_like_heading(value: str) -> bool:
    key = _purpose_key(value)
    return key in {
        "효능효과",
        "주효능효과",
        "적응증",
        "사용목적",
        "다음질환",
    }


def _deduplicate_items(values: list[str]) -> list[str]:
    result: list[str] = []
    keys: list[str] = []
    for raw in values:
        value = str(raw or "").strip()
        key = value
        if not key:
            continue
        if key in keys:
            continue
        keys.append(key)
        result.append(value)
    return result


def _without_summary_duplicate(values: list[str], summary: str) -> list[str]:
    summary_key = summary.strip()
    if not summary_key:
        return values
    return [
        value
        for value in values
        if value.strip() != summary_key
    ]


def official_source_hash(medicine: dict[str, Any]) -> str:
    material = {key: str(medicine.get(key) or "").strip() for key in (
        "medicine_code", "product_name", "manufacturer", "ingredient",
        "efficacy", "usage", "precautions",
    )}
    return "official-v1:" + hashlib.sha256(
        json.dumps(material, ensure_ascii=False, sort_keys=True).encode("utf-8")
    ).hexdigest()


def _purpose_key(value: str) -> str:
    return re.sub(r"[^0-9A-Za-z가-힣]", "", str(value or "")).casefold()


def _complete_user_text(value: str) -> bool:
    text = str(value or "").strip()
    if len(text) < 8:
        return False
    if text.endswith(("및", "또는", "등의", ",", ";", ":", "-")):
        return False
    return True


def _load_list(value: Any) -> list[str]:
    if isinstance(value, list):
        return [str(item).strip() for item in value if str(item).strip()]
    if not value:
        return []
    try:
        parsed = json.loads(str(value))
    except (json.JSONDecodeError, TypeError):
        parsed = None
    if isinstance(parsed, list):
        return [str(item).strip() for item in parsed if str(item).strip()]
    return [str(value).strip()] if str(value).strip() else []


def _dump(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False)
