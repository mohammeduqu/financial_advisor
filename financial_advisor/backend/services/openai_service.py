"""Backend-only OpenAI vision transport for invoice and shopping-list extraction."""
import base64
import json

import requests

from services.errors import InvoiceError
from services.invoice_service import CATEGORIES, INVOICE_SCHEMA, SYSTEM_PROMPT

OPENAI_RESPONSES_URL = "https://api.openai.com/v1/responses"
MAX_RESPONSE_BYTES = 1024 * 1024


def _strict_schema(value):
    """Copy the shared schemas and require every object property for strict output."""
    if isinstance(value, list):
        return [_strict_schema(item) for item in value]
    if not isinstance(value, dict):
        return value
    result = {key: _strict_schema(item) for key, item in value.items()}
    if "properties" in result:
        result["required"] = list(result["properties"])
        result["additionalProperties"] = False
    return result


class OpenAIService:
    def __init__(self, settings):
        self.api_key = str(settings.get("OPENAI_API_KEY") or "").strip()
        self.model = settings.get("OPENAI_MODEL", "gpt-4.1-mini")
        self.timeout_seconds = settings.get("OPENAI_TIMEOUT_SECONDS", 120)
        self.max_output_tokens = settings.get("OPENAI_MAX_OUTPUT_TOKENS", 8192)
        self.image_detail = settings.get("OPENAI_IMAGE_DETAIL", "high")

    @property
    def configured(self):
        return bool(self.api_key)

    def analyze(self, image_bytes):
        return self.generate(
            image_bytes, INVOICE_SCHEMA, SYSTEM_PROMPT,
            "Extract this invoice. Allowed categories: " + ", ".join(CATEGORIES),
        )

    def generate(self, image_bytes, schema, system_prompt, user_prompt):
        if not self.api_key:
            raise InvoiceError(
                "ai_not_configured", "Invoice analysis has not been configured. Please contact support.", 503,
            )
        content = [{"type": "input_text", "text": user_prompt}]
        if image_bytes is not None:
            # Routes prepare JPEG bytes first, stripping receipt EXIF/location data.
            content.append({
                "type": "input_image",
                "image_url": "data:image/jpeg;base64," + base64.b64encode(image_bytes).decode("ascii"),
                "detail": self.image_detail,
            })
        payload = {
            "model": self.model,
            "store": False,
            "stream": False,
            "max_output_tokens": self.max_output_tokens,
            "input": [
                {"role": "system", "content": [{"type": "input_text", "text": system_prompt}]},
                {"role": "user", "content": content},
            ],
            "text": {"format": {
                "type": "json_schema", "name": "extracted_data", "strict": True,
                "schema": _strict_schema(schema),
            }},
        }
        try:
            with requests.Session() as session:
                # The key and receipt go only to OpenAI, without proxy env vars,
                # redirects, or automatic retries that could create extra charges.
                session.trust_env = False
                with session.post(
                    OPENAI_RESPONSES_URL,
                    headers={"Authorization": f"Bearer {self.api_key}", "Accept": "application/json"},
                    json=payload, timeout=(5, self.timeout_seconds),
                    allow_redirects=False, stream=True,
                ) as response:
                    self._check_status(response.status_code)
                    chunks, size = [], 0
                    for chunk in response.iter_content(chunk_size=16 * 1024):
                        size += len(chunk)
                        if size > MAX_RESPONSE_BYTES:
                            raise InvoiceError("analysis_failed", "AI analysis returned too much data.", 502)
                        chunks.append(chunk)
            return self._read_output(json.loads(b"".join(chunks)))
        except requests.Timeout:
            raise InvoiceError("analysis_timeout", "Invoice analysis timed out. Please try again.", 504) from None
        except requests.ConnectionError:
            raise InvoiceError("ai_unavailable", "Invoice analysis is temporarily unavailable. Please try again later.", 503) from None
        except requests.RequestException:
            raise InvoiceError("analysis_failed", "AI analysis failed. Please try again.", 502) from None
        except (ValueError, TypeError, AttributeError):
            raise InvoiceError("analysis_failed", "AI analysis returned an invalid response.", 502) from None

    @staticmethod
    def _check_status(status):
        if status == 200:
            return
        errors = {
            400: ("ai_configuration_error", "Invoice analysis is not configured correctly. Please contact support.", 503),
            401: ("ai_authentication_failed", "Invoice analysis authorization failed. Please contact support.", 503),
            403: ("ai_authentication_failed", "Invoice analysis authorization failed. Please contact support.", 503),
            404: ("ai_model_unavailable", "The selected invoice model is unavailable. Please contact support.", 503),
            408: ("analysis_timeout", "Invoice analysis timed out. Please try again.", 504),
            429: ("ai_rate_limited", "Invoice analysis has reached its usage limit. Please try again later.", 429),
            500: ("ai_unavailable", "Invoice analysis is temporarily unavailable. Please try again later.", 503),
            502: ("ai_unavailable", "Invoice analysis is temporarily unavailable. Please try again later.", 503),
            503: ("ai_unavailable", "Invoice analysis is temporarily unavailable. Please try again later.", 503),
            504: ("analysis_timeout", "Invoice analysis timed out. Please try again.", 504),
            524: ("analysis_timeout", "Invoice analysis timed out. Please try again.", 504),
        }
        raise InvoiceError(*errors.get(status, ("analysis_failed", "AI analysis failed. Please try again.", 502)))

    @staticmethod
    def _read_output(envelope):
        if not isinstance(envelope, dict):
            raise ValueError("Invalid response envelope")
        if envelope.get("status") == "incomplete":
            details = envelope.get("incomplete_details") or {}
            if isinstance(details, dict) and details.get("reason") == "content_filter":
                raise InvoiceError("analysis_refused", "This image or text could not be analyzed. Please try another.", 422)
            raise InvoiceError(
                "incomplete_analysis", "The invoice is too long. Photograph a smaller section and try again.", 422,
            )
        if envelope.get("status") != "completed" or envelope.get("error"):
            raise ValueError("Unsuccessful response")
        output = envelope.get("output")
        if not isinstance(output, list):
            raise ValueError("Missing response output")
        texts = []
        for item in output:
            if not isinstance(item, dict):
                raise ValueError("Invalid response output")
            if item.get("type") != "message":
                continue
            if item.get("status") == "incomplete":
                raise InvoiceError(
                    "incomplete_analysis", "The invoice is too long. Photograph a smaller section and try again.", 422,
                )
            blocks = item.get("content")
            if not isinstance(blocks, list):
                raise ValueError("Invalid message content")
            for block in blocks:
                if not isinstance(block, dict):
                    raise ValueError("Invalid message content")
                if block.get("type") == "refusal":
                    raise InvoiceError("analysis_refused", "This image or text could not be analyzed. Please try another.", 422)
                if block.get("type") == "output_text":
                    text = block.get("text")
                    if not isinstance(text, str):
                        raise ValueError("Invalid output text")
                    texts.append(text)
        result = "".join(texts)
        if not result.strip():
            raise ValueError("Missing output text")
        return result
