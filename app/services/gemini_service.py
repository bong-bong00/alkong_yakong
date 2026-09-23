"""Compatibility wrappers. OCR lives in ocr/, cards in pharmacist/generate."""

import json
import logging
import re
import time
from pathlib import Path
from typing import Any

from fastapi import HTTPException

from app.core.config import GEMINI_API_KEY, GEMINI_MODEL
from app.services.pharmacist.generate import generate_card_from_source


logger = logging.getLogger(__name__)


def _compact_product_name(value: object) -> str:
    return "".join(str(value or "").split()).casefold()


def _with_official_permission_ingredient(
    medicine: dict[str, Any],
    *,
    required_fields: set[str] | None = None,
) -> dict[str, Any]:
    """정확히 일치하는 공식 허가정보에서 비어 있는 근거 필드만 보완한다."""
    from app.services.mfds_drug_permission.client import fetch_permission_detail
    from app.services.mfds_drug_permission.db import (
        DB_PATH,
        find_permission_product_by_item_seq,
        product_to_medicine,
    )
    from app.services.pharmacist.ingredient import (
        ingredient_keys,
        is_usable_ingredient,
    )

    code = str(medicine.get("medicine_code") or "").strip()
    expected_name = _compact_product_name(medicine.get("product_name"))
    local_db_available = Path(DB_PATH).is_file()
    local_exact_found = False
    local_ingredient_usable = False
    api_fallback_attempted = False
    api_call_succeeded = False
    exact_item_seq_match = False
    exact_product_name_match = False
    if not code or not expected_name:
        logger.warning(
            "Permission ingredient diagnostic selected_code_present=%s "
            "local_db_available=%s local_exact_found=false "
            "local_ingredient_usable=false api_fallback_attempted=false "
            "api_call_succeeded=false exact_item_seq_match=false "
            "exact_product_name_match=false final_ingredient_usable=false "
            "ingredient_key_count=0",
            bool(code),
            local_db_available,
        )
        return medicine

    candidates: list[dict[str, Any]] = []
    try:
        local_row = find_permission_product_by_item_seq(code)
        if local_row:
            local_exact_found = True
            local_medicine = product_to_medicine(local_row)
            local_ingredient_usable = is_usable_ingredient(
                local_medicine.get("ingredient"),
                local_medicine.get("product_name"),
            )
            candidates.append(local_medicine)
    except Exception as error:
        logger.warning(
            "Permission ingredient local_lookup_failed exception_type=%s",
            type(error).__name__,
        )

    required = required_fields or {"ingredient"}
    if not candidates or any(not candidates[0].get(field) for field in required):
        api_fallback_attempted = True
        try:
            detail = fetch_permission_detail(
                str(medicine.get("product_name") or ""),
                item_seq=code,
            )
            api_call_succeeded = True
            if detail:
                normalized_detail = {
                    str(key).lower(): value for key, value in detail.items()
                }
                candidates.append(product_to_medicine(normalized_detail))
        except Exception as error:
            logger.warning(
                "Permission ingredient permission_api_failed exception_type=%s",
                type(error).__name__,
            )

    result = medicine
    added_fields: dict[str, Any] = {}
    for candidate in candidates:
        code_matches = str(candidate.get("medicine_code") or "").strip() == code
        name_matches = (
            _compact_product_name(candidate.get("product_name")) == expected_name
        )
        exact_item_seq_match = exact_item_seq_match or code_matches
        exact_product_name_match = exact_product_name_match or name_matches
        if code_matches and name_matches:
            fallback_fields = (
                "ingredient",
                "manufacturer",
                "efficacy",
                "usage",
                "cautions",
                "precautions",
                "side_effects",
                "storage",
                "image_url",
            )
            added_fields = {
                field: candidate[field]
                for field in fallback_fields
                if not medicine.get(field) and candidate.get(field)
            }
            result = {
                **medicine,
                **added_fields,
                "_permission_identity_verified": True,
            }
            if (
                any(field != "ingredient" for field in added_fields)
                and medicine.get("source") == "e약은요"
            ):
                result["source"] = "e약은요 + 식약처 의약품 제품 허가정보"
            break

    final_ingredient_usable = is_usable_ingredient(
        result.get("ingredient"),
        result.get("product_name"),
    )
    logger.warning(
        "Permission ingredient diagnostic selected_code_present=true "
        "local_db_available=%s local_exact_found=%s "
        "local_ingredient_usable=%s api_fallback_attempted=%s "
        "api_call_succeeded=%s exact_item_seq_match=%s "
        "exact_product_name_match=%s final_ingredient_usable=%s "
        "ingredient_key_count=%d",
        local_db_available,
        local_exact_found,
        local_ingredient_usable,
        api_fallback_attempted,
        api_call_succeeded,
        exact_item_seq_match,
        exact_product_name_match,
        final_ingredient_usable,
        len(ingredient_keys(result.get("ingredient"))),
    )
    logger.warning(
        "Permission content diagnostic required_fields=%s exact_match=%s "
        "efficacy_present=%s dosage_present=%s precautions_present=%s "
        "side_effects_present=%s fallback_used=%s",
        sorted(required),
        bool(exact_item_seq_match and exact_product_name_match),
        bool(result.get("efficacy")),
        bool(result.get("usage")),
        bool(result.get("cautions")),
        bool(result.get("side_effects")),
        bool(result is not medicine and added_fields),
    )
    return result


