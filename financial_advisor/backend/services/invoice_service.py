import io
import re
import warnings
from datetime import date
from decimal import Decimal, InvalidOperation, ROUND_HALF_UP

from PIL import Image, ImageOps, UnidentifiedImageError

from services.errors import InvoiceError
from utils.json_utils import parse_invoice_json

MAX_IMAGE_BYTES = 8 * 1024 * 1024
MAX_IMAGE_PIXELS = 20_000_000
MAX_ITEMS = 200
CATEGORIES = (
    "Food", "Transportation", "Housing", "Utilities", "Shopping", "Healthcare",
    "Entertainment", "Education", "Subscriptions", "Travel", "Other",
)
_DIGITS = str.maketrans(
    "٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹٫٬", "01234567890123456789.,"
)
_CATEGORY_ALIASES = {
    "foods": "Food", "groceries": "Food", "grocery": "Food", "dining": "Food",
    "restaurant": "Food", "طعام": "Food", "الطعام": "Food", "أطعمة": "Food",
    "الأطعمة": "Food", "غذاء": "Food", "مطاعم": "Food", "بقالة": "Food",
    "transport": "Transportation", "fuel": "Transportation", "مواصلات": "Transportation",
    "المواصلات": "Transportation", "النقل": "Transportation", "نقل": "Transportation",
    "وقود": "Transportation", "health": "Healthcare", "medical": "Healthcare",
    "صحة": "Healthcare", "الصحة": "Healthcare", "الرعاية الصحية": "Healthcare",
    "صيدلية": "Healthcare", "دواء": "Healthcare", "rent": "Housing",
    "سكن": "Housing", "السكن": "Housing", "إيجار": "Housing", "منزل": "Housing",
    "مرافق": "Utilities", "المرافق": "Utilities", "فواتير": "Utilities",
    "تسوق": "Shopping", "التسوق": "Shopping", "ترفيه": "Entertainment",
    "الترفيه": "Entertainment", "تعليم": "Education", "التعليم": "Education",
    "اشتراكات": "Subscriptions", "الاشتراكات": "Subscriptions",
    "سفر": "Travel", "السفر": "Travel", "miscellaneous": "Other",
    "misc": "Other", "أخرى": "Other", "اخرى": "Other", "متفرقات": "Other",
    "savings": "Other", "debt": "Other",
}
_CURRENCY_ALIASES = {
    "ر.س": "SAR", "ر.س.": "SAR", "ريال": "SAR", "ريال سعودي": "SAR",
    "الريال السعودي": "SAR", "saudi riyal": "SAR", "sr": "SAR",
    "د.إ": "AED", "درهم إماراتي": "AED", "€": "EUR", "£": "GBP",
    "us$": "USD", "دولار أمريكي": "USD",
}
_AMOUNT_CURRENCY = re.compile(
    r"(?:SAR|USD|AED|EUR|GBP|EGP|KWD|BHD|QAR|OMR|SR|ر\.س\.?|ريال(?: سعودي)?|[€£$])",
    re.IGNORECASE,
)
NULL_STRING = {"", "null", "none", "n/a", "unknown", "غير معروف", "غير متوفر"}


def _nullable(kind):
    return {"type": [kind, "null"]}


PRODUCT_IDENTITY_PROPERTIES = {
    **{field: _nullable("string") for field in ("brand", "model", "variant", "search_query")},
    "size_value": _nullable("number"),
    "size_unit": {"type": ["string", "null"], "enum": ["ml", "l", "g", "kg", "unit", None]},
    "pack_size": _nullable("integer"),
    "condition": {"type": ["string", "null"], "enum": ["new", "used", "refurbished", None]},
    "confidence": _nullable("number"),
}


