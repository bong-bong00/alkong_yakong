"""처방전 용법 문구에서 복용 시간대를 읽는다.

처방전에는 "아침 약"이라고 적혀 있지 않다. 적혀 있는 것은 "1일 3회 매
식후 30분", "1일 1회 취침 전" 같은 용법이다. 이 문구를 읽어 아침·점심·
저녁·취침전으로 옮긴다.

문구가 없으면 **지어내지 않는다.** 1일 N회만으로 시각을 정하면 1일 1회
약이 전부 아침으로 가는데, 스타틴·수면제처럼 저녁에 드시는 약이 그렇게
아침으로 넘어가면 어르신은 그 시각에 드시게 된다.
"""

from __future__ import annotations

import re
from typing import Any

MORNING = "아침"
LUNCH = "점심"
EVENING = "저녁"
BEDTIME = "취침전"

#: 하루 안에서의 차례. 화면과 스케줄이 모두 이 순서를 쓴다.
SLOT_ORDER = (MORNING, LUNCH, EVENING, BEDTIME)

#: 때를 가리키는 말. 취침을 먼저 본다 — "저녁 식후 취침 전"처럼 두 말이
#: 같이 있으면 마지막 복용이 취침 전이기 때문이다.
_SLOT_WORDS: tuple[tuple[re.Pattern[str], str], ...] = (
    (re.compile(r"취침\s*(?:전|시|직전)|자기\s*전|잠자기\s*전|주무시기\s*전|자기전"), BEDTIME),
    (re.compile(r"아침|조식|기상\s*(?:직)?후|오전"), MORNING),
    (re.compile(r"점심|중식|정오|낮"), LUNCH),
    (re.compile(r"저녁|석식|오후|밤"), EVENING),
)

#: 끼니에 맞춰 드시는 약. 때는 안 적혀 있어도 1일 N회와 함께 보면 알 수 있다.
_MEAL_WORD = re.compile(r"식\s*(?:전|후|간)|매\s*식|밥\s*(?:먹기\s*)?(?:전|후)")

#: 용법으로 읽을 만한 줄. 이 말이 있는 자리에서만 때를 찾는다.
_INSTRUCTION_HINT = re.compile(
    r"식\s*(?:전|후|간)|매\s*식|취침|자기\s*전|아침|점심|저녁|조식|중식|석식|"
    r"기상|오전|오후|복용\s*법|용\s*법|복약"
)

#: 1일 N회를 끼니에 맞춰 나눈 기본값. 용법에 "식후"라고 적혀 있을 때만 쓴다.
_MEAL_SLOTS: dict[int, tuple[str, ...]] = {
    1: (MORNING,),
    2: (MORNING, EVENING),
    3: (MORNING, LUNCH, EVENING),
}


def sort_slots(slots) -> list[str]:
    """하루 차례대로 세우고 겹치는 것은 하나만 남긴다."""
    seen = []
    for slot in slots or ():
        text = str(slot or "").strip()
        if text in SLOT_ORDER and text not in seen:
            seen.append(text)
    return sorted(seen, key=SLOT_ORDER.index)


def instruction_line(text: str) -> str:
    """용법으로 보이는 가장 짧은 한 줄. 없으면 빈 문자열."""
    best = ""
    for raw in str(text or "").splitlines():
        line = re.sub(r"\s+", " ", raw).strip()
        if not line or len(line) > 60:
            continue
        if not _INSTRUCTION_HINT.search(line):
            continue
        # 여러 줄이 걸리면 짧은 쪽이 용법일 가능성이 높다. 긴 줄은 대개
        # 주의사항 문장이다.
        if not best or len(line) < len(best):
            best = line
    return best


def read_timing(text: str, frequency: int | None = None) -> dict[str, Any]:
    """용법 문구에서 복용 시간대를 읽는다.

    돌려주는 것:
      * ``slots`` — 확실히 읽은 때. 모르면 빈 목록이다.
      * ``instruction`` — 화면에 그대로 보여 줄 용법 한 줄.
      * ``meal_relative`` — 끼니에 맞춰 드시는 약인지.
    """
    source = str(text or "")
    instruction = instruction_line(source)
    scope = instruction or source

    found: list[str] = []
    for pattern, slot in _SLOT_WORDS:
        if pattern.search(scope):
            found.append(slot)
    slots = sort_slots(found)
    meal = bool(_MEAL_WORD.search(scope))

    if slots and frequency is not None and len(slots) != frequency:
        # 적힌 때의 수와 1일 횟수가 다르면 어느 쪽이 맞는지 알 수 없다.
        # 반쯤 맞는 값을 넣기보다 모른다고 두고 사람에게 묻는다.
        if meal and frequency in _MEAL_SLOTS and set(slots) <= set(_MEAL_SLOTS[frequency]):
            slots = list(_MEAL_SLOTS[frequency])
        else:
            slots = []

    if not slots and meal and frequency in _MEAL_SLOTS:
        # "1일 3회 매 식후"는 아침·점심·저녁이 분명하다.
        slots = list(_MEAL_SLOTS[frequency])

    return {"slots": slots, "instruction": instruction, "meal_relative": meal}


def timing_from_usage(usage: str | None, frequency: int | None = None) -> list[str]:
    """허가 용법에서 때를 짐작한다. 처방전에 안 적혀 있을 때만 쓴다.

    허가 용법은 "1일 1회 취침 전"처럼 때가 분명한 약에만 쓸모가 있다.
    "의사의 처방에 따라" 같은 문장에서는 아무것도 돌려주지 않는다.
    """
    text = str(usage or "")
    if not text.strip():
        return []
    # 허가 용법은 길다. 때를 말하는 조각만 본다.
    windows = [
        segment
        for segment in re.split(r"[.。\n]", text)
        if _SLOT_WORDS[0][0].search(segment) or _MEAL_WORD.search(segment)
    ]
    if not windows:
        return []
    timing = read_timing(" ".join(windows[:3]), frequency)
    return timing["slots"]


def default_slots_for_frequency(frequency: int | None) -> list[str]:
    """아무 단서도 없을 때의 마지막 기본값. 추정이라고 밝혀서 쓴다."""
    if frequency is None:
        return []
    return list(_MEAL_SLOTS.get(frequency, ()))
