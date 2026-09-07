"""SQLite map: official phrases → easy labels, and everyday chat related links."""

from __future__ import annotations

import sqlite3
from pathlib import Path

from app.core.config import EASY_CATEGORY_MAP_DB_PATH

DB_PATH = EASY_CATEGORY_MAP_DB_PATH

# (공식 표현, 쉬운 말, name|efficacy, 메모)
SEED_ROWS: tuple[tuple[str, str, str, str], ...] = (
    ("암로디핀", "혈압 낮춤", "name", "제품명/성분"),
    ("메트포르민", "혈당 조절", "name", "제품명/성분"),
    ("아스피린", "피 묽게", "name", "제품명/성분"),
    ("아스트릭스", "피 묽게", "name", "아스피린 계열"),
    ("타이레놀", "해열·통증", "name", "제품명"),
    ("아세트아미노펜", "해열·통증", "name", "성분명"),
    ("부루펜", "해열·통증", "name", "제품명"),
    ("이부프로펜", "해열·통증", "name", "성분명"),
    ("게보린", "두통·통증", "name", "제품명"),
    ("메퀴타진", "가려움·알레르기", "name", "성분명"),
    ("프리마란", "가려움·알레르기", "name", "제품명"),
    ("스멕타", "설사", "name", "지사제"),
    ("정로환", "설사·배아픔", "name", "지사제"),
    ("로페라", "설사", "name", "지사제"),
    ("듀파락", "변비", "name", "변비약"),
    ("마그밀", "변비", "name", "변비약"),
    ("감기의 제증상", "감기 증상", "efficacy", "큰 묶음"),
    ("감기로 인한 발열", "열", "efficacy", ""),
    ("콧물", "콧물", "efficacy", ""),
    ("재채기", "재채기", "efficacy", ""),
    ("코막힘", "코막힘", "efficacy", ""),
    ("인후통", "목아픔", "efficacy", ""),
    ("인후", "목아픔", "efficacy", ""),
    ("기침", "기침", "efficacy", ""),
    ("오한", "오한", "efficacy", ""),
    ("해열", "해열", "efficacy", ""),
    ("발열", "열", "efficacy", ""),
    ("진통", "통증", "efficacy", ""),
    ("동통", "통증", "efficacy", ""),
    ("두통", "두통", "efficacy", ""),
    ("치통", "이앓이", "efficacy", ""),
    ("근육통", "근육통", "efficacy", ""),
    ("생리통", "생리통", "efficacy", ""),
    ("관절통", "관절통", "efficacy", ""),
    ("설사", "설사", "efficacy", ""),
    ("묽은변", "설사", "efficacy", ""),
    ("변비", "변비", "efficacy", ""),
    ("배변", "배변", "efficacy", ""),
    ("복통", "배아픔", "efficacy", ""),
    ("복부", "배아픔", "efficacy", ""),
    ("고혈압", "혈압 낮춤", "efficacy", ""),
    ("혈압을 낮", "혈압 낮춤", "efficacy", ""),
    ("혈압강하", "혈압 낮춤", "efficacy", ""),
    ("당뇨", "혈당 조절", "efficacy", ""),
    ("혈당", "혈당 조절", "efficacy", ""),
    ("혈전", "피 묽게", "efficacy", ""),
    ("항혈소판", "피 묽게", "efficacy", ""),
    ("알레르기 비염", "코알레르기", "efficacy", ""),
    ("알레르기", "알레르기", "efficacy", ""),
    ("가려움", "가려움", "efficacy", ""),
    ("두드러기", "두드러기", "efficacy", ""),
    ("결막염", "눈충혈", "efficacy", ""),
    ("위염", "속쓰림·위", "efficacy", ""),
    ("속쓰림", "속쓰림", "efficacy", ""),
    ("소화불량", "소화", "efficacy", ""),
    ("소화", "소화", "efficacy", ""),
    ("구역", "메스꺼움", "efficacy", ""),
    ("구토", "토함", "efficacy", ""),
    ("어지러", "어지러움", "efficacy", ""),
    ("불면", "잠", "efficacy", ""),
)

