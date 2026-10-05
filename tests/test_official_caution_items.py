from app.services.medicine_detail_service import _official_items

# 프리마란정(메퀴타진) 허가정보 "사용상의 주의사항" 앞부분. 목차 제목과
# 목차 밑 "○○ 환자" 조각이 내용보다 먼저 온다.
PRIMALAN_PRECAUTIONS = """사용상의주의사항
다음 환자에는 투여하지 말 것.
다음 환자에는 신중히 투여할 것.
이상반응
일반적 주의
상호작용
임부 및 수유부에 대한 투여
소아에 대한 투여
과량투여시의 처치
페노티아진계 약물 및 그 유사화합물에 과민반응 환자
녹내장환자(항콜린작용에 의함)
이 약은 유당을 함유하고 있으므로, 유전적인 문제가 있는 환자에게는 투여하면 안 된다.
과민반응 : 드물게 발진, 광민감반응 등이 나타날 수 있으므로 이러한 증상이 나타날 경우에는 투여를 중지한다.
기타 : 졸음이 올 수 있으므로 자동차운전 등 위험한 기계조작에 종사하지 않도록 주의한다.
"""


def test_official_cautions_skip_section_headings_and_bare_patient_groups():
    items = _official_items(PRIMALAN_PRECAUTIONS, limit=3)

    assert items == [
        "이 약은 유당을 함유하고 있으므로, 유전적인 문제가 있는 환자에게는 투여하면 안 된다.",
        "과민반응 : 드물게 발진, 광민감반응 등이 나타날 수 있으므로 이러한 증상이 나타날 경우에는 투여를 중지한다.",
        # 내용 앞에 붙은 목차 이름 "기타 :"는 뗀다.
        "졸음이 올 수 있으므로 자동차운전 등 위험한 기계조작에 종사하지 않도록 주의한다.",
    ]


def test_official_cautions_drop_list_pointers_markup_and_cut_fragments():
    text = (
        "이 약을 복용하는 동안 다음의 약(식품)을 복용하지 말 것.\n"
        "상담 시 가능한 한 이 첨부문서를 소지할 것.\n"
        "다음과 같은 사람은 이 약을 복용하지 말 것 2.\n"
        "다음 의약품의 작용이 증강될 위험성이 있다\n"
        "심혈관계 사망률 위험이 다른 약 투여 시보다\n"
        "습진, 옻 등에 의한 피부염, 상처부위\n"
        "고령자에 대한 투여(캡슐제에 한함.) 고령자는&nbsp;신중히 투여한다.\n"
    )

    assert _official_items(text, limit=3) == ["고령자는 신중히 투여한다."]


def test_heading_with_trailing_condition_is_still_a_heading():
    text = "적용상의 주의(주사제에 한함.)\n저장상의 주의사항\n다음과 같은 사람은 이 약을 복용하지 말 것.\n속이 쓰리면 복용을 멈추고 약사와 상의한다."

    assert _official_items(text, limit=3) == ["속이 쓰리면 복용을 멈추고 약사와 상의한다."]
