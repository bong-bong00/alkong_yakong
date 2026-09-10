from datetime import datetime, timedelta

from fastapi import HTTPException

from app.database import get_connection
from app.models.schemas import HeartRateCreate


def save_heart_rate(request: HeartRateCreate) -> dict:
    conn = get_connection()
    try:
        cursor = conn.cursor()
        if not cursor.execute(
            "SELECT 1 FROM users WHERE id = ?", (request.user_id,)
        ).fetchone():
            raise HTTPException(status_code=404, detail="사용자가 없습니다.")

        measured_at = request.measured_at or datetime.now().isoformat(timespec="seconds")
        cursor.execute(
            """
            INSERT INTO heart_rate_logs (
                user_id, bpm, measured_at, device_id, source
            ) VALUES (?, ?, ?, ?, ?)
            """,
            (
                request.user_id,
                request.bpm,
                measured_at,
                request.device_id,
                request.source,
            ),
        )
        log_id = cursor.lastrowid
        baseline = cursor.execute(
            "SELECT * FROM baseline_heart_rate WHERE user_id = ?",
            (request.user_id,),
        ).fetchone()
        if not baseline:
            min_bpm = max(40, request.bpm - 20)
            max_bpm = request.bpm + 20
            cursor.execute(
                """
                INSERT INTO baseline_heart_rate (
                    user_id, resting_bpm, min_normal_bpm, max_normal_bpm
                ) VALUES (?, ?, ?, ?)
                """,
                (request.user_id, request.bpm, min_bpm, max_bpm),
            )
            baseline = cursor.execute(
                "SELECT * FROM baseline_heart_rate WHERE user_id = ?",
                (request.user_id,),
            ).fetchone()

        event = None
        if request.bpm < baseline["min_normal_bpm"] or request.bpm > baseline["max_normal_bpm"]:
            event_type = "LOW_HEART_RATE" if request.bpm < baseline["min_normal_bpm"] else "HIGH_HEART_RATE"
            difference = abs(request.bpm - baseline["resting_bpm"])
            severity = "HIGH" if difference >= 40 else "WARNING"
            cursor.execute(
                """
                INSERT INTO abnormal_events (
                    user_id, heart_rate_log_id, event_type, bpm,
                    baseline_bpm, severity, occurred_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    request.user_id,
                    log_id,
                    event_type,
                    request.bpm,
                    baseline["resting_bpm"],
                    severity,
                    measured_at,
                ),
            )
            event_id = cursor.lastrowid
            event = {
                "id": event_id,
                "event_type": event_type,
                "severity": severity,
            }
            guardians = cursor.execute(
                """
                SELECT id FROM guardians
                WHERE user_id = ? AND notification_enabled = 1
                """,
                (request.user_id,),
            ).fetchall()
            for guardian in guardians:
                cursor.execute(
                    """
                    INSERT INTO notifications (
                        user_id, guardian_id, abnormal_event_id,
                        notification_type, title, message
                    ) VALUES (?, ?, ?, 'ABNORMAL_HEART_RATE', ?, ?)
                    """,
                    (
                        request.user_id,
                        guardian["id"],
                        event_id,
                        "심박 이상 감지",
                        f"사용자의 심박수가 {request.bpm} BPM으로 측정되었습니다.",
                    ),
                )

        conn.commit()
        return {
            "heart_rate_log_id": log_id,
            "bpm": request.bpm,
            "measured_at": measured_at,
            "baseline": dict(baseline),
            "abnormal_event": event,
        }
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


def get_abnormal_events(user_id: str) -> list[dict]:
    conn = get_connection()
    try:
        rows = conn.execute(
            """
            SELECT * FROM abnormal_events
            WHERE user_id = ?
            ORDER BY occurred_at DESC, id DESC
            """,
            (user_id,),
        ).fetchall()
        return [dict(row) for row in rows]
    finally:
        conn.close()


# ── 심박수 요약 ────────────────────────────────────────────────
#
# 이 앱은 심박수를 연속으로 재지 않는다. 약 먹기 전에 한 번, 먹은 뒤에
# 한 번. 그래서 값은 늘 쌍으로 다닌다. 아래 함수들이 heart_rate_logs 와
# medication_logs 를 시각으로 맞춰 그 쌍을 만든다.

# 복약 시각에서 이만큼 안쪽의 측정만 그 복약의 전·후로 본다.
_PAIR_WINDOW_MINUTES = 90

# 이 값 이상이면 빠른 것으로 본다. Flutter 의 HeartPair.isFast 와 같은 값이다.
FAST_BPM = 80

_WEEKDAY_LABELS = ["월", "화", "수", "목", "금", "토", "일"]


def _parse(value: str) -> datetime | None:
    """DB 의 시각 문자열을 datetime 으로. 형식이 섞여 있어도 죽지 않는다."""
    if not value:
        return None
    text = str(value).strip().replace("T", " ")
    for fmt in ("%Y-%m-%d %H:%M:%S", "%Y-%m-%d %H:%M", "%Y-%m-%d"):
        try:
            return datetime.strptime(text[: len(fmt) + 2].strip(), fmt)
        except ValueError:
            continue
    return None


def _pair_for(taken_at: datetime, readings: list[tuple[datetime, int]]) -> dict:
    """복약 한 번의 전·후 쌍.

    복약 시각 앞뒤 [_PAIR_WINDOW_MINUTES] 안에서 가장 가까운 측정을 고른다.
    없으면 None 으로 둔다 — **없는 값을 지어내지 않는다.**
    """
    window = timedelta(minutes=_PAIR_WINDOW_MINUTES)
    before = None
    after = None
    for measured_at, bpm in readings:
        delta = measured_at - taken_at
        if -window <= delta < timedelta(0):
            if before is None or measured_at > before[0]:
                before = (measured_at, bpm)
        elif timedelta(0) <= delta <= window:
            if after is None or measured_at < after[0]:
                after = (measured_at, bpm)
    return {
        "before": before[1] if before else None,
        "after": after[1] if after else None,
        "before_at": before[0].strftime("%H:%M") if before else None,
        "after_at": after[0].strftime("%H:%M") if after else None,
    }


def _slot_label(taken_at: datetime) -> str:
    if taken_at.hour < 11:
        return "아침 약"
    if taken_at.hour < 16:
        return "점심 약"
    return "저녁 약"


def get_heart_summary(user_id: str, today: datetime | None = None) -> dict:
    """심박수 화면 하나가 쓰는 것을 한 번에 돌려준다.

    화면이 오늘·이번 주·한 달을 따로 부르면 요청이 세 번이 되고, 그 사이
    날짜가 바뀌면 서로 다른 기준의 숫자가 한 화면에 놓인다.
    """
    now = today or datetime.now()
    conn = get_connection()
    try:
        cursor = conn.cursor()
        if not cursor.execute(
            "SELECT 1 FROM users WHERE id = ?", (user_id,)
        ).fetchone():
            raise HTTPException(status_code=404, detail="사용자가 없습니다.")

        # 한 달치만 읽는다. 화면이 그 이상을 보여주지 않는다.
        since = (now - timedelta(days=31)).isoformat(timespec="seconds")

        readings: list[tuple[datetime, int]] = []
        for row in cursor.execute(
            """
            SELECT measured_at, bpm FROM heart_rate_logs
            WHERE user_id = ? AND measured_at >= ?
            ORDER BY measured_at
            """,
            (user_id, since),
        ).fetchall():
            measured_at = _parse(row["measured_at"])
            if measured_at:
                readings.append((measured_at, int(row["bpm"])))

        takes: list[datetime] = []
        for row in cursor.execute(
            """
            SELECT taken_at FROM medication_logs
            WHERE user_id = ? AND taken_at >= ? AND status = 'TAKEN'
            ORDER BY taken_at
            """,
            (user_id, since),
        ).fetchall():
            taken_at = _parse(row["taken_at"])
            if taken_at:
                takes.append(taken_at)
    finally:
        conn.close()

    by_date: dict[str, dict] = {}
    for taken_at in takes:
        pair = _pair_for(taken_at, readings)
        if pair["before"] is None and pair["after"] is None:
            continue
        key = taken_at.date().isoformat()
        # 하루에 여러 번 드셨으면 마지막 복약을 그날의 대표로 둔다.
        by_date[key] = {**pair, "slot_label": _slot_label(taken_at)}

    today_key = now.date().isoformat()
    today_pair = by_date.get(today_key, {})

    monday = now.date() - timedelta(days=now.weekday())
    week = []
    for offset in range(7):
        date = monday + timedelta(days=offset)
        entry = by_date.get(date.isoformat(), {})
        week.append(
            {
                "weekday": _WEEKDAY_LABELS[offset],
                "before": entry.get("before"),
                "after": entry.get("after"),
            }
        )

    month = []
    for day in range(1, now.day + 1):
        date = now.date().replace(day=day)
        entry = by_date.get(date.isoformat(), {})
        month.append(
            {
                "day": day,
                "before": entry.get("before"),
                "after": entry.get("after"),
            }
        )

    return {
        "today": {
            "before": today_pair.get("before"),
            "after": today_pair.get("after"),
        },
        "today_slot_label": today_pair.get("slot_label") or "저녁 약",
        "before_at": today_pair.get("before_at"),
        "after_at": today_pair.get("after_at"),
        "week": week,
        "month": month,
        "streak_days": _streak(month),
        "best_streak_days": _best_streak(month),
        "anomaly": _anomaly(month, now),
    }


def _is_normal(entry: dict) -> bool:
    after = entry.get("after")
    return after is not None and after < FAST_BPM


def _streak(month: list[dict]) -> int:
    """오늘부터 거슬러 올라가며 잰 값이 정상인 날을 센다.

    못 잰 날은 끊지 않고 건너뛴다 — 센서를 안 찬 날이 "이상한 날"이 되면
    안 된다.
    """
    count = 0
    for entry in reversed(month):
        if entry.get("after") is None:
            continue
        if not _is_normal(entry):
            break
        count += 1
    return count


def _best_streak(month: list[dict]) -> int:
    best = 0
    current = 0
    for entry in month:
        if entry.get("after") is None:
            continue
        if _is_normal(entry):
            current += 1
            best = max(best, current)
        else:
            current = 0
    return best


def _anomaly(month: list[dict], now: datetime) -> dict | None:
    """가장 최근에 빨랐던 날 하나. 없으면 None."""
    for entry in reversed(month):
        if entry.get("after") is None:
            continue
        if not _is_normal(entry):
            return {
                "day": entry["day"],
                "label": f"{now.month}월 {entry['day']}일",
                "before": entry.get("before"),
                "after": entry.get("after"),
            }
    return None
