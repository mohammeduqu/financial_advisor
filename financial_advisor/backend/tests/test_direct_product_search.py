from contextlib import closing
import json
from pathlib import Path
import sqlite3
import tempfile
import unittest
from unittest.mock import Mock

import requests

from app import create_app
from cache.search_cache import SearchCache, query_key
from services.errors import InvoiceError
from services.serpapi_service import (
    MAX_OFFERS, SerpApiService, direct_query_key, direct_search_parameters,
    normalize_listings, safe_image_url, safe_public_url,
)
from tests.test_serpapi_service import Response, Transport, envelope, row


class DirectProductSearchTests(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.path = Path(self.folder.name) / "searches.sqlite3"
        self.cache = SearchCache(self.path)

    def tearDown(self):
        self.folder.cleanup()

    def service(self, transport=None, key="synthetic-test-key"):
        transport = transport or Transport()
        service = SerpApiService(api_key=key, cache=self.cache, session_factory=transport.session)
        return service, transport

    def client(self, service):
        ai = Mock()
        app = create_app(
            ai_service=ai, shopping=service,
            recommendation_config={"SERPAPI_KEY": "synthetic-test-key"},
        )
        app.extensions["recommendation_service"] = Mock()
        return app.test_client(), app, ai

    def test_saudi_arabic_defaults_and_one_direct_provider_request(self):
        service, transport = self.service()
        client, app, ai = self.client(service)
        response = client.post("/api/recommendations/search", json={"q": " tea "})
        self.assertEqual(response.status_code, 200, response.json)
        self.assertEqual(transport.calls[0][1]["params"], {
            "engine": "google_shopping", "q": "tea", "api_key": "synthetic-test-key",
            "gl": "sa", "google_domain": "google.com.sa", "location": "Saudi Arabia",
            "hl": "ar",
        })
        self.assertEqual(len(transport.calls), 1)
        self.assertEqual(response.json["summary"], {"total_results": 1})
        self.assertTrue(response.json["direct_search"])
        self.assertEqual(response.json["recommendations"], [])
        self.assertEqual(response.json["query"], "tea")
        self.assertEqual(response.json["search_parameters"]["gl"], "sa")
        self.assertIsNone(response.json["search_parameters"]["max_price"])
        self.assertNotIn("sort_by", response.json["search_parameters"])
        self.assertEqual(ai.mock_calls, [])
        self.assertEqual(app.extensions["recommendation_service"].mock_calls, [])
        self.assertNotIn("synthetic-test-key", response.get_data(as_text=True))

    def test_custom_country_domain_language_location_and_maximum(self):
        service, transport = self.service()
        client, _, _ = self.client(service)
        response = client.post("/api/recommendations/search", json={
            "q": "coffee", "gl": " GB ", "hl": " EN ", "google_domain": "Google.co.uk",
            "location": " London, England, United Kingdom ", "max_price": "100.25",
        })
        self.assertEqual(response.status_code, 200, response.json)
        params = transport.calls[0][1]["params"]
        self.assertEqual(params["gl"], "gb")
        self.assertEqual(params["google_domain"], "google.co.uk")
        self.assertEqual(params["hl"], "en")
        self.assertEqual(params["location"], "London, England, United Kingdom")
        self.assertEqual(params["max_price"], "100.25")
        self.assertEqual(response.json["search_parameters"]["max_price"], 100.25)
        self.assertEqual(len(transport.calls), 1)

    def test_supported_non_saudi_countries_keep_their_search_settings(self):
        service, transport = self.service()
        client, _, _ = self.client(service)
        countries = (
            ("ae", "United Arab Emirates", "google.ae", "ar"),
            ("us", "United States", "google.com", "en"),
            ("gb", "United Kingdom", "google.co.uk", "en"),
        )
        for code, location, domain, language in countries:
            with self.subTest(country=code):
                settings = {
                    "gl": code, "location": location,
                    "google_domain": domain, "hl": language,
                }
                response = client.post("/api/recommendations/search", json={"q": "tea", **settings})
                self.assertEqual(response.status_code, 200, response.json)
                self.assertEqual(transport.calls[-1][1]["params"], {
                    "engine": "google_shopping", "q": "tea", "api_key": "synthetic-test-key",
                    **settings,
                })
                self.assertEqual(response.json["search_parameters"], {**settings, "max_price": None})
                self.assertEqual(len(response.json["shopping_results"]), 1)
        self.assertEqual(len(transport.calls), len(countries))

    def test_supported_countries_outside_app_dropdown_are_still_accepted(self):
        for code in ("au", "de", "fr", "in", "jp", "uk"):
            with self.subTest(country=code):
                _, parameters = direct_search_parameters("tea", gl=code)
                self.assertEqual(parameters["gl"], code)

    def test_unsupported_countries_fail_before_cache_credentials_or_provider_use(self):
        service, transport = self.service(key="")
        service.cache = Mock(spec=SearchCache)
        client, app, ai = self.client(service)
        for code in ("kw", "eg", "qa", "bh", "om", " KW "):
            with self.subTest(country=code):
                with self.assertRaises(InvoiceError) as raised:
                    service.search_listings("tea", gl=code)
                self.assertEqual(raised.exception.code, "unsupported_search_country")
                response = client.post("/api/recommendations/search", json={"q": "tea", "gl": code})
                self.assertEqual(response.status_code, 400, response.json)
                self.assertEqual(response.json["code"], "unsupported_search_country")
                self.assertIn("Google Shopping does not support", response.json["error"])
        self.assertEqual(service.cache.mock_calls, [])
        self.assertEqual(transport.calls, [])
        self.assertEqual(ai.mock_calls, [])
        self.assertEqual(app.extensions["recommendation_service"].mock_calls, [])

    def test_explicit_null_uses_same_uncapped_search_as_omitted_price(self):
        service, transport = self.service()
        client, _, _ = self.client(service)
        response = client.post("/api/recommendations/search", json={"q": "tea", "max_price": None})
        self.assertEqual(response.status_code, 200, response.json)
        self.assertIsNone(response.json["search_parameters"]["max_price"])
        self.assertNotIn("max_price", transport.calls[0][1]["params"])
        self.assertNotIn("sort_by", transport.calls[0][1]["params"])
        repeated = client.post("/api/recommendations/search", json={"q": "tea"})
        self.assertTrue(repeated.json["cached"])
        self.assertEqual(len(transport.calls), 1)

    def test_price_parameters_use_compact_decimal_strings(self):
        service, transport = self.service()
        for value, expected in ((100.0, "100"), (12.30, "12.3"), (0.01, "0.01"), (1000, "1000")):
            with self.subTest(value=value):
                service.search_listings("tea", max_price=value)
                self.assertEqual(transport.calls[-1][1]["params"]["max_price"], expected)

    def test_all_36_results_images_and_provider_order_survive_route_and_cache(self):
        rows = [row(
            title=f"Tea {index}", extracted_price=36 - index, price=f"SAR {36 - index}",
            serpapi_thumbnail=f"https://serpapi.com/images/url/aBc9_-{index}",
            source_icon=(f"https://serpapi.com/images/i/aBc9_-{index}.png" if index % 2
                         else f"https://serpapi.com/searches/search123/images/aBc9_-{index}.png"),
        ) for index in range(36)]
        service, transport = self.service(Transport(Response(envelope(*rows))))
        client, app, ai = self.client(service)
        for cached in (False, True):
            response = client.post("/api/recommendations/search", json={"q": "tea"})
            self.assertEqual(response.status_code, 200, response.json)
            self.assertEqual(response.json["summary"], {"total_results": 36})
            cards = response.json["shopping_results"]
            self.assertEqual(len(cards), 36)
            self.assertEqual(response.json["cached"], cached)
            for original, card in zip(rows, cards):
                for field in ("title", "extracted_price", "source", "product_link", "source_icon", "serpapi_thumbnail"):
                    self.assertEqual(card[field], original[field])
        self.assertEqual(len(transport.calls), 1)
        self.assertEqual(ai.mock_calls, [])
        self.assertEqual(app.extensions["recommendation_service"].mock_calls, [])

    def test_all_documented_provider_image_paths_are_display_only(self):
        paths = (
            "/images/url/aBc9_-opaque", "/images/i/aBc9_-opaque.png",
            "/images/i/aBc9_-opaque.jpg", "/images/i/aBc9_-opaque.webp",
            "/searches/search123/images/aBc9_-opaque.png",
            "/searches/search123/images/group/other/aBc9_-opaque.jpg",
        )
        for path in paths:
            url = f"https://serpapi.com{path}"
            with self.subTest(path=path):
                self.assertEqual(safe_image_url(url), url)
                self.assertIsNone(safe_public_url(url))

    def test_provider_image_paths_reject_credentials_other_endpoints_and_traversal(self):
        paths = (
            "/images/url/", "/images/url/https://example.com/image.png",
            "/images/url/../account.json", "/images/url/%2e%2e%2faccount.json",
            "/images/i/opaque", "/images/i/opaque.exe", "/images/i/opaque.png/extra",
            "/images/i/../account.json", "/images/i/opaque.png?api_key=synthetic-test-key",
            "/images/url/opaque?token=synthetic-test-key", "/images/url/opaque#fragment",
            "/account.json", "/search.json",
        )
        for path in paths:
            with self.subTest(path=path):
                self.assertIsNone(safe_image_url(f"https://serpapi.com{path}"))
        for url in (
            "http://serpapi.com/images/url/opaque",
            "https://user:password@serpapi.com/images/url/opaque",
            "https://subdomain.serpapi.com/images/url/opaque",
            "https://serpapi.com:80/images/url/opaque",
        ):
            with self.subTest(url=url):
                self.assertIsNone(safe_image_url(url))

    def test_card_fields_product_thumbnail_and_provider_price_labels_survive_cache(self):
        icon = "https://serpapi.com/searches/abc/images/def/icon.png"
        thumbnail = "https://serpapi.com/searches/abc/images/def/product.jpg"
        link = "https://www.google.com/shopping/product/123?q=tea bags"
        service, transport = self.service(Transport(Response(envelope(
            row(title="Tea bags", source_icon=icon, serpapi_thumbnail=thumbnail, product_link=link,
                price="SAR 10 / month", extracted_price=10),
            row(title="Tea collection", price="$19.95", extracted_price=19.95),
        ))))
        first = service.search_listings("tea")
        second = service.search_listings("tea")
        self.assertEqual(first["offers"], second["offers"])
        self.assertEqual(first["offers"][0], {
            "title": "Tea bags", "product_link": link.replace(" ", "%20"),
            "source": "Example Saudi Store", "source_icon": icon,
            "serpapi_thumbnail": thumbnail,
            "extracted_price": 10, "price_label": "SAR 10 / month", "currency": None,
        })
        self.assertEqual(first["offers"][1]["currency"], "USD")
        self.assertTrue(second["cached"])
        self.assertEqual(len(transport.calls), 1)

    def test_product_thumbnail_and_store_icon_are_distinct_in_api_response(self):
        thumbnail = "https://serpapi.com/searches/abc/images/def/product.jpg"
        icon = "https://example.com/store.png"
        service, transport = self.service(Transport(Response(envelope(
            row(serpapi_thumbnail=thumbnail, source_icon=icon,
                thumbnail="https://example.com/other-product.png"),
        ))))
        client, _, _ = self.client(service)
        response = client.post("/api/recommendations/search", json={"q": "tea"})
        self.assertEqual(response.status_code, 200, response.json)
        card = response.json["shopping_results"][0]
        self.assertEqual(card["serpapi_thumbnail"], thumbnail)
        self.assertEqual(card["source_icon"], icon)
        self.assertNotIn("thumbnail", card)
        self.assertEqual(len(transport.calls), 1)

    def test_missing_empty_or_unsafe_image_fields_are_null_without_replacing_each_other(self):
        valid_thumbnail = "https://serpapi.com/searches/abc/images/def/product.jpg"
        valid_icon = "https://example.com/store.png"
        for value in (None, "", "   ", 42, "javascript:alert(1)",
                      "http://localhost/image.png", "http://127.0.0.1/image.png",
                      "https://example.com/image.png?api_key=synthetic-test-key",
                      "https://serpapi.com/search.json"):
            with self.subTest(value=value):
                cards = normalize_listings(envelope(
                    row(serpapi_thumbnail=value, source_icon=valid_icon),
                    row(serpapi_thumbnail=valid_thumbnail, source_icon=value),
                ))
                self.assertEqual(len(cards), 2)
                self.assertIsNone(cards[0]["serpapi_thumbnail"])
                self.assertEqual(cards[0]["source_icon"], valid_icon)
                self.assertEqual(cards[1]["serpapi_thumbnail"], valid_thumbnail)
                self.assertIsNone(cards[1]["source_icon"])
                self.assertNotIn("synthetic-test-key", json.dumps(cards))
        missing = normalize_listings(envelope({"title": "Tea"}))[0]
        self.assertIsNone(missing["serpapi_thumbnail"])
        self.assertIsNone(missing["source_icon"])

    def test_old_cache_without_product_thumbnail_remains_usable_without_paid_refetch(self):
        service, transport = self.service()
        query, parameters = direct_search_parameters("tea")
        icon = "https://example.com/store.png"
        self.cache.put(direct_query_key(query, parameters), {
            "query": query, "fetched_at": self.cache.timestamp(),
            "offers": [{"title": "Tea", "source_icon": icon, "extracted_price": 10}],
        })
        result = service.search_listings(query)
        self.assertTrue(result["cached"])
        self.assertIsNone(result["offers"][0]["serpapi_thumbnail"])
        self.assertEqual(result["offers"][0]["source_icon"], icon)
        self.assertEqual(transport.calls, [])

    def test_incomplete_fields_never_drop_a_titled_card(self):
        values = normalize_listings(envelope(
            {"title": "Tea"},
            row(title="Another tea", source=None, price="Price on request", extracted_price=None,
                product_link="javascript:alert(1)", source_icon="http://localhost/icon.png"),
            row(title="Unexpected currency label", price="In an unfamiliar currency", extracted_price=10.12345),
            row(title="Contradictory label", price="SAR 50", extracted_price=40),
        ))
        self.assertEqual(len(values), 4)
        self.assertIsNone(values[0]["extracted_price"])
        self.assertIsNone(values[1]["product_link"])
        self.assertIsNone(values[1]["source_icon"])
        self.assertIsNone(values[1]["source"])
        self.assertEqual(values[2]["extracted_price"], 10.12345)
        self.assertEqual(values[3]["extracted_price"], 40)

    def test_no_matching_deduplication_or_local_price_reranking(self):
        rows = [
            row(title="Tea set", extracted_price=60, price="SAR 60"),
            row(title="Unrelated provider suggestion", extracted_price=20, price="SAR 20"),
            row(title="Unrelated provider suggestion", extracted_price=20, price="SAR 20"),
            row(title="Another suggestion", extracted_price=5, price="SAR 5"),
        ]
        service, transport = self.service(Transport(Response(envelope(*rows))))
        result = service.search_listings("tea", max_price=50)
        self.assertEqual([value["title"] for value in result["offers"]], [value["title"] for value in rows])
        self.assertEqual([value["extracted_price"] for value in result["offers"]], [60, 20, 20, 5])
        self.assertNotIn("sort_by", transport.calls[0][1]["params"])

    def test_only_shopping_results_are_used_with_bounded_cards(self):
        payload = envelope(*[{"title": f"Tea {index}"} for index in range(MAX_OFFERS + 10)])
        payload["inline_shopping_results"] = [row(title="Inline excluded")]
        payload["categorized_shopping_results"] = [{"shopping_results": [row(title="Category excluded")]}]
        values = normalize_listings(payload)
        self.assertEqual(len(values), MAX_OFFERS)
        self.assertEqual(values[-1]["title"], f"Tea {MAX_OFFERS - 1}")
        self.assertEqual(normalize_listings({"inline_shopping_results": [row()]}), [])
        self.assertEqual(normalize_listings(envelope(None, "wrong", {}, {"title": "  "})), [])

    def test_invalid_raw_prices_are_null_while_labels_are_retained(self):
        for raw in (None, "10", True, 0, -1, float("nan"), float("inf"), 10 ** 400):
            with self.subTest(raw=str(raw)[:20]):
                values = normalize_listings(envelope(row(extracted_price=raw, price="SAR 10")))
                self.assertEqual(len(values), 1)
                self.assertIsNone(values[0]["extracted_price"])
                self.assertEqual(values[0]["price_label"], "SAR 10")

    def test_provider_links_with_credentials_are_removed_without_dropping_card(self):
        values = normalize_listings(envelope(row(
            product_link="https://serpapi.com/search.json?api_key=synthetic-test-key",
            source_icon="https://example.com/icon.png?api_key=synthetic-test-key",
        )))
        self.assertEqual(len(values), 1)
        self.assertIsNone(values[0]["product_link"])
        self.assertIsNone(values[0]["source_icon"])
        self.assertNotIn("synthetic-test-key", json.dumps(values))

    def test_every_setting_has_an_isolated_cache_identity(self):
        service, transport = self.service()
        cases = [
            {}, {"gl": "ae"}, {"hl": "en"}, {"location": "Jeddah, Saudi Arabia"},
            {"google_domain": "google.com"}, {"max_price": 100}, {"max_price": 101},
        ]
        for options in cases:
            self.assertFalse(service.search_listings("tea", **options)["cached"])
            self.assertTrue(service.search_listings("tea", **options)["cached"])
        self.assertEqual(len(transport.calls), len(cases))
        self.assertTrue(service.search_listings("tea", max_price="100.00")["cached"])
        self.assertFalse(service.search_listings("coffee")["cached"])
        query, params = direct_search_parameters("tea")
        self.assertNotEqual(direct_query_key(query, params), query_key(query, "sa", "ar"))

    def test_old_sorted_results_cannot_be_reused_for_provider_order(self):
        service, transport = self.service()
        query, parameters = direct_search_parameters("tea")
        old_key = direct_query_key(query, {**parameters, "sort_by": 1})
        self.cache.put(old_key, {
            "query": query, "fetched_at": self.cache.timestamp(),
            "offers": [{"title": "Previously sorted result", "extracted_price": 0.45}],
        })
        result = service.search_listings(query)
        self.assertFalse(result["cached"])
        self.assertNotEqual(result["offers"][0]["title"], "Previously sorted result")
        self.assertEqual(len(transport.calls), 1)

    def test_cache_is_sanitized_again_and_uses_only_allowlisted_fields(self):
        service, transport = self.service()
        query, params = direct_search_parameters("tea")
        self.cache.put(direct_query_key(query, params), {
            "query": query, "fetched_at": self.cache.timestamp(),
            "offers": [{"title": "Tea", "product_link": "http://127.0.0.1/private",
                        "source_icon": "javascript:alert(1)", "private_field": "private-value",
                        "serpapi_thumbnail": "http://localhost/image.png",
                        "extracted_price": -10, "price_label": "price unavailable"}],
        })
        result = service.search_listings("tea")
        self.assertTrue(result["cached"])
        self.assertEqual(len(result["offers"]), 1)
        self.assertIsNone(result["offers"][0]["product_link"])
        self.assertIsNone(result["offers"][0]["source_icon"])
        self.assertIsNone(result["offers"][0]["serpapi_thumbnail"])
        self.assertIsNone(result["offers"][0]["extracted_price"])
        self.assertNotIn("private_field", result["offers"][0])
        self.assertEqual(transport.calls, [])

    def test_upstream_envelope_secrets_never_enter_cache_or_response(self):
        payload = envelope(row())
        payload["search_parameters"] = {"api_key": "synthetic-test-key"}
        payload["raw_image"] = "private-image-bytes"
        service, _ = self.service(Transport(Response(payload)))
        result = service.search_listings("tea")
        with closing(sqlite3.connect(self.path)) as db:
            cached, = db.execute("SELECT payload FROM searches").fetchone()
        for text in (json.dumps(result), cached):
            self.assertNotIn("synthetic-test-key", text)
            self.assertNotIn("private-image-bytes", text)

    def test_provider_empty_result_is_cached_without_extra_requests(self):
        service, transport = self.service(Transport(Response({
            "search_metadata": {"status": "Success"},
            "error": "Google hasn't returned any results for this query.",
        })))
        client, _, _ = self.client(service)
        for _ in range(2):
            response = client.post("/api/recommendations/search", json={"q": "tea"})
            self.assertEqual(response.status_code, 200)
            self.assertEqual(response.json["shopping_results"], [])
            self.assertEqual(response.json["summary"]["total_results"], 0)
        self.assertTrue(response.json["cached"])
        self.assertEqual(len(transport.calls), 1)

    def test_missing_key_does_not_contact_provider(self):
        service, transport = self.service(key="")
        client, _, _ = self.client(service)
        response = client.post("/api/recommendations/search", json={"q": "tea"})
        self.assertEqual(response.status_code, 503)
        self.assertEqual(response.json["code"], "serpapi_not_configured")
        self.assertEqual(transport.calls, [])
        self.assertFalse(self.path.exists())

    def test_errors_are_safe_and_never_retried(self):
        cases = [
            (Transport(Response(status=401)), "serpapi_auth_failed"),
            (Transport(Response(status=429)), "serpapi_quota_exceeded"),
            (Transport(Response(status=502)), "serpapi_failed"),
            (Transport(error=requests.Timeout("secret")), "serpapi_timeout"),
            (Transport(error=requests.ConnectionError("secret")), "serpapi_unavailable"),
            (Transport(Response(raw=b"not json")), "serpapi_failed"),
        ]
        for index, (transport, expected) in enumerate(cases):
            with self.subTest(expected=expected):
                service, _ = self.service(transport)
                client, _, _ = self.client(service)
                response = client.post("/api/recommendations/search", json={"q": f"tea {index}"})
                self.assertEqual(response.json["code"], expected)
                self.assertNotIn("secret", response.get_data(as_text=True))
                self.assertEqual(len(transport.calls), 1)

    def test_invalid_search_names_do_not_contact_provider(self):
        service, transport = self.service()
        client, _, _ = self.client(service)
        for query in (None, "", "  ", [], 10, "x" * 401, "tea\ncoffee", "tea\tcoffee", "tea\x00", "tea\u2028coffee"):
            with self.subTest(query=query):
                response = client.post("/api/recommendations/search", json={"q": query})
                self.assertEqual(response.status_code, 400)
                self.assertEqual(response.json["code"], "invalid_search_text")
        self.assertEqual(transport.calls, [])

    def test_invalid_options_do_not_contact_provider(self):
        service, transport = self.service()
        client, _, _ = self.client(service)
        cases = [
            {"gl": "Saudi Arabia"}, {"gl": None}, {"hl": "fr"}, {"location": ""},
            {"location": "x" * 201}, {"location": "Saudi\nArabia"},
            {"google_domain": "https://google.com.sa"}, {"google_domain": "google.com.evil.com"},
            {"google_domain": "localhost"}, {"google_domain": None},
            {"max_price": 0}, {"max_price": -1}, {"max_price": True},
            {"max_price": "1.001"}, {"max_price": "NaN"}, {"max_price": "Infinity"},
            {"max_price": 1000000000}, {"max_price": "1000000000.00"},
            {"max_price": "1000000000.01"}, {"max_price": []}, {"max_price": ""},
            {"sort_by": 9}, {"api_key": "synthetic-unaccepted-key"},
        ]
        for options in cases:
            with self.subTest(options=options):
                response = client.post("/api/recommendations/search", json={"q": "tea", **options})
                self.assertEqual(response.status_code, 400, response.json)
                self.assertEqual(response.json["code"], "invalid_search_options")
        self.assertEqual(transport.calls, [])

    def test_price_boundaries_accept_two_decimal_positive_values_below_limit(self):
        for value in (0.01, "0.01", "12.30", 999999999.99, "999999999.99"):
            with self.subTest(value=value):
                _, parameters = direct_search_parameters("tea", max_price=value)
                self.assertEqual(parameters["max_price"], float(value))

    def test_literal_query_is_preserved_without_ai_rewriting(self):
        service, transport = self.service()
        query = 'شاي  أخضر "250 g"'
        service.search_listings(query)
        self.assertEqual(transport.calls[0][1]["params"]["q"], query)

    def test_malformed_or_oversized_json_does_not_contact_provider(self):
        service, transport = self.service()
        client, _, _ = self.client(service)
        for raw in ('[]', '{', '{"q":"tea","q":"coffee"}', '{"q":"tea","max_price":NaN}'):
            with self.subTest(raw=raw):
                response = client.post("/api/recommendations/search", data=raw, content_type="application/json")
                self.assertEqual(response.status_code, 400)
        response = client.post("/api/recommendations/search", json={"q": "x" * (24 * 1024)})
        self.assertEqual(response.status_code, 413)
        response = client.post("/api/recommendations/search", data={"q": "tea"})
        self.assertEqual(response.status_code, 400)
        self.assertEqual(transport.calls, [])

    def test_busy_search_does_not_start_a_paid_call_and_slot_is_released(self):
        service, transport = self.service()
        client, app, _ = self.client(service)
        slot = app.extensions["product_search_slot"]
        slot.acquire()
        try:
            response = client.post("/api/recommendations/search", json={"q": "tea"})
            self.assertEqual(response.status_code, 503)
            self.assertEqual(response.json["code"], "server_busy")
            self.assertEqual(response.headers["Retry-After"], "5")
            self.assertEqual(transport.calls, [])
        finally:
            slot.release()
        response = client.post("/api/recommendations/search", json={"q": "tea"})
        self.assertEqual(response.status_code, 200)
        self.assertTrue(slot.acquire(blocking=False))
        slot.release()


if __name__ == "__main__":
    unittest.main()
