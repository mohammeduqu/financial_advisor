from contextlib import closing
import json
from pathlib import Path
import sqlite3
import tempfile
import threading
import time
import unittest
from concurrent.futures import ThreadPoolExecutor

import requests

from cache.search_cache import SearchCache, normalize_query, query_key
from services.errors import InvoiceError
from services.serpapi_service import (
    MAX_RESPONSE_BYTES, SERPAPI_URL, SerpApiService, normalize_offers, safe_public_url,
)


def row(**changes):
    result = {
        "title": "Apple AirPods Pro 2 USB-C", "source": "Example Saudi Store",
        "price": "SAR 749.00", "extracted_price": 749,
        "product_link": "https://example.com/product/airpods",
        "thumbnail": "https://images.example.com/airpods.png",
        "rating": 4.8, "reviews": 540, "delivery": "Free delivery",
    }
    result.update(changes)
    return result


def envelope(*rows):
    return {"search_metadata": {"status": "Success"}, "shopping_results": list(rows)}


class Response:
    def __init__(self, payload=None, status=200, raw=None, headers=None):
        self.status_code = status
        self.raw = raw if raw is not None else json.dumps(payload or envelope(row())).encode()
        self.headers = headers or {}

    def __enter__(self):
        return self

    def __exit__(self, *_):
        return False

    def iter_content(self, chunk_size):
        for start in range(0, len(self.raw), chunk_size):
            yield self.raw[start:start + chunk_size]


class Transport:
    def __init__(self, response=None, error=None, before_get=None):
        self.response = response or Response()
        self.error = error
        self.before_get = before_get
        self.calls = []
        self.lock = threading.Lock()
        self.sessions = []

    def session(self):
        transport = self

        class Session:
            trust_env = True

            def __enter__(self):
                transport.sessions.append(self)
                return self

            def __exit__(self, *_):
                return False

            def get(self, url, **kwargs):
                with transport.lock:
                    transport.calls.append((url, kwargs))
                if transport.before_get:
                    transport.before_get()
                if transport.error:
                    raise transport.error
                return transport.response
        return Session()


