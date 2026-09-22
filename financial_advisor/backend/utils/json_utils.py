import json

from services.errors import InvoiceError

MAX_MODEL_TEXT_BYTES = 256 * 1024


def _unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("Duplicate JSON field")
        result[key] = value
    return result


def _reject_constant(_value):
    raise ValueError("Non-finite JSON number")


def _load_json(value):
    return json.loads(
        value, object_pairs_hook=_unique_object, parse_constant=_reject_constant
    )


def _json_spans(text):
    """Find complete outer JSON containers without extracting nested fragments."""
    spans = []
    stack = []
    quoted = False
    escaped = False
    start = None
    for index, char in enumerate(text):
        if not stack:
            if char in "{[":
                start = index
                stack.append(char)
            continue
        if quoted:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                quoted = False
            continue
        if char == '"':
            quoted = True
        elif char in "{[":
            stack.append(char)
        elif char in "}]":
            if (stack[-1], char) not in (("{", "}"), ("[", "]")):
                raise ValueError("Unbalanced JSON")
            stack.pop()
            if not stack:
                spans.append(text[start:index + 1])
    if stack:
        raise ValueError("Incomplete JSON")
    return spans


def parse_invoice_json(text):
    if not isinstance(text, str) or len(text.encode("utf-8")) > MAX_MODEL_TEXT_BYTES:
        raise InvoiceError("invalid_invoice_json", "Unable to parse invoice analysis.")
    text = text.strip().lstrip("\ufeff")
    try:
        try:
            value = _load_json(text)
        except json.JSONDecodeError:
            # Tolerate fences/prose, but never choose between multiple objects.
            spans = _json_spans(text)
            if len(spans) != 1:
                raise ValueError("Expected one JSON object")
            value = _load_json(spans[0])
        if not isinstance(value, dict):
            raise ValueError("Expected an invoice object")
        if "invoice" in value:
            if set(value) - {"invoice", "success", "warnings"}:
                raise ValueError("Ambiguous invoice envelope")
            if value.get("success") is False or not isinstance(value["invoice"], dict):
                raise ValueError("Invalid invoice envelope")
            value = value["invoice"]
        return value
    except (ValueError, TypeError, RecursionError) as error:
        raise InvoiceError(
            "invalid_invoice_json", "Unable to parse invoice analysis. Please try again."
        ) from error
