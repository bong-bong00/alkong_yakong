from app.services.dur_sync_service import (
    _ingredient_query_terms,
    _item_mentions_ingredient,
)


def test_ingredient_query_terms_strip_dose():
    terms = _ingredient_query_terms(["암로디핀베실산염 5mg", "암로디핀"])
    assert "암로디핀베실산염 5mg" not in terms or "암로디핀" in terms
    assert "암로디핀" in terms


def test_item_mentions_ingredient():
    item = {"INGR_KOR_NAME": "암로디핀", "MIXTURE_INGR_KOR_NAME": "심바스타틴"}
    assert _item_mentions_ingredient(item, "암로디핀")
    assert not _item_mentions_ingredient(item, "에스암로디핀")
