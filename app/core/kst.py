"""한국 시간 기준의 오늘.

서버는 UTC로 돌지만 쓰는 분은 한국에 계신다. `date.today()`를 그대로 쓰면
자정부터 오전 9시 사이에 달력이 하루 전날을 "오늘"로 칠한다.
"""

from datetime import date, datetime, timedelta, timezone

KST = timezone(timedelta(hours=9))


def now_kst() -> datetime:
    return datetime.now(KST)


def today_kst() -> date:
    return now_kst().date()