def normalize_product_fields(raw):
    """Optional visible product identity; absent attributes are never invented."""
    fields = {key: _text(raw.get(key), 300) for key in ("brand", "model", "variant", "search_query")}
    size = _number(raw.get("size_value"), quantity=True)
    unit = _text(raw.get("size_unit"), 30)
    units = {"ml": "ml", "milliliter": "ml", "مل": "ml", "l": "l", "liter": "l",
             "litre": "l", "لتر": "l", "g": "g", "gram": "g", "غرام": "g",
             "kg": "kg", "kilogram": "kg", "كجم": "kg", "unit": "unit",
             "item": "unit", "piece": "unit", "قطعة": "unit"}
    fields["size_unit"] = units.get(unit.casefold()) if unit else None
    fields["size_value"] = size if fields["size_unit"] and size and size > 0 else None
    if fields["size_value"] is None:
        fields["size_unit"] = None
    pack = _number(raw.get("pack_size"), quantity=True)
    fields["pack_size"] = int(pack) if pack and pack.is_integer() and pack <= 10000 else None
    condition = _text(raw.get("condition"), 30)
    fields["condition"] = condition.casefold() if condition and condition.casefold() in {
        "new", "used", "refurbished"} else None
    confidence = _number(raw.get("confidence"))
    fields["confidence"] = confidence if confidence is not None and confidence <= 1 else None
    return fields


ITEM_SCHEMA = {
    "type": "object", "additionalProperties": False,
    "properties": {
        **PRODUCT_IDENTITY_PROPERTIES,
        "name": _nullable("string"), "quantity": _nullable("number"),
        "unit_price": _nullable("number"), "total_price": _nullable("number"),
        "category": {"type": ["string", "null"], "enum": [*CATEGORIES, None]},
    },
    "required": ["name", "quantity", "unit_price", "total_price", "category", *PRODUCT_IDENTITY_PROPERTIES],
}
INVOICE_SCHEMA = {
    "type": "object", "additionalProperties": False,
    "properties": {
        "merchant_name": _nullable("string"), "invoice_number": _nullable("string"),
        "date": _nullable("string"), "currency": _nullable("string"),
        "subtotal": _nullable("number"), "tax": _nullable("number"),
        "discount": _nullable("number"), "total": _nullable("number"),
        "category": {"type": ["string", "null"], "enum": [*CATEGORIES, None]},
        "items": {"type": "array", "maxItems": MAX_ITEMS, "items": ITEM_SCHEMA},
    },
    "required": [
        "merchant_name", "invoice_number", "date", "currency", "subtotal", "tax",
        "discount", "total", "category", "items",
    ],
}


def prepare_image(data):
    if not data:
        raise InvoiceError("missing_image", "Please select an invoice image.", 400)
    if len(data) > MAX_IMAGE_BYTES:
        raise InvoiceError("image_too_large", "The image must be 8 MB or smaller.", 413)
    try:
        with warnings.catch_warnings():
            warnings.simplefilter("error", Image.DecompressionBombWarning)
            with Image.open(io.BytesIO(data)) as original:
                if original.format not in {"JPEG", "PNG"}:
                    raise InvoiceError("unsupported_image", "Use a JPG, JPEG or PNG image.", 415)
                if original.width * original.height > MAX_IMAGE_PIXELS:
                    raise InvoiceError("image_too_large", "The image exceeds 20 megapixels.", 413)
                original.verify()
            with Image.open(io.BytesIO(data)) as original:
                corrected = ImageOps.exif_transpose(original)
                corrected.thumbnail((2400, 2400))
                if corrected.mode in {"RGBA", "LA"} or "transparency" in corrected.info:
                    rgba = corrected.convert("RGBA")
                    image = Image.new("RGB", rgba.size, "white")
                    image.paste(rgba, mask=rgba.getchannel("A"))
                else:
                    image = corrected.convert("RGB")
                output = io.BytesIO()
                # Re-encoding strips EXIF/location metadata; nothing is written to disk.
                image.save(output, format="JPEG", quality=90)
                return output.getvalue()
    except (Image.DecompressionBombWarning, Image.DecompressionBombError) as error:
        raise InvoiceError("image_too_large", "The image dimensions are too large.", 413) from error
    except (UnidentifiedImageError, OSError, ValueError, SyntaxError) as error:
        raise InvoiceError("invalid_image", "The image is damaged or could not be opened.", 400) from error


