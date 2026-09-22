"""Google Shopping adapter. Credentials and uploaded images are never logged by this adapter.

Source fields: https://serpapi.com/shopping-results and
https://serpapi.com/google-shopping-api (checked 2026-09-08).
"""
from decimal import Decimal, InvalidOperation
import ipaddress
import json
import math
import os
import re
import time
from urllib.parse import parse_qsl, quote, urlsplit, urlunsplit

import requests

from cache.search_cache import SearchCache, normalize_query, query_key
from services.errors import InvoiceError

SERPAPI_URL = "https://serpapi.com/search.json"
MAX_RESPONSE_BYTES = 2 * 1024 * 1024
MAX_OFFERS = 80
_DIGITS = str.maketrans("٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹٫٬", "01234567890123456789.,")
_SAR = re.compile(r"(?:\bSAR\b|\bSR\b|ر\s*\.\s*س\.?|ريال\s+سعودي|\u20c1)", re.I)
_FOREIGN = re.compile(
    r"(?:\b(?:USD|AED|EUR|GBP|QAR|OMR|KWD|BHD|EGP|CAD|AUD|INR)\b|[$€£¥]|د\.?\s*إ|دولار)",
    re.I,
)
_NUMBER = re.compile(r"(?:\d{1,3}(?:,\d{3})+|\d+)(?:\.\d{1,2})?")
_BIDI = str.maketrans("", "", "\u200e\u200f\u061c\u202a\u202b\u202c\u202d\u202e\u2066\u2067\u2068\u2069")


def _text(value, limit=500):
    if not isinstance(value, str):
        return None
    value = " ".join(value.split())
    return value[:limit] if value else None


def safe_public_url(value, *, allow_provider_image=False):
    """Only emit ordinary public HTTP(S) links; never resolve or fetch these URLs."""
    if not isinstance(value, str) or not value or len(value) > 4096:
        return None
    # Google Shopping can return literal spaces in q/path components.
    # Encode them after validating the authority, but never accept controls.
    if any(ord(char) < 32 or ord(char) == 127 or (char.isspace() and char != " ")
           for char in value) or "\\" in value:
        return None
    try:
        parsed = urlsplit(value)
        host = (parsed.hostname or "").rstrip(".").lower()
        if (
            parsed.scheme.lower() not in {"http", "https"}
            or parsed.username is not None or parsed.password is not None
            or parsed.port not in {None, 80, 443}
            or not host or any(char.isspace() for char in parsed.netloc)
        ):
            return None
        if host == "localhost" or host.endswith((".localhost", ".local", ".internal", ".invalid", ".test")):
            return None
        if host == "serpapi.com" or host.endswith(".serpapi.com"):
            # Only credential-free static result images can be displayed.
            # Search, account and archive API URLs are never card destinations.
            if not (allow_provider_image and host == "serpapi.com"
                    and parsed.scheme.lower() == "https" and parsed.port in {None, 443}
                    and not parsed.query and not parsed.fragment
                    and re.fullmatch(r"/searches/[a-zA-Z0-9_-]+/images/(?:[a-zA-Z0-9_-]+/)*[a-zA-Z0-9_-]+\.(?:png|jpg|jpeg|webp|gif|svg)", parsed.path)):
                return None
        try:
            if not ipaddress.ip_address(host).is_global:
                return None
        except ValueError:
            ascii_host = host.encode("idna").decode("ascii")
            labels = ascii_host.split(".")
            if len(labels) < 2 or labels[-1].isdigit() or any(
                not re.fullmatch(r"[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?", label)
                for label in labels
            ):
                return None
        if any(key.lower() in {"key", "token", "api_key", "apikey", "access_token"} for key, _ in parse_qsl(parsed.query)):
            return None
        cleaned = urlunsplit((
            parsed.scheme.lower(), parsed.netloc,
            quote(parsed.path, safe="/%:@!$&'()*+,;=-._~"),
            quote(parsed.query, safe="/?%:@!$&'()*+,;=-._~"),
            quote(parsed.fragment, safe="/?%:@!$&'()*+,;=-._~"),
        ))
        return cleaned if len(cleaned) <= 4096 else None
    except (ValueError, UnicodeError):
        return None


def safe_image_url(value):
    return safe_public_url(value, allow_provider_image=True)


