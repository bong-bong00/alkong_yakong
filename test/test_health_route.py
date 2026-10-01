from app.main import health


def test_health_reports_demo_seeding_disabled():
    payload = health()
    assert payload["status"] == "ok"
    assert payload["demo_seed_enabled"] is False
