from app.services.seed_mvp_medicines import MVP_USER_ID, ensure_mvp_demo_medicines
from app.services.today_medication_service import get_today_medicines
from app.services.user_medicines_service import (
    _interaction_for_medicine,
    get_user_medicine,
    get_user_medicines,
)


def test_user_medicines_one_row_per_medicine_code():
    ensure_mvp_demo_medicines()
    data = get_user_medicines(MVP_USER_ID)
    assert data["user_id"] == MVP_USER_ID
    assert data["has_medicines"] is True
    assert len(data["medicines"]) >= 3

    codes = [med["medicine_code"] for med in data["medicines"]]
    assert len(codes) == len(set(codes))

    names = [med["display_name"] for med in data["medicines"]]
    assert any("코다론" in name for name in names)
    assert any("부루펜" in name for name in names)
    assert any("게루삼" in name for name in names)

    active = [med for med in data["medicines"] if med["status"] == "active"]
    assert len(active) >= 3
    for med in active:
        assert med.get("purpose_label")
        assert med.get("short_explanation")
        assert med.get("amount") == "1알"
        assert med.get("frequency_per_day") == 3
        assert isinstance(med.get("administration_times"), list)


def test_user_medicine_detail_matches_list_item():
    ensure_mvp_demo_medicines()
    listing = get_user_medicines(MVP_USER_ID)
    sample = listing["medicines"][0]
    code = sample["medicine_code"]

    detail = get_user_medicine(MVP_USER_ID, code)
    med = detail["medicine"]
    assert med["medicine_code"] == code
    assert med["display_name"] == sample["display_name"]
    assert med["short_explanation"] == sample["short_explanation"]
    assert med["purpose_label"] == sample["purpose_label"]
    assert isinstance(med.get("easy_purposes"), list)
    assert isinstance(med.get("key_cautions"), list)


def test_user_medicines_matches_home_card_guidance():
    ensure_mvp_demo_medicines()
    medicines = get_user_medicines(MVP_USER_ID)["medicines"]
    today = get_today_medicines(MVP_USER_ID)
    home_by_code = {
        med["medicine_code"]: med
        for dose in today["doses"]
        for med in dose["medicines"]
        if med.get("medicine_code")
    }
    for med in medicines:
        code = med["medicine_code"]
        if code not in home_by_code:
            assert med["status"] == "past"
            continue
        home = home_by_code[code]
        assert med["display_name"] == home["display_name"]
        assert med["short_explanation"] == home["short_explanation"]
        assert med["purpose_label"] == home["purpose_label"]


def test_mvp_user_has_birth_date_and_multiple_key_cautions():
    ensure_mvp_demo_medicines()
    from app.database import get_connection
    from app.services.pharmacist.easy_category import backfill_all_medicine_guidance

    backfill_all_medicine_guidance()
    conn = get_connection()
    try:
        user = conn.execute(
            "SELECT birth_date FROM users WHERE id = ?", (MVP_USER_ID,)
        ).fetchone()
        assert user["birth_date"]
        caution_codes = conn.execute(
            """
            SELECT DISTINCT um.medicine_code
            FROM user_medicines um
            JOIN medicine_key_cautions kc ON kc.medicine_code = um.medicine_code
            WHERE um.user_id = ? AND COALESCE(um.is_active, 1) = 1
            """,
            (MVP_USER_ID,),
        ).fetchall()
        assert len(caution_codes) >= 3
    finally:
        conn.close()


def test_interaction_summary_distinguishes_risk_incomplete_and_none():
    medicine = {
        "product_name": "아디팜정(히드록시진염산염)",
        "ingredient": "히드록시진염산염",
        "created_at": "2026-09-01",
    }
    risk = _interaction_for_medicine(
        medicine,
        {
            "created_at": "2026-09-11",
            "assessment_status": "RISK_FOUND",
            "risk_level": "HIGH",
            "matches": [
                {
                    "medicine_names_a": ["아디팜정(히드록시진염산염)"],
                    "medicine_names_b": ["코다론정"],
                    "reason": "함께 먹으면 안 되는 조합이에요.",
                }
            ],
        },
    )
    assert risk["interaction_status"] == "risk_found"
    assert "안 되는" in risk["interaction_summary"]
    assert risk["interaction_risk_level"] == "HIGH"
    assert risk["interaction_conflict_names"] == ["코다론정"]

    incomplete = _interaction_for_medicine(
        medicine,
        {
            "created_at": "2026-09-11",
            "assessment_status": "INCOMPLETE",
            "description": "최신 기준을 전부 확인하지 못했어요.",
            "matches": [],
        },
    )
    assert incomplete["interaction_status"] == "check_needed"

    safe = _interaction_for_medicine(
        medicine,
        {
            "created_at": "2026-09-11",
            "assessment_status": "SAFE",
            "matches": [],
        },
    )
    assert safe["interaction_status"] == "none"