def shopping_link(value):
    url = safe_public_url(value)
    if not url:
        return False
    host = urlsplit(url).hostname.lower().rstrip(".")
    return bool(re.fullmatch(r"(?:[a-z0-9-]+\.)?(?:google\.(?:com|com\.sa|co\.uk)|googleadservices\.com)", host))


def merchant_url(value):
    url = safe_public_url(value)
    if not url:
        return None
    if not shopping_link(url):
        return url
    parsed = urlsplit(url)
    if parsed.path in {"/url", "/aclk", "/pagead/aclk"}:
        params = dict(parse_qsl(parsed.query))
        for key in ("adurl", "url", "q"):
            target = safe_public_url(params.get(key))
            if target and not shopping_link(target):
                return target
    return None


def page_token(value):
    # Google's opaque lookup token is not the SerpAPI credential.
    if isinstance(value, str) and 1 <= len(value) <= 12000 and re.fullmatch(r"[A-Za-z0-9_+/=-]+", value):
        return value
    return None


def _number(value, maximum, integer=False):
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    if value < 0 or value > maximum or not math.isfinite(value):
        return None
    if integer and int(value) != value:
        return None
    return int(value) if integer else float(value)


def _price(result):
    label = _text(result.get("price"), 200) or ""
    label = label.translate(_BIDI).translate(_DIGITS).strip()
    currency = (_text(result.get("currency"), 8) or "").upper()
    if currency not in {"", "SAR"} or _FOREIGN.search(label):
        return None
    if currency != "SAR" and not _SAR.search(label):
        return None
    # A region is not proof of currency. Reject ranges, instalments and ambiguous
    # amounts instead of using a cheap monthly payment as the purchase price.
    amount_label = _SAR.sub("", label).strip()
    if amount_label and not _NUMBER.fullmatch(amount_label):
        return None
    raw = result.get("extracted_price")
    if raw is None:
        raw = amount_label.replace(",", "")
    if isinstance(raw, bool) or not isinstance(raw, (int, float, str)):
        return None
    try:
        amount = Decimal(str(raw))
        if not amount.is_finite() or amount <= 0 or amount > Decimal("1000000000"):
            return None
        if amount != amount.quantize(Decimal("0.01")):
            return None
        if amount_label and Decimal(amount_label.replace(",", "")) != amount:
            return None
        return float(amount)
    except (InvalidOperation, ValueError):
        return None


def listing_price(result):
    """Keep the currency on a shopping listing; never convert it to SAR."""
    original_label = _text(result.get("price"), 200)
    label = (original_label or "").translate(_BIDI).translate(_DIGITS).strip()
    codes = {"SAR", "USD", "AED", "EUR", "GBP", "QAR", "OMR", "KWD", "BHD",
             "EGP", "CAD", "AUD", "INR", "JPY", "CNY", "TRY", "CHF", "SEK",
             "NOK", "DKK", "SGD", "NZD", "HKD", "ZAR", "PKR", "MYR", "IDR"}
    explicit = (_text(result.get("currency"), 8) or "").upper()
    if explicit and explicit not in codes:
        return None
    found = set()
    def remove_code(match):
        found.add(match[0].upper())
        return ""
    amount_label = re.sub(r"\b(?:" + "|".join(sorted(codes)) + r")\b", remove_code, label, flags=re.I)
    # Google Shopping uses $ for USD, and qualified dollar signs for the
    # other dollar currencies. Retain the exact label in the response too.
    for pattern, currency in (
        (r"(?<![A-Za-z])US\$", "USD"), (r"(?<![A-Za-z])(?:CA|C)\$", "CAD"),
        (r"(?<![A-Za-z])(?:AU|A)\$", "AUD"), (r"(?<![A-Za-z])NZ\$", "NZD"),
        (r"(?<![A-Za-z])(?:SG|S)\$", "SGD"), (r"(?<![A-Za-z])HK\$", "HKD"),
        (_SAR.pattern, "SAR"), (r"\$", "USD"), (r"€", "EUR"),
        (r"£", "GBP"), (r"₹", "INR"), (r"د\.?\s*إ\.?", "AED"),
    ):
        if re.search(pattern, amount_label, flags=re.I):
            found.add(currency)
            amount_label = re.sub(pattern, "", amount_label, flags=re.I)
    if explicit:
        found.add(explicit)
    if len(found) > 1:
        return None
    # A generic rial/yen symbol does not establish which national currency.
    amount_label = re.sub(r"(?:¥|﷼|\bريال\b)", "", amount_label).strip()
    currency = next(iter(found), None)
    if result.get("installment") and not label:
        return None
    if amount_label and not _NUMBER.fullmatch(amount_label):
        return None
    raw = result.get("extracted_price")
    if raw is None:
        raw = amount_label.replace(",", "")
    # Reuse exact positive-money validation, with no foreign-currency relabeling.
    amount = _price({"currency": "SAR", "price": amount_label, "extracted_price": raw})
    if amount is None:
        return None
    return amount, currency, original_label


