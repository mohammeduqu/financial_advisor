import base64
from dataclasses import FrozenInstanceError
import io
import json
import unittest
from unittest.mock import Mock, patch

from PIL import Image
import requests

from app import create_app
import ollama_config
from ollama_config import OllamaConfig, get_ollama_config
from services.errors import InvoiceError
from services.invoice_service import INVOICE_SCHEMA
from services.ollama_service import OllamaService


class OllamaConfigTests(unittest.TestCase):
    def config_for_url(self, url):
        with patch.dict(ollama_config.OLLAMA_TARGETS, {
            "test": {"base_url": url, "model": "test-model", "think": False},
        }):
            return get_ollama_config("test")

    def test_one_selector_switches_endpoint_model_and_thinking(self):
        for target, endpoint, model, think in (
            ("runpod", "https://x95wve7xogsidc-11434.proxy.runpod.net/api/chat", "gemma4:12b", False),
            ("local", "http://127.0.0.1:11434/api/chat", "qwen3-vl:4b-instruct", None),
        ):
            with self.subTest(target=target), patch.object(ollama_config, "ACTIVE_OLLAMA_TARGET", target):
                config = get_ollama_config()
                self.assertEqual(config.chat_url, endpoint)
                self.assertEqual(config.model, model)
                self.assertIs(config.think, think)

    def test_explicit_target_does_not_change_the_default(self):
        with patch.object(ollama_config, "ACTIVE_OLLAMA_TARGET", "local"):
            self.assertEqual(get_ollama_config("runpod").model, "gemma4:12b")
            self.assertEqual(get_ollama_config().model, "qwen3-vl:4b-instruct")

    def test_tags_and_chat_links_are_normalized_to_the_chat_endpoint(self):
        for suffix in ("", "/", "/api", "/api/", "/api/tags", "/api/tags/", "/api/chat", "/api/chat/"):
            with self.subTest(suffix=suffix):
                config = self.config_for_url("https://test.proxy.runpod.net" + suffix)
                self.assertEqual(config.base_url, "https://test.proxy.runpod.net")
                self.assertEqual(config.chat_url, "https://test.proxy.runpod.net/api/chat")

    def test_accepts_loopback_urls_and_preserves_the_port(self):
        for url in ("http://127.0.0.1:11434", "http://localhost:11434", "http://[::1]:11434"):
            with self.subTest(url=url):
                self.assertEqual(self.config_for_url(url).chat_url, url + "/api/chat")

    def test_invalid_urls_fail_without_echoing_private_config(self):
        for url in (
            "", "private-host", "ftp://private-host", "https:///private-host",
            "https://private-host?token=private-token", "https://private-host#private-token",
            "https://private-user:private-password@private-host", "https://private-host:70000",
            "https://private-host:not-a-port", "https://private host", "https://private-host\n.other",
        ):
            with self.subTest(url=url), self.assertRaises(ValueError) as raised:
                self.config_for_url(url)
            self.assertNotIn("private", str(raised.exception).lower())

    def test_unknown_target_fails_without_echoing_the_value(self):
        with self.assertRaises(ValueError) as raised:
            get_ollama_config("private-invalid-target")
        self.assertNotIn("private-invalid-target", str(raised.exception))

    def test_resolved_config_is_immutable(self):
        config = get_ollama_config("local")
        with self.assertRaises(FrozenInstanceError):
            config.base_url = "https://other.example"


