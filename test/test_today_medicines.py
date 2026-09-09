from app.services.seed_mvp_medicines import MVP_USER_ID, ensure_mvp_demo_medicines
from app.services.today_medication_service import (
    _doses_from_active_medicines,
    _medicine_item,
    get_today_medicines,
)


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
    assert any("코다론" in name for name in names)
    assert any("부루펜" in name for name in names)
    assert any("게루삼" in name for name in names)
    assert not any("아디팜" in name for name in names)
    assert not any("프리마란" in name for name in names)
    assert not any("프레벨" in name for name in names)
    assert not any("휴온스시" in name for name in names)
    assert any(med.get("efficacy") for dose in data["doses"] for med in dose["medicines"])
    assert any(
        "약이에요" in str(med.get("easy_category") or "")
        for dose in data["doses"]
        for med in dose["medicines"]
    )


def test_home_amount_uses_take_dose_not_name_milligrams():
    milligrams = _medicine_item(
        {
            "product_name": "휴온스시메티딘정200밀리그램",
            "dosage": "200밀리그램",
            "ingredient": "시메티딘",
            "easy_category": "위약",
            "efficacy": "위궤양",
        }
    )
    assert milligrams["amount"] == ""
    assert "200" not in milligrams["amount"]

    half = _medicine_item(
        {
            "product_name": "휴온스시메티딘정200밀리그램",
            "dosage": "0.50",
            "ingredient": "시메티딘",
            "easy_category": "위약",
            "efficacy": "위궤양",
        }
    )
    assert half["amount"] == "0.50"


def test_home_item_separates_purpose_explanation_and_key_caution():
    item = _medicine_item(
        {
            "medicine_code": "197800210",
            "product_name": "아디팜정(히드록시진염산염)",
            "ingredient": "히드록시진염산염",
            "dosage": "1알",
            "efficacy": (
                "신경증에서의 불안, 긴장, 초조. "
                "두드러기, 피부질환에 수반하는 가려움"
            ),
            "precautions": "졸음이 올 수 있으며 운전 및 기계조작을 피한다.",
        }
    )
    assert item["purpose_label"] == "가려움 완화 · 불안·긴장 완화"
    assert item["short_explanation"].endswith("약이에요.")
    assert "운전" in item["key_caution"]
    assert len(item["easy_purposes"]) == 2


def test_active_medicine_without_frequency_does_not_get_a_made_up_morning_dose():
    rows = [
        {
            "medicine_code": "TEST-1",
            "product_name": "테스트정",
            "ingredient": "테스트성분",
            "dosage": "1알",
            "frequency_per_day": None,
            "administration_times": "[]",
            "easy_category": "처방받은 약이에요",
            "efficacy": "",
        }
    ]
    assert _doses_from_active_medicines(rows) == []