# (일상어 trigger, link_type, link_value, note)
# link_type: search=약검색키, phrase=연관검색어(입력만), faq=질문전송
CHAT_LINK_SEED: tuple[tuple[str, str, str, str], ...] = (
    # ----- 감기 -----
    ("감기", "phrase", "콧물", ""),
    ("감기", "phrase", "기침", ""),
    ("감기", "phrase", "열", ""),
    ("감기", "phrase", "코막힘", ""),
    ("감기", "phrase", "목아픔", ""),
    ("감기", "phrase", "몸살", ""),
    ("감기", "search", "타이레놀콜드", ""),
    ("감기", "search", "타이레놀", ""),
    ("감기", "search", "게보린", ""),
    ("감기", "faq", "이 약 설명", ""),
    ("몸살", "phrase", "감기", ""),
    ("몸살", "phrase", "열", ""),
    ("몸살", "phrase", "근육통", ""),
    ("몸살", "search", "타이레놀", ""),
    ("몸살", "search", "부루펜", ""),
    ("독감", "phrase", "열", ""),
    ("독감", "phrase", "기침", ""),
    ("독감", "phrase", "몸살", ""),
    ("독감", "search", "타이레놀", ""),
    ("콧물", "phrase", "감기", ""),
    ("콧물", "phrase", "코막힘", ""),
    ("콧물", "phrase", "재채기", ""),
    ("콧물", "search", "타이레놀콜드", ""),
    ("기침", "phrase", "감기", ""),
    ("기침", "phrase", "목아픔", ""),
    ("기침", "search", "타이레놀콜드", ""),
    ("코막힘", "phrase", "콧물", ""),
    ("코막힘", "phrase", "감기", ""),
    ("코막힘", "search", "타이레놀콜드", ""),
    ("재채기", "phrase", "콧물", ""),
    ("재채기", "phrase", "알레르기", ""),
    ("목아픔", "phrase", "기침", ""),
    ("목아픔", "phrase", "감기", ""),
    ("인후통", "phrase", "목아픔", ""),
    # ----- 열·통증 -----
    ("열", "phrase", "해열", ""),
    ("열", "phrase", "오한", ""),
    ("열", "phrase", "감기", ""),
    ("열", "search", "타이레놀", ""),
    ("열", "search", "부루펜", ""),
    ("열나", "phrase", "열", ""),
    ("열나", "search", "타이레놀", ""),
    ("해열", "phrase", "열", ""),
    ("해열", "search", "타이레놀", ""),
    ("두통", "phrase", "머리아픔", ""),
    ("두통", "phrase", "진통", ""),
    ("두통", "search", "게보린", ""),
    ("두통", "search", "타이레놀", ""),
    ("머리아", "phrase", "두통", ""),
    ("머리아", "search", "게보린", ""),
    ("골치", "phrase", "두통", ""),
    ("골치", "search", "게보린", ""),
    ("통증", "phrase", "두통", ""),
    ("통증", "phrase", "근육통", ""),
    ("통증", "search", "타이레놀", ""),
    ("통증", "search", "부루펜", ""),
    ("근육통", "phrase", "몸살", ""),
    ("근육통", "search", "부루펜", ""),
    ("생리통", "search", "타이레놀", ""),
    ("생리통", "search", "게보린", ""),
    ("치통", "phrase", "이앓이", ""),
    ("치통", "search", "타이레놀", ""),
    ("이앓이", "phrase", "치통", ""),
    ("관절통", "search", "부루펜", ""),
    ("무릎", "phrase", "관절통", ""),
    ("무릎", "search", "부루펜", ""),
    ("허리", "phrase", "요통", ""),
    ("허리", "search", "부루펜", ""),
    ("요통", "search", "부루펜", ""),
    # ----- 배·설사·변비 -----
    ("설사", "phrase", "배아픔", ""),
    ("설사", "phrase", "물설사", ""),
    ("설사", "phrase", "배탈", ""),
    ("설사", "phrase", "장염", ""),
    ("설사", "search", "스멕타", ""),
    ("설사", "search", "정로환", ""),
    ("설사", "faq", "이 약 설명", ""),
    ("설사", "faq", "같이 먹으면", ""),
    ("물설사", "phrase", "설사", ""),
    ("물설사", "search", "스멕타", ""),
    ("배탈", "phrase", "설사", ""),
    ("배탈", "phrase", "배아픔", ""),
    ("배탈", "phrase", "체함", ""),
    ("배탈", "search", "정로환", ""),
    ("배아", "phrase", "배아픔", ""),
    ("배아픔", "phrase", "설사", ""),
    ("배아픔", "phrase", "체함", ""),
    ("배아픔", "phrase", "속쓰림", ""),
    ("배아픔", "search", "정로환", ""),
    ("복통", "phrase", "배아픔", ""),
    ("장염", "phrase", "설사", ""),
    ("장염", "phrase", "배아픔", ""),
    ("변비", "phrase", "배변", ""),
    ("변비", "phrase", "배아픔", ""),
    ("변비", "search", "듀파락", ""),
    ("변비", "search", "마그밀", ""),
    ("변비", "faq", "이 약 설명", ""),
    ("체함", "phrase", "소화", ""),
    ("체함", "phrase", "배아픔", ""),
    ("체함", "phrase", "메스꺼움", ""),
    ("체한", "phrase", "체함", ""),
    ("소화", "phrase", "체함", ""),
    ("소화", "phrase", "속쓰림", ""),
    ("속쓰림", "phrase", "위", ""),
    ("속쓰림", "phrase", "소화", ""),
    ("속안좋", "phrase", "속쓰림", ""),
    ("속안좋", "phrase", "소화", ""),
    ("메스꺼움", "phrase", "토할것같", ""),
    ("구토", "phrase", "토함", ""),
    ("토함", "phrase", "메스꺼움", ""),
    # ----- 혈압·당뇨 -----
    ("혈압", "phrase", "고혈압", ""),
    ("혈압", "search", "암로디핀", ""),
    ("혈압", "faq", "같이 먹으면", ""),
    ("혈압", "faq", "이 약 설명", ""),
    ("고혈압", "phrase", "혈압", ""),
    ("고혈압", "search", "암로디핀", ""),
    ("당뇨", "phrase", "혈당", ""),
    ("당뇨", "search", "메트포르민", ""),
    ("당뇨", "faq", "같이 먹으면", ""),
    ("당뇨", "faq", "이 약 설명", ""),
    ("혈당", "phrase", "당뇨", ""),
    ("혈당", "search", "메트포르민", ""),
    # ----- 알레르기·피부 -----
    ("알레르기", "phrase", "가려움", ""),
    ("알레르기", "phrase", "두드러기", ""),
    ("알레르기", "phrase", "재채기", ""),
    ("알레르기", "search", "프리마란", ""),
    ("가려움", "phrase", "두드러기", ""),
    ("가려움", "phrase", "알레르기", ""),
    ("가려움", "search", "프리마란", ""),
    ("두드러기", "phrase", "가려움", ""),
    ("두드러기", "search", "프리마란", ""),
    # ----- 복용 습관 -----
    ("같이먹", "faq", "같이 먹으면", ""),
    ("같이", "faq", "같이 먹으면", ""),
    ("겹쳐", "faq", "같이 먹으면", ""),
    ("안먹", "faq", "안 먹었을 때", ""),
    ("깜빡", "faq", "안 먹었을 때", ""),
    ("잊었", "faq", "안 먹었을 때", ""),
    ("어제안", "faq", "안 먹었을 때", ""),
    ("언제먹", "faq", "이 약 설명", ""),
    ("밥전", "faq", "이 약 설명", ""),
    ("식후", "faq", "이 약 설명", ""),
    ("몇알", "faq", "이 약 설명", ""),
    ("두알", "faq", "이 약 설명", ""),
    ("먹어도돼", "faq", "같이 먹으면", ""),
    ("술먹", "faq", "같이 먹으면", ""),
    ("술하고", "faq", "같이 먹으면", ""),
    ("부작용", "faq", "이 약 설명", ""),
    ("어지러", "phrase", "어지러움", ""),
    ("어지러", "faq", "이 약 설명", ""),
    ("졸려", "faq", "이 약 설명", ""),
    ("뭐야", "faq", "이 약 설명", ""),
    ("이거뭐", "faq", "이 약 설명", ""),
    ("효과있", "faq", "이 약 설명", ""),
    # ----- 약 이름 오타·초성 -----
    ("타이", "search", "타이레놀", ""),
    ("타이레", "search", "타이레놀", ""),
    ("타이래", "search", "타이레놀", ""),
    ("ㅌㄹㄴ", "search", "타이레놀", ""),
    ("ㅌㅇㄹㄴ", "search", "타이레놀", ""),
    ("부루", "search", "부루펜", ""),
    ("부르펜", "search", "부루펜", ""),
    ("ㅂㄹㅍ", "search", "부루펜", ""),
    ("게보", "search", "게보린", ""),
    ("게보링", "search", "게보린", ""),
    ("ㄱㅂㄹ", "search", "게보린", ""),
    ("아스피", "search", "아스피린", ""),
    ("ㅇㅅㅍㄹ", "search", "아스피린", ""),
    ("프리마", "search", "프리마란", ""),
    ("ㅍㄹㅁ", "search", "프리마란", ""),
)

