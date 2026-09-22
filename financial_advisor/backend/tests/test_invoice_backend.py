import base64
import io
import json
import unittest
from unittest.mock import Mock, patch

import requests
from PIL import Image

from app import create_app
from ollama_config import get_ollama_config
from services.errors import InvoiceError
from services.invoice_service import normalize_invoice, prepare_image
from services.ollama_service import INVOICE_SCHEMA, OllamaService
from utils.json_utils import parse_invoice_json


def image_bytes(image_format="PNG", size=(80, 120)):
    output = io.BytesIO()
    Image.new("RGB", size, "white").save(output, format=image_format)
    return output.getvalue()


def example_invoice(**overrides):
    invoice = {
        "merchant_name": "Example Store", "invoice_number": "000123",
        "date": "2026-09-08", "currency": "SAR", "subtotal": 100,
        "tax": 15, "discount": 0, "total": 115, "category": "Shopping",
        "items": [
            {"name": "Product 1", "quantity": 2, "unit_price": 20,
             "total_price": 40, "category": "Shopping"},
            {"name": "Product 2", "quantity": 1, "unit_price": 60,
             "total_price": 60, "category": "Shopping"},
        ],
    }
    invoice.update(overrides)
    return invoice


class JsonParserTests(unittest.TestCase):
    def test_markdown_prose_and_braces_inside_strings(self):
        raw = example_invoice(merchant_name='Shop {north} "A"')
        wrapped = "Result:\n```json\n" + json.dumps(raw) + "\n```\nPlease review."
        self.assertEqual(parse_invoice_json(wrapped), raw)

    def test_rejects_multiple_objects_and_arrays(self):
        for value in ('{"total": 10} {"total": 20}', '[{"total": 10}]'):
            with self.subTest(value=value), self.assertRaises(InvoiceError):
                parse_invoice_json(value)

    def test_rejects_duplicate_fields_and_non_finite_values(self):
        for value in ('{"total": 10, "total": 20}', '{"total": NaN}', '{"total": Infinity}'):
            with self.subTest(value=value), self.assertRaises(InvoiceError):
                parse_invoice_json(value)

    def test_never_salvages_nested_item_from_truncated_invoice(self):
        with self.assertRaises(InvoiceError):
            parse_invoice_json('Receipt: {"items": [{"total_price": 40}]')

    def test_accepts_one_invoice_envelope(self):
        raw = example_invoice()
        self.assertEqual(parse_invoice_json(json.dumps({"success": True, "invoice": raw})), raw)
        with self.assertRaises(InvoiceError):
            parse_invoice_json(json.dumps({"invoice": raw, "other_invoice": raw}))


