import io
import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock, patch

from PIL import Image

from app import create_app
from config import load_settings
from services.errors import InvoiceError
from services.invoice_service import normalize_invoice
from services.product_recognition_service import PRODUCT_SCHEMA, PRODUCT_PROMPT, reviewed_products
from ollama_config import get_ollama_config
from services.ollama_service import OllamaService


def photo():
    data = io.BytesIO()
    Image.new("RGB", (80, 120), "white").save(data, format="PNG")
    return data.getvalue()


def product():
    return {
        "id": "airpods", "name": "Apple AirPods Pro 2 USB-C", "brand": "Apple",
        "model": "AirPods Pro 2", "variant": "USB-C", "category": "Shopping",
        "confidence": .95, "quantity": 1, "unit_price": 849, "total_price": 849,
    }


def invoice():
    return {"merchant_name": "Receipt Store", "date": "2026-09-08", "currency": "SAR",
            "subtotal": 849, "tax": 0, "discount": 0, "total": 849,
            "category": "Shopping", "items": [product()]}


class RecommendationApiTests(unittest.TestCase):
    def setUp(self):
        self.environment = patch.dict(os.environ, {"SERPAPI_KEY": ""})
        self.environment.start()
        self.addCleanup(self.environment.stop)
        self.ollama = Mock()
        self.ollama.generate.return_value = json.dumps(product())
        self.ollama.analyze.return_value = json.dumps(invoice())
        self.shopping = Mock()
        self.shopping.search_products.return_value = {
            "offers": [{
                "title": "Apple AirPods Pro 2 USB-C", "store": "Example Store",
                "price": 749, "currency": "SAR", "rating": 4.8, "reviews": 50,
                "product_url": "https://shop.example.com/airpods",
                "image_url": None, "availability": None, "shipping": None,
            }],
            "cached": False, "fetched_at": "2026-09-08T12:00:00+00:00", "query": "test",
        }
        self.app = create_app(ollama=self.ollama, shopping=self.shopping)
        self.app.config["TESTING"] = True
        self.client = self.app.test_client()

    def upload(self, mode="product", **kwargs):
        return self.client.post(
            f"/api/recommendations/{mode}",
            data={"image": (io.BytesIO(photo()), "photo.png"), **kwargs},
            content_type="multipart/form-data",
        )

    def search(self, mode="product", **changes):
        body = {"confirmed": True, "products": [product()]}
        if mode == "invoice":
            body["invoice"] = invoice()
        body.update(changes)
        return self.client.post(f"/api/recommendations/{mode}", json=body)

    def test_product_image_returns_review_without_spending_search_quota(self):
        response = self.upload(optional_current_price="849")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json["stage"], "review")
        self.assertEqual(response.json["products"][0]["variant"], "USB-C")
        self.assertEqual(response.json["products"][0]["unit_price"], 849)
        self.ollama.generate.assert_called_once()
        self.shopping.search_products.assert_not_called()

    def test_recognition_does_not_assume_new_condition_from_appearance(self):
        self.ollama.generate.return_value = json.dumps({**product(), "condition": "new"})
        response = self.upload()
        self.assertIsNone(response.json["products"][0]["condition"])
        receipt = invoice()
        receipt["items"][0]["condition"] = "new"
        self.ollama.analyze.return_value = json.dumps(receipt)
        self.assertIsNone(self.upload("invoice").json["invoice"]["items"][0]["condition"])
        reviewed = reviewed_products([{**product(), "condition": "new"}], "product")
        self.assertEqual(reviewed[0]["condition"], "new")

    def test_invoice_recognition_reuses_existing_invoice_service_and_metadata(self):
        response = self.upload("invoice")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json["invoice"]["total"], 849)
        self.assertEqual(response.json["products"][0]["brand"], "Apple")
        self.assertEqual(response.json["invoice"]["items"][0]["model"], "AirPods Pro 2")
        self.ollama.analyze.assert_called_once()
        self.ollama.generate.assert_not_called()
        self.shopping.search_products.assert_not_called()

    def test_confirmed_product_runs_real_comparison_without_another_model_call(self):
        response = self.search()
        self.assertEqual(response.status_code, 200, response.json)
        self.assertEqual(response.json["stage"], "results")
        self.assertEqual(response.json["summary"]["potential_savings"], 100)
        self.assertEqual(response.json["recommendations"][0]["best_offer"]["currency"], "SAR")
        self.shopping.search_products.assert_called_once()
        self.ollama.generate.assert_not_called()
        self.ollama.analyze.assert_not_called()

    def test_confirmed_invoice_preserves_invoice_total_and_comparable_subset(self):
        source = invoice()
        source["tax"] = 127.35
        source["total"] = 976.35
        response = self.search("invoice", invoice=source)
        self.assertEqual(response.status_code, 200, response.json)
        self.assertEqual(response.json["summary"]["original_total"], 976.35)
        self.assertEqual(response.json["summary"]["comparable_original_total"], 849)
        self.assertEqual(response.json["summary"]["potential_savings"], 100)

    def test_invoice_multiple_items_share_one_search_and_each_get_two_cards(self):
        lamp = {"id": "lamp", "name": "Acme Desk Lamp", "brand": "Acme", "model": "Desk Lamp", "quantity": 2, "unit_price": 100, "total_price": 200}
        pool = self.shopping.search_products.return_value["offers"]
        pool.extend([
            {**pool[0], "price": 779, "store": "Second shop"},
            {**pool[0], "price": 799, "store": "Third shop"},
            {**pool[0], "title": "Acme Desk Lamp", "price": 70, "store": "Lamp shop"},
            {**pool[0], "title": "Acme Desk Lamp", "price": 80, "store": "Second lamp shop"},
            {**pool[0], "title": "Acme Desk Lamp", "price": 90, "store": "Third lamp shop"},
        ])
        source = invoice()
        source.update(items=[product(), lamp], subtotal=1049, total=1049)
        response = self.search("invoice", products=[product(), lamp], invoice=source)
        self.assertEqual(response.status_code, 200, response.json)
        self.shopping.search_products.assert_called_once()
        query = self.shopping.search_products.call_args.args[0]
        self.assertEqual(query, '"acme desk lamp" OR "apple airpods pro 2 usb-c"')
        self.assertEqual([[offer["extracted_price"] for offer in item["offers"]] for item in response.json["recommendations"]], [[749, 779], [70, 80]])
        self.assertEqual(response.json["summary"]["potential_savings"], 160)
        self.assertIn("combined_search_limited_coverage", response.json["warnings"])
        self.ollama.generate.assert_not_called()
        self.ollama.analyze.assert_not_called()

    def test_oversized_combined_list_returns_actionable_400_without_search(self):
        items = [{"id": str(index), "name": f"Acme item {index} " + "x" * 300, "quantity": 1} for index in range(30)]
        response = self.client.post("/api/recommendations/shopping-list", json={"confirmed": True, "products": items})
        self.assertEqual(response.status_code, 400, response.json)
        self.assertEqual(response.json["code"], "combined_query_too_long")
        self.assertIn("Shorten", response.json["error"])
        self.shopping.search_products.assert_not_called()
        # The rejected request must not leave the shared search slot locked.
        self.assertEqual(self.search().status_code, 200)
        self.shopping.search_products.assert_called_once()

    def test_review_confirmation_and_valid_payload_required_before_any_search(self):
        for body in (
            {"products": [product()]},
            {"confirmed": "true", "products": [product()]},
            {"confirmed": True, "products": []},
            {"confirmed": True, "products": [product(), product()]},
            {"confirmed": True, "products": [{**product(), "unit_price": -1}]},
        ):
            with self.subTest(body=body):
                response = self.client.post("/api/recommendations/product", json=body)
                self.assertEqual(response.status_code, 400)
        self.shopping.search_products.assert_not_called()

    def test_duplicate_json_and_nonfinite_values_are_rejected(self):
        for data in ('{"confirmed":true,"confirmed":false,"products":[]}',
                     '{"confirmed":true,"products":[],"bad":NaN}'):
            response = self.client.post("/api/recommendations/product",
                                        data=data, content_type="application/json")
            self.assertEqual(response.status_code, 400)
        self.shopping.search_products.assert_not_called()

    def test_foreign_currency_cannot_be_compared_as_sar(self):
        source = invoice()
        source["currency"] = "USD"
        response = self.search("invoice", invoice=source)
        self.assertEqual(response.status_code, 422)
        self.assertEqual(response.json["code"], "unsupported_currency")
        self.shopping.search_products.assert_not_called()

    def test_recommendation_origin_policy_and_safe_headers(self):
        response = self.client.post(
            "/api/recommendations/product", json={"confirmed": True, "products": [product()]},
            headers={"Origin": "https://unrelated.example"},
        )
        self.assertEqual(response.status_code, 403)
        self.shopping.search_products.assert_not_called()
        response = self.client.options(
            "/api/recommendations/product",
            headers={"Origin": "http://localhost:60105", "Access-Control-Request-Method": "POST",
                     "Access-Control-Request-Headers": "content-type"},
        )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.headers["Access-Control-Allow-Origin"], "http://localhost:60105")
        self.assertEqual(response.headers["Cache-Control"], "no-store")

    def test_model_slot_is_shared_and_released_after_failed_recognition(self):
        slot = self.app.extensions["invoice_analysis_slot"]
        slot.acquire()
        try:
            self.assertEqual(self.upload().json["code"], "server_busy")
        finally:
            slot.release()
        self.ollama.generate.side_effect = InvoiceError("analysis_timeout", "Timed out", 504)
        self.assertEqual(self.upload().status_code, 504)
        self.assertTrue(slot.acquire(blocking=False))
        slot.release()

    def test_search_slot_is_released_when_service_fails(self):
        service = Mock()
        service.recommend.side_effect = InvoiceError("serpapi_not_configured", "Set the backend key.", 503)
        self.app.extensions["recommendation_service"] = service
        self.assertEqual(self.search().status_code, 503)
        slot = self.app.extensions["recommendation_search_slot"]
        self.assertTrue(slot.acquire(blocking=False))
        slot.release()

    def test_status_reports_configuration_without_credentials_or_network(self):
        response = self.client.get("/api/recommendations/status")
        self.assertEqual(response.status_code, 200)
        self.assertFalse(response.json["configured"])
        self.assertEqual(response.json["max_searches"], 1)
        self.assertEqual(response.json["search_strategy"], "combined")
        self.assertEqual(response.json["max_offers_per_item"], 2)
        self.assertNotIn("SERPAPI_KEY", response.get_data(as_text=True))
        self.shopping.search_products.assert_not_called()

    def test_unidentified_product_and_invalid_image_do_not_search(self):
        self.ollama.generate.return_value = '{"name":null}'
        self.assertEqual(self.upload().json["code"], "unidentified_product")
        response = self.client.post("/api/recommendations/product",
                                    data={"image": (io.BytesIO(b"bad"), "bad.png")})
        self.assertEqual(response.json["code"], "invalid_image")
        self.shopping.search_products.assert_not_called()


