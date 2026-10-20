from app.services.pharmacist.plain_language import explain_health_terms


def test_explanations_keep_original_terms_conditions_and_numbers():
    source = ("중증 저칼륨혈증 또는 저마그네슘혈증이 있으면 사용하지 마세요. "
              "QT 간격 연장 또는 Torsade de pointes 관련 안내를 확인하세요. 18세 미만은 제외합니다.")
    result = explain_health_terms(source)
    assert "중증 저칼륨혈증(혈액 속 칼륨이 부족한 상태)" in result
    assert "저마그네슘혈증(혈액 속 마그네슘이 부족한 상태)" in result
    assert "심장이 다음 박동을 준비하는 전기 신호의 시간이 길어지는 상태" in result
    assert "Torsade de pointes(" in result
    assert "사용하지 마세요" in result and "18세 미만은 제외합니다" in result
    assert explain_health_terms(result) == result


def test_existing_explanations_are_not_repeated():
    text = "저칼륨혈증(혈액 속 칼륨이 부족한 상태)이면 주의하세요."
    assert explain_health_terms(text) == text
    assert explain_health_terms("아디팜정은 술을 피해야 해요.") == "아디팜정은 술을 피해야 해요."


def test_qt_interval_is_not_double_explained_and_torsades_variant_supported():
    text = "QT 간격 연장과 Torsades de pointes를 확인하세요."
    result = explain_health_terms(text)
    assert result.count("다음 박동") == 1
    assert "Torsades de pointes(심장이 매우 빠르고 불규칙하게 뛰는 부정맥의 한 종류)" in result
