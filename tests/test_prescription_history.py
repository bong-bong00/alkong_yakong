import sqlite3

from app.services import prescription_service
from init_db import TABLE_DEFINITIONS


class _Shared:
    """get_user_prescriptions가 닫아도 테스트가 계속 쓰는 연결."""

    def __init__(self, conn):
        self._conn = conn

    def __getattr__(self, name):
        return getattr(self._conn, name)

    def close(self):
        pass


def _db():
    conn = sqlite3.connect(":memory:")
    conn.row_factory = sqlite3.Row
    for table in ("medicines", "prescriptions", "prescription_items"):
        conn.execute(TABLE_DEFINITIONS[table])
    conn.execute(
        "INSERT INTO medicines (medicine_code, product_name, ingredient) "
        "VALUES ('P1', '휴온스시메티딘정200밀리그램(수출명:TAGAMENTTab.200밀리그램)', '시메티딘')"
    )
    return conn


def _add(conn, rx_id, created_at, fingerprint=None, hospital="미래의원"):
    conn.execute(
        "INSERT INTO prescriptions (id, user_id, hospital_name, prescribed_date, "
        "registration_fingerprint, created_at) VALUES (?, 'u', ?, '2023-10-30', ?, ?)",
        (rx_id, hospital, fingerprint, created_at),
    )
    conn.execute(
        "INSERT INTO prescription_items (prescription_id, medicine_code, ocr_drug_name) "
        "VALUES (?, 'P1', '시메티딘정')",
        (rx_id,),
    )


def test_same_prescription_registered_twice_is_listed_once(monkeypatch):
    conn = _db()
    _add(conn, "old", "2026-10-01 10:00:00", fingerprint="fp")
    _add(conn, "new", "2026-10-02 10:00:00", fingerprint="fp")
    # 지문이 없던 예전 등록도 병원·날짜·약이 같으면 같은 처방전이다.
    _add(conn, "legacy-a", "2026-09-01 10:00:00", hospital="오래된의원")
    _add(conn, "legacy-b", "2026-09-02 10:00:00", hospital="오래된의원")
    monkeypatch.setattr(prescription_service, "get_connection", lambda: _Shared(conn))

    rows = prescription_service.get_user_prescriptions("u")

    assert [row["id"] for row in rows] == ["new", "legacy-b"]


def test_items_carry_a_display_name_without_export_alias(monkeypatch):
    conn = _db()
    _add(conn, "rx", "2026-10-02 10:00:00", fingerprint="fp")
    monkeypatch.setattr(prescription_service, "get_connection", lambda: _Shared(conn))

    item = prescription_service.get_user_prescriptions("u")[0]["items"][0]

    assert item["display_name"] == "휴온스시메티딘정200밀리그램"
    # 허가 제품명은 그대로 둔다.
    assert "수출명" in item["product_name"]