class ConfiguredOllamaTransportTests(unittest.TestCase):
    def setUp(self):
        patcher = patch("services.ollama_service.requests.Session")
        self.session_class = patcher.start()
        self.addCleanup(patcher.stop)
        self.session = self.session_class.return_value.__enter__.return_value
        self.response = self.session.post.return_value.__enter__.return_value
        self.response.status_code = 200
        self.response.iter_content.return_value = [json.dumps({
            "done": True, "done_reason": "stop",
            "message": {"content": '{"merchant_name":"Test Store","currency":"SAR","total":12,"items":[]}'},
        }).encode()]

    def test_runpod_receives_the_invoice_schema_and_image_without_redirects(self):
        config = get_ollama_config("runpod")
        content = OllamaService(timeout_seconds=123, config=config).analyze(b"invoice-image")
        self.assertEqual(json.loads(content)["total"], 12)
        args, kwargs = self.session.post.call_args
        self.assertEqual(args, (config.chat_url,))
        self.assertEqual(kwargs["json"]["model"], "gemma4:12b")
        self.assertIs(kwargs["json"]["think"], False)
        self.assertIs(kwargs["json"]["stream"], False)
        self.assertEqual(kwargs["json"]["format"], INVOICE_SCHEMA)
        self.assertEqual(kwargs["json"]["messages"][1]["images"], [base64.b64encode(b"invoice-image").decode()])
        self.assertEqual(kwargs["timeout"], (5, 123))
        self.assertIs(kwargs["allow_redirects"], False)
        self.assertIs(kwargs["stream"], True)
        self.assertIs(self.session.trust_env, False)
        self.session.post.assert_called_once()

    def test_service_captures_selected_configuration_at_creation(self):
        with patch.object(ollama_config, "ACTIVE_OLLAMA_TARGET", "local"):
            service = OllamaService()
        with patch.object(ollama_config, "ACTIVE_OLLAMA_TARGET", "runpod"):
            service.analyze(b"invoice-image")
            other = OllamaService()
        args, kwargs = self.session.post.call_args
        self.assertEqual(args[0], "http://127.0.0.1:11434/api/chat")
        self.assertEqual(kwargs["json"]["model"], "qwen3-vl:4b-instruct")
        self.assertNotIn("think", kwargs["json"])
        self.assertEqual(other.config.model, "gemma4:12b")

    def test_proxy_errors_are_stable_and_do_not_leak_private_response_data(self):
        self.response.text = "PRIVATE RESPONSE https://private-pod.example/api/chat"
        for upstream_status, code, status in (
            (502, "ollama_unavailable", 503), (503, "ollama_unavailable", 503),
            (504, "analysis_timeout", 504), (524, "analysis_timeout", 504),
            (404, "model_not_installed", 503), (500, "analysis_failed", 502),
            (302, "analysis_failed", 502),
        ):
            with self.subTest(upstream_status=upstream_status):
                self.response.status_code = upstream_status
                self.session.post.reset_mock()
                with self.assertRaises(InvoiceError) as raised:
                    OllamaService(config=get_ollama_config("runpod")).analyze(b"invoice-image")
                self.assertEqual((raised.exception.code, raised.exception.status), (code, status))
                self.assertNotIn("private", raised.exception.message.lower())
                self.assertNotIn("http", raised.exception.message.lower())
                self.assertNotIn("local", raised.exception.message.lower())
                self.session.post.assert_called_once()

    def test_connection_failure_does_not_disclose_endpoint(self):
        self.session.post.side_effect = requests.ConnectionError("https://private-pod.example PRIVATE")
        with self.assertRaises(InvoiceError) as raised:
            OllamaService(config=get_ollama_config("runpod")).analyze(b"invoice-image")
        self.assertEqual(raised.exception.code, "ollama_unavailable")
        self.assertNotIn("private", raised.exception.message.lower())
        self.assertNotIn("http", raised.exception.message.lower())
        self.assertNotIn("local", raised.exception.message.lower())

    def test_existing_flutter_upload_contract_works_with_the_remote_model(self):
        buffer = io.BytesIO()
        Image.new("RGB", (80, 120), "white").save(buffer, format="PNG")
        client = create_app(
            ollama=OllamaService(config=get_ollama_config("runpod")), shopping=Mock(),
        ).test_client()
        response = client.post(
            "/api/invoice/analyze",
            data={"image": (io.BytesIO(buffer.getvalue()), "receipt.png")},
            content_type="multipart/form-data",
        )
        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.json["success"])
        self.assertEqual(response.json["invoice"]["total"], 12)
        self.assertIn("warnings", response.json)
        self.assertEqual(self.session.post.call_args.args[0], get_ollama_config("runpod").chat_url)

    def test_health_uses_the_injected_service_config_without_calling_the_model(self):
        config = OllamaConfig(base_url="https://private-pod.example", model="custom-invoice-model", think=False)
        client = create_app(ollama=OllamaService(config=config), shopping=Mock()).test_client()
        response = client.get("/api/health")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json["model"], "custom-invoice-model")
        self.assertNotIn("private-pod", response.get_data(as_text=True))
        self.session.post.assert_not_called()

    def test_health_can_report_the_active_model_for_an_injected_mock(self):
        with patch.object(ollama_config, "ACTIVE_OLLAMA_TARGET", "local"):
            client = create_app(ollama=Mock(), shopping=Mock()).test_client()
            response = client.get("/api/health")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json["model"], "qwen3-vl:4b-instruct")
        self.assertNotIn("127.0.0.1", response.get_data(as_text=True))
        self.session.post.assert_not_called()


if __name__ == "__main__":
    unittest.main()
