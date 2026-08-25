"""Generate a simple answer from verified medicine source text only."""

from __future__ import annotations

import json
from typing import Any

from app.core.config import GEMINI_API_KEY, GEMINI_MODEL


def generate_from_source(question: str, official: dict[str, Any]) -> str:
    source_text = str(official.get("source_text") or "").strip()
    if not source_text:
        raise ValueError("official source required")
    if not GEMINI_API_KEY:
        raise RuntimeError("GEMINI_API_KEY가 설정되지 않았습니다.")

    from google import genai

    prompt = (
        "공식 의약품 원문만 근거로 질문에 짧고 쉬운 한국어로 답하세요. "
        "원문에 없는 효능, 복용법, 부작용을 추가하지 마세요. "
        "근거가 부족하면 정확히 '공식 자료에 명시되어 있지 않습니다.'라고 답하세요.\n\n"
        f"공식 원문:\n{source_text}\n\n질문:\n{question}"
    )
    with genai.Client(api_key=GEMINI_API_KEY) as client:
        response = client.models.generate_content(
            model=GEMINI_MODEL,
            contents=prompt,
            config={"temperature": 0.0},
        )
    reply = str(getattr(response, "text", None) or "").strip()
    if not reply:
        raise RuntimeError("답변이 비어 있습니다.")
    return reply