class ShoppingTests(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.path = Path(self.folder.name) / "searches.sqlite3"
        self.now = [1800000000.0]
        self.cache = SearchCache(self.path, clock=lambda: self.now[0])

    def tearDown(self):
        self.folder.cleanup()

    def service(self, transport=None, **kwargs):
        transport = transport or Transport()
        return SerpApiService(api_key="synthetic-test-key", cache=self.cache,
                              session_factory=transport.session, **kwargs), transport

    def test_exact_request_and_normalized_real_fields(self):
        service, transport = self.service()
        result = service.search_products(" Apple  AirPods Pro 2 ")
        self.assertFalse(result["cached"])
        self.assertEqual(result["query"], "Apple AirPods Pro 2")
        self.assertEqual(result["offers"][0]["price"], 749)
        self.assertEqual(result["offers"][0]["rating"], 4.8)
        self.assertEqual(result["offers"][0]["shipping"], "Free delivery")
        self.assertIsNone(result["offers"][0]["availability"])
        self.assertIsNone(result["offers"][0]["condition"])
        url, kwargs = transport.calls[0]
        self.assertEqual(url, SERPAPI_URL)
        self.assertEqual(kwargs["params"], {
            "engine": "google_shopping", "q": "Apple AirPods Pro 2", "gl": "sa",
            "google_domain": "google.com.sa", "location": "Saudi Arabia", "sort_by": 1,
            "hl": "en", "api_key": "synthetic-test-key",
        })
        self.assertEqual(kwargs["timeout"], (5, 20))
        self.assertFalse(kwargs["allow_redirects"])
        self.assertTrue(kwargs["stream"])
        self.assertFalse(transport.sessions[0].trust_env)

    def test_missing_key_does_not_write_or_connect(self):
        transport = Transport()
        service = SerpApiService(api_key="", cache=self.cache, session_factory=transport.session)
        with self.assertRaises(InvoiceError) as caught:
            service.search_products("AirPods")
        self.assertEqual(caught.exception.code, "serpapi_not_configured")
        self.assertEqual(transport.calls, [])
        self.assertFalse(self.path.exists())

    def test_persistent_case_unicode_whitespace_cache_and_ttl(self):
        service, transport = self.service()
        first = service.search_products("  ＡｉｒＰｏｄｓ   Pro 2 ")
        restarted = SerpApiService(
            api_key="different-key", cache=SearchCache(self.path, clock=lambda: self.now[0]),
            session_factory=transport.session,
        )
        second = restarted.search_products("airpods pro 2")
        self.assertTrue(second["cached"])
        self.assertEqual(first["fetched_at"], second["fetched_at"])
        self.assertEqual(len(transport.calls), 1)
        second["offers"][0]["price"] = 1
        self.assertEqual(restarted.search_products("airpods pro 2")["offers"][0]["price"], 749)
        self.now[0] += 43200
        fresh = restarted.search_products("airpods pro 2")
        self.assertFalse(fresh["cached"])
        self.assertEqual(len(transport.calls), 2)
        self.assertNotEqual(first["fetched_at"], fresh["fetched_at"])

    def test_region_and_language_are_distinct_cache_keys(self):
        en, transport = self.service()
        ar, _ = self.service(transport, language="ar")
        region, _ = self.service(transport, region="ae")
        en.search_products("AirPods")
        ar.search_products("AirPods")
        region.search_products("AirPods")
        self.assertEqual(len(transport.calls), 3)
        self.assertNotEqual(query_key("airpods", "sa", "en"), query_key("airpods", "sa", "ar"))

    def test_only_exact_positive_purchase_prices_with_consistent_currency(self):
        bad = [
            row(price="USD 749", currency="SAR"),
            row(price="SAR 749", currency="AED"),
            row(price="SAR 749", extracted_price=9),
            row(price="SAR 0", extracted_price=0),
            row(price="SAR -1", extracted_price=-1),
            row(price="SAR 10 / month", extracted_price=10),
            row(price="From SAR 10", extracted_price=10),
            row(price="SAR 10 - 20", extracted_price=10),
            row(price="SAR 1.001", extracted_price=1.001),
            row(price="SAR 749", extracted_price=True),
            row(price="SAR 749", extracted_price=float("inf")),
        ]
        self.assertEqual(normalize_offers(envelope(*bad)), [])
        valid = normalize_offers(envelope(
            row(price="١٬٢٤٩٫٥٠ ر.س", extracted_price=1249.5),
            row(price="SAR 749", extracted_price=None, source="Second shop"),
            row(price=None, currency="SAR", source="Third shop"),
        ))
        self.assertEqual([offer["price"] for offer in valid], [1249.5, 749, 749])

    def test_listing_currency_is_preserved_instead_of_dropping_foreign_prices(self):
        cases = [
            ("$444.99", 444.99, "USD"), ("US$444.99", 444.99, "USD"),
            ("CA$444.99", 444.99, "CAD"), ("A$444.99", 444.99, "AUD"),
            ("EUR 444.99", 444.99, "EUR"), ("\u20ac444.99", 444.99, "EUR"),
            ("\u00a3444.99", 444.99, "GBP"), ("444.99 \u20c1", 444.99, "SAR"),
            ("444.99", 444.99, None), ("\u00a5444.99", 444.99, None),
        ]
        for label, amount, currency in cases:
            with self.subTest(label=label):
                offers = normalize_offers(envelope(row(price=label, extracted_price=amount)))
                self.assertEqual(len(offers), 1)
                self.assertEqual(offers[0]["currency"], currency)
                self.assertEqual(offers[0]["price_label"], label)
                self.assertEqual(offers[0]["price"], amount)

    def test_dollar_iphone_response_returns_cards_without_sar_savings_or_extra_calls(self):
        from app import create_app
        service, transport = self.service(Transport(Response(envelope(
            row(title="Apple iPhone 14 Plus", price="$444.99", extracted_price=444.99),
            row(title="Apple iPhone 8", price="$129.99", extracted_price=129.99),
            row(title="Apple iPhone SE", price="$212.01", extracted_price=212.01),
        ))))
        app = create_app(shopping=service, recommendation_config={"SERPAPI_KEY": "synthetic-test-key"})
        client = app.test_client()
        review = client.post('/api/recommendations/product', json={'text': 'iPhone'})
        for _ in range(2):
            response = client.post('/api/recommendations/product', json={'confirmed':True, 'products':review.json['products']})
            self.assertEqual(response.status_code, 200, response.json)
            offers = response.json['recommendations'][0]['offers']
            self.assertEqual([o['price'] for o in offers], [129.99, 212.01])
            self.assertEqual([o['currency'] for o in offers], ['USD', 'USD'])
            self.assertEqual([o['price_label'] for o in offers], ['$129.99', '$212.01'])
            self.assertTrue(all(o['broad_match'] for o in offers))
            self.assertIsNone(response.json['summary']['shopping_total'])
            self.assertEqual(response.json['summary']['potential_savings'], 0)
            self.assertIn('shopping_currency_not_comparable', response.json['warnings'])
        self.assertTrue(response.json['recommendations'][0]['cached'])
        self.assertEqual(len(transport.calls), 1)
        self.assertEqual(transport.calls[0][1]['params']['q'], 'iPhone')

    def test_equivalent_currency_labels_do_not_duplicate_the_same_offer(self):
        offers = normalize_offers(envelope(
            row(price='$749', extracted_price=749),
            row(price='USD 749', extracted_price=749),
            row(price='SAR 749', extracted_price=749),
        ))
        self.assertEqual([offer['currency'] for offer in offers], ['USD', 'SAR'])

    def test_documented_nested_and_inline_results_and_deduplication(self):
        payload = envelope(row())
        payload["inline_shopping_results"] = [
            row(product_link=None, link="https://example.com/inline", source="Inline store"),
        ]
        payload["categorized_shopping_results"] = [
            {"shopping_results": [row(), row(source="Nested store", second_hand_condition="Used")]},
        ]
        offers = normalize_offers(payload)
        self.assertEqual(len(offers), 3)
        self.assertEqual(offers[-1]["condition"], "Used")

    def test_public_links_only(self):
        bad_urls = [
            "javascript:alert(1)", "file:///secret", "https://user:pass@example.com",
            "http://127.0.0.1/product", "http://[::1]/product", "http://10.0.0.1",
            "https://localhost/product", "https://printer.local", "http://2130706433",
            "https://example.com\\@127.0.0.1", "https://example.com:444",
            "https://serpapi.com/search.json?api_key=secret", "https://example.com?api_key=secret",
            "https://foo.localhost/", "https://example.com/\nfoo",
        ]
        for url in bad_urls:
            with self.subTest(url=url):
                self.assertIsNone(safe_public_url(url))
        self.assertEqual(safe_public_url("https://www.google.com/shopping/product/123"),
                         "https://www.google.com/shopping/product/123")
        self.assertEqual(normalize_offers(envelope(row(product_link="javascript:alert(1)"))), [])
        offer = normalize_offers(envelope(row(thumbnail="http://127.0.0.1/private")))[0]
        self.assertIsNone(offer["image_url"])

    def test_successful_empty_result_is_cached(self):
        payload = {
            "search_metadata": {"status": "Success"},
            "error": "Google hasn't returned any results for this query.",
        }
        service, transport = self.service(Transport(Response(payload)))
        self.assertEqual(service.search_products("Specific discontinued product")["offers"], [])
        self.assertTrue(service.search_products("Specific discontinued product")["cached"])
        self.assertEqual(len(transport.calls), 1)

    def test_errors_are_safe_distinct_and_not_retried(self):
        cases = [
            (Transport(Response(status=401)), "serpapi_auth_failed"),
            (Transport(Response(status=403)), "serpapi_auth_failed"),
            (Transport(Response(status=429)), "serpapi_quota_exceeded"),
            (Transport(Response(status=500)), "serpapi_failed"),
            (Transport(Response(status=302)), "serpapi_failed"),
            (Transport(error=requests.Timeout("URL?api_key=synthetic-test-key")), "serpapi_timeout"),
            (Transport(error=requests.ConnectionError("URL?api_key=synthetic-test-key")), "serpapi_unavailable"),
            (Transport(error=requests.RequestException("URL?api_key=synthetic-test-key")), "serpapi_failed"),
            (Transport(Response(raw=b"<html>bad response</html>")), "serpapi_failed"),
            (Transport(Response({"search_metadata": {"status": "Processing"}})), "serpapi_failed"),
            (Transport(Response({"error": "synthetic-test-key"})), "serpapi_failed"),
        ]
        for index, (transport, code) in enumerate(cases):
            with self.subTest(code=code, index=index):
                service, _ = self.service(transport)
                with self.assertRaises(InvoiceError) as caught:
                    service.search_products(f"Product {index}")
                self.assertEqual(caught.exception.code, code)
                self.assertNotIn("synthetic-test-key", str(caught.exception))
                self.assertIsNone(caught.exception.__cause__)
                self.assertEqual(len(transport.calls), 1)
                self.assertIsNone(self.cache.get(query_key(f"Product {index}")))

    def test_response_size_is_bounded(self):
        for response in [
            Response(headers={"Content-Length": str(MAX_RESPONSE_BYTES + 1)}),
            Response(raw=b" " * (MAX_RESPONSE_BYTES + 1)),
        ]:
            service, _ = self.service(Transport(response))
            with self.assertRaises(InvoiceError) as caught:
                service.search_products("Large provider response")
            self.assertEqual(caught.exception.code, "serpapi_failed")

    def test_cache_cannot_store_credentials_or_image_bytes(self):
        payload = envelope(row())
        payload["search_parameters"] = {"api_key": "synthetic-test-key"}
        payload["raw_image"] = "private uploaded image"
        service, _ = self.service(Transport(Response(payload)))
        service.search_products("AirPods")
        with closing(sqlite3.connect(self.path)) as db, db:
            raw, = db.execute("SELECT payload FROM searches").fetchone()
        self.assertNotIn("synthetic-test-key", raw)
        self.assertNotIn("private uploaded image", raw)
        self.assertNotIn("search_parameters", raw)

    def test_invalid_cache_entry_is_replaced_but_corrupt_database_is_safe(self):
        service, transport = self.service()
        service.search_products("AirPods")
        with closing(sqlite3.connect(self.path)) as db, db:
            db.execute("UPDATE searches SET payload = ?", ("not JSON",))
        service.search_products("AirPods")
        self.assertEqual(len(transport.calls), 2)
        self.path.write_bytes(b"Not a SQLite database")
        with self.assertRaises(InvoiceError) as caught:
            service.search_products("AirPods")
        self.assertEqual(caught.exception.code, "price_cache_unavailable")
        self.assertEqual(len(transport.calls), 2)

    def test_pruning_and_ttl_limits(self):
        cache = SearchCache(self.path, ttl_seconds=1, clock=lambda: self.now[0], max_entries=2)
        self.assertEqual(cache.ttl_seconds, 21600)
        for index in range(4):
            self.now[0] += 1
            cache.put(str(index), {"offers": [], "query": str(index), "fetched_at": cache.timestamp()})
        with closing(sqlite3.connect(self.path)) as db, db:
            count, = db.execute("SELECT COUNT(*) FROM searches").fetchone()
        self.assertEqual(count, 2)
        self.assertIsNone(cache.get("0"))
        self.assertEqual(SearchCache(self.path, ttl_seconds=9999999).ttl_seconds, 86400)

    def test_concurrent_identical_requests_share_one_fetch(self):
        start = threading.Barrier(6)
        service, transport = self.service(Transport(before_get=lambda: time.sleep(0.12)))

        def search(_):
            start.wait(timeout=2)
            return service.search_products("AirPods")

        with ThreadPoolExecutor(max_workers=6) as pool:
            results = list(pool.map(search, range(6)))
        self.assertEqual(len(transport.calls), 1)
        self.assertTrue(all(result["offers"][0]["price"] == 749 for result in results))

    def test_concurrent_failure_is_shared_without_paid_retries(self):
        start = threading.Barrier(6)
        service, transport = self.service(Transport(
            error=requests.Timeout("secret"), before_get=lambda: time.sleep(0.12),
        ))

        def search(_):
            start.wait(timeout=2)
            try:
                service.search_products("AirPods")
            except InvoiceError as error:
                return error.code

        with ThreadPoolExecutor(max_workers=6) as pool:
            results = list(pool.map(search, range(6)))
        self.assertEqual(results, ["serpapi_timeout"] * 6)
        self.assertEqual(len(transport.calls), 1)

    def test_query_validation(self):
        for value in ("", " " * 500, "a" * 8001, None, "phone\x00price"):
            with self.subTest(value=value), self.assertRaises(InvoiceError):
                normalize_query(value)
        self.assertEqual(normalize_query("  حليب   المراعي  ٢ لتر  "), "حليب المراعي ٢ لتر")
        self.assertEqual(normalize_query("a" * 8000), "a" * 8000)

    def test_card_fields_preserve_source_link_icon_and_price_through_cache(self):
        icon = "https://serpapi.com/searches/abc123/images/def456/abc789.png"
        product_link = "https://www.google.com/shopping/product/123?q=AirPods Pro"
        service, transport = self.service(Transport(Response(envelope(row(
            source_icon=icon, product_link=product_link,
            link="https://example.com/airpods",
        )))))
        first = service.search_products("AirPods")
        cached = service.search_products("airpods")
        for value in (first, cached):
            offer = value["offers"][0]
            self.assertEqual(offer["title"], row()["title"])
            self.assertEqual(offer["source"], offer["store"])
            self.assertEqual(offer["source_icon"], icon)
            self.assertEqual(offer["product_link"], product_link.replace(" ", "%20"))
            self.assertEqual(offer["product_url"], "https://example.com/airpods")
            self.assertEqual(offer["extracted_price"], offer["price"])
        self.assertTrue(cached["cached"])
        self.assertEqual(len(transport.calls), 1)
        self.assertIsNone(safe_public_url(icon))

    def test_source_icon_cannot_call_provider_api_or_expose_credentials(self):
        for icon in (
            "https://serpapi.com/search.json?api_key=secret",
            "https://serpapi.com/account.json",
            "https://serpapi.com/searches/abc.json",
            "https://serpapi.com/searches/abc/images/image.png?api_key=secret",
            "https://serpapi.com/searches/abc/images/../../account.json",
            "https://serpapi.com:80/searches/abc/images/icon.png",
            "https://example.com/icon.png?api_key=secret",
            "http://127.0.0.1/icon.png",
            "javascript:alert(1)",
            "data:image/svg+xml,<svg></svg>",
        ):
            with self.subTest(icon=icon):
                offers = normalize_offers(envelope(row(source_icon=icon)))
                self.assertEqual(len(offers), 1)
                self.assertIsNone(offers[0]["source_icon"])
        icon = "https://encrypted-tbn2.gstatic.com/favicon-tbn?q=tbn:shop"
        self.assertEqual(normalize_offers(envelope(row(source_icon=icon)))[0]["source_icon"], icon)
        self.assertIsNone(normalize_offers(envelope(row()))[0]["source_icon"])

    def test_previous_unsorted_cache_key_is_not_reused(self):
        import hashlib
        legacy_key = hashlib.sha256(json.dumps(
            ["shopping-v2", "airpods", "sa", "en"], ensure_ascii=False,
        ).encode("utf-8")).hexdigest()
        self.cache.put(legacy_key, {"offers": [], "query": "AirPods", "fetched_at": self.cache.timestamp()})
        service, transport = self.service()
        self.assertTrue(service.search_products("AirPods")["offers"])
        self.assertEqual(len(transport.calls), 1)
        self.assertNotEqual(query_key("AirPods"), legacy_key)

    def test_unused_seller_tokens_are_not_stored_or_returned(self):
        payload = envelope(*[row(
            source=f"Shop {index}",
            immersive_product_page_token="x" * 12000,
        ) for index in range(80)])
        service, transport = self.service(Transport(Response(payload)))
        first = service.search_products("AirPods")
        self.assertEqual(len(first["offers"]), 80)
        self.assertTrue(all(value["shop_lookup_token"] is None for value in first["offers"]))
        self.assertTrue(service.search_products("AirPods")["cached"])
        self.assertEqual(len(transport.calls), 1)

    def test_combined_list_api_uses_one_fetch_then_reuses_cache_when_reordered(self):
        from app import create_app
        titles = ["Samsung Galaxy S26 Ultra", "Apple AirPods Pro 2"]
        rows = [row(
            title=title, source=f"Shop {price}", price=f"SAR {price}", extracted_price=price,
            product_link=f"https://www.google.com/shopping/product/{item}{price}",
            source_icon="https://example.com/icon.png",
        ) for item, title in enumerate(titles) for price in (900, 500, 700)]
        service, transport = self.service(Transport(Response(envelope(*rows))))
        app = create_app(shopping=service, recommendation_config={"SERPAPI_KEY": "synthetic-test-key"})
        client = app.test_client()
        products = [{"name": name, "quantity": 1} for name in ("galaxy s26 ultra", "Apple AirPods Pro 2", "Sony WH1000XM5")]
        for order in (products, list(reversed(products))):
            response = client.post('/api/recommendations/shopping-list', json={'confirmed': True, 'products': order})
            self.assertEqual(response.status_code, 200, response.json)
            by_name = {item['item_name']: item for item in response.json['recommendations']}
            for name in ('galaxy s26 ultra', 'Apple AirPods Pro 2'):
                self.assertEqual([offer['extracted_price'] for offer in by_name[name]['offers']], [500, 700])
                for offer in by_name[name]['offers']:
                    for field in ('title', 'product_link', 'source', 'source_icon', 'extracted_price'):
                        self.assertIn(field, offer)
                    self.assertIsNone(offer['shop_lookup_token'])
            self.assertEqual(by_name['Sony WH1000XM5']['offers'], [])
            self.assertIn('combined_search_limited_coverage', response.json['warnings'])
        self.assertEqual(len(transport.calls), 1)
        self.assertTrue(all(item['cached'] for item in response.json['recommendations']))
        params = transport.calls[0][1]['params']
        self.assertIn(' OR ', params['q'])
        self.assertEqual(params['sort_by'], 1)
        self.assertEqual(params['google_domain'], 'google.com.sa')
        self.assertEqual(params['location'], 'Saudi Arabia')


    def test_google_shopping_spaces_are_encoded_without_dropping_offers(self):
        from urllib.parse import parse_qs, urlsplit
        link = ("https://www.google.com/search?ibp=oshop&q=galaxy s26 ultra Saudi Arabia"
                "&prds=catalogid:123,rds:PC_123|PROD_PC_123&hl=en&gl=sa&udm=28")
        offers = normalize_offers(envelope(row(product_link=link)))
        self.assertEqual(len(offers), 1)
        cleaned = offers[0]["product_url"]
        self.assertNotIn(" ", cleaned)
        self.assertIn("%20", cleaned)
        self.assertIn("%7C", cleaned)
        self.assertEqual(parse_qs(urlsplit(cleaned).query)["q"],
                         ["galaxy s26 ultra Saudi Arabia"])
        self.assertEqual(offers[0]["link_kind"], "shopping")
        self.assertEqual(safe_public_url(cleaned), cleaned)
        self.assertEqual(safe_public_url("https://example.com/product name?q=one two"),
                         "https://example.com/product%20name?q=one%20two")

    def test_encoding_spaces_does_not_relax_host_or_control_validation(self):
        for link in (
            "https://example .com/product", "https://user name@example.com/item",
            "https://example.com/\nproduct", "https://example.com/\tproduct",
            "https://example.com/\x7fproduct", "https://example.com/\u00a0product",
            "https://example.com\\@127.0.0.1/item", "http://127.0.0.1/item name",
            "https://example.com?api_key=not-a-real-key",
        ):
            with self.subTest(link=link):
                self.assertIsNone(safe_public_url(link))

    def test_named_product_returns_offers_from_realistic_google_link_shape_and_cache(self):
        from services.product_recognition_service import product_from_text, reviewed_products
        from services.recommendation_service import RecommendationService
        google = "https://www.google.com/search?ibp=oshop&q=galaxy s26 ultra Saudi Arabia&udm=28"
        service, transport = self.service(Transport(Response(envelope(
            row(title="Samsung Galaxy S26 Ultra", product_link=google,
                price="SAR 3670.00", extracted_price=3670),
            row(title="Samsung Galaxy S26", product_link=google,
                price="SAR 2999.00", extracted_price=2999),
        ))))
        engine = RecommendationService(service, {})
        products = reviewed_products([product_from_text("galaxy s26 ultra")], "product")
        first = engine.recommend(products, shopping=True)
        second = engine.recommend(products, shopping=True)
        self.assertEqual(first["summary"]["found_items"], 1)
        self.assertEqual(first["recommendations"][0]["best_offer"]["title"],
                         "Samsung Galaxy S26 Ultra")
        self.assertTrue(second["recommendations"][0]["cached"])
        self.assertEqual(len(transport.calls), 1)


if __name__ == "__main__":
    unittest.main()