def _required_official_fields(intents: set[str]) -> set[str]:
    fields: set[str] = set()
    if intents & {"efficacy", "overview"}:
        fields.add("efficacy")
    if intents & {"dosage", "usage"}:
        fields.add("usage")
    if "precautions" in intents:
        fields.add("cautions")
    if "side_effects" in intents:
        fields.add("side_effects")
    return fields


def _has_requested_official_content(
    medicine: dict[str, Any],
    intents: set[str],
) -> bool:
    required = _required_official_fields(intents)
    return bool(required) and all(medicine.get(field) for field in required)

CHAT_EXTRACTION_SCHEMA = {
    "type": "object",
    "properties": {
        "drug_names": {
            "type": "array",
            "items": {"type": "string"},
            "description": "질문에 포함된 약품명 또는 성분명 목록 (없으면 빈 배열 반환)"
        }
    },
    "required": ["drug_names"],
    "additionalProperties": False,
}


def generate_easy_explanation(
    official_info: dict[str, Any],
) -> dict[str, Any] | None:
    try:
        return generate_card_from_source(official_info)
    except (ValueError, RuntimeError, ImportError, TypeError):
        return None


def _is_gemini_unavailable(error: Exception) -> bool:
    status_code = getattr(error, "status_code", None)
    code = getattr(error, "code", None)
    message = str(error).upper()
    return (
        status_code == 503
        or code == 503
        or ("503" in message and "UNAVAILABLE" in message)
    )


def _generate_content_with_retry(client, **kwargs):
    retry_delays = (1, 2)
    for attempt in range(len(retry_delays) + 1):
        try:
            return client.models.generate_content(**kwargs)
        except Exception as error:
            if not _is_gemini_unavailable(error) or attempt >= len(retry_delays):
                raise
            delay = retry_delays[attempt]
            logger.warning(
                "Gemini unavailable; retrying in %s second(s) (%s/2).",
                delay,
                attempt + 1,
            )
            time.sleep(delay)


def _read_response_text(response) -> str:
    try:
        return str(getattr(response, "text", None) or "")
    except Exception as error:
        logger.debug("Unable to read Gemini response.text: %s", error)
        return ""


def _strip_json_code_fence(response_text: str) -> str:
    stripped = response_text.strip()
    if not stripped.startswith("```"):
        return stripped

    first_newline = stripped.find("\n")
    if first_newline == -1:
        return stripped

    fenced_body = stripped[first_newline + 1 :]
    if fenced_body.rstrip().endswith("```"):
        fenced_body = fenced_body.rstrip()[:-3]
    return fenced_body.strip()


def _json_boundary_kind(response_text: str, *, first: bool) -> str:
    stripped = response_text.strip()
    if not stripped:
        return "empty"
    boundary = stripped[0] if first else stripped[-1]
    if boundary in "{}[]`":
        return boundary
    if boundary.isalpha():
        return "alphabetic"
    return "other"


def _gemini_part_kind(part) -> str:
    if getattr(part, "function_call", None) is not None:
        return "function_call"
    if isinstance(getattr(part, "text", None), str):
        return "thought_text" if getattr(part, "thought", False) else "text"
    return "other"


