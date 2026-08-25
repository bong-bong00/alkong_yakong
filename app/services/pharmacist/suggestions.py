"""Suggestions for the guided pharmacist chat."""

from __future__ import annotations

from app.database import get_connection


FAQ_SUGGESTIONS = (
    "지금 먹을 약",
    "이 약 설명",
    "같이 먹으면",
    "안 먹었을 때",
)


def get_chat_suggestions(query: str = "", user_id: str | None = None) -> list[dict[str, str]]:
    needle = "".join((query or "").casefold().split())
    suggestions = [{"label": label, "type": "faq"} for label in FAQ_SUGGESTIONS]

    conn = get_connection()
    try:
        rows = conn.execute(
            "SELECT product_name FROM medicines WHERE product_name IS NOT NULL"
        ).fetchall()
        for row in rows:
            label = str(row["product_name"] or "").strip()
            if label and (not needle or needle in "".join(label.casefold().split())):
                suggestions.append({"label": label, "type": "medicine"})

        if user_id:
            rows = conn.execute(
                """
                SELECT DISTINCT m.product_name
                FROM user_medicines um
                JOIN medicines m ON m.medicine_code = um.medicine_code
                WHERE um.user_id = ? AND m.product_name IS NOT NULL
                """,
                (user_id,),
            ).fetchall()
            for row in rows:
                label = str(row["product_name"] or "").strip()
                if label and (not needle or needle in "".join(label.casefold().split())):
                    suggestions.append({"label": label, "type": "today_medicine"})
    finally:
        conn.close()

    unique: list[dict[str, str]] = []
    seen: set[tuple[str, str]] = set()
    for item in suggestions:
        key = (item["label"], item["type"])
        if key not in seen:
            seen.add(key)
            unique.append(item)
    return unique[:20]
