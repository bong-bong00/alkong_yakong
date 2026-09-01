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


def test_permission_db_has_full_list():
    stats = count_stats()
    assert stats["total"] >= 40000


def test_permission_db_finds_primalan():
    names = search_permission_names("프리마란", limit=5)
    assert any("프리마란" in name for name in names)