def _log_extraction_diagnostics(response, response_text: str) -> None:
    extracted_parsed = getattr(response, "parsed", None)
    candidates = getattr(response, "candidates", None) or []
    finish_reasons = []
    part_types = []
    part_count = 0

    for candidate in candidates:
        finish_reason = getattr(candidate, "finish_reason", None)
        if finish_reason is not None:
            finish_reasons.append(str(finish_reason))
        content = getattr(candidate, "content", None)
        parts = getattr(content, "parts", None) or []
        part_count += len(parts)
        part_types.extend(_gemini_part_kind(part) for part in parts)

    logger.warning(
        "Gemini extraction_parse_failed parsed_type=%s parsed_is_none=%s "
        "candidate_count=%d finish_reason=%s part_count=%d part_types=%s "
        "response_length=%d first_char_type=%s last_char_type=%s",
        type(extracted_parsed).__name__,
        extracted_parsed is None,
        len(candidates),
        ",".join(finish_reasons) or "none",
        part_count,
        ",".join(part_types) or "none",
        len(response_text),
        _json_boundary_kind(response_text, first=True),
        _json_boundary_kind(response_text, first=False),
    )


def _extract_drug_names(response) -> list[str]:
    extracted_parsed = getattr(response, "parsed", None)
    if hasattr(extracted_parsed, "model_dump"):
        extracted_parsed = extracted_parsed.model_dump()

    if extracted_parsed is None:
        response_text = _read_response_text(response)
        cleaned_text = _strip_json_code_fence(response_text)
        if cleaned_text:
            try:
                extracted_parsed = json.loads(cleaned_text)
            except (json.JSONDecodeError, TypeError):
                _log_extraction_diagnostics(response, response_text)
                return []
        else:
            _log_extraction_diagnostics(response, response_text)
            return []

    if not isinstance(extracted_parsed, dict):
        return []

    drug_names = extracted_parsed.get("drug_names", [])
    if not isinstance(drug_names, list):
        return []
    return [name.strip() for name in drug_names if isinstance(name, str) and name.strip()]


def _complete_response_text(response, *, response_text: str | None = None) -> str:
    primary_text = (
        _read_response_text(response) if response_text is None else response_text
    )
    if primary_text:
        return primary_text.strip()

    completed_parts = []
    for candidate in getattr(response, "candidates", None) or []:
        content = getattr(candidate, "content", None)
        for part in getattr(content, "parts", None) or []:
            part_text = getattr(part, "text", None)
            if part_text:
                completed_parts.append(str(part_text))
    return "".join(completed_parts).strip()


def _finish_reasons(response) -> list[str]:
    reasons = []
    direct_reason = getattr(response, "finish_reason", None)
    if direct_reason is not None:
        reasons.append(str(direct_reason))
    for candidate in getattr(response, "candidates", None) or []:
        reason = getattr(candidate, "finish_reason", None)
        if reason is not None:
            reasons.append(str(reason))
    return reasons


def _plain_chat_reply(value: str) -> str:
    """Remove AI reply markup only; preserve medicine text and clinical values."""
    text = value.replace("\r\n", "\n").replace("\r", "\n")
    text = re.sub(r"(?m)^[ \t]*```(?:[A-Za-z][A-Za-z0-9_-]*)?[ \t]*$", "", text)
    text = re.sub(r"(?m)^[ \t]{0,3}#{1,6}[ \t]+", "", text)
    text = re.sub(r"(?m)^[ \t]{0,3}[-*+][ \t]+", "• ", text)
    text = re.sub(r"\*\*([^*\n]+)\*\*", r"\1", text)
    text = re.sub(r"__([^\n]+?)__", r"\1", text)
    text = re.sub(r"(?<![\w*])\*([^*\s\n](?:[^*\n]*?[^*\s\n])?)\*(?!\*)", r"\1", text)
    text = re.sub(r"(?<![\w_])_([^_\s\n](?:[^_\n]*?[^_\s\n])?)_(?!_)", r"\1", text)
    text = text.replace("`", "")
    return re.sub(r"\n{3,}", "\n\n", text).strip()


