"""가장 최근에 잰 심박수 한 번. 홈 바로가기와 보호자 현황이 같이 쓴다."""

from __future__ import annotations

import sqlite3

# Display reference range only, not a diagnosis or an emergency threshold.
_NORMAL_LOW = 60
_NORMAL_HIGH = 100


def latest_heart_reading(conn: sqlite3.Connection, user_id: str) -> dict | None:
    row = conn.execute(
        """
        SELECT bpm, measured_at FROM heart_rate_logs
        WHERE user_id = ?
        ORDER BY measured_at DESC, id DESC
        LIMIT 1
        """,
        (user_id,),
    ).fetchone()
    if row is None:
        return None
    bpm = int(row["bpm"])
    return {"bpm": bpm, "measured_at": row["measured_at"],
            "normal": _NORMAL_LOW <= bpm <= _NORMAL_HIGH}
