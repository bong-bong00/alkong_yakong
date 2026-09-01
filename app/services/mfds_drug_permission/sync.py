"""Sync MFDS drug permission API into the local mirror DB."""

from __future__ import annotations

import time
from typing import Callable

import requests

from app.services.mfds_drug_permission.client import (
    extract_items,
    extract_total_count,
    fetch_permission_detail,
    fetch_permission_list_page,
)
from app.services.mfds_drug_permission.db import (
    count_stats,
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