def _finalize_chat_response(response) -> str:
    response_text = _read_response_text(response)
    logger.debug("Gemini response.text length: %d", len(response_text))

    reasons = _finish_reasons(response)
    if reasons:
        logger.debug("Gemini finish_reason: %s", ", ".join(reasons))

    reply = _plain_chat_reply(
        _complete_response_text(response, response_text=response_text)
    )
    logger.debug("Gemini final reply length: %d", len(reply))

    has_valid_ending = reply.endswith((".", "요", "다", "니다"))
    candidates = getattr(response, "candidates", None) or []
    part_count = sum(
        len(getattr(getattr(candidate, "content", None), "parts", None) or [])
        for candidate in candidates
    )
    usage_metadata = getattr(response, "usage_metadata", None)
    logger.warning(
        "Gemini final_response_diagnostic response_length=%d candidate_count=%d "
        "finish_reason=%s part_count=%d valid_ending=%s "
        "prompt_token_count=%s candidates_token_count=%s "
        "thoughts_token_count=%s total_token_count=%s",
        len(reply),
        len(candidates),
        ",".join(reasons) or "none",
        part_count,
        has_valid_ending,
        getattr(usage_metadata, "prompt_token_count", None),
        getattr(usage_metadata, "candidates_token_count", None),
        getattr(usage_metadata, "thoughts_token_count", None),
        getattr(usage_metadata, "total_token_count", None),
    )
    if len(reply) < 20 or not has_valid_ending:
        logger.warning(
            "Gemini response may be incomplete: length=%d valid_ending=%s",
            len(reply),
            has_valid_ending,
        )
    if len(reply) < 20:
        return "응답 생성이 불완전했습니다. 다시 질문해주세요."
    return reply


def _dur_context_unavailable_reply(
    intents: set[str],
    status: str,
    reason: str | None = None,
) -> str:
    if "combination" in intents:
        if reason == "official_medicine_unavailable":
            return (
                "선택한 약의 성분을 공식 자료에서 확인하지 못했어요. "
                "함께 사용할 때 주의할 점과 겹치는 약을 모두 확인하지 못했으니 다시 확인이 필요해요."
            )
        if reason == "dur_data_unavailable":
            return (
                "지금은 함께 사용할 때 주의할 공식 정보와 겹치는 약 정보를 모두 확인하지 못했어요. "
                "잠시 후 다시 확인해 주세요."
            )
        if status == "missing":
            return (
                "함께 사용할 때 주의할 점과 겹치는 약 정보를 확인한 결과를 찾지 못했어요. "
                "현재 복용약으로 다시 확인이 필요해요."
            )
        if status == "stale":
            return (
                "복용 중인 약이 바뀌어 이전 결과를 그대로 사용하기 어려워요. "
                "함께 사용할 때 주의할 점과 겹치는 약을 다시 확인해야 해요."
            )
        return (
            "현재 복용 중인 약과 선택한 약의 함께 사용 주의 및 겹치는 약 정보를 "
            "모두 확인하지 못했어요. 현재 복용약으로 다시 확인이 필요해요."
        )
    if "interaction" in intents:
        if status == "missing":
            return (
                "현재 복용 중인 약에 함께 사용하면 안 되는 조합이 있는지 확인한 결과를 찾지 못했어요. "
                "현재 복용약으로 다시 확인이 필요해요."
            )
        return (
            "복용 중인 약이 바뀌어 이전 결과를 그대로 사용하기 어려워요. "
            "함께 사용하면 안 되는 조합이 있는지 다시 확인이 필요해요."
        )
    if "age" in intents:
        if status == "missing":
            return (
                "현재 사용자 기준으로 나이에 따른 약 사용 제한을 확인한 결과를 찾지 못했어요. "
                "현재 복용약으로 다시 확인이 필요해요."
            )
        return (
            "복용 중인 약이 바뀌어 이전 결과를 그대로 사용하기 어려워요. "
            "나이에 따른 약 사용 제한을 다시 확인해야 해요."
        )
    if "pregnancy" in intents:
        if status == "missing":
            return (
                "현재 사용자 기준으로 임신 중 약 사용 제한을 확인한 결과를 찾지 못했어요. "
                "현재 복용약으로 다시 확인이 필요해요."
            )
        return (
            "복용 중인 약이 바뀌어 이전 결과를 그대로 사용하기 어려워요. "
            "임신 중 약 사용 제한을 다시 확인해야 해요."
        )
    if "duplicate" in intents:
        if reason == "official_medicine_unavailable":
            return (
                "선택한 약의 성분을 공식 자료에서 확인하지 못했어요. "
                "성분이나 효과가 겹치는지 확인할 수 없어요."
            )
        if reason == "dur_data_unavailable":
            return (
                "지금은 약을 함께 사용할 때 주의할 공식 정보를 확인하지 못했어요. "
                "잠시 후 다시 시도해 주세요."
            )
        if status == "missing":
            return (
                "현재 복용 중인 약에서 비슷한 효과가 겹치는지 확인한 결과를 찾지 못했어요. "
                "현재 복용약으로 다시 확인이 필요해요."
            )
        return (
            "복용 중인 약이 바뀌어 이전 결과를 그대로 사용하기 어려워요. "
            "비슷한 효과가 겹치는지 다시 확인이 필요해요."
        )
    return (
        "현재 약 사용 시 주의할 내용을 확인한 결과를 찾지 못했어요. "
        "현재 복용약으로 다시 확인이 필요해요."
        if status == "missing"
        else "복용 중인 약이 바뀌어 다시 확인이 필요해요."
    )