def _text(value, limit=300):
    if not isinstance(value, str):
        return None
    value = " ".join(value.strip().split())
    if value.casefold() in NULL_STRING or len(value) > limit:
        return None
    return value


def _number(value, quantity=False):
    if value is None or isinstance(value, bool):
        return None
    if isinstance(value, str):
        value = value.translate(_DIGITS).strip()
        # Only remove a currency token at the edges, never arbitrary invoice text.
        value = re.sub(r"^(?:" + _AMOUNT_CURRENCY.pattern + r")\s*", "", value, flags=re.I)
        value = re.sub(r"\s*(?:" + _AMOUNT_CURRENCY.pattern + r")$", "", value, flags=re.I).strip()
        if re.fullmatch(r"\d+,\d{1,2}", value):
            value = value.replace(",", ".")
        elif "," in value:
            if not re.fullmatch(r"\d{1,3}(?:,\d{3})+(?:\.\d+)?", value):
                return None
            value = value.replace(",", "")
        if not re.fullmatch(r"\d+(?:\.\d+)?", value):
            return None
    elif not isinstance(value, (int, float, Decimal)):
        return None
    try:
        result = Decimal(str(value))
        if not result.is_finite() or result < 0 or result >= Decimal("1000000000"):
            return None
        if quantity and result <= 0:
            return None
        precision = Decimal("0.001") if quantity else Decimal("0.01")
        return float(result.quantize(precision, rounding=ROUND_HALF_UP))
    except (InvalidOperation, ValueError, OverflowError):
        return None


def _date(value):
    text = _text(value)
    if text is None:
        return None
    text = text.translate(_DIGITS)
    match = re.fullmatch(r"(\d{4})[-/](\d{1,2})[-/](\d{1,2})", text)
    if match:
        year, month, day = map(int, match.groups())
    else:
        match = re.fullmatch(r"(\d{1,2})[-/](\d{1,2})[-/](\d{4})", text)
        if not match:
            return None
        first, second, year = map(int, match.groups())
        # Do not guess between month/day and day/month for ambiguous dates.
        if first > 12 and second <= 12:
            day, month = first, second
        elif second > 12 and first <= 12:
            month, day = first, second
        elif first == second:
            month, day = first, second
        else:
            return None
    try:
        return date(year, month, day).isoformat() if 1900 <= year <= 2200 else None
    except ValueError:
        return None


def _currency(value):
    text = _text(value, 30)
    if text is None:
        return None
    if text.casefold() in _CURRENCY_ALIASES:
        return _CURRENCY_ALIASES[text.casefold()]
    return text.upper() if re.fullmatch(r"[a-zA-Z]{3}", text) else None


def _category(value):
    text = _text(value, 100)
    if text is None:
        return None
    canonical = next((item for item in CATEGORIES if item.casefold() == text.casefold()), None)
    return canonical or _CATEGORY_ALIASES.get(text.casefold(), "Other")


def _different(first, second):
    return abs(Decimal(str(first)) - Decimal(str(second))) > Decimal("0.02")


