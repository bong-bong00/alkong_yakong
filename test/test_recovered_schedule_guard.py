import sqlite3

import pytest

from init_db import TABLE_DEFINITIONS
from app.services.today_medication_service import _ensure_today_schedules


@pytest.mark.parametrize('pending,expected', [(0, 1), (1, 0)])
def test_partial_recovery_does_not_invent_today_schedule(pending, expected):
    with sqlite3.connect(':memory:') as connection:
        connection.row_factory = sqlite3.Row
        for definition in TABLE_DEFINITIONS.values():
            connection.execute(definition)
        connection.execute("INSERT INTO users(id,name,role) VALUES('qa','Synthetic','PATIENT')")
        connection.execute("INSERT INTO medicines(medicine_code,product_name,ingredient) VALUES('QA','Synthetic drug','Synthetic ingredient')")
        connection.execute('''INSERT INTO user_medicines(user_id,medicine_code,is_active,administration_times,schedule_recovery_pending)
                              VALUES('qa','QA',1,'["08:00"]',?)''', (pending,))
        _ensure_today_schedules(connection, 'qa', '2026-10-16')
        assert connection.execute('SELECT COUNT(*) FROM medication_schedules').fetchone()[0] == expected
        assert connection.execute('SELECT COUNT(*) FROM medication_logs').fetchone()[0] == 0