class InvoiceValidationTests(unittest.TestCase):
    def test_normalizes_arabic_digits_currency_dates_and_categories(self):
        raw = example_invoice(
            date="٢٠٢٦/٩/٨", currency="ريال سعودي", total="١٬١٥٠٫٥٠ ر.س",
            subtotal="1,000.50", tax="١٥٠", category="Foods",
            items=[{"name": "قهوة", "quantity": "٢", "unit_price": "٥٫٥٠",
                    "total_price": "١١", "category": "طعام"}],
        )
        invoice, warnings = normalize_invoice(raw)
        self.assertEqual(invoice["date"], "2026-09-08")
        self.assertEqual(invoice["currency"], "SAR")
        self.assertEqual(invoice["total"], 1150.5)
        self.assertEqual(invoice["category"], "Food")
        self.assertEqual(invoice["items"][0]["unit_price"], 5.5)
        self.assertEqual(invoice["items"][0]["quantity"], 2)
        self.assertIn("items_total_mismatch", warnings)

    def test_missing_fields_stay_null_and_prices_are_not_inferred(self):
        invoice, warnings = normalize_invoice({
            "merchant_name": "Store", "items": [{"name": "Coffee", "total_price": 12}]
        })
        for field in ("date", "currency", "total", "subtotal", "tax", "discount", "category"):
            self.assertIsNone(invoice[field])
        self.assertIsNone(invoice["items"][0]["quantity"])
        self.assertIsNone(invoice["items"][0]["unit_price"])
        self.assertIn("partial_data", warnings)

    def test_invalid_money_cannot_enter_financial_records(self):
        for value in (True, -1, "-2", "1,23,4", "TOTAL 99", float("inf"), "1e999", 1_000_000_000):
            with self.subTest(value=value):
                invoice, warnings = normalize_invoice(example_invoice(total=value))
                self.assertIsNone(invoice["total"])
                self.assertIn("partial_data", warnings)

    def test_ambiguous_or_invalid_dates_are_not_guessed(self):
        for value in ("08/09/2026", "2026-02-30", "1448-02-03"):
            with self.subTest(value=value):
                invoice, _ = normalize_invoice(example_invoice(date=value))
                self.assertIsNone(invoice["date"])
        invoice, _ = normalize_invoice(example_invoice(date="31/08/2026"))
        self.assertEqual(invoice["date"], "2026-08-31")

    def test_tax_is_never_added_to_an_already_printed_total(self):
        invoice, warnings = normalize_invoice(example_invoice(
            subtotal=100, tax=15, total=115,
            items=[{"name": "VAT-inclusive purchase", "quantity": 1,
                    "unit_price": 115, "total_price": 115, "category": "Shopping"}],
        ))
        self.assertEqual(invoice["total"], 115)
        self.assertEqual(invoice["items"][0]["total_price"], 115)
        self.assertNotIn("items_total_mismatch", warnings)
        self.assertNotIn("totals_mismatch", warnings)

    def test_total_mismatches_warn_without_changing_model_values(self):
        invoice, warnings = normalize_invoice(example_invoice(total=150))
        self.assertEqual(invoice["total"], 150)
        self.assertIn("totals_mismatch", warnings)

    def test_no_items_remains_reviewable_when_header_is_readable(self):
        invoice, warnings = normalize_invoice(example_invoice(items=[]))
        self.assertEqual(invoice["items"], [])
        self.assertIn("no_items", warnings)

    def test_unreadable_invoice_is_a_structured_error(self):
        with self.assertRaises(InvoiceError) as raised:
            normalize_invoice({"items": []})
        self.assertEqual(raised.exception.code, "unreadable_invoice")

    def test_unknown_categories_cannot_create_new_app_categories(self):
        invoice, warnings = normalize_invoice(example_invoice(category="Totally random"))
        self.assertEqual(invoice["category"], "Other")
        self.assertIn("category_mapped", warnings)

    def test_invalid_or_excessive_items_are_not_silently_dropped(self):
        for items in ("coffee", ["coffee"], [{}] * 201):
            with self.subTest(items=str(items)[:20]), self.assertRaises(InvoiceError):
                normalize_invoice(example_invoice(items=items))


class ImageValidationTests(unittest.TestCase):
    def test_accepts_real_png_and_jpeg_and_strips_metadata(self):
        for image_format in ("PNG", "JPEG"):
            with self.subTest(image_format=image_format):
                output = prepare_image(image_bytes(image_format))
                with Image.open(io.BytesIO(output)) as image:
                    self.assertEqual(image.format, "JPEG")
                    self.assertEqual(image.size, (80, 120))
                    self.assertFalse(image.getexif())

    def test_rejects_other_formats_and_fake_images(self):
        with self.assertRaises(InvoiceError) as raised:
            prepare_image(image_bytes("GIF"))
        self.assertEqual(raised.exception.code, "unsupported_image")
        with self.assertRaises(InvoiceError) as raised:
            prepare_image(b"pretending to be invoice.jpg")
        self.assertEqual(raised.exception.code, "invalid_image")

    def test_enforces_size_and_pixel_limits(self):
        with patch("services.invoice_service.MAX_IMAGE_BYTES", 10):
            with self.assertRaises(InvoiceError) as raised:
                prepare_image(b"0" * 11)
            self.assertEqual(raised.exception.status, 413)
        with patch("services.invoice_service.MAX_IMAGE_PIXELS", 100):
            with self.assertRaises(InvoiceError) as raised:
                prepare_image(image_bytes())
            self.assertEqual(raised.exception.status, 413)