class ProductMetadataTests(unittest.TestCase):
    def test_legacy_invoice_item_remains_valid_and_new_attributes_optional(self):
        original = invoice()
        original["items"] = [{"name": "Coffee", "quantity": 1, "unit_price": 10,
                              "total_price": 10, "category": "Food"}]
        result, _ = normalize_invoice(original)
        item = result["items"][0]
        self.assertEqual(item["name"], "Coffee")
        self.assertIsNone(item["brand"])
        self.assertIsNone(item["size_value"])
        self.assertIsNone(item["confidence"])

    def test_visible_metadata_normalizes_without_guessing(self):
        original = invoice()
        original["items"][0].update(size_value="٢", size_unit="لتر", pack_size=6,
                                     confidence=.93, condition="used")
        result, _ = normalize_invoice(original)
        item = result["items"][0]
        self.assertEqual((item["size_value"], item["size_unit"], item["pack_size"]), (2, "l", 6))
        self.assertEqual(item["confidence"], .93)
        self.assertEqual(item["condition"], "used")

    @patch("services.ollama_service.requests.Session")
    def test_product_and_invoice_share_private_vision_transport(self, session_class):
        session = session_class.return_value.__enter__.return_value
        response = session.post.return_value.__enter__.return_value
        response.status_code = 200
        response.iter_content.return_value = [json.dumps({
            "done": True, "message": {"content": json.dumps(product())},
        }).encode()]
        config = get_ollama_config("runpod")
        OllamaService(config=config).generate(b"photo", PRODUCT_SCHEMA, PRODUCT_PROMPT, "Identify")
        args, kwargs = session.post.call_args
        self.assertEqual(args[0], config.chat_url)
        self.assertEqual(kwargs["json"]["model"], config.model)
        self.assertEqual(kwargs["json"]["format"], PRODUCT_SCHEMA)
        self.assertFalse(session.trust_env)
        self.assertFalse(kwargs["allow_redirects"])


