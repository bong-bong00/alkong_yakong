import unittest
from unittest.mock import patch

import requests
from fastapi import HTTPException

from app.routes.drug_explain import search_official_drugs
from app.services import external_api_service


def _item(name: str, manufacturer: str, sequence: str) -> dict:
    return {"itemName": name, "entpName": manufacturer, "itemSeq": sequence}


class DrugCandidateSearchTest(unittest.TestCase):
    def search(self, query: str, items: list[dict]) -> dict:
        with (
            patch.object(external_api_service, "E_DRUG_API_KEY", "test-key"),
            patch.object(
                external_api_service,
                "_request_drug_items",
                return_value=items,
            ) as request_items,
        ):
            result = external_api_service.search_drug_candidates(query)
        request_items.assert_called_once_with(query, page_no=1, num_of_rows=16)
        return result

    def test_gevourin_returns_multiple_official_candidates(self):
        result = self.search(
            "게보",
            [
                _item("게보린릴랙스연질캡슐", "제조사B", "2"),
                _item("게보린정", "삼진제약(주)", "1"),
                _item("게보린소프트연질캡슐", "제조사C", "3"),
            ],
        )
        self.assertEqual(result["count"], 3)
        self.assertEqual(
            [item["item_name"] for item in result["items"]],
            ["게보린정", "게보린릴랙스연질캡슐", "게보린소프트연질캡슐"],
        )

    def test_acamprosate_returns_multiple_official_candidates(self):
        result = self.search(
            "아캄",
            [
                _item("환인아캄프로세이트정", "환인제약", "10"),
                _item("명인아캄프로세이트정333mg", "명인제약", "11"),
            ],
        )
        self.assertEqual(result["count"], 2)
        self.assertEqual(
            {item["item_name"] for item in result["items"]},
            {"환인아캄프로세이트정", "명인아캄프로세이트정333mg"},
        )

    def test_one_character_is_rejected_before_external_request(self):
        with (
            patch.object(external_api_service, "E_DRUG_API_KEY", "test-key"),
            patch.object(external_api_service, "_request_drug_items") as request_items,
            self.assertRaises(HTTPException) as raised,
        ):
            external_api_service.search_drug_candidates("게")
        self.assertEqual(raised.exception.status_code, 422)
        request_items.assert_not_called()

    def test_blank_query_is_rejected(self):
        with self.assertRaises(HTTPException) as raised:
            search_official_drugs("  ")
        self.assertEqual(raised.exception.status_code, 422)

    def test_no_official_result_returns_empty_items(self):
        result = self.search("없는약", [])
        self.assertEqual(result, {"query": "없는약", "count": 0, "items": []})

    def test_candidate_results_are_limited_to_eight(self):
        result = self.search(
            "테스트",
            [
                _item(f"테스트약{i}정", f"제조사{i}", str(i))
                for i in range(10)
            ],
        )
        self.assertEqual(result["count"], 8)
        self.assertEqual(len(result["items"]), 8)

    def test_timeout_is_mapped_to_safe_gateway_timeout(self):
        with (
            patch.object(external_api_service, "E_DRUG_API_KEY", "test-key"),
            patch.object(
                external_api_service,
                "_request_drug_items",
                side_effect=requests.Timeout,
            ),
            self.assertRaises(HTTPException) as raised,
        ):
            external_api_service.search_drug_candidates("게보")
        self.assertEqual(raised.exception.status_code, 504)

    def test_exact_product_name_wins_over_similar_products(self):
        items = [
            _item("게보린릴랙스연질캡슐", "제조사B", "2"),
            _item("게보린정", "삼진제약(주)", "1"),
        ]
        with (
            patch.object(external_api_service, "E_DRUG_API_KEY", "test-key"),
            patch.object(
                external_api_service,
                "_request_drug_items",
                return_value=items,
            ),
        ):
            result = external_api_service.search_drug_info_by_name("게보린정")

        self.assertEqual(result["match_type"], "exact")
        self.assertEqual(
            [item["product_name"] for item in result["items"]],
            ["게보린정"],
        )

    def test_main_product_name_only_contract_is_preserved(self):
        items = [
            _item("게보린정", "삼진제약(주)", "1"),
            _item("게보린릴랙스연질캡슐", "제조사B", "2"),
        ]
        with (
            patch.object(external_api_service, "E_DRUG_API_KEY", "test-key"),
            patch.object(
                external_api_service,
                "_request_drug_items",
                return_value=items,
            ) as request_items,
        ):
            result = external_api_service.search_drug_info_by_name(
                "게보린",
                product_name_only=True,
            )

        request_items.assert_called_once_with("게보린", page_no=1, num_of_rows=10)
        self.assertEqual(result["match_type"], "product_name")
        self.assertEqual(result["count"], 2)

    def test_unique_best_rank_is_selected_over_lower_rank_candidates(self):
        items = [
            _item("게보린정", "삼진제약(주)", "1"),
            _item("게보린릴랙스연질캡슐", "제조사B", "2"),
            _item("게보린소프트연질캡슐", "제조사C", "3"),
        ]
        with (
            patch.object(external_api_service, "E_DRUG_API_KEY", "test-key"),
            patch.object(
                external_api_service,
                "_request_drug_items",
                return_value=items,
            ),
        ):
            result = external_api_service.search_drug_info_by_name("게보린")

        self.assertEqual(result["match_type"], "partial")
        self.assertEqual(
            [item["product_name"] for item in result["items"]],
            ["게보린정"],
        )

    def test_equal_best_rank_candidates_are_ambiguous(self):
        items = [
            _item("환인아캄프로세이트정", "환인제약", "10"),
            _item("명인아캄프로세이트정333mg", "명인제약", "11"),
        ]
        with (
            patch.object(external_api_service, "E_DRUG_API_KEY", "test-key"),
            patch.object(
                external_api_service,
                "_request_drug_items",
                side_effect=[[], items],
            ),
        ):
            result = external_api_service.search_drug_info_by_name(
                "아캄프로세이트정"
            )

        self.assertEqual(result["match_type"], "ambiguous")
        self.assertEqual(result["count"], 2)


if __name__ == "__main__":
    unittest.main()