class ApiTests(unittest.TestCase):
    def setUp(self):
        self.ollama = Mock()
        self.ollama.analyze.return_value = json.dumps(example_invoice())
        self.app = create_app(ollama=self.ollama)
        self.app.config["TESTING"] = True
        self.client = self.app.test_client()

    def upload(self, data=None, **kwargs):
        return self.client.post(
            "/api/invoice/analyze",
            data={"image": (io.BytesIO(data if data is not None else image_bytes()), "invoice.png")},
            content_type="multipart/form-data", **kwargs,
        )

    def test_real_image_multipart_contract(self):
        response = self.upload()
        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.json["success"])
        self.assertEqual(response.json["invoice"]["total"], 115)
        self.assertEqual(len(response.json["invoice"]["items"]), 2)
        self.assertEqual(response.headers["Cache-Control"], "no-store")
        self.ollama.analyze.assert_called_once()

    def test_rejects_missing_and_invalid_images_before_inference(self):
        response = self.client.post("/api/invoice/analyze")
        self.assertEqual(response.json["code"], "missing_image")
        self.assertEqual(self.upload(b"bad image").status_code, 400)
        self.ollama.analyze.assert_not_called()

    def test_bounds_request_body(self):
        self.app.config["MAX_CONTENT_LENGTH"] = 50
        response = self.upload()
        self.assertEqual(response.status_code, 413)
        self.assertEqual(response.json["code"], "image_too_large")
        self.ollama.analyze.assert_not_called()

    def test_busy_response_then_slot_can_be_used_again(self):
        slot = self.app.extensions["invoice_analysis_slot"]
        slot.acquire()
        try:
            response = self.upload()
            self.assertEqual(response.status_code, 503)
            self.assertEqual(response.json["code"], "server_busy")
            self.assertEqual(response.headers["Retry-After"], "5")
        finally:
            slot.release()
        self.assertEqual(self.upload().status_code, 200)

    def test_failure_releases_slot_and_does_not_leak_model_output(self):
        self.ollama.analyze.side_effect = RuntimeError("PRIVATE RECEIPT CONTENT")
        response = self.upload()
        self.assertEqual(response.status_code, 500)
        self.assertNotIn("PRIVATE", response.get_data(as_text=True))
        self.ollama.analyze.side_effect = None
        self.assertEqual(self.upload().status_code, 200)

    def test_safe_error_code_survives_to_flutter(self):
        self.ollama.analyze.side_effect = InvoiceError("analysis_timeout", "Analysis timed out.", 504)
        response = self.upload()
        self.assertEqual(response.status_code, 504)
        self.assertEqual(response.json["code"], "analysis_timeout")

    def test_arbitrary_browser_origin_is_rejected(self):
        response = self.upload(headers={"Origin": "https://unrelated.example"})
        self.assertEqual(response.status_code, 403)
        self.assertEqual(response.json["code"], "forbidden_origin")
        self.ollama.analyze.assert_not_called()

    def test_local_preview_origin_is_allowed(self):
        response = self.upload(headers={"Origin": "http://127.0.0.1:8080"})
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.headers["Access-Control-Allow-Origin"], "http://127.0.0.1:8080")

    def test_health_does_not_claim_model_readiness(self):
        response = self.client.get("/api/health")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json["service"], "numo-local-invoice")
        self.ollama.analyze.assert_not_called()


class OllamaServiceTests(unittest.TestCase):
    def request_mock(self, session_class, status=200, envelope=None):
        session = session_class.return_value.__enter__.return_value
        response = session.post.return_value.__enter__.return_value
        response.status_code = status
        response.iter_content.return_value = [json.dumps(envelope or {
            "done": True, "done_reason": "stop", "message": {"content": json.dumps(example_invoice())}
        }).encode()]
        return session, response

    @patch("services.ollama_service.requests.Session")
    def test_loopback_vision_schema_payload_and_no_environment_proxy(self, session_class):
        session, _ = self.request_mock(session_class)
        config = get_ollama_config("local")
        result = OllamaService(config=config).analyze(b"real-image-bytes")
        self.assertEqual(json.loads(result)["total"], 115)
        args, kwargs = session.post.call_args
        self.assertEqual(args[0], config.chat_url)
        self.assertEqual(config.chat_url, "http://127.0.0.1:11434/api/chat")
        self.assertFalse(session.trust_env)
        self.assertFalse(kwargs["allow_redirects"])
        self.assertEqual(kwargs["timeout"], (5, 300))
        self.assertEqual(kwargs["json"]["model"], config.model)
        self.assertNotIn("think", kwargs["json"])
        self.assertEqual(kwargs["json"]["format"], INVOICE_SCHEMA)
        self.assertEqual(kwargs["json"]["messages"][1]["images"], [base64.b64encode(b"real-image-bytes").decode()])
        self.assertFalse(kwargs["json"]["stream"])

    @patch("services.ollama_service.requests.Session")
    def test_missing_model_is_actionable(self, session_class):
        self.request_mock(session_class, status=404)
        with self.assertRaises(InvoiceError) as raised:
            OllamaService().analyze(b"image")
        self.assertEqual(raised.exception.code, "model_not_installed")
        self.assertEqual(raised.exception.status, 503)

    @patch("services.ollama_service.requests.Session")
    def test_timeout_and_unavailable_are_distinct(self, session_class):
        session, _ = self.request_mock(session_class)
        for failure, code in ((requests.Timeout(), "analysis_timeout"),
                              (requests.ConnectionError(), "ollama_unavailable")):
            with self.subTest(code=code):
                session.post.side_effect = failure
                with self.assertRaises(InvoiceError) as raised:
                    OllamaService().analyze(b"image")
                self.assertEqual(raised.exception.code, code)

    @patch("services.ollama_service.requests.Session")
    def test_truncated_extraction_is_not_accepted_as_complete(self, session_class):
        self.request_mock(session_class, envelope={
            "done": True, "done_reason": "length", "message": {"content": '{"items": []}'}
        })
        with self.assertRaises(InvoiceError) as raised:
            OllamaService().analyze(b"image")
        self.assertEqual(raised.exception.code, "incomplete_analysis")

    @patch("services.ollama_service.requests.Session")
    def test_oversized_model_output_is_bounded(self, session_class):
        _, response = self.request_mock(session_class)
        response.iter_content.return_value = [b"x" * 1_048_577]
        with self.assertRaises(InvoiceError) as raised:
            OllamaService().analyze(b"image")
        self.assertEqual(raised.exception.code, "analysis_failed")