def normalize_offers(envelope):
    """Normalize documented result blocks without inventing missing stock/shipping."""
    blocks = []
    for field in ("shopping_results", "inline_shopping_results"):
        values = envelope.get(field)
        if isinstance(values, list):
            blocks.extend(values[:100])
    categories = envelope.get("categorized_shopping_results")
    if isinstance(categories, list):
        for category in categories[:20]:
            values = category.get("shopping_results") if isinstance(category, dict) else None
            if isinstance(values, list):
                blocks.extend(values[:100])
    offers, seen = [], set()
    for result in blocks:
        if not isinstance(result, dict):
            continue
        title, store = _text(result.get("title")), _text(result.get("source"), 160)
        parsed_price = listing_price(result)
        url = (merchant_url(result.get("link")) or merchant_url(result.get("product_link"))
               or safe_public_url(result.get("product_link")) or safe_public_url(result.get("link")))
        if not title or not store or parsed_price is None or not url:
            continue
        price, currency, price_label = parsed_price
        identity = (title.casefold(), store.casefold(), price, currency,
                    price_label if currency is None else None, url)
        if identity in seen:
            continue
        seen.add(identity)
        # Cards open the provider's supplied product link without a paid lookup.
        thumbnails = result.get("thumbnails")
        candidates = ([result.get("thumbnail")] + thumbnails[:5]) if isinstance(thumbnails, list) else [result.get("thumbnail")]
        image = next((safe_image_url(value) for value in candidates if safe_image_url(value)), None)
        offers.append({
            "title": title,
            "product_link": safe_public_url(result.get("product_link")) or url,
            "source": store,
            "source_icon": safe_image_url(result.get("source_icon")),
            "extracted_price": price,
            "store": store,
            "price": price,
            "currency": currency,
            "price_label": price_label,
            "rating": _number(result.get("rating"), 5),
            "reviews": _number(result.get("reviews"), 1000000000, integer=True),
            "product_url": url,
            "link_kind": "shopping" if shopping_link(url) else "merchant",
            "shop_lookup_token": None,
            "image_url": image,
            "availability": _text(result.get("availability"), 150),
            "shipping": _text(result.get("delivery"), 300),
            "condition": _text(result.get("second_hand_condition"), 100),
            "multiple_sources": result.get("multiple_sources") is True,
        })
        if len(offers) >= MAX_OFFERS:
            break
    return offers


