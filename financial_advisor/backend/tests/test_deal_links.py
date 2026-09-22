from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock

import requests

from app import create_app
from cache.search_cache import SearchCache
from services.deal_service import DISABLED_MESSAGE, resolve_shop_link
from services.errors import InvoiceError
from services.serpapi_service import SerpApiService, merchant_url, normalize_offers
from tests.test_serpapi_service import Transport, envelope, row

TITLE = "Apple AirPods Pro 2 USB-C"
TOKEN = "opaqueGooglePageToken=="
SHOP_URL = "https://example.com/airpods-pro-2"


class DealTests(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.cache_path = Path(self.folder.name) / "prices.sqlite3"
        self.transport = Transport()
        self.shopping = SerpApiService(
            api_key="synthetic-test-key", cache=SearchCache(self.cache_path),
            session_factory=self.transport.session,
        )
        self.ai_service = Mock()
        self.app = create_app(
            ai_service=self.ai_service, shopping=self.shopping,
            recommendation_config={"SERPAPI_KEY": "synthetic-test-key"},
        )
        self.client = self.app.test_client()
        self.body = {
            "page_token": TOKEN, "store": "Example Saudi Store",
            "title": TITLE, "price": 749,
        }

    def tearDown(self):
        self.folder.cleanup()

    def assert_disabled(self, response):
        self.assertEqual(response.status_code, 410, response.json)
        self.assertEqual(response.json, {
            "success": False, "code": "shop_lookup_disabled", "error": DISABLED_MESSAGE,
        })
        self.assertEqual(response.headers["Cache-Control"], "no-store")
        self.assertNotIn("synthetic-test-key", response.get_data(as_text=True))
        self.assertNotIn("product_url", response.json)
        self.assertEqual(self.transport.calls, [])
        self.assertFalse(self.cache_path.exists())

    def test_normalized_offers_preserve_real_links_without_lookup_tokens(self):
        google = "https://www.google.com/shopping/product/123"
        direct = normalize_offers(envelope(row(
            product_link=google, link=SHOP_URL, immersive_product_page_token=TOKEN,
        )))[0]
        self.assertEqual(direct["product_url"], SHOP_URL)
        self.assertEqual(direct["link_kind"], "merchant")
        self.assertIsNone(direct["shop_lookup_token"])
        listing = normalize_offers(envelope(row(
            product_link=google, immersive_product_page_token=TOKEN,
        )))[0]
        self.assertEqual(listing["product_url"], google)
        self.assertEqual(listing["link_kind"], "shopping")
        self.assertIsNone(listing["shop_lookup_token"])
        self.assertEqual(self.transport.calls, [])

    def test_google_redirect_unwraps_public_shop_without_following_network(self):
        self.assertEqual(
            merchant_url("https://www.google.com/url?q=https%3A%2F%2Fexample.com%2Fproduct"),
            "https://example.com/product",
        )
        self.assertIsNone(merchant_url("https://www.google.com/url?q=http%3A%2F%2F127.0.0.1"))
        self.assertIsNone(merchant_url("https://www.google.com/shopping/product/123"))
        self.assertIsNone(merchant_url("https://example.com?api_key=secret"))
        self.assertEqual(self.transport.calls, [])

    def test_legacy_and_current_payloads_are_always_retired_without_network(self):
        bodies = [
            self.body,
            {"product_url": SHOP_URL, "title": TITLE, "store": "Example Saudi Store", "price": 749},
            {"product_url": "https://www.google.com/shopping/product/123", "shop_lookup_token": None},
            {},
        ]
        for body in bodies:
            for _ in range(2):
                with self.subTest(body=body):
                    self.assert_disabled(self.client.post("/api/recommendations/deal", json=body))
        self.ai_service.analyze.assert_not_called()
        self.ai_service.generate.assert_not_called()

    def test_unconfigured_provider_still_returns_retirement_without_access(self):
        self.shopping.api_key = ""
        self.assert_disabled(self.client.post("/api/recommendations/deal", json=self.body))

    def test_busy_search_slot_does_not_block_or_release_an_unrelated_search(self):
        slot = self.app.extensions["recommendation_search_slot"]
        self.assertTrue(slot.acquire(blocking=False))
        try:
            self.assert_disabled(self.client.post("/api/recommendations/deal", json=self.body))
            self.assertFalse(slot.acquire(blocking=False))
        finally:
            slot.release()
        self.assertTrue(slot.acquire(blocking=False))
        slot.release()

    def test_provider_failure_is_irrelevant_because_no_request_is_made(self):
        self.transport.error = requests.Timeout("URL?api_key=synthetic-test-key")
        self.assert_disabled(self.client.post("/api/recommendations/deal", json=self.body))

    def test_compatibility_service_does_not_inspect_provider_or_body(self):
        class NoAccess:
            def __getattribute__(self, name):
                raise AssertionError("Retired lookup accessed an argument")
        with self.assertRaises(InvoiceError) as caught:
            resolve_shop_link(NoAccess(), NoAccess())
        self.assertEqual(caught.exception.code, "shop_lookup_disabled")
        self.assertEqual(caught.exception.status, 410)

    def test_malformed_payloads_remain_bounded_and_never_spend_quota(self):
        invalid = [
            ('{"price":749,"price":1}', "application/json"),
            ('{"price":NaN}', "application/json"),
            ('{"price":', "application/json"),
            ('[]', "application/json"),
            ('null', "application/json"),
            ('"offer"', "application/json"),
            ('plain text', "text/plain"),
        ]
        for body, content_type in invalid:
            with self.subTest(body=body):
                response = self.client.post("/api/recommendations/deal", data=body,
                                            content_type=content_type)
                self.assertEqual(response.status_code, 400, response.json)
                self.assertEqual(response.json["code"], "invalid_deal")
        oversized = self.client.post("/api/recommendations/deal", data=" " * 25000,
                                     content_type="application/json")
        self.assertEqual(oversized.status_code, 413)
        self.assertEqual(self.transport.calls, [])
        self.assertFalse(self.cache_path.exists())

    def test_origin_protection_still_applies_to_retired_endpoint(self):
        denied = self.client.post("/api/recommendations/deal", json=self.body,
                                  headers={"Origin": "https://unrelated.example.com"})
        self.assertEqual(denied.status_code, 403)
        self.assertEqual(denied.json["code"], "forbidden_origin")
        allowed = self.client.post("/api/recommendations/deal", json=self.body,
                                   headers={"Origin": "http://localhost:60105"})
        self.assert_disabled(allowed)
        self.assertEqual(allowed.headers["Access-Control-Allow-Origin"], "http://localhost:60105")


if __name__ == "__main__":
    unittest.main()