class BrowserReopenTests(unittest.TestCase):
    def setUp(self):
        self.ollama = Mock()
        self.ollama.analyze.return_value = json.dumps(example_invoice())
        self.app = create_app(self.ollama)
        self.client = self.app.test_client()

    def test_reopened_flutter_ports_are_allowed_and_echoed(self):
        for origin in ["http://localhost:60101", "http://localhost:54321",
                       "http://127.0.0.1:8081", "http://[::1]:54321",
                       "https://localhost:65535"]:
            with self.subTest(origin=origin):
                response = self.client.post("/api/invoice/analyze",
                    data={"image": (io.BytesIO(image_bytes()), "receipt.png")},
                    headers={"Origin": origin})
                self.assertEqual(response.status_code, 200)
                self.assertEqual(response.headers["Access-Control-Allow-Origin"], origin)
                self.assertIn("Origin", response.headers.get("Vary", ""))
                self.assertNotIn("Access-Control-Allow-Credentials", response.headers)
                self.assertEqual(response.json["invoice"]["total"], 115)

    def test_reopened_browser_preflight(self):
        origin = "http://localhost:60101"
        response = self.client.options("/api/invoice/analyze", headers={
            "Origin": origin, "Access-Control-Request-Method": "POST",
            "Access-Control-Request-Headers": "content-type",
        })
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.headers["Access-Control-Allow-Origin"], origin)
        self.assertIn("POST", response.headers["Access-Control-Allow-Methods"])
        self.assertIn("content-type", response.headers["Access-Control-Allow-Headers"].lower())
        self.ollama.analyze.assert_not_called()

    def test_unrelated_or_malformed_origins_cannot_analyze_invoices(self):
        for origin in ["https://unrelated.example", "http://localhost.evil.example:60101",
                       "http://127.0.0.1.evil.example:60101", "null",
                       "http://localhost:0", "http://localhost:65536", "http://localhost:123/path",
                       "http://user@localhost:123", "http://localhost:123?x=1",
                       "http://localhost:123#fragment", "http://192.168.1.99:123"]:
            with self.subTest(origin=origin):
                response = self.client.post("/api/invoice/analyze",
                    data={"image": (io.BytesIO(image_bytes()), "receipt.png")},
                    headers={"Origin": origin})
                self.assertEqual(response.status_code, 403)
                self.assertEqual(response.json["code"], "forbidden_origin")
                self.assertNotIn("Access-Control-Allow-Origin", response.headers)
        self.ollama.analyze.assert_not_called()

    @patch.dict("os.environ", {"NUMO_ALLOWED_ORIGINS": "http://192.168.1.163:8080"})
    def test_explicit_lan_origin_is_exact_and_preserves_loopback(self):
        client = create_app(self.ollama).test_client()
        for origin, status in [("http://192.168.1.163:8080", 200),
                               ("http://192.168.1.163:8081", 403),
                               ("http://localhost:60101", 200)]:
            response = client.get("/api/health", headers={"Origin": origin})
            self.assertEqual(response.status_code, status)

    def test_config_does_not_treat_origins_as_regex_or_wildcards(self):
        from utils.origin_policy import allowed_origin_patterns, origin_is_allowed
        with self.assertRaises(ValueError):
            allowed_origin_patterns("*")
        patterns = allowed_origin_patterns("https://dev.example")
        self.assertTrue(origin_is_allowed("https://dev.example", patterns))
        self.assertFalse(origin_is_allowed("https://devXexample", patterns))


if __name__ == "__main__":
    unittest.main()
