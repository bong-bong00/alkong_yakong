from unittest.mock import patch

from app.models.schemas import DrugExplainChatRequest
from app.routes.drug_explain import chat_with_pharmacist


def test_chat_forwards_current_medicines_without_reading_a_second_user_db():
    request = DrugExplainChatRequest(
        user_id="user-1",
        message="같이 먹어도 되나요?",
        intent="combination",
        selected_medicine={
            "medicine_code": "20000001",
            "product_name": "아디팜정",
        },
        current_medicines=[
            {
                "medicine_code": "20000001",
                "product_name": "아디팜정",
                "ingredient": "히드록시진염산염",
            },
            {
                "medicine_code": "20000002",
                "product_name": "코다론정",
                "ingredient": "아미오다론염산염",
            },
        ],
    )

    with patch("app.services.gemini_service.generate_chat_response", return_value="답변") as generate:
        assert chat_with_pharmacist(request) == {"reply": "답변"}

    assert generate.call_args.kwargs["current_medicines"] == [
        {
            "medicine_code": "20000001",
            "product_name": "아디팜정",
            "ingredient": "히드록시진염산염",
        },
        {
            "medicine_code": "20000002",
            "product_name": "코다론정",
            "ingredient": "아미오다론염산염",
        },
    ]


def test_combination_without_current_medicines_never_falls_back_to_team_db():
    from app.services.gemini_service import generate_chat_response

    reply = generate_chat_response(
        "같이 먹어도 되나요?",
        user_id="user-1",
        intent="combination",
        selected_medicine={
            "medicine_code": "20000001",
            "product_name": "아디팜정",
        },
        current_medicines=[],
    )

    assert "현재 복용약 목록을 불러오지 못해서" in reply
