"""Sync MFDS drug permission API into the local mirror DB."""

from __future__ import annotations

import re
import time
from typing import Any, Callable

import requests

from app.services.matching.name_matcher import _medicine_key, match_medicine_name
from app.services.mfds_drug_permission.client import (
    extract_items,
    extract_total_count,
    fetch_permission_detail,
    fetch_permission_list_page,
)
from app.services.mfds_drug_permission.db import (
    count_stats,
    find_permission_product,
    get_permission_connection,
    initialize_permission_db,
    update_detail_item,
    upsert_list_item,
)


ProgressCb = Callable[[str], None]


def sync_permission_list(
    *,
    page_size: int = 500,
    sleep_seconds: float = 0.05,
    progress: ProgressCb | None = None,
) -> dict[str, int]:
    initialize_permission_db()
    log = progress or (lambda message: None)

    first = fetch_permission_list_page(page_no=1, num_of_rows=page_size)
    total = extract_total_count(first)
    pages = max(1, (total + page_size - 1) // page_size)
    log(f"list total={total} pages={pages} page_size={page_size}")

    conn = get_permission_connection()
    saved = 0
    try:
        for page_no in range(1, pages + 1):
            payload = (
                first
                if page_no == 1
                else fetch_permission_list_page(page_no=page_no, num_of_rows=page_size)
            )
            items = extract_items(payload)
            for item in items:
                upsert_list_item(conn, item)
                saved += 1
            conn.commit()
            if page_no == 1 or page_no % 10 == 0 or page_no == pages:
                log(f"list page {page_no}/{pages} saved~{saved}")
            if page_no < pages and sleep_seconds:
                time.sleep(sleep_seconds)
    finally:
        conn.close()

    stats = count_stats()
    log(f"list done db_total={stats['total']} detailed={stats['detailed']}")
    return {"api_total": total, "saved": saved, **stats}


def sync_permission_details(
    *,
    max_items: int | None = None,
    sleep_seconds: float = 0.12,
    progress: ProgressCb | None = None,
) -> dict[str, int]:
    initialize_permission_db()
    log = progress or (lambda message: None)
    conn = get_permission_connection()
    updated = 0
    failed = 0
    try:
        query = """
            SELECT item_seq, item_name FROM products
            WHERE detail_synced = 0
            ORDER BY item_seq
        """
        params: tuple = ()
        if max_items is not None:
            query += " LIMIT ?"
            params = (int(max_items),)
        rows = conn.execute(query, params).fetchall()
        total = len(rows)
        log(f"detail pending={total}")
        for index, row in enumerate(rows, start=1):
            item_seq = row["item_seq"]
            item_name = row["item_name"]
            try:
                detail = fetch_permission_detail(item_name)
                if detail:
                    # Prefer matching the same item_seq when API returns one.
                    if str(detail.get("ITEM_SEQ") or "") != str(item_seq):
                        # Still store onto requested row when names collide.
                        pass
                    update_detail_item(conn, item_seq, detail)
                    updated += 1
                else:
                    failed += 1
                if index % 50 == 0:
                    conn.commit()
                    log(f"detail {index}/{total} updated={updated} failed={failed}")
                if sleep_seconds:
                    time.sleep(sleep_seconds)
            except requests.HTTPError as error:
                failed += 1
                status = getattr(error.response, "status_code", None)
                log(f"detail HTTP {status} at {index}/{total}: {item_name}")
                if status in {22, 429} or status == 22:
                    break
                # Public data portal often returns XML error body with code 22
                body = ""
                try:
                    body = error.response.text[:200]
                except Exception:
                    body = ""
                if "LIMITED_NUMBER_OF_SERVICE_REQUESTS" in body:
                    log("daily/second limit hit; stopping detail sync")
                    break
            except Exception as error:
                failed += 1
                log(f"detail error {type(error).__name__}: {item_name}")
            if index % 20 == 0:
                conn.commit()
        conn.commit()
    finally:
        conn.close()
    stats = count_stats()
    log(f"detail done updated={updated} failed={failed} stats={stats}")
    return {"updated": updated, "failed": failed, **stats}


def ensure_detail_for_product(item_seq: str, item_name: str) -> bool:
    """Fetch and cache one product detail on demand."""
    initialize_permission_db()
    try:
        detail = fetch_permission_detail(item_name)
    except Exception:
        return False
    if not detail:
        return False
    conn = get_permission_connection()
    try:
        update_detail_item(conn, item_seq, detail)
        conn.commit()
        return True
    finally:
        conn.close()


def _ocr_name_query_variants(name: str, *, similar: bool = False) -> list[str]:
    """OCR 약명 → 식약처 검색어."""
    raw = (name or "").strip()
    if not raw:
        return []
    variants: list[str] = []

    def _add(value: str) -> None:
        text = (value or "").strip()
        if text and text not in variants:
            variants.append(text)

    _add(raw)
    stripped = re.sub(
        r"\d+(?:\.\d+)?\s*(?:mg|ml|g|%|밀리그램|밀리그람)",
        "",
        raw,
        flags=re.IGNORECASE,
    )
    stripped = re.sub(r"\s+", "", stripped)
    _add(stripped)
    key = _medicine_key(raw)
    _add(key)
    for suffix in ("정", "캡슐", "액", "시럽", "서방정", "패취", "플라스타"):
        if key:
            _add(key + suffix)
    # 유사 추론용: 앞부분으로 후보 풀을 넓힘 + 흔한 한 글자 혼동
    if similar:
        hangul = re.sub(r"[^가-힣]", "", key or stripped or raw)
        if len(hangul) >= 4:
            _add(hangul[:4])
        if len(hangul) >= 3:
            _add(hangul[:3])
        for a, b in (("짓", "짙"), ("짙", "짓"), ("짓", "짇"), ("짙", "짇"), ("짇", "짓"), ("핀", "피"), ("피", "핀")):
            if a in raw:
                _add(raw.replace(a, b, 1))
            if a in (key or ""):
                _add((key or "").replace(a, b, 1))
    return variants


def _pick_official_name(
    query: str,
    candidates: list[str],
    *,
    dosage_hint: str | float | None = None,
    similar: bool = False,
) -> str | None:
    if not candidates:
        return None
    match = match_medicine_name(
        query,
        candidates,
        dosage_hint=dosage_hint,
        similar=similar,
    )
    return match.matched_name


def _row_matches_query(
    query: str,
    row: dict[str, Any] | None,
    *,
    dosage_hint: str | float | None = None,
    similar: bool = False,
) -> dict[str, Any] | None:
    if not row:
        return None
    official = str(row.get("item_name") or "")
    if not official:
        return None
    match = match_medicine_name(
        query,
        [official],
        dosage_hint=dosage_hint,
        similar=similar,
    )
    return row if match.matched_name else None


def lookup_permission_by_ocr_name(
    name: str,
    *,
    dosage_hint: str | float | None = None,
    allow_similar: bool = True,
) -> dict[str, Any] | None:
    """OCR 약명 → 식약처 공식명. 1차 정확 매칭, 실패 시 유사 추론."""
    initialize_permission_db()
    query = (name or "").strip()
    if not query:
        return None

    for similar in (False, True) if allow_similar else (False,):
        cached = _row_matches_query(
            query,
            find_permission_product(query),
            dosage_hint=dosage_hint,
            similar=similar,
        )
        if cached:
            return cached

        collected: list[dict[str, Any]] = []
        seen_seq: set[str] = set()
        for variant in _ocr_name_query_variants(query, similar=similar):
            try:
                payload = fetch_permission_list_page(
                    page_no=1,
                    num_of_rows=15 if similar else 10,
                    item_name=variant,
                )
            except Exception:
                continue
            for item in extract_items(payload):
                seq = str(item.get("ITEM_SEQ") or "").strip()
                item_name = str(item.get("ITEM_NAME") or "").strip()
                if not seq or not item_name or seq in seen_seq:
                    continue
                seen_seq.add(seq)
                collected.append(item)

        if not collected:
            continue

        names = [str(item.get("ITEM_NAME") or "") for item in collected]
        chosen = _pick_official_name(
            query,
            names,
            dosage_hint=dosage_hint,
            similar=similar,
        )
        if not chosen:
            continue

        chosen_item = next(
            (item for item in collected if str(item.get("ITEM_NAME") or "") == chosen),
            None,
        )
        if not chosen_item:
            continue

        conn = get_permission_connection()
        try:
            upsert_list_item(conn, chosen_item)
            conn.commit()
        finally:
            conn.close()

        row = find_permission_product(chosen)
        if not row:
            continue
        ensure_detail_for_product(str(row["item_seq"]), str(row["item_name"]))
        matched = _row_matches_query(
            query,
            find_permission_product(chosen) or row,
            dosage_hint=dosage_hint,
            similar=similar,
        )
        if matched:
            return matched
    return None
