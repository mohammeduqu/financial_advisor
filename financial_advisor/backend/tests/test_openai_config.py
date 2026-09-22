import io
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock, patch

from PIL import Image

from app import create_app
from config import load_settings
from services.openai_service import OpenAIService


def receipt_image():
    buffer = io.BytesIO()
    Image.new("RGB", (80, 120), "white").save(buffer, format="PNG")
    return io.BytesIO(buffer.getvalue())


def receipt_data():
    return {
        "merchant_name": "Example Store", "currency": "SAR", "total": 12,
        "category": "Food", "items": [
            {"name": "Milk", "quantity": 1, "unit_price": 12, "total_price": 12,
             "category": "Food"},
        ],
    }


class OpenAIConfigTests(unittest.TestCase):
    def setUp(self):
        env = patch.dict(os.environ, {}, clear=True)
        env.start()
        self.addCleanup(env.stop)
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.directory = Path(temporary.name)
        directory = patch("config.BACKEND_DIR", self.directory)
        directory.start()
        self.addCleanup(directory.stop)

    def test_defaults_allow_startup_without_a_key(self):
        settings = load_settings()
        self.assertEqual(settings["OPENAI_API_KEY"], "")
        self.assertEqual(settings["OPENAI_MODEL"], "gpt-4.1-mini")
        self.assertEqual(settings["OPENAI_TIMEOUT_SECONDS"], 120)
        self.assertEqual(settings["OPENAI_MAX_OUTPUT_TOKENS"], 8192)
        self.assertEqual(settings["OPENAI_IMAGE_DETAIL"], "high")
        self.assertFalse(OpenAIService(settings).configured)

    def test_one_backend_dotenv_controls_key_and_model_with_environment_precedence(self):
        (self.directory / ".env").write_text(
            "OPENAI_API_KEY=synthetic-dotenv-key\nOPENAI_MODEL=gpt-4.1\n"
            "OPENAI_TIMEOUT_SECONDS=75.5\nOPENAI_MAX_OUTPUT_TOKENS=4096\n"
            "OPENAI_IMAGE_DETAIL=auto\n",
            encoding="utf-8",
        )
        settings = load_settings()
        self.assertEqual(settings["OPENAI_API_KEY"], "synthetic-dotenv-key")
        self.assertEqual(settings["OPENAI_MODEL"], "gpt-4.1")
        self.assertEqual(settings["OPENAI_TIMEOUT_SECONDS"], 75.5)
        self.assertEqual(settings["OPENAI_MAX_OUTPUT_TOKENS"], 4096)
        self.assertEqual(settings["OPENAI_IMAGE_DETAIL"], "auto")
        with patch.dict(os.environ, {
            "OPENAI_API_KEY": "synthetic-process-key", "OPENAI_MODEL": "gpt-4.1-mini",
        }):
            settings = load_settings()
            self.assertEqual(settings["OPENAI_API_KEY"], "synthetic-process-key")
            self.assertEqual(settings["OPENAI_MODEL"], "gpt-4.1-mini")
            overridden = load_settings({"OPENAI_API_KEY": "", "OPENAI_MODEL": "test-model"})
            self.assertEqual(overridden["OPENAI_API_KEY"], "")
            self.assertEqual(overridden["OPENAI_MODEL"], "test-model")

    def test_config_values_are_trimmed_without_restricting_supported_model_ids(self):
        settings = load_settings({
            "OPENAI_API_KEY": "  synthetic-key  ",
            "OPENAI_MODEL": " gpt-4.1-2025-04-14 ",
            "OPENAI_IMAGE_DETAIL": " HIGH ",
        })
        self.assertEqual(settings["OPENAI_API_KEY"], "synthetic-key")
        self.assertEqual(settings["OPENAI_MODEL"], "gpt-4.1-2025-04-14")
        self.assertEqual(settings["OPENAI_IMAGE_DETAIL"], "high")

    def test_invalid_limits_fail_before_any_request_without_echoing_values(self):
        for name, values in (
            ("OPENAI_TIMEOUT_SECONDS", [0, 301, "NaN", "Infinity", "private-invalid"]),
            ("OPENAI_MAX_OUTPUT_TOKENS", [511, 32769, "4096.5", "private-invalid"]),
        ):
            for value in values:
                with self.subTest(name=name, value=value), self.assertRaises(ValueError) as raised:
                    load_settings({name: value})
                self.assertIn(name, str(raised.exception))
                self.assertNotIn("private-invalid", str(raised.exception))

    def test_invalid_model_key_and_detail_fail_without_disclosing_secrets(self):
        for override in (
            {"OPENAI_MODEL": "private invalid model"},
            {"OPENAI_MODEL": "private\nmodel"},
            {"OPENAI_MODEL": " "},
            {"OPENAI_MODEL": "private" * 30},
            {"OPENAI_API_KEY": "private key"},
            {"OPENAI_API_KEY": "private\nkey"},
            {"OPENAI_IMAGE_DETAIL": "private-invalid"},
        ):
            with self.subTest(setting=next(iter(override))), self.assertRaises(ValueError) as raised:
                load_settings(override)
            self.assertNotIn("private", str(raised.exception))