def normalize_invoice(raw):
    if not isinstance(raw, dict):
        raise InvoiceError("invalid_invoice_json", "Unable to parse invoice analysis.")
    warning_codes = set()
    invoice = {
        "merchant_name": _text(raw.get("merchant_name")),
        "invoice_number": _text(raw.get("invoice_number")),
        "date": _date(raw.get("date")), "currency": _currency(raw.get("currency")),
        **{field: _number(raw.get(field)) for field in ("subtotal", "tax", "discount", "total")},
        "category": _category(raw.get("category")), "items": [],
    }
    # Some models emit numeric invoice IDs; preserve the ID, never a monetary guess.
    invoice_number = raw.get("invoice_number")
    if isinstance(invoice_number, int) and not isinstance(invoice_number, bool):
        invoice["invoice_number"] = str(invoice_number)
    raw_items = raw.get("items")
    if raw_items is None:
        raw_items = []
    if not isinstance(raw_items, list) or len(raw_items) > MAX_ITEMS:
        raise InvoiceError("invalid_invoice_json", "Invoice items could not be read reliably.")
    for raw_item in raw_items:
        if not isinstance(raw_item, dict):
            raise InvoiceError("invalid_invoice_json", "Invoice items could not be read reliably.")
        item = {
            **normalize_product_fields(raw_item),
            "name": _text(raw_item.get("name"), 500),
            "quantity": _number(raw_item.get("quantity"), quantity=True),
            "unit_price": _number(raw_item.get("unit_price")),
            "total_price": _number(raw_item.get("total_price")),
            "category": _category(raw_item.get("category")),
        }
        if not any(item[key] is not None for key in ("name", "quantity", "unit_price", "total_price")):
            warning_codes.add("partial_data")
            continue
        invoice["items"].append(item)
        if any(item[key] is None for key in ("name", "quantity", "unit_price", "total_price", "category")):
            warning_codes.add("partial_data")
        if raw_item.get("category") is not None and item["category"] == "Other" and str(raw_item["category"]).casefold() != "other":
            warning_codes.add("category_mapped")
    meaningful = any(
        invoice[field] is not None
        for field in ("merchant_name", "invoice_number", "date", "subtotal", "tax", "discount", "total")
    ) or bool(invoice["items"])
    if not meaningful:
        raise InvoiceError("unreadable_invoice", "Invoice could not be read. Please retake the photo.")
    if not invoice["items"]:
        warning_codes.add("no_items")
    if any(invoice[field] is None for field in ("merchant_name", "date", "currency", "total", "category")):
        warning_codes.add("partial_data")
    if raw.get("category") is not None and invoice["category"] == "Other" and str(raw["category"]).casefold() != "other":
        warning_codes.add("category_mapped")
    subtotal, tax, discount, total = (invoice[field] for field in ("subtotal", "tax", "discount", "total"))
    if all(value is not None for value in (subtotal, tax, discount, total)):
        calculated = Decimal(str(subtotal)) + Decimal(str(tax)) - Decimal(str(discount))
        if _different(calculated, total):
            warning_codes.add("totals_mismatch")
    items = invoice["items"]
    if items and all(item["total_price"] is not None for item in items):
        items_sum = sum(Decimal(str(item["total_price"])) for item in items)
        # Item prices can already include VAT. Never add tax to them blindly.
        possible_totals = [value for value in (subtotal, total) if value is not None]
        if total is not None and tax is not None and discount is not None:
            possible_totals.append(Decimal(str(total)) - Decimal(str(tax)) + Decimal(str(discount)))
        if possible_totals and all(_different(items_sum, value) for value in possible_totals):
            warning_codes.add("items_total_mismatch")
    return invoice, sorted(warning_codes)


def retain_printed_condition(item):
    # A model may infer condition from a clean-looking photo. Treat unsupported
    # condition as unknown; explicit user edits are preserved on the review path.
    evidence = str(item.get("name") or "").casefold()
    markers = {
        "new": r"\b(?:brand new|new condition)\b|جديد",
        "used": r"\b(?:used|pre[ -]owned|second[ -]hand)\b|مستعمل",
        "refurbished": r"\b(?:refurbished|renewed)\b|مجدد",
    }
    condition = item.get("condition")
    if condition and not re.search(markers.get(condition, r"(?!)"), evidence):
        item["condition"] = None
    return item


def analyze_invoice(image_bytes, ollama):
    raw_text = ollama.analyze(image_bytes)
    invoice, warnings = normalize_invoice(parse_invoice_json(raw_text))
    for item in invoice["items"]:
        retain_printed_condition(item)
    return invoice, warnings
