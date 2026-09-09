from app.services.mfds_drug_permission.db import (
    count_stats,
    search_permission_names,
    xml_doc_to_text,
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


def test_xml_article_title_to_text():
    raw = """
    <DOC title="효능효과" type="EE">
      <SECTION title="">
        <ARTICLE title="1. 수술 후, 신경증에서의 불안, 긴장, 초조" />
        <ARTICLE title="2. 두드러기, 피부질환에 수반하는 가려움(습진, 피부염, 피부가려움증)" />
      </SECTION>
    </DOC>
    """
    text = xml_doc_to_text(raw)
    assert "불안, 긴장, 초조" in text
    assert "두드러기" in text
    assert "효능효과" not in text


def test_xml_title_and_cdata_keep_official_wording():
    raw = """
    <DOC title="효능효과" type="EE">
      <SECTION title="">
        <ARTICLE title="">
          <PARAGRAPH><![CDATA[&nbsp;]]></PARAGRAPH>
        </ARTICLE>
        <ARTICLE title="다음 질환의 진통 및 해열시 단기치료:">
          <PARAGRAPH><![CDATA[- 두통, 치통]]></PARAGRAPH>
        </ARTICLE>
      </SECTION>
    </DOC>
    """
    text = xml_doc_to_text(raw)
    assert "다음 질환의 진통 및 해열시 단기치료:" in text
    assert "두통, 치통" in text
    assert "&nbsp;" not in text


def test_xml_strips_html_tags():
    raw = '<ARTICLE title="위&lt;sup&gt;.&lt;/sup&gt;십이지장궤양" />'
    text = xml_doc_to_text(raw)
    assert "위" in text
    assert "십이지장궤양" in text
    assert "<sup>" not in text
    assert "&lt;" not in text


def test_permission_db_has_full_list():
    stats = count_stats()
    assert stats["total"] >= 40000


def test_permission_db_finds_primalan():
    names = search_permission_names("프리마란", limit=5)
    assert any("프리마란" in name for name in names)
