from app.services.pharmacist.easy_category import (
    derive_easy_category,
    format_display_name,
)
from app.services.pharmacist.easy_category_db import initialize_easy_category_map_db


def setup_module():
    initialize_easy_category_map_db(reset_seed=True)


def test_amlodipine_is_blood_pressure():
    assert (
        derive_easy_category(product_name="암로디핀", ingredient="암로디핀 5mg")
        == "혈압 낮춤"
    )


def test_aspirin_is_blood_thinning():
    assert derive_easy_category(ingredient="아스피린 100mg") == "피 묽게"


def test_metformin_is_diabetes():
    assert derive_easy_category(ingredient="메트포르민 500mg") == "혈당 조절"


def test_tylenol_name_fallback():
    assert (
        derive_easy_category(product_name="타이레놀정500밀리그램") == "해열·통증"
    )


def test_cold_symptoms_are_detailed():
    label = derive_easy_category(
        efficacy="이 약은 감기의 제증상(콧물, 코막힘, 재채기, 발열)의 완화에 사용합니다"
    )
    assert label is not None
    assert "콧물" in label
    assert "코막힘" in label or "재채기" in label or "열" in label


def test_fever_and_pain_from_efficacy():
    label = derive_easy_category(efficacy="해열 및 감기에 의한 동통, 두통")
    assert label is not None
    assert "해열" in label
    assert "통증" in label or "두통" in label


def test_unknown_without_keyword_returns_none():
    assert derive_easy_category(product_name="무명정") is None


def test_format_display_name():
    assert format_display_name("암로디핀 5mg", "혈압 낮춤") == "암로디핀 5mg (혈압 낮춤)"
    assert format_display_name("암로디핀 5mg", None) == "암로디핀 5mg"