_MAX_DETAIL_LABELS = 3

SCHEMA_SQL = """
CREATE TABLE IF NOT EXISTS category_map (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    official_phrase TEXT NOT NULL,
    easy_label TEXT NOT NULL,
    match_scope TEXT NOT NULL DEFAULT 'efficacy',
    note TEXT,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(official_phrase, match_scope)
);

CREATE TABLE IF NOT EXISTS chat_links (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    trigger TEXT NOT NULL,
    link_type TEXT NOT NULL,
    link_value TEXT NOT NULL,
    note TEXT,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(trigger, link_type, link_value)
);

CREATE INDEX IF NOT EXISTS idx_category_map_phrase ON category_map(official_phrase);
CREATE INDEX IF NOT EXISTS idx_category_map_scope ON category_map(match_scope);
CREATE INDEX IF NOT EXISTS idx_chat_links_trigger ON chat_links(trigger);
CREATE INDEX IF NOT EXISTS idx_chat_links_type ON chat_links(link_type);
"""


def get_connection() -> sqlite3.Connection:
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn


def initialize_easy_category_map_db(*, reset_seed: bool = False) -> Path:
    path = Path(DB_PATH)
    path.parent.mkdir(parents=True, exist_ok=True)
    conn = get_connection()
    try:
        conn.executescript(SCHEMA_SQL)
        if reset_seed:
            conn.execute("DELETE FROM category_map")
            conn.execute("DELETE FROM chat_links")
        cat_n = conn.execute("SELECT COUNT(*) AS n FROM category_map").fetchone()["n"]
        if cat_n == 0 or reset_seed:
            conn.executemany(
                """
                INSERT OR REPLACE INTO category_map (
                    official_phrase, easy_label, match_scope, note
                ) VALUES (?, ?, ?, ?)
                """,
                SEED_ROWS,
            )
        link_n = conn.execute("SELECT COUNT(*) AS n FROM chat_links").fetchone()["n"]
        if link_n == 0 or reset_seed:
            conn.executemany(
                """
                INSERT OR REPLACE INTO chat_links (
                    trigger, link_type, link_value, note
                ) VALUES (?, ?, ?, ?)
                """,
                CHAT_LINK_SEED,
            )
        conn.commit()
    finally:
        conn.close()
    return path