def _dur_no_match_reply(intents: set[str]) -> str:
    if "combination" in intents:
        return (
            "현재 저장된 약과 공식 자료를 확인한 범위에서는 함께 사용할 때 주의할 정보나 "
            "성분·역할이 겹치는 약 정보를 찾지 못했어요. "
            "이것만으로 안전하다고 단정할 수는 없어요."
        )
    if "interaction" in intents:
        risk_type = "함께 사용하면 안 되는 조합"
    elif "age" in intents:
        risk_type = "나이에 따른 약 사용 제한"
    elif "pregnancy" in intents:
        risk_type = "임신 중 약 사용 제한"
    elif "duplicate" in intents:
        return (
            "현재 복용 중인 약과 선택한 약 사이에서 성분이나 비슷한 효과가 겹친다는 정보를 "
            "확인한 공식 자료에서는 찾지 못했어요. 이것이 모든 위험이 없다는 뜻은 아니에요. "
            "함께 사용할 때 생기는 다른 영향이나 개인 상태에 따른 주의사항은 "
            "따로 확인해야 해요."
        )
    else:
        risk_type = "약 사용 시 주의할 내용"
    return (
        f"현재 저장된 최신 확인 결과에서는 {risk_type}에 해당하는 정보를 "
        "찾지 못했어요. 이 결과만으로 안전하다고 단정할 수는 없어요. "
        "약 사용 여부는 의사 또는 약사에게 확인해 주세요."
    )


