from datetime import date
import sqlite3

import pytest

from app.services import dashboard_service, medication_history_service
from init_db import TABLE_DEFINITIONS


@pytest.fixture
def planned_db(tmp_path, monkeypatch):
    path = tmp_path / 'planned.sqlite3'
    def open_db():
        conn = sqlite3.connect(path)
        conn.row_factory = sqlite3.Row
        return conn
    with open_db() as conn:
        for name in ('users', 'medicines', 'user_medicines', 'medication_schedules'):
            conn.execute(TABLE_DEFINITIONS[name])
        for user in ('patient', 'other'):
            conn.execute('INSERT INTO users(id,name,role) VALUES (?,?,?)', (user,user,'PATIENT'))
        for code, name in [('a','등록약A'),('b','등록약B'),('c','중단약'),('d','다른환자약')]:
            conn.execute('INSERT INTO medicines(medicine_code,product_name,ingredient) VALUES (?,?,?)', (code,name,'시험성분'))
        conn.executemany('INSERT INTO user_medicines(id,user_id,medicine_code,dose_amount,dose_unit,is_active) VALUES (?,?,?,?,?,?)', [
            (1,'patient','a',0.5,'정',1), (2,'patient','b',5,'mL',1),
            (3,'patient','c',1,'정',0), (4,'other','d',1,'정',1),
        ])
        conn.executemany('INSERT INTO medication_schedules(user_id,user_medicine_id,scheduled_date,scheduled_time,time_slot,status) VALUES (?,?,?,?,?,?)', [
            ('patient',1,'2030-01-31','08:15','MORNING','PENDING'),
            ('patient',2,'2030-01-31','08:15','MORNING','PENDING'),
            ('patient',1,'2030-01-31','19:30','EVENING','PENDING'),
            ('patient',1,'2030-02-01','08:15','MORNING','PENDING'),
            ('patient',3,'2030-01-31','12:00','LUNCH','PENDING'),
            ('other',4,'2030-01-31','08:15','MORNING','PENDING'),
            ('patient',1,'2030-01-29','08:15','MORNING','TAKEN'),
        ])
    monkeypatch.setattr(dashboard_service, 'get_connection', open_db)
    monkeypatch.setattr(medication_history_service, 'get_connection', open_db)
    monkeypatch.setattr(dashboard_service, 'today_kst', lambda: date(2030,1,30))
    monkeypatch.setattr(medication_history_service, 'today_kst', lambda: date(2030,1,30))
    return open_db


def test_future_calendar_returns_actual_times_amounts_and_only_target_active_medicines(planned_db):
    result = dashboard_service.get_medication_calendar('patient',2030,1)
    day = result['days'][30]
    assert day['mark'] == 'future'
    assert day['planned_slots'] == [
        {'slot':'아침','time':'08:15','medicines':[{'name':'등록약A','amount':'0.5정'},{'name':'등록약B','amount':'5mL'}]},
        {'slot':'저녁','time':'19:30','medicines':[{'name':'등록약A','amount':'0.5정'}]},
    ]
    assert result['days'][28]['mark'] == 'done'
    assert result['days'][28]['planned_slots'] == []
    with planned_db() as conn:
        assert conn.execute('SELECT COUNT(*) FROM medication_schedules').fetchone()[0] == 7
        assert conn.execute("SELECT COUNT(*) FROM medication_schedules WHERE status='TAKEN'").fetchone()[0] == 1


def test_next_month_and_days_without_schedule_do_not_invent_plans(planned_db):
    result = dashboard_service.get_medication_calendar('patient',2030,2)
    assert len(result['days'][0]['planned_slots']) == 1
    assert all(day['planned_slots'] == [] for day in result['days'][1:])


def test_future_week_history_counts_only_active_schedule_slots(planned_db):
    result = medication_history_service.get_medication_history('patient','2030-01-29','2030-02-02')
    future = next(day for day in result['days'] if day['date']=='2030-01-31')
    assert future['total'] == 2
    assert future['taken'] == 0
