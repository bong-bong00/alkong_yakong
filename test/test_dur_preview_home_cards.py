from app.database import get_connection
from app.models.schemas import DurAnalyzeRequest
from app.services.dur_service import (
    analyze_dur,
    preview_conflicts_for_codes,
)
from app.services.seed_mvp_medicines import MVP_USER_ID, ensure_mvp_demo_medicines
from app.services.today_medication_service import get_today_medicines

ADIPAM = "197800210"
CODARONE = "200701021"


def test_ocr_preview_flags_adipam_against_registered_codarone():
    ensure_mvp_demo_medicines()
    conflicts = preview_conflicts_for_codes(MVP_USER_ID, [ADIPAM])
    assert ADIPAM in conflicts
    other_names = " ".join(row["other_name"] for row in conflicts[ADIPAM])
    assert "코다론" in other_names
    assert any("심부정맥" in str(row.get("reason") or "") for row in conflicts[ADIPAM])


def test_preview_conflicts_do_not_save_risk_results():
    ensure_mvp_demo_medicines()
    conn = get_connection()
    before = conn.execute(
        "SELECT COUNT(*) AS n FROM risk_results WHERE user_id = ?",
        (MVP_USER_ID,),
    ).fetchone()["n"]
    conn.close()
    preview_conflicts_for_codes(MVP_USER_ID, [ADIPAM])
    conn = get_connection()
    after = conn.execute(
        "SELECT COUNT(*) AS n FROM risk_results WHERE user_id = ?",
        (MVP_USER_ID,),
    ).fetchone()["n"]
    conn.close()
    assert after == before


def test_home_puts_pair_caution_cards_first():
    ensure_mvp_demo_medicines()
    result = analyze_dur(
        DurAnalyzeRequest(user_id=MVP_USER_ID, medicine_codes=[ADIPAM, CODARONE]),
        persist=True,
        refresh=False,
    )
    assert result["has_risk"] is True
    try:
        today = get_today_medicines(MVP_USER_ID)
        cards = today["interaction_cards"]
        assert cards
        names = f"{cards[0]['name_a']} {cards[0]['name_b']}"
        assert "아디팜" in names
        assert "코다론" in names
        assert cards[0]["reason"]
        assert "함께 먹을 때 주의" in str(today.get("interaction_alert") or "")
    finally:
        conn = get_connection()
        conn.execute(
            "DELETE FROM risk_results WHERE id = ?",
            (result["risk_result_id"],),
        )
        conn.commit()
        conn.close()