class RecommendationConfigTests(unittest.TestCase):
    def test_backend_dotenv_and_environment_precedence(self):
        with tempfile.TemporaryDirectory() as directory:
            Path(directory, ".env").write_text("SERPAPI_KEY=example-private-key\nPRICE_CACHE_TTL_SECONDS=21600\n")
            with patch("config.BACKEND_DIR", Path(directory)), patch.dict(os.environ, {}, clear=True):
                values = load_settings()
                self.assertEqual(values["SERPAPI_KEY"], "example-private-key")
                self.assertEqual(values["PRICE_CACHE_TTL_SECONDS"], 21600)
                with patch.dict(os.environ, {"SERPAPI_KEY": "environment-key"}):
                    self.assertEqual(load_settings()["SERPAPI_KEY"], "environment-key")

    def test_invalid_or_unsafe_settings_fail_without_echoing_values(self):
        for override in (
            {"PRICE_CACHE_TTL_SECONDS": -1},
            {"RECOMMENDATION_MAX_SEARCHES": 201},
            {"RECOMMENDATION_MIN_MATCH_SCORE": .1},
            {"RECOMMENDATION_GOOD_SAVING_PERCENTAGE": 30, "RECOMMENDATION_EXCELLENT_SAVING_PERCENTAGE": 20},
            {"SERPAPI_LANGUAGE": "invalid"},
        ):
            with self.subTest(override=override), self.assertRaises(ValueError):
                load_settings(override)


if __name__ == "__main__":
    unittest.main()

