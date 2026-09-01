from app.services.pharmacist import suggestions as suggestions_mod
from app.services.pharmacist.suggestions import get_chat_suggestions


def test_empty_query_returns_faq_chips():
    items = get_chat_suggestions("")
    labels = [item["label"] for item in items]
    assert "지금 먹을 약" in labels
    assert "이 약 설명" in labels


def test_ty_prefix_returns_tylenol_related(monkeypatch):
    monkeypatch.setattr(
        suggestions_mod,
        "_official_names",
        lambda query: ["타이레놀정500밀리그램", "타이레놀8시간이알서방정"],
    )
    items = get_chat_suggestions("타이")
    labels = [item["label"] for item in items]
    assert "타이레놀정500밀리그램" in labels
    assert "타이레놀 이 약 설명" in labels
    assert "타이레놀 같이 먹으면" in labels


def test_fallback_official_names_when_api_empty(monkeypatch):
    def boom(*args, **kwargs):
        raise RuntimeError("offline")

    monkeypatch.setattr(suggestions_mod, "search_drug_info_by_name", boom)
    suggestions_mod._official_cache.clear()
    items = get_chat_suggestions("타이")
    labels = [item["label"] for item in items]
    assert "타이레놀정500밀리그램" in labels


def test_senior_symptom_fever_maps_to_tylenol(monkeypatch):
    monkeypatch.setattr(
        suggestions_mod,
        "_official_names",
        lambda query: ["타이레놀정500밀리그램"] if "타이레놀" in query else [],
    )
    items = get_chat_suggestions("열나")
    labels = [item["label"] for item in items]
    assert "타이레놀정500밀리그램" in labels
    assert "이 약 설명" in labels


def test_senior_typo_maps_to_tylenol(monkeypatch):
    monkeypatch.setattr(
        suggestions_mod,
        "_official_names",
        lambda query: ["타이레놀정500밀리그램"] if "타이레놀" in query else [],
    )
    items = get_chat_suggestions("타이래")
    labels = [item["label"] for item in items]
    assert "타이레놀정500밀리그램" in labels


def test_senior_forgot_dose_faq():
    items = get_chat_suggestions("깜빡")
    labels = [item["label"] for item in items]
    assert "안 먹었을 때" in labels


def test_senior_together_faq():
    items = get_chat_suggestions("같이먹")
    labels = [item["label"] for item in items]
    assert "같이 먹으면" in labels


def test_chosung_tylenol(monkeypatch):
    monkeypatch.setattr(
        suggestions_mod,
        "_official_names",
        lambda query: ["타이레놀정500밀리그램"]
        if query.replace(" ", "") in {"ㅌㄹㄴ", "ㅌㅇㄹㄴ", "타이레놀"}
        else [],
    )
    items = get_chat_suggestions("ㅌㄹㄴ")
    labels = [item["label"] for item in items]
    assert "타이레놀정500밀리그램" in labels


def test_chosung_brufen_hint(monkeypatch):
    monkeypatch.setattr(
        suggestions_mod,
        "_official_names",
        lambda query: ["부루펜정200밀리그램(이부프로펜)"] if "부루펜" in query else [],
    )
    items = get_chat_suggestions("ㅂㄹㅍ")
    labels = [item["label"] for item in items]
    assert any("부루펜" in label for label in labels)
