"""SQLite map: official phrase snippets → short senior-friendly labels."""

from __future__ import annotations

import sqlite3
from pathlib import Path

from app.core.config import EASY_CATEGORY_MAP_DB_PATH

DB_PATH = EASY_CATEGORY_MAP_DB_PATH

# (공식 문서·제품명에 자주 나오는 표현, 쉬운 말, 구분, 메모)
# match_scope: name = 이름/성분만, efficacy = 효능·용법 원문
# 효능은 큰 분류(감기약)보다 증상·작용 디테일(콧물, 해열)을 우선한다.
SEED_ROWS: tuple[tuple[str, str, str, str], ...] = (
    # 이름·성분 (효능 원문이 없을 때 쓰는 기본)
    ("암로디핀", "혈압 낮춤", "name", "제품명/성분"),
    ("메트포르민", "혈당 조절", "name", "제품명/성분"),
    ("아스피린", "피 묽게", "name", "제품명/성분"),
    ("아스트릭스", "피 묽게", "name", "아스피린 계열 제품명"),
    ("타이레놀", "해열·통증", "name", "제품명 — 효능 있으면 증상으로 덮음"),
    ("아세트아미노펜", "해열·통증", "name", "성분명"),
    ("부루펜", "해열·통증", "name", "제품명"),
    ("이부프로펜", "해열·통증", "name", "성분명"),
    ("게보린", "두통·통증", "name", "제품명"),
    ("메퀴타진", "가려움·알레르기", "name", "성분명"),
    ("프리마란", "가려움·알레르기", "name", "제품명"),
    # 효능 원문 → 디테일 쉬운 말
    ("감기의 제증상", "감기 증상", "efficacy", "큰 묶음. 아래 증상이 있으면 그쪽 우선"),
    ("감기로 인한 발열", "열", "efficacy", "효능 원문"),
    ("콧물", "콧물", "efficacy", "효능 원문 증상"),
    ("재채기", "재채기", "efficacy", "효능 원문 증상"),
    ("코막힘", "코막힘", "efficacy", "효능 원문 증상"),
    ("인후통", "목아픔", "efficacy", "효능 원문"),
    ("인후", "목아픔", "efficacy", "효능 원문"),
    ("기침", "기침", "efficacy", "효능 원문"),
    ("오한", "오한", "efficacy", "효능 원문"),
    ("해열", "해열", "efficacy", "효능 원문"),
    ("발열", "열", "efficacy", "효능 원문"),
    ("진통", "통증", "efficacy", "효능 원문"),
    ("동통", "통증", "efficacy", "통증의 한자 표현"),
    ("두통", "두통", "efficacy", "효능 원문"),
    ("치통", "이앓이", "efficacy", "효능 원문"),
    ("근육통", "근육통", "efficacy", "효능 원문"),
    ("생리통", "생리통", "efficacy", "효능 원문"),
    ("관절통", "관절통", "efficacy", "효능 원문"),
    ("고혈압", "혈압 낮춤", "efficacy", "효능 원문"),
    ("혈압을 낮", "혈압 낮춤", "efficacy", "효능 원문"),
    ("혈압강하", "혈압 낮춤", "efficacy", "효능 원문"),
    ("당뇨", "혈당 조절", "efficacy", "효능 원문"),
    ("혈당", "혈당 조절", "efficacy", "효능 원문"),
    ("혈전", "피 묽게", "efficacy", "효능 원문"),
    ("항혈소판", "피 묽게", "efficacy", "효능 원문"),
    ("알레르기 비염", "코알레르기", "efficacy", "효능 원문"),
    ("알레르기", "알레르기", "efficacy", "효능 원문"),
    ("가려움", "가려움", "efficacy", "효능 원문"),
    ("두드러기", "두드러기", "efficacy", "효능 원문"),
    ("결막염", "눈충혈", "efficacy", "효능 원문"),
    ("위염", "속쓰림·위", "efficacy", "효능 원문"),
    ("속쓰림", "속쓰림", "efficacy", "효능 원문"),
    ("소화불량", "소화", "efficacy", "효능 원문"),
    ("소화", "소화", "efficacy", "효능 원문"),
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

CREATE INDEX IF NOT EXISTS idx_category_map_phrase
    ON category_map(official_phrase);
CREATE INDEX IF NOT EXISTS idx_category_map_scope
    ON category_map(match_scope);
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
        existing = conn.execute("SELECT COUNT(*) AS n FROM category_map").fetchone()["n"]
        if existing == 0 or reset_seed:
            conn.executemany(
                """
                INSERT OR REPLACE INTO category_map (
                    official_phrase, easy_label, match_scope, note
                ) VALUES (?, ?, ?, ?)
                """,
                SEED_ROWS,
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
    """
    효능 원문에 맞는 디테일 라벨을 모아 '해열·콧물'처럼 이어 붙인다.
    효능 매칭이 없으면 이름/성분 기본 라벨을 쓴다.
    """
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

    # (원문에서 처음 나온 위치, 쉬운 말) — 긴 구문 우선 매칭 후, 표시는 등장 순
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
