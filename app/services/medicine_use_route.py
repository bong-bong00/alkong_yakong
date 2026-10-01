"""Evidence-based UI grouping; absence of evidence must not imply oral use."""

from __future__ import annotations

import re
from typing import Any


def classify_medicine_use(data: dict[str, Any]) -> str:
    route = str(data.get("administration_route") or "").strip().lower()
    explicit = {
        "경구": "eat", "oral": "eat", "po": "eat",
        "외용": "apply", "topical": "apply", "apply": "apply",
        "patch": "patch", "eye": "eye", "ophthalmic": "eye",
        "inhalation": "inhale", "흡입": "inhale", "nasal": "nose",
        "otic": "ear", "injection": "injection", "주사": "injection",
        "rectal": "other", "vaginal": "other",
    }
    # Legacy 'eat' may have been a default guess, so require independent evidence.
    explicit_type = explicit.get(route)
    form = str(data.get("dosage_form") or "").strip()
    name = str(data.get("official_product_name") or data.get("product_name") or "")
    name = re.split(r"[（(]", name)[0].strip()
    usage = str(data.get("usage") or "")
    categories: set[str] = set()
    if explicit_type:
        categories.add(explicit_type)
    evidence = f"{name} {form}"
    for tokens, category in (
        (("점안", "안연고"), "eye"),
        (("점이", "귀에 넣"), "ear"),
        (("점비", "비강", "코에 뿌"), "nose"),
        (("흡입", "흡입제"), "inhale"),
        (("주사",), "injection"),
        (("좌제", "질정", "질크림"), "other"),
        (("패치", "패취", "첩부", "플라스타", "플라스터"), "patch"),
    ):
        if any(token in evidence for token in tokens):
            categories.add(category)
    # A mention of another formulation in precautions is not route evidence.
    for pattern, category in (
        (r"점안한다|눈에\s*(?:넣는다|투여한다)", "eye"),
        (r"귀에\s*넣는다", "ear"),
        (r"코에\s*뿌린다|비강에\s*투여한다", "nose"),
        (r"흡입한다", "inhale"),
    ):
        if re.search(pattern, usage):
            categories.add(category)
    if not categories:
        if any(token in evidence for token in ("연고", "크림", "로션", "외용")) or re.search(
            r"(?:피부|환부).{0,30}(?:바르|도포)|바른다|도포한다|외용으로", usage
        ):
            categories.add("apply")
    if not categories:
        if (
            form in {"정제", "캡슐", "캡슐제", "시럽", "시럽제", "경구액", "경구액제"}
            or re.search(r"(?:정|캡슐|시럽)(?:\d|밀리그램|mg|%|\.)*$", name, re.I)
            or re.search(r"경구(?:로)?\s*(?:투여한다|복용한다)|복용한다", usage)
        ):
            categories.add("eat")
    return next(iter(categories)) if len(categories) == 1 else "unknown"
