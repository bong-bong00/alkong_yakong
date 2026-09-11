from app.services.mfds_drug_permission.db import (
    count_stats,
    product_to_medicine,
    search_permission_names,
    xml_doc_to_text,
    xml_doc_section_to_text,
)


def test_xml_cdata_to_text():
    raw = """
    <DOC title="효능효과" type="EE">
      <SECTION title="">
        <ARTICLE title="">
          <PARAGRAPH><![CDATA[두드러기, 고초열, 알레르기 비염]]></PARAGRAPH>
        </ARTICLE>
      </SECTION>
    </DOC>
    """
    assert xml_doc_to_text(raw) == "두드러기, 고초열, 알레르기 비염"


def test_permission_documents_map_to_official_context_fields():
    row = {
        "item_seq": "1",
        "item_name": "공식약정",
        "ee_doc_data": '<DOC><SECTION><PARAGRAPH><![CDATA[공식 효능]]></PARAGRAPH></SECTION></DOC>',
        "ud_doc_data": '<DOC><SECTION><PARAGRAPH><![CDATA[공식 복용법]]></PARAGRAPH></SECTION></DOC>',
        "nb_doc_data": '<DOC><SECTION title="주의사항"><ARTICLE title="이상반응"><PARAGRAPH><![CDATA[공식 이상반응]]></PARAGRAPH></ARTICLE></SECTION></DOC>',
    }
    medicine = product_to_medicine(row)
    assert medicine["efficacy"] == "공식 효능"
    assert medicine["usage"] == "공식 복용법"
    assert "공식 이상반응" in medicine["cautions"]
    assert medicine["side_effects"] == "공식 이상반응"


def test_side_effects_require_an_explicit_official_section_title():
    raw = '<DOC><SECTION title="주의사항"><PARAGRAPH><![CDATA[일반 주의 원문]]></PARAGRAPH></SECTION></DOC>'
    assert xml_doc_section_to_text(raw, ("이상반응", "부작용")) == ""


def test_permission_db_has_full_list():
    stats = count_stats()
    assert stats["total"] >= 40000


def test_permission_db_finds_primalan():
    names = search_permission_names("프리마란", limit=5)
    assert any("프리마란" in name for name in names)
