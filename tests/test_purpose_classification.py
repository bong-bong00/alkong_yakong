import sqlite3

from init_db import TABLE_DEFINITIONS
from app.services.medicine_detail_service import (
    _build_profile,
    _parse_official_purposes,
    treatment_use_items,
)
from app.services.today_medication_service import _josa


def _titles(efficacy: str) -> list[str]:
    parsed = _parse_official_purposes(efficacy)
    return [
        use["title"]
        for use in treatment_use_items("", parsed["representative"], parsed["all"])
    ]


def test_aspirin_is_not_read_as_anxiety_blood_pressure_or_sugar_medicine():
    # "불안정형 협심증"의 "불안", 괄호 속 위험인자(고혈압·당뇨)를 쓰임으로 읽지 않는다.
    efficacy = (
        "다음 질환에서 혈전 생성 억제 · 심근경색 · 뇌경색 · 불안정형 협심증 "
        "2) 관상동맥 우회술 후 혈전 생성 억제 3) 고위험군환자(허혈성 심장질환의 "
        "가족력, 고혈압, 고콜레스테롤혈증, 비만, 당뇨 등 복합적 위험인자를 가진 환자)"
    )
    assert _titles(efficacy) == ["혈전 예방"]


def test_causes_listed_after_a_colon_are_not_uses():
    efficacy = (
        "울혈성심부전(폐부종 등 포함) : 판막질환, 고혈압, 허혈성심질환에 의한 것.\n"
        "심방세동·조동에 의한 빈맥\n"
        "기타 심질환, 갑상선기능항진증 및 저하증"
    )
    assert _titles(efficacy) == ["약해진 심장(심부전)", "빠르거나 불규칙한 심장 박동"]


def test_negated_condition_is_not_a_use():
    efficacy = "고혈압\n관상동맥심질환이 확인된 환자로 심부전이 없거나 심박출량이 40% 미만이 아닌 환자"
    assert _titles(efficacy) == ["높은 혈압"]


def test_uses_follow_the_order_the_label_mentions_them():
    efficacy = "우울증\n신경성 식욕과항진증\n월경전 불쾌장애"
    assert _titles(efficacy)[0] == "우울한 기분"


def test_raw_label_fragment_is_not_glued_into_ingredient_sentence():
    conn = sqlite3.connect(":memory:")
    conn.row_factory = sqlite3.Row
    for table in (
        "medicines",
        "ai_explanation_cards",
        "ingredient_explanations",
        "medicine_detail_profiles",
        "medicine_detail_jobs",
    ):
        conn.execute(TABLE_DEFINITIONS[table])
    profile = _build_profile(
        conn.cursor(),
        {
            "medicine_code": "T1",
            "product_name": "테스트정",
            "ingredient": "테스트성분",
            "efficacy": "말라리아(P.vivax)의 치료",
        },
    )
    assert "주성분이에요. 말라리아" not in (profile["ingredient_explanation"] or "")


def test_particles_follow_the_final_consonant():
    assert _josa("아디팜정", "과", "와") == "과"
    assert _josa("부루펜", "과", "와") == "과"
    assert _josa("코다론정", "은", "는") == "은"
    assert _josa("타이레놀", "은", "는") == "은"
    assert _josa("아스피린(장용)", "은", "는") == "은"
    assert _josa("게루사", "은", "는") == "는"