def lookup_easy_label(
    *,
    name_text: str = "",
    efficacy_text: str = "",
) -> str | None:
    initialize_easy_category_map_db()
    name_blob = (name_text or "").casefold()
    efficacy_blob = (efficacy_text or "").casefold()
    conn = get_connection()
    try:
        rows = conn.execute(
            """
            SELECT official_phrase, easy_label, match_scope
            FROM category_map
            ORDER BY LENGTH(official_phrase) DESC, id ASC
            """
        ).fetchall()
    finally:
        conn.close()

    detail_hits: list[tuple[int, str]] = []
    seen: set[str] = set()
    name_fallback: str | None = None
    has_cold_bundle = False

    for row in rows:
        phrase = str(row["official_phrase"] or "").casefold()
        label = str(row["easy_label"] or "").strip()
        if not phrase or not label:
            continue
        scope = row["match_scope"]
        if scope == "efficacy" and phrase in efficacy_blob:
            if label == "감기 증상":
                has_cold_bundle = True
                continue
            if label in seen:
                continue
            seen.add(label)
            detail_hits.append((efficacy_blob.find(phrase), label))
        elif scope == "name" and phrase in name_blob and name_fallback is None:
            name_fallback = label

    if detail_hits:
        detail_hits.sort(key=lambda item: item[0])
        labels = [label for _, label in detail_hits[:_MAX_DETAIL_LABELS]]
        return "·".join(labels)

    if has_cold_bundle or "감기" in efficacy_blob:
        return "감기 증상"
    return name_fallback