def generate_chat_response(
    message: str,
    *,
    user_id: str = "",
    selected_medicine: dict[str, Any] | None = None,
    current_medicines: list[dict[str, Any]] | None = None,
    intent: str | None = None,
) -> str:
    from app.services.chat_context_service import (
        DUR_TYPES_BY_INTENT,
        build_grounded_chat_prompt,
        enrich_dur_matches,
        general_conversation_reply,
        is_safety_question,
        load_latest_dur_context,
        resolve_question_intents,
        select_official_context,
    )

    if general_reply := general_conversation_reply(message):
        return general_reply

    intents = resolve_question_intents(message, intent)
    safety_question = is_safety_question(intents)
    # 약 데이터 Render에서 읽은 목록이 없으면 팀 서버 DB로 대체하지 않는다.
    # 서로 다른 SQLite DB의 오래된 약으로 함께먹기를 판단하면 위험하다.
    # [] means the current app asked the medication-data Render but received
    # no usable list. None remains compatibility for older internal callers.
    if "combination" in intents and current_medicines == []:
        return (
            "현재 복용약 목록을 불러오지 못해서 함께먹기 확인을 할 수 없어요. "
            "약 목록을 다시 불러온 뒤 확인해 주세요."
        )
    unavailable_reply = (
        "현재 확인된 식약처 정보만으로는 답변하기 어려워요. "
        "현재 복용약으로 다시 확인하고, 복용 중인 약 전체를 의사 또는 약사에게 알려 주세요."
        if safety_question
        else "현재 식약처 공식정보를 확인할 수 없어 답변하기 어려워요. 잠시 후 다시 시도해 주세요."
    )
    if not GEMINI_API_KEY:
        return unavailable_reply

    try:
        from google import genai
        from app.services.dur_service import analyze_dur_consultation
        from app.services.external_api_service import (
            fetch_e_drug_info,
            search_drug_info_by_name,
        )

        selected_official = None
        official_data_list = []
        if selected_medicine is not None:
            required_fields = (
                {"ingredient"}
                if safety_question
                else _required_official_fields(intents)
            )
            selected_code = str(
                selected_medicine.get("medicine_code") or ""
            ).strip()
            selected_name = str(
                selected_medicine.get("product_name") or ""
            ).strip()
            e_drug_exact = False
            if selected_code.isdigit() and selected_name:
                try:
                    selected_official = fetch_e_drug_info(
                        medicine_code=selected_code,
                    )
                except Exception as error:
                    logger.warning(
                        "Selected medicine e_drug_lookup_failed error_type=%s",
                        type(error).__name__,
                    )
                e_drug_exact = bool(
                    selected_official
                    and selected_official.get("medicine_code") == selected_code
                    and _compact_product_name(
                        selected_official.get("product_name")
                    )
                    == _compact_product_name(selected_name)
                )

            if e_drug_exact:
                if any(not selected_official.get(field) for field in required_fields):
                    selected_official = _with_official_permission_ingredient(
                        selected_official,
                        required_fields=required_fields,
                    )
            elif selected_code.isdigit() and selected_name:
                permission_candidate = _with_official_permission_ingredient(
                    {
                        "medicine_code": selected_code,
                        "product_name": selected_name,
                        "source": "식약처 의약품 제품 허가정보",
                    },
                    required_fields=required_fields,
                )
                from app.services.pharmacist.ingredient import (
                    is_usable_ingredient,
                )

                permission_usable = (
                    is_usable_ingredient(
                        permission_candidate.get("ingredient"),
                        permission_candidate.get("product_name"),
                    )
                    if safety_question
                    else bool(
                        permission_candidate.get("_permission_identity_verified")
                        and _has_requested_official_content(
                            permission_candidate,
                            intents,
                        )
                    )
                )
                if permission_usable:
                    selected_official = permission_candidate
                else:
                    selected_official = None
            else:
                selected_official = None

            if not selected_official:
                return (
                    _dur_context_unavailable_reply(
                        intents,
                        "missing",
                        "official_medicine_unavailable",
                    )
                    if safety_question
                    else unavailable_reply
                )
            if (
                not safety_question
                and not _has_requested_official_content(selected_official, intents)
            ):
                return unavailable_reply
            official_data_list.append(
                {
                    "검색된_약품명": selected_official["product_name"],
                    "match_type": "exact",
                    "식약처_공식정보": selected_official,
                }
            )

        with genai.Client(api_key=GEMINI_API_KEY) as client:
            # Step 0 & 1: 오타 교정 및 약품명 추출 (추론 강화)
            extract_prompt = (
                "당신은 제약 전문가입니다. 사용자의 질문에서 약품명이나 성분명을 추출해야 합니다.\n"
                "사용자가 약품명을 잘못 입력했거나(오타), 속어/줄임말을 사용했을 수 있습니다. "
                "의약품 정보는 아주 작은 오타로도 검색이 안 되거나 잘못된 결과가 나올 수 있으므로, "
                "반드시 머릿속으로 다음 3번의 검증(추론)을 거쳐 가장 정확한 명칭을 도출하세요:\n\n"
                "1. 원본 확인: 사용자가 입력한 단어 그대로 인식\n"
                "2. 오타 및 유사도 검증: 해당 단어가 흔한 오타인지, 혹은 시판되는 비슷한 이름의 정식 약품이 있는지 분석 (예: 타이래놀 -> 타이레놀, 후시딘 -> 부채표후시딘연고)\n"
                "3. 최종 확정: 식약처 DB에 검색될 확률이 가장 높은 '정확한 정식 제품명' 또는 '표준 성분명'으로 교정\n\n"
                "3단계 검증을 모두 마친 최종 확정된 약품명들만 'drug_names' 배열에 담아 JSON으로 반환하세요. 없으면 빈 배열을 반환하세요.\n\n"
                f"질문: {message}"
            )
            extract_response = _generate_content_with_retry(
                client,
                model=GEMINI_MODEL,
                contents=extract_prompt,
                config={
                    "temperature": 0.2,
                    "max_output_tokens": 512,
                    "response_mime_type": "application/json",
                    "response_json_schema": CHAT_EXTRACTION_SCHEMA,
                    "thinking_config": {"thinking_budget": 0},
                },
            )

            drug_names = _extract_drug_names(extract_response)
            logger.warning(
                "Gemini extraction_result drug_name_count=%d",
                len(drug_names),
            )

            # 2. 식약처 공식 데이터 수집
            for drug_index, name in enumerate(drug_names):
                found_data = None
                # 2-1. 먼저 식약처 API 시도
                logger.warning(
                    "Gemini official_search_start drug_index=%d",
                    drug_index,
                )
                try:
                    search_result = search_drug_info_by_name(name)
                    search_items = (
                        search_result.get("items", [])
                        if isinstance(search_result, dict)
                        else []
                    )
                    logger.warning(
                        "Gemini official_search_result drug_index=%d "
                        "items_found=%d match_type_present=%s",
                        drug_index,
                        len(search_items) if isinstance(search_items, list) else 0,
                        bool(
                            isinstance(search_result, dict)
                            and search_result.get("match_type")
                        ),
                    )
                    if search_result and search_result.get("items"):
                        found_data = {
                            "검색된_약품명": name,
                            "match_type": search_result.get("match_type"),
                            "식약처_공식정보": search_result["items"][0],
                        }
                except Exception as e:
                    logger.warning(
                        "Gemini official_search_failed drug_index=%d error_type=%s "
                        "status_code=%s detail_type=%s",
                        drug_index,
                        type(e).__name__,
                        getattr(e, "status_code", None),
                        type(getattr(e, "detail", None)).__name__,
                    )

                if found_data and not any(
                    item["식약처_공식정보"].get("medicine_code")
                    == found_data["식약처_공식정보"].get("medicine_code")
                    for item in official_data_list
                ):
                    official_data_list.append(found_data)

            official_contexts = [
                select_official_context(item["식약처_공식정보"], intents)
                for item in official_data_list
                if item.get("match_type") in {"exact", "partial"}
                and item.get("식약처_공식정보")
            ]
            official_contexts = [item for item in official_contexts if item]
            if "combination" in intents and selected_official is None:
                return (
                    "함께먹기 확인할 약을 먼저 선택해 주세요. "
                    "선택한 약과 현재 복용약 전체를 함께 살펴볼게요."
                )
            if safety_question and selected_official is not None:
                wanted_types = set().union(
                    *(DUR_TYPES_BY_INTENT.get(intent, set()) for intent in intents)
                )
                dur_result = analyze_dur_consultation(
                    user_id=user_id,
                    selected_medicine=selected_official,
                    risk_types=wanted_types,
                    current_medicines=current_medicines,
                )
                dur_result["items"] = enrich_dur_matches(dur_result["items"])
            else:
                dur_result = load_latest_dur_context(user_id, intents)

            if safety_question and (
                dur_result.get("status") in {"stale", "missing"}
                or (
                    "combination" in intents
                    and (
                        dur_result.get("status") != "current"
                        or dur_result.get("has_risk", False) is None
                    )
                )
            ):
                return _dur_context_unavailable_reply(
                    intents,
                    dur_result.get("status") or "missing",
                    dur_result.get("reason"),
                )
            if (
                safety_question
                and dur_result["status"] == "current"
                and not dur_result["items"]
            ):
                return _dur_no_match_reply(intents)
            if not official_contexts and not dur_result["items"]:
                return unavailable_reply

            prompt = build_grounded_chat_prompt(
                message=message,
                intents=intents,
                official_contexts=official_contexts,
                dur_result=dur_result,
            )

            response = _generate_content_with_retry(
                client,
                model=GEMINI_MODEL,
                contents=prompt,
                config={
                    "temperature": 0.2,
                    "max_output_tokens": 512,
                    "thinking_config": {"thinking_budget": 0},
                },
            )
            return _finalize_chat_response(response)
    except HTTPException:
        raise
    except Exception as error:
        logger.warning("Gemini chat failed: %s", error, exc_info=True)
        return (
            "현재 정보를 불러오는 중 문제가 발생했습니다. "
            "잠시 후 다시 확인해주세요."
        )
