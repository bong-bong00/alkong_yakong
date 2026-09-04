from app.services.pharmacist.retrieve import retrieve_official


def test_retrieve_uses_local_permission_only(monkeypatch):
    order: list[str] = []

    monkeypatch.setattr(
        "app.services.pharmacist.retrieve._find_permission_local",
        lambda name, dosage_hint=None: order.append("local")
        or {
            "source": "식약처 의약품 제품 허가정보",
            "medicine": {"product_name": name},
            "source_text": "product_name: x",
        },
    )
    monkeypatch.setattr(
        "app.services.pharmacist.retrieve._find_permission_live",
        lambda name, dosage_hint=None: order.append("live") or None,
    )

    result = retrieve_official("게보린정")
    assert order == ["local"]
    assert result["source"] == "식약처 의약품 제품 허가정보"


def test_retrieve_does_not_call_live_api(monkeypatch):
    order: list[str] = []

    monkeypatch.setattr(
        "app.services.pharmacist.retrieve._find_permission_local",
        lambda name, dosage_hint=None: order.append("local") or None,
    )
    monkeypatch.setattr(
        "app.services.pharmacist.retrieve._find_permission_live",
        lambda name, dosage_hint=None: order.append("live") or None,
    )

    assert retrieve_official("없는약정") is None
    assert order == ["local"]
