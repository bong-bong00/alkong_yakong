import pytest

from app.services.medicine_use_route import classify_medicine_use
from app.services.today_medication_service import _medicine_item


@pytest.mark.parametrize("data, expected", [
    ({"product_name": "테스트정(성분)"}, "eat"),
    ({"product_name": "테스트시럽"}, "eat"),
    ({"product_name": "테스트액", "usage": "1일 1회 환부에 바른다."}, "apply"),
    ({"product_name": "테스트크림"}, "apply"),
    ({"product_name": "테스트안연고"}, "eye"),
    ({"product_name": "테스트점안액"}, "eye"),
    ({"product_name": "테스트패치"}, "patch"),
    ({"product_name": "테스트주사"}, "injection"),
    ({"product_name": "테스트질정"}, "other"),
    ({"product_name": "테스트흡입액"}, "inhale"),
    ({"product_name": "테스트정", "usage": "주사제에서 전환하는 경우 용량을 확인한다."}, "eat"),
    ({"product_name": "미확인액", "administration_route": "eat", "efficacy": "가려움"}, "unknown"),
    ({"product_name": "미확인액", "dosage_form": "액제"}, "unknown"),
    ({}, "unknown"),
    ({"product_name": "테스트주사", "administration_route": "경구"}, "unknown"),
])
def test_route_group_requires_evidence(data, expected):
    assert classify_medicine_use(data) == expected


def test_route_type_is_in_medicine_list_response():
    item = _medicine_item({
        "product_name": "테스트액", "administration_route": "eat",
        "usage": "하루 1회 환부에 바른다.",
    })
    assert item["use_route_type"] == "apply"
