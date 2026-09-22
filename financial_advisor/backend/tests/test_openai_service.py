import base64
import copy
import json
import traceback
import unittest
from unittest.mock import patch

import requests

from services.errors import InvoiceError
from services.invoice_service import INVOICE_SCHEMA
from services.openai_service import MAX_RESPONSE_BYTES, OPENAI_RESPONSES_URL, OpenAIService
from services.product_recognition_service import PRODUCT_PROMPT, PRODUCT_SCHEMA
from services.shopping_list_service import LIST_PROMPT, LIST_SCHEMA


def completed(text='{"total": 12.5}'):
    return {
        "status": "completed", "error": None,
        "output": [{
            "type": "message", "status": "completed", "role": "assistant",
            "content": [{"type": "output_text", "text": text}],
        }],
    }


class OpenAIServiceTests(unittest.TestCase):
    def setUp(self):
        self.settings = {"OPENAI_API_KEY": "dummy-test-key"}
        self.service = OpenAIService(self.settings)
        self.session_patch = patch("services.openai_service.requests.Session")
        self.session_type = self.session_patch.start()
        self.addCleanup(self.session_patch.stop)
        self.session = self.session_type.return_value.__enter__.return_value
        self.response = self.session.post.return_value.__enter__.return_value
        self.respond(completed())

    def respond(self, envelope, status=200):
        self.response.status_code = status
        self.response.iter_content.return_value = [json.dumps(envelope).encode()]

    def assert_error(self, code, status):
        with self.assertRaises(InvoiceError) as raised:
            self.service.analyze(b"prepared jpeg image")
        self.assertEqual(raised.exception.code, code)
        self.assertEqual(raised.exception.status, status)
        return raised.exception

    def test_invoice_request_uses_openai_vision_and_strict_output(self):
        original_schema = copy.deepcopy(INVOICE_SCHEMA)
        result = self.service.analyze(b"prepared jpeg image")
        self.assertEqual(result, '{"total": 12.5}')
        self.session.post.assert_called_once()
        args, kwargs = self.session.post.call_args
        self.assertEqual(args, (OPENAI_RESPONSES_URL,))
        self.assertEqual(kwargs["headers"]["Authorization"], "Bearer dummy-test-key")
        self.assertFalse(self.session.trust_env)
        self.assertFalse(kwargs["allow_redirects"])
        self.assertTrue(kwargs["stream"])
        self.assertEqual(kwargs["timeout"], (5, 120))
        payload = kwargs["json"]
        self.assertEqual(payload["model"], "gpt-4.1-mini")
        self.assertFalse(payload["store"])
        self.assertFalse(payload["stream"])
        self.assertEqual(payload["max_output_tokens"], 8192)
        self.assertNotIn("temperature", payload)
        self.assertNotIn("tools", payload)
        image = payload["input"][1]["content"][1]
        self.assertEqual(image["type"], "input_image")
        self.assertEqual(image["detail"], "high")
        self.assertEqual(image["image_url"], "data:image/jpeg;base64," + base64.b64encode(b"prepared jpeg image").decode())
        output_format = payload["text"]["format"]
        self.assertEqual(output_format["type"], "json_schema")
        self.assertTrue(output_format["strict"])
        strict = output_format["schema"]
        self.assertEqual(set(strict["required"]), set(INVOICE_SCHEMA["properties"]))
        item = strict["properties"]["items"]["items"]
        self.assertEqual(set(item["required"]), set(item["properties"]))
        self.assertEqual(INVOICE_SCHEMA, original_schema)

    def test_model_and_limits_can_be_changed_in_settings(self):
        self.service = OpenAIService({
            **self.settings, "OPENAI_MODEL": "gpt-4.1", "OPENAI_TIMEOUT_SECONDS": 60,
            "OPENAI_MAX_OUTPUT_TOKENS": 4096, "OPENAI_IMAGE_DETAIL": "auto",
        })
        self.service.analyze(b"jpeg")
        kwargs = self.session.post.call_args.kwargs
        self.assertEqual(kwargs["json"]["model"], "gpt-4.1")
        self.assertEqual(kwargs["json"]["max_output_tokens"], 4096)
        self.assertEqual(kwargs["json"]["input"][1]["content"][1]["detail"], "auto")
        self.assertEqual(kwargs["timeout"], (5, 60))

    def test_text_only_list_does_not_send_an_image(self):
        self.service.generate(None, LIST_SCHEMA, LIST_PROMPT, "untrusted shopping list")
        messages = self.session.post.call_args.kwargs["json"]["input"]
        self.assertEqual(messages, [
            {"role": "system", "content": [{"type": "input_text", "text": LIST_PROMPT}]},
            {"role": "user", "content": [{"type": "input_text", "text": "untrusted shopping list"}]},
        ])

    def test_product_schema_remains_supported_without_mutation(self):
        before = copy.deepcopy(PRODUCT_SCHEMA)
        self.service.generate(b"product jpeg", PRODUCT_SCHEMA, PRODUCT_PROMPT, "Identify this retail product.")
        payload = self.session.post.call_args.kwargs["json"]
        schema = payload["text"]["format"]["schema"]
        self.assertEqual(set(schema["required"]), set(PRODUCT_SCHEMA["properties"]))
        self.assertFalse(schema["additionalProperties"])
        self.assertEqual(PRODUCT_SCHEMA, before)
        self.assertEqual(payload["input"][0]["content"][0]["text"], PRODUCT_PROMPT)
        self.assertEqual(payload["input"][1]["content"][1]["type"], "input_image")

    def test_configuration_status_reveals_only_presence(self):
        self.assertTrue(self.service.configured)
        self.assertFalse(OpenAIService({}).configured)
        self.assertFalse(OpenAIService({"OPENAI_API_KEY": "  "}).configured)

    def test_strict_schema_copies_nested_objects_and_requires_optional_fields(self):
        schema = {
            "type": "object", "properties": {
                "items": {"type": "array", "items": {
                    "type": "object", "properties": {"label": {"type": ["string", "null"]}},
                }},
                "nested": {"anyOf": [{"type": "null"}, {
                    "type": "object", "properties": {"count": {"type": "integer"}},
                }]},
            }, "required": [],
        }
        before = copy.deepcopy(schema)
        self.service.generate(None, schema, "system", "list")
        strict = self.session.post.call_args.kwargs["json"]["text"]["format"]["schema"]
        self.assertEqual(schema, before)
        self.assertEqual(strict["required"], ["items", "nested"])
        self.assertFalse(strict["additionalProperties"])
        self.assertEqual(strict["properties"]["items"]["items"]["required"], ["label"])
        self.assertFalse(strict["properties"]["items"]["items"]["additionalProperties"])
        self.assertEqual(strict["properties"]["nested"]["anyOf"][1]["required"], ["count"])

    def test_missing_key_fails_before_creating_network_session(self):
        for key in (None, "", "  "):
            with self.subTest(key=key):
                self.service = OpenAIService({"OPENAI_API_KEY": key})
                self.assert_error("ai_not_configured", 503)
        self.session_type.assert_not_called()

    def test_status_errors_are_safe_and_never_read_or_retry_error_bodies(self):
        cases = {
            400: ("ai_configuration_error", 503),
            401: ("ai_authentication_failed", 503),
            403: ("ai_authentication_failed", 503),
            404: ("ai_model_unavailable", 503),
            408: ("analysis_timeout", 504),
            429: ("ai_rate_limited", 429),
            500: ("ai_unavailable", 503),
            502: ("ai_unavailable", 503),
            503: ("ai_unavailable", 503),
            504: ("analysis_timeout", 504),
            524: ("analysis_timeout", 504),
            302: ("analysis_failed", 502),
            418: ("analysis_failed", 502),
        }
        for http_status, expected in cases.items():
            with self.subTest(http_status=http_status):
                self.session.post.reset_mock()
                self.response.iter_content.reset_mock()
                self.respond({"error": "private receipt data dummy-test-key"}, http_status)
                error = self.assert_error(*expected)
                self.assertNotIn("private", str(error))
                self.assertNotIn("dummy-test-key", str(error))
                self.session.post.assert_called_once()
                self.response.iter_content.assert_not_called()

    def test_request_errors_hide_sensitive_exception_details(self):
        cases = [
            (requests.Timeout, "analysis_timeout", 504),
            (requests.ConnectionError, "ai_unavailable", 503),
            (requests.RequestException, "analysis_failed", 502),
        ]
        for error_type, code, status in cases:
            with self.subTest(error_type=error_type):
                self.session.post.reset_mock()
                self.session.post.side_effect = error_type("dummy-test-key private image content")
                error = self.assert_error(code, status)
                printed = "".join(traceback.format_exception(error))
                self.assertNotIn("dummy-test-key", printed)
                self.assertNotIn("private image content", printed)
                self.session.post.assert_called_once()

    def test_response_body_read_error_is_safe(self):
        self.response.iter_content.side_effect = requests.ConnectionError("private receipt content")
        error = self.assert_error("ai_unavailable", 503)
        self.assertNotIn("private receipt content", str(error))

    def test_response_size_is_bounded(self):
        self.response.iter_content.return_value = [b"x" * MAX_RESPONSE_BYTES, b"x"]
        self.assert_error("analysis_failed", 502)

    def test_chunked_json_response_is_read(self):
        encoded = json.dumps(completed('{"merchant_name":"متجر"}')).encode()
        self.response.iter_content.return_value = [encoded[:10], b"", encoded[10:]]
        self.assertEqual(self.service.analyze(b"jpeg"), '{"merchant_name":"متجر"}')

    def test_invalid_json_response_is_safe(self):
        self.response.iter_content.return_value = [b"invalid private response"]
        error = self.assert_error("analysis_failed", 502)
        self.assertNotIn("private response", str(error))

    def test_refusal_is_not_treated_as_invoice_json(self):
        envelope = completed()
        envelope["output"][0]["content"].append({"type": "refusal", "refusal": "private refusal reason"})
        self.respond(envelope)
        error = self.assert_error("analysis_refused", 422)
        self.assertNotIn("private refusal", str(error))

    def test_incomplete_output_is_not_treated_as_complete_invoice(self):
        envelope = completed('{"total":')
        envelope.update(status="incomplete", incomplete_details={"reason": "max_output_tokens"})
        self.respond(envelope)
        self.assert_error("incomplete_analysis", 422)

    def test_content_filter_incomplete_maps_to_refusal(self):
        self.respond({"status": "incomplete", "incomplete_details": {"reason": "content_filter"}})
        self.assert_error("analysis_refused", 422)

    def test_incomplete_message_is_rejected_even_if_envelope_says_completed(self):
        envelope = completed()
        envelope["output"][0]["status"] = "incomplete"
        self.respond(envelope)
        self.assert_error("incomplete_analysis", 422)

    def test_reasoning_output_is_skipped_and_all_text_blocks_are_joined(self):
        envelope = completed('{"total":')
        envelope["output"].insert(0, {"type": "reasoning", "summary": []})
        envelope["output"][1]["content"].append({"type": "output_text", "text": "12.5}"})
        self.respond(envelope)
        self.assertEqual(self.service.analyze(b"jpeg"), '{"total":12.5}')

    def test_malformed_envelopes_fail_safely(self):
        cases = [
            [], None, {}, {"status": "in_progress"},
            {"status": "failed", "error": {"message": "private information"}},
            {"status": "completed", "output": None},
            {"status": "completed", "output": []},
            {"status": "completed", "output": [None]},
            {"status": "completed", "output": [{"type": "message", "content": None}]},
            {"status": "completed", "output": [{"type": "message", "content": [None]}]},
            completed("  "), completed(None),
        ]
        for envelope in cases:
            with self.subTest(envelope=envelope):
                self.respond(envelope)
                self.assert_error("analysis_failed", 502)


if __name__ == "__main__":
    unittest.main()
