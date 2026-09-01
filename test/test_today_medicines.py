from app.services.seed_mvp_medicines import MVP_USER_ID, ensure_mvp_demo_medicines
from app.services.today_medication_service import get_today_medicines


def test_mvp_user_today_medicines_from_server():
    ensure_mvp_demo_medicines()
    data = get_today_medicines(MVP_USER_ID)
    assert data["user_id"] == MVP_USER_ID
    assert data["has_server_medicines"] is True
    assert data["doses"]
    names = [
        med["ingredient"]
        for dose in data["doses"]
        for med in dose["medicines"]
    ]
    assert any("암로디핀" in name for name in names)
    assert any(med.get("easy_category") for dose in data["doses"] for med in dose["medicines"])