class OpenAIFlaskIntegrationTests(unittest.TestCase):
    def setUp(self):
        env = patch.dict(os.environ, {}, clear=True)
        env.start()
        self.addCleanup(env.stop)
        dotenv = patch("config.dotenv_values", return_value={})
        dotenv.start()
        self.addCleanup(dotenv.stop)
        session_patch = patch("services.openai_service.requests.Session")
        self.session_class = session_patch.start()
        self.addCleanup(session_patch.stop)
        self.session = self.session_class.return_value.__enter__.return_value
        self.upstream = self.session.post.return_value.__enter__.return_value
        self.upstream.status_code = 200
        self.set_output(receipt_data())
        self.shopping = Mock()
        self.app = create_app(shopping=self.shopping, recommendation_config={
            "OPENAI_API_KEY": "synthetic-private-key", "OPENAI_MODEL": "test-vision-model",
        })
        self.app.config["TESTING"] = True
        self.client = self.app.test_client()

    def set_output(self, data):
        self.upstream.iter_content.return_value = [json.dumps({
            "status": "completed", "output": [{
                "type": "message", "status": "completed", "role": "assistant",
                "content": [{"type": "output_text", "text": json.dumps(data)}],
            }],
        }).encode("utf-8")]

    def upload(self, path="/api/invoice/analyze"):
        return self.client.post(path, data={"image": (receipt_image(), "receipt.png")},
                                content_type="multipart/form-data")

    def test_default_provider_sends_invoice_and_preserves_flutter_response_contract(self):
        self.assertIsInstance(self.app.extensions["ai_service"], OpenAIService)
        response = self.upload()
        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.json["success"])
        self.assertEqual(response.json["invoice"]["total"], 12)
        self.assertEqual(response.json["invoice"]["items"][0]["name"], "Milk")
        self.assertIn("warnings", response.json)
        self.assertEqual(response.headers["Cache-Control"], "no-store")
        self.assertNotIn("synthetic-private-key", response.get_data(as_text=True))
        self.session.post.assert_called_once()
        self.assertEqual(self.session.post.call_args.args[0], "https://api.openai.com/v1/responses")
        self.assertEqual(self.session.post.call_args.kwargs["json"]["model"], "test-vision-model")
        self.shopping.search_products.assert_not_called()

    def test_all_existing_extraction_routes_use_openai_without_searching_prices(self):
        for path, data in (
            ("/api/recommendations/invoice", receipt_data()),
            ("/api/recommendations/product", {"name": "Whole Milk 1L", "category": "Food"}),
            ("/api/recommendations/shopping-list", {
                "source_type": "shopping_list", "currency": None,
                "items": [{"name": "Whole Milk 1L", "quantity": 2}],
            }),
        ):
            with self.subTest(path=path):
                self.set_output(data)
                self.session.post.reset_mock()
                response = self.upload(path)
                self.assertEqual(response.status_code, 200, response.json)
                self.assertEqual(response.json["stage"], "review")
                self.session.post.assert_called_once()
                self.assertEqual(self.session.post.call_args.kwargs["json"]["model"], "test-vision-model")
        self.shopping.search_products.assert_not_called()

    def test_list_text_uses_openai_but_product_text_does_not_need_inference(self):
        self.set_output({"source_type": "shopping_list", "currency": None,
                         "items": [{"name": "Milk", "quantity": 2}]})
        response = self.client.post("/api/recommendations/shopping-list", json={"text": "2 milk"})
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json["stage"], "review")
        self.session.post.assert_called_once()
        self.session.post.reset_mock()
        response = self.client.post("/api/recommendations/product", json={"text": "Whole Milk 1L"})
        self.assertEqual(response.status_code, 200)
        self.session.post.assert_not_called()
        self.shopping.search_products.assert_not_called()

    def test_health_reports_configuration_without_sending_key_or_checking_inference(self):
        response = self.client.get("/api/health")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json, {
            "success": True, "service": "numo-invoice", "provider": "openai",
            "model": "test-vision-model", "model_configured": True,
        })
        self.assertNotIn("synthetic-private-key", response.get_data(as_text=True))
        self.assertNotIn("https://", response.get_data(as_text=True))
        self.session_class.assert_not_called()

    def test_health_uses_injected_provider_model_and_configuration(self):
        service = OpenAIService(load_settings({"OPENAI_API_KEY": "", "OPENAI_MODEL": "injected-model"}))
        client = create_app(ai_service=service, shopping=Mock(), recommendation_config={
            "OPENAI_API_KEY": "synthetic-key", "OPENAI_MODEL": "other-model",
        }).test_client()
        response = client.get("/api/health")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json["model"], "injected-model")
        self.assertFalse(response.json["model_configured"])
        self.session_class.assert_not_called()

    def test_missing_key_keeps_health_available_and_returns_safe_scanning_error(self):
        client = create_app(shopping=Mock(), recommendation_config={"OPENAI_API_KEY": ""}).test_client()
        health = client.get("/api/health")
        self.assertEqual(health.status_code, 200)
        self.assertTrue(health.json["success"])
        self.assertFalse(health.json["model_configured"])
        for _ in range(2):
            response = client.post("/api/invoice/analyze", data={"image": (receipt_image(), "receipt.png")})
            self.assertEqual(response.status_code, 503)
            self.assertFalse(response.json["success"])
            self.assertEqual(response.json["code"], "ai_not_configured")
            self.assertNotIn("https://", response.get_data(as_text=True))
        self.session_class.assert_not_called()


if __name__ == "__main__":
    unittest.main()
