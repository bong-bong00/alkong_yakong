import sqlite3
from unittest.mock import MagicMock, patch

from app.services import dur_sync_service
from app.services.dur_sync_service import (
    _ingredient_query_terms,
    _item_mentions_ingredient,
)


def test_ingredient_query_terms_strip_dose():
    terms = _ingredient_query_terms(["암로디핀베실산염 5mg", "암로디핀"])
    assert "암로디핀베실산염 5mg" not in terms or "암로디핀" in terms
    assert "암로디핀" in terms


def test_ingredient_query_terms_include_every_compound_component():
    terms = _ingredient_query_terms(["성분A|성분B|성분C"])
    assert "성분A" in terms
    assert "성분B" in terms
    assert "성분C" in terms


def test_item_mentions_ingredient():
    item = {"INGR_KOR_NAME": "암로디핀", "MIXTURE_INGR_KOR_NAME": "심바스타틴"}
    assert _item_mentions_ingredient(item, "암로디핀")
    assert not _item_mentions_ingredient(item, "에스암로디핀")


def test_forced_refresh_limits_types_and_accepts_successful_zero_results():
    conn = sqlite3.connect(":memory:")
    conn.row_factory = sqlite3.Row
    with (
        patch.object(dur_sync_service, "DUR_API_KEY", "test-key"),
        patch.object(dur_sync_service, "DUR_AUTO_SYNC", True),
        patch.object(dur_sync_service, "get_connection", return_value=conn),
        patch.object(
            dur_sync_service,
            "_sync_ingredient_type",
            return_value={"fetched": 0, "upserted": 0, "error": None},
        ) as sync,
    ):
        result = dur_sync_service.refresh_dur_for_ingredients(
            ["성분C"], risk_types={"연령금기"}, force_refresh=True
        )
    assert result["status"] == "ok"
    assert {call.args[1] for call in sync.call_args_list} == {"연령금기"}


def test_forced_refresh_reports_any_requested_type_failure():
    conn = sqlite3.connect(":memory:")
    conn.row_factory = sqlite3.Row
    with (
        patch.object(dur_sync_service, "DUR_API_KEY", "test-key"),
        patch.object(dur_sync_service, "DUR_AUTO_SYNC", True),
        patch.object(dur_sync_service, "get_connection", return_value=conn),
        patch.object(
            dur_sync_service,
            "_sync_ingredient_type",
            return_value={"fetched": 0, "upserted": 0, "error": "unavailable"},
        ),
    ):
        result = dur_sync_service.refresh_dur_for_ingredients(
            ["성분C"], risk_types={"연령금기"}, force_refresh=True
        )
    assert result["status"] == "failed"


def test_operation_uses_official_ingredient_query_parameter():
    expected = {
        "병용금기": ("getUsjntTabooInfoList02", "ingrKorName"),
        "연령금기": ("getSpcifyAgrdeTabooInfoList02", "ingrName"),
        "임부금기": ("getPwnmTabooInfoList02", "ingrName"),
        "효능군중복": ("getEfcyDplctInfoList02", "ingrName"),
    }

    for risk_type, (operation, parameter) in expected.items():
        with patch.object(
            dur_sync_service,
            "_fetch_page",
            return_value=([], 0),
        ) as fetch:
            result = dur_sync_service._sync_ingredient_type(
                MagicMock(),
                risk_type,
                query="테스트성분",
                api_key="test-key",
            )

        assert result == {"fetched": 0, "upserted": 0, "error": None}
        fetch.assert_called_once()
        assert fetch.call_args.args[0] == operation
        assert fetch.call_args.kwargs["extra_params"] == {
            parameter: "테스트성분"
        }
        assert "INGR_KOR_NAME" not in fetch.call_args.kwargs["extra_params"]


def test_zero_results_do_not_retry_with_non_official_parameter():
    with patch.object(
        dur_sync_service,
        "_fetch_page",
        return_value=([], 0),
    ) as fetch:
        result = dur_sync_service._sync_ingredient_type(
            MagicMock(),
            "임부금기",
            query="테스트성분",
            api_key="test-key",
        )

    assert result == {"fetched": 0, "upserted": 0, "error": None}
    fetch.assert_called_once()
    assert fetch.call_args.kwargs["extra_params"] == {"ingrName": "테스트성분"}