class SerpApiService:
    def __init__(
        self, api_key=None, cache=None, ttl_seconds=43200, cache_path=None,
        region="sa", language="en", timeout_seconds=20, session_factory=None,
    ):
        self.api_key = (api_key if api_key is not None else os.getenv("SERPAPI_KEY", "")).strip()
        self.cache = cache if cache is not None else SearchCache(cache_path, ttl_seconds)
        self.region = region.lower()
        self.language = language.lower()
        if not re.fullmatch(r"[a-z]{2}", self.region) or self.language not in {"en", "ar"}:
            raise ValueError("Use a two-letter shopping region and en/ar language.")
        self.timeout_seconds = max(5, min(60, float(timeout_seconds)))
        self.session_factory = session_factory or requests.Session

    def search_products(self, query):
        query = normalize_query(query)
        if not self.api_key:
            raise InvoiceError(
                "serpapi_not_configured",
                "Price search is not configured. Set SERPAPI_KEY in the Flask backend .env and restart Flask.",
                503,
            )
        key = query_key(query, self.region, self.language)
        result = self.cache.get_or_fetch(key, lambda: self._fetch(query))
        # Cache is local but still validate its URL/price fields before returning.
        result["offers"] = [
            offer for offer in result["offers"]
            if isinstance(offer, dict)
            and _text(offer.get("title")) and _text(offer.get("store"))
            and listing_price({"currency": offer.get("currency"),
                               "price": offer.get("price_label"),
                               "extracted_price": offer.get("price")}) is not None
            and _number(offer.get("price"), 1000000000) not in {None, 0}
            and safe_public_url(offer.get("product_url"))
        ]
        for offer in result["offers"]:
            offer["product_url"] = safe_public_url(offer["product_url"])
            offer["product_link"] = safe_public_url(offer.get("product_link")) or offer["product_url"]
            offer["source"] = _text(offer.get("store"), 160)
            offer["source_icon"] = safe_image_url(offer.get("source_icon"))
            offer["extracted_price"] = offer["price"]
            offer["image_url"] = safe_image_url(offer.get("image_url"))
            offer["shop_lookup_token"] = None
            offer["link_kind"] = "shopping" if shopping_link(offer["product_url"]) else "merchant"
        return result

    def _fetch(self, query):
        params = {
            "engine": "google_shopping", "q": query, "gl": self.region,
            "google_domain": "google.com.sa", "location": "Saudi Arabia", "sort_by": 1,
            "hl": self.language, "api_key": self.api_key,
        }
        envelope = self._request(params)
        return {
            "offers": normalize_offers(envelope), "cached": False,
            "fetched_at": self.cache.timestamp(), "query": query,
        }

    def _request(self, params):
        deadline = time.monotonic() + self.timeout_seconds
        try:
            with self.session_factory() as session:
                # API credentials must not be sent to an environment-configured proxy.
                # requests defaults to zero retries; an explicit action starts each search.
                session.trust_env = False
                with session.get(
                    SERPAPI_URL, params=params, timeout=(5, self.timeout_seconds),
                    allow_redirects=False, stream=True,
                ) as response:
                    status = response.status_code
                    if status in {401, 403}:
                        raise InvoiceError(
                            "serpapi_auth_failed",
                            "The price search API key was rejected. Check SERPAPI_KEY and the SerpAPI account.",
                            503,
                        )
                    if status == 429:
                        raise InvoiceError(
                            "serpapi_quota_exceeded",
                            "The price search quota or rate limit was reached. Check the SerpAPI account and try later.",
                            503,
                        )
                    if status != 200:
                        raise InvoiceError("serpapi_failed", "The price provider could not complete this search.", 502)
                    length = response.headers.get("Content-Length")
                    if length and int(length) > MAX_RESPONSE_BYTES:
                        raise InvoiceError("serpapi_failed", "The price provider returned too much data.", 502)
                    chunks, size = [], 0
                    for chunk in response.iter_content(chunk_size=16 * 1024):
                        if time.monotonic() > deadline:
                            raise InvoiceError("serpapi_timeout", "Price search timed out. Try again.", 504)
                        size += len(chunk)
                        if size > MAX_RESPONSE_BYTES:
                            raise InvoiceError("serpapi_failed", "The price provider returned too much data.", 502)
                        chunks.append(chunk)
            envelope = json.loads(b"".join(chunks))
            if not isinstance(envelope, dict):
                raise ValueError("Invalid envelope")
            metadata = envelope.get("search_metadata")
            if not isinstance(metadata, dict) or metadata.get("status") != "Success":
                raise ValueError("Unsuccessful search")
            if envelope.get("error"):
                # SerpAPI documents successful empty searches with this error value.
                # Other errors are not cached or shown verbatim.
                if envelope["error"] != "Google hasn't returned any results for this query.":
                    raise ValueError("Upstream error")
            return envelope
        except requests.Timeout:
            raise InvoiceError("serpapi_timeout", "Price search timed out. Try again.", 504) from None
        except requests.ConnectionError:
            raise InvoiceError("serpapi_unavailable", "Could not connect to the price provider. Try again later.", 503) from None
        except requests.RequestException:
            # requests exception strings include the full URL and api_key. Never
            # chain, log or expose those exception values.
            raise InvoiceError("serpapi_failed", "The price provider could not complete this search.", 502) from None
        except (ValueError, TypeError, AttributeError):
            raise InvoiceError("serpapi_failed", "The price provider returned an invalid response.", 502) from None
