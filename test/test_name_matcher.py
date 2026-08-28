from app.services.matching.name_matcher import match_medicine_name


LEXICON = ["타이레놀정500밀리그램", "부루펜정200밀리그램(이부프로펜)", "게보린정"]


def test_exact_match():
    result = match_medicine_name("게보린정", LEXICON)
    assert result.method == "exact"
    assert result.matched_name == "게보린정"


def test_typo_not_auto_accepted():
    result = match_medicine_name("타이래놀", LEXICON)
    assert result.matched_name is None
    assert result.method == "none"
    assert result.score < 0.90


def test_empty_query():
    result = match_medicine_name("", LEXICON)
    assert result.matched_name is None
    assert result.method == "none"
