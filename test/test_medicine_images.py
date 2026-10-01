import pytest

import app.services.today_medication_service as service


def test_image_uses_stored_matched_product_without_lookup(monkeypatch):
    def unexpected_lookup(code):
        raise AssertionError("Stored photos must not trigger another lookup")
    monkeypatch.setattr(service, "find_permission_product_by_item_seq", unexpected_lookup)
    assert service._medicine_image_url({
        "medicine_code": "123", "image_url": "https://example.org/pill.png",
    }) == "https://example.org/pill.png"


@pytest.mark.parametrize("product, expected", [
    ({"item_seq": "123", "big_prdt_img_url": "https://example.org/pill.png"}, "https://example.org/pill.png"),
    ({"item_seq": "456", "big_prdt_img_url": "https://example.org/other.png"}, None),
    ({"item_seq": "123", "big_prdt_img_url": "javascript:bad"}, None),
    ({"item_seq": "123", "big_prdt_img_url": ""}, None),
    (None, None),
])
def test_image_fallback_requires_exact_code_and_valid_url(monkeypatch, product, expected):
    monkeypatch.setattr(service, "find_permission_product_by_item_seq", lambda code: product)
    item = service._medicine_item({"medicine_code": "123", "product_name": "테스트정"})
    assert item["image_url"] == expected


def test_photo_lookup_failure_does_not_break_medicine_list(monkeypatch):
    def failed_lookup(code):
        raise RuntimeError("Unavailable photo cache")
    monkeypatch.setattr(service, "find_permission_product_by_item_seq", failed_lookup)
    item = service._medicine_item({"medicine_code": "123", "product_name": "테스트정"})
    assert item["image_url"] is None
    assert item["display_name"] == "테스트정"