def lookup_chat_links(query: str) -> dict[str, list[str]]:
    """일상어 입력에 묶인 search/phrase/faq 목록."""
    initialize_easy_category_map_db()
    needle = "".join(str(query or "").casefold().split())
    result: dict[str, list[str]] = {"search": [], "phrase": [], "faq": []}
    if not needle:
        return result

    conn = get_connection()
    try:
        rows = conn.execute(
            """
            SELECT trigger, link_type, link_value
            FROM chat_links
            ORDER BY LENGTH(trigger) DESC, id ASC
            """
        ).fetchall()
    finally:
        conn.close()

    # 입력에 들어 있는 trigger만 인정.
    # (설사 → 물설사 trigger로 잘못 잡히지 않게 needle in trigger 는 쓰지 않음)
    matched_triggers: list[str] = []
    best_len = 0
    for row in rows:
        trigger = str(row["trigger"] or "").casefold()
        if not trigger:
            continue
        hit = needle == trigger or trigger in needle
        if not hit and len(trigger) == 1:
            hit = needle.startswith(trigger)
        if not hit:
            continue
        if len(trigger) > best_len:
            best_len = len(trigger)
            matched_triggers = [trigger]
        elif len(trigger) == best_len and trigger not in matched_triggers:
            matched_triggers.append(trigger)

    if not matched_triggers:
        return result

    seen: dict[str, set[str]] = {"search": set(), "phrase": set(), "faq": set()}
    for row in rows:
        trigger = str(row["trigger"] or "").casefold()
        if trigger not in matched_triggers:
            continue
        link_type = str(row["link_type"] or "")
        value = str(row["link_value"] or "").strip()
        if link_type not in seen or not value or value in seen[link_type]:
            continue
        seen[link_type].add(value)
        result[link_type].append(value)
    return result


def list_map_rows(limit: int = 200) -> list[dict]:
    initialize_easy_category_map_db()
    conn = get_connection()
    try:
        rows = conn.execute(
            """
            SELECT official_phrase, easy_label, match_scope, note
            FROM category_map
            ORDER BY match_scope, LENGTH(official_phrase) DESC, id
            LIMIT ?
            """,
            (limit,),
        ).fetchall()
        return [dict(row) for row in rows]
    finally:
        conn.close()


def list_chat_link_rows(limit: int = 300) -> list[dict]:
    initialize_easy_category_map_db()
    conn = get_connection()
    try:
        rows = conn.execute(
            """
            SELECT trigger, link_type, link_value, note
            FROM chat_links
            ORDER BY trigger, link_type, id
            LIMIT ?
            """,
            (limit,),
        ).fetchall()
        return [dict(row) for row in rows]
    finally:
        conn.close()
