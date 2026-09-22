"""Conservative, deterministic product identity checks (scores are not probabilities)."""
import re
import unicodedata
from decimal import Decimal, InvalidOperation

_DIGITS = str.maketrans("٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹٫", "01234567890123456789.")
_UNIT_MAP = {
    "ml": ("liter", Decimal(".001")), "milliliter": ("liter", Decimal(".001")),
    "milliliters": ("liter", Decimal(".001")), "مل": ("liter", Decimal(".001")),
    "l": ("liter", Decimal(1)), "liter": ("liter", Decimal(1)),
    "liters": ("liter", Decimal(1)), "litre": ("liter", Decimal(1)),
    "litres": ("liter", Decimal(1)), "لتر": ("liter", Decimal(1)),
    "g": ("kg", Decimal(".001")), "gram": ("kg", Decimal(".001")),
    "grams": ("kg", Decimal(".001")), "جم": ("kg", Decimal(".001")),
    "غرام": ("kg", Decimal(".001")), "kg": ("kg", Decimal(1)),
    "kilogram": ("kg", Decimal(1)), "kilograms": ("kg", Decimal(1)),
    "كجم": ("kg", Decimal(1)), "كيلو": ("kg", Decimal(1)),
    "unit": ("item", Decimal(1)), "item": ("item", Decimal(1)),
}
_SIZE_RE = re.compile(r"(?<!\w)(?:\d+\s*[x×]\s*)?(\d+(?:\.\d+)?)\s*(milliliters?|kilograms?|liters?|litres?|grams?|ml|kg|l|g|مل|لتر|كجم|جم|غرام|كيلو)(?!\w)", re.I)
_PACK_PATTERNS = (
    r"(?:pack|case|box)\s+of\s+(\d+)", r"(\d+)\s*[- ]?(?:pack|pcs|pieces|units|bottles|cans|items)\b",
    r"(\d+)\s*[x×]\s*\d+(?:\.\d+)?\s*(?:ml|l|g|kg|مل|لتر|جم|كجم)\b",
    r"\d+(?:\.\d+)?\s*(?:ml|l|g|kg|مل|لتر|جم|كجم)\s*[x×]\s*(\d+)\b",
    r"عبوة\s*(?:من\s*)?(\d+)", r"(\d+)\s*(?:حبة|حبات|عبوات)",
)
_GENERIC = {
    "milk", "water", "coffee", "tea", "bread", "rice", "sugar", "item", "product",
    "grocery", "groceries", "food", "charger", "cable", "unknown", "misc",
    "حليب", "ماء", "مياه", "قهوة", "شاي", "خبز", "أرز", "ارز", "منتج", "صنف",
}
_FEE_RE = re.compile(r"^(?:vat|tax|discount|subtotal|sub total|total|grand total|shipping|delivery|service fee|service charge|payment|change|rounding|ضريبة|ضريبة القيمة المضافة|خصم|المجموع|الإجمالي|اجمالي|شحن|توصيل|رسوم الخدمة|الدفع|الباقي)(?:\s+[\d.%]+)*$", re.I)
_STOP = {"the", "a", "an", "and", "with", "of", "in", "saudi", "arabia", "ksa", "sar", "pack", "pcs", "pieces", "units", "unit", "item", "new", "brand", "جديد", "السعودية"}
_CONSUMABLES = {"food", "grocery", "groceries", "consumables", "personal care", "household", "household goods", "healthcare", "cleaning"}
_VARIANTS = (
    "full fat", "low fat", "skimmed", "skim", "unsweetened", "sugar free",
    "lactose free", "decaf", "organic", "usb c", "lightning",
    "black", "white", "silver", "gold", "blue", "green", "purple", "red",
    "كامل الدسم", "قليل الدسم", "خالي الدسم", "اسود", "أبيض", "ابيض",
)
_ACCESSORY_RE = re.compile(r"\b(?:compatible(?: with)?|case for|cover for|replacement|screen protector|protective case|silicone case|case only|strap|skin|ear pads|earpads|ear tips|left earbud|right earbud|single earbud|earbud only)\b", re.I)
_BAD_CONDITION_RE = re.compile(r"\b(?:refurbished|renewed|used|pre owned|open box|second hand)\b|مستعمل|مجدد", re.I)


def number(value, positive=False):
    if value is None or isinstance(value, bool):
        return None
    try:
        result = Decimal(str(value))
    except (InvalidOperation, ValueError):
        return None
    if not result.is_finite() or result < 0 or result > Decimal("1000000000"):
        return None
    return result if not positive or result > 0 else None


def normalized_text(value):
    text = unicodedata.normalize("NFKC", str(value or "")).translate(_DIGITS).lower()
    return " ".join(re.sub(r"[^\w]+", " ", text, flags=re.UNICODE).split())


def _raw_title(value):
    text = str(value.get("title") or value.get("name") or "").translate(_DIGITS).lower()
    return re.sub(r"(\d)\s+(?=(?:gb|tb|mah|hz|w|v)\b)", r"\1", text)


def _measurement_title(value):
    text = _raw_title(value)
    # In named phone/network products, 5G is connectivity, not five grams.
    # Keep gram measurements untouched for food and other physical products.
    if re.search(r"\b(?:galaxy|iphone|pixel|phone|smartphone|router|modem|hotspot|broadband)\b|هاتف|جوال|راوتر|مودم", text):
        text = re.sub(r"(?<![\w.])([2-6])\s*g\b", lambda match: "network" + match[1] + "g", text)
    return text


def _shopping_identity_title(value):
    """Keep optional listing attributes distinct from the requested generation."""
    text = _measurement_title(value)
    def screen(match):
        amount = format(Decimal(match[1]).normalize(), "f").replace(".", "p")
        return " screen" + amount + "inch "
    text = re.sub(r"\b(\d+(?:\.\d+)?)\s*(?:-\s*)?(?:inches\b|inch\b|in\b|[\"″]|بوصة)", screen, text)
    # Samsung SKU suffixes describe a regional/retail model; unknown suffixes
    # are discovery choices. A suffix explicitly requested must still match.
    text = re.sub(r"\bsm[-\s]?s\d{3}[a-z0-9]*(?:[/\-][a-z0-9]+)?\b",
                  lambda match: " sku" + re.sub(r"[^a-z0-9]", "", match[0]) + " ", text)
    text = re.sub(r"\b(\d+)\s*(gb|tb)\s*(?:ram|memory)\b",
                  lambda match: " ram" + match[1] + match[2] + " ", text)
    text = re.sub(r"\bram\s*(\d+)\s*(gb|tb)\b",
                  lambda match: " ram" + match[1] + match[2] + " ", text)
    def numeric_label(prefix, amount, suffix=""):
        return " " + prefix + format(Decimal(amount).normalize(), "f").replace(".", "p") + suffix + " "
    text = re.sub(r"\b(\d+(?:\.\d+)?)\s*cm\b",
                  lambda match: numeric_label("length", match[1], "cm"), text)
    text = re.sub(r"\bandroid\s*(\d+(?:\.\d+)?)\b",
                  lambda match: numeric_label("osandroid", match[1]), text)
    text = re.sub(r"\b(\d+(?:\.\d+)?)\s*mp\b",
                  lambda match: numeric_label("camera", match[1], "mp"), text)
    # Some phone listings omit the screen unit ("6.9 12GB RAM ...").
    # Keep a bare decimal as an unspecified numeric attribute, never label it
    # as inches or let it masquerade as a different S-series generation.
    if re.search(r"\b(?:galaxy|iphone|pixel|phone|smartphone)\b", text):
        text = re.sub(r"(?<!\w)(\d+\.\d+)(?!\w)",
                      lambda match: numeric_label("decimal", match[1]), text)
    return text


def size_info(value):
    amount = number(value.get("size_value"), positive=True)
    unit = str(value.get("size_unit") or "").lower().strip()
    if amount is not None and unit in _UNIT_MAP:
        dimension, factor = _UNIT_MAP[unit]
        return amount * factor, dimension
    found = _SIZE_RE.findall(_measurement_title(value))
    if len(found) != 1:
        return None, None
    amount, unit = found[0]
    dimension, factor = _UNIT_MAP[unit.lower()]
    return Decimal(amount) * factor, dimension


def pack_info(value):
    explicit = number(value.get("pack_size"), positive=True)
    if explicit is not None:
        return explicit if explicit == explicit.to_integral_value() else None
    title = _raw_title(value)
    found = []
    for pattern in _PACK_PATTERNS:
        found.extend(Decimal(n) for n in re.findall(pattern, title, re.I))
    if found:
        return found[0] if all(n == found[0] and n > 0 for n in found) else None
    if re.search(r"\b(?:single|1 unit|1 item|1 bottle|one bottle|one unit)\b", title):
        return Decimal(1)
    return None


def metadata_conflict(value):
    """Explicit measures must agree with every parseable measure in the title."""
    amount = number(value.get("size_value"), positive=True)
    unit = str(value.get("size_unit") or "").lower().strip()
    title = _measurement_title(value)
    if amount is not None and unit in _UNIT_MAP:
        dimension, factor = _UNIT_MAP[unit]
        explicit_size = (amount * factor, dimension)
        for parsed_amount, parsed_unit in _SIZE_RE.findall(title):
            parsed_dimension, parsed_factor = _UNIT_MAP[parsed_unit.lower()]
            if (Decimal(parsed_amount) * parsed_factor, parsed_dimension) != explicit_size:
                return "size_metadata_conflict"
    explicit_pack = number(value.get("pack_size"), positive=True)
    if explicit_pack is not None:
        parsed_packs = []
        for pattern in _PACK_PATTERNS:
            parsed_packs.extend(Decimal(n) for n in re.findall(pattern, title, re.I))
        if re.search(r"\b(?:single|1 unit|1 item|1 bottle|one bottle|one unit)\b", title):
            parsed_packs.append(Decimal(1))
        if any(pack != explicit_pack for pack in parsed_packs):
            return "pack_metadata_conflict"
    return None


def identity_tokens(value):
    text = _measurement_title(value)
    text = _SIZE_RE.sub(" ", text)
    for pattern in _PACK_PATTERNS:
        text = re.sub(pattern, " ", text, flags=re.I)
    return set(normalized_text(text).split()) - _STOP


def meaningful_product(product, shopping=False):
    name = normalized_text(product.get("name"))
    fee_name = re.sub(r"\b(?:amount|sar|sr)\s*(?=\d|\s|$)|ر\s+س\s*(?=\d|\s|$)|\b(?:ريال|المبلغ|السعودي)\b", " ", name)
    fee_name = " ".join(re.sub(r"\b\d+\b", " ", fee_name).split())
    if not name or _FEE_RE.fullmatch(name) or _FEE_RE.fullmatch(fee_name):
        return False, "non_product_line"
    words = identity_tokens(product)
    specifics = {word for word in words - _GENERIC if not word.isdigit()}
    specifics -= set(" ".join(_VARIANTS).split()) | {"usb", "c"}
    identity = any(str(product.get(key) or "").strip() for key in ("brand", "model"))
    if not identity and (len(words) < 2 or not specifics):
        placeholders = {"item", "product", "unknown", "misc", "منتج", "صنف", "غير", "معروف"}
        real_name = {word for word in words if not word.isdigit()} - placeholders
        if not shopping or not real_name:
            return False, "product_too_generic"
    confidence = number(product.get("confidence"))
    if confidence is not None and confidence < Decimal(".70") and not product.get("reviewed"):
        return False, "insufficient_recognition_confidence"
    return True, None


def build_search_query(product, truncate=True, include_location=True):
    # Rebuild from reviewed identity fields: never trust an unrelated generated query.
    pieces = []
    seen = ""
    for key in ("brand", "name", "model", "variant"):
        part = str(product.get(key) or "").strip()
        canonical = normalized_text(part)
        if key == "brand" and canonical and f" {canonical} " in f" {normalized_text(product.get('name'))} ":
            continue
        if canonical and f" {canonical} " not in f" {seen} ":
            # Join overlapping identity fragments without requiring a duplicate
            # phrase such as 'Apple Apple AirPods' in a combined quoted query.
            previous_words, next_words = " ".join(pieces).split(), part.split()
            overlap = 0
            for count in range(1, min(len(previous_words), len(next_words)) + 1):
                if normalized_text(" ".join(previous_words[-count:])) == normalized_text(" ".join(next_words[:count])):
                    overlap = count
            pieces.append(" ".join(next_words[overlap:]))
            seen = normalized_text(" ".join(pieces))
    amount = product.get("size_value")
    unit = product.get("size_unit")
    if amount is not None and unit and size_info({"name": " ".join(pieces)})[0] is None:
        pieces.append(f"{amount}{unit}")
    pack = pack_info(product)
    if pack is not None and pack > 1 and pack_info({"name": " ".join(pieces)}) is None:
        pieces.append(f"pack of {pack}")
    condition = str(product.get("condition") or "").strip()
    if condition and normalized_text(condition) not in seen:
        pieces.append(condition)
    query = " ".join(pieces)
    if include_location:
        query += " Saudi Arabia"
    return query[:400] if truncate else query


class ProductMatchingService:
    def __init__(self, minimum_score=.85):
        self.minimum_score = max(.70, min(1., float(minimum_score)))

    def match(self, product, offer):
        title = normalized_text(offer.get("title"))
        base = {"match_score": 0., "match_label": "Not comparable", "eligible": False}
        def rejected(reason):
            return dict(base, reason=reason)
        if not title:
            return rejected("missing_offer_title")
        for source_label, value in (("original", product), ("offer", offer)):
            conflict = metadata_conflict(value)
            if conflict:
                return rejected(f"{source_label}_{conflict}")
        original_identity = " ".join(str(product.get(field) or "") for field in ("name", "model", "variant"))
        original_text = normalized_text(original_identity)
        # Premium/base model suffixes are identity, even when recognition left
        # model null but the user supplied the information in the product name.
        qualifiers = {"pro", "max", "ultra", "plus", "mini", "lite", "fe", "se"}
        expected_qualifiers = set(original_text.split()) & qualifiers
        offered_qualifiers = set(title.split()) & qualifiers
        if expected_qualifiers != offered_qualifiers:
            return rejected("model_variant_mismatch")
        for field in ("brand", "model", "variant"):
            wanted = set(normalized_text(product.get(field)).split())
            if wanted and not wanted.issubset(set(title.split())):
                return rejected(f"{field}_mismatch")
        for variant in _VARIANTS:
            if re.search(r"\b" + re.escape(variant) + r"\b", original_text) and not re.search(r"\b" + re.escape(variant) + r"\b", title):
                return rejected("variant_mismatch")
        # Identity numbers distinguish generations, storage, model suffixes and capacity.
        wanted_tokens = identity_tokens({"name": original_identity})
        offered_tokens = identity_tokens(offer)
        numeric_identity = {w for w in wanted_tokens if any(c.isdigit() for c in w)}
        offered_numeric_identity = {w for w in offered_tokens if any(c.isdigit() for c in w)}
        if numeric_identity != offered_numeric_identity:
            return rejected("model_or_capacity_mismatch")
        storage = set(re.findall(r"\b\d+\s*(?:gb|tb)\b", _raw_title({"name": original_identity})))
        candidate_storage = set(re.findall(r"\b\d+\s*(?:gb|tb)\b", _raw_title(offer)))
        compact = lambda values: {re.sub(r"\s", "", v) for v in values}
        if compact(storage) != compact(candidate_storage):
            return rejected("storage_mismatch")
        connector_variants = ("usb c", "lightning")
        if {v for v in connector_variants if v in original_text} != {v for v in connector_variants if v in title}:
            return rejected("connector_variant_unknown_or_mismatch")
        if _ACCESSORY_RE.search(title) and not _ACCESSORY_RE.search(original_text):
            return rejected("accessory_mismatch")
        if "charging case" in title and "charging case" not in original_text:
            complete_product = re.search(r"\b(?:with|includes?) (?:\w+ )?charging case\b|\b(?:earbuds|earphones|headphones)\b", title)
            if not complete_product:
                return rejected("accessory_mismatch")
        for accessory in ("charger", "case", "cover", "screen", "ear tips", "ear pads"):
            if re.search(r"\b" + accessory + r"\b", title) and not re.search(r"\b" + accessory + r"\b", original_text):
                bundled = re.search(r"\b(?:with|includes?|including) (?:\w+ ){0,3}" + accessory + r"\b", title)
                if not bundled:
                    return rejected("accessory_mismatch")
        condition = normalized_text(product.get("condition"))
        offered_condition = normalized_text(offer.get("condition"))
        old_original = bool(_BAD_CONDITION_RE.search(condition + " " + original_text))
        old_offer = bool(_BAD_CONDITION_RE.search(offered_condition + " " + title))
        if old_original != old_offer or (old_original and condition and condition not in offered_condition + " " + title):
            return rejected("condition_mismatch")
        original_size, original_unit = size_info(product)
        offered_size, offered_unit = size_info(offer)
        if original_size is not None and offered_size is None:
            return rejected("size_unknown")
        if original_size is None and offered_size is not None:
            return rejected("original_size_unknown")
        if original_unit != offered_unit:
            return rejected("size_dimension_mismatch")
        sizes_differ = original_size != offered_size
        if sizes_differ:
            # Different weights/volumes only for an explicitly matching brand of consumables.
            consumable = normalized_text(product.get("category")) in _CONSUMABLES
            if not product.get("brand") or not consumable or original_unit not in ("liter", "kg"):
                return rejected("size_mismatch")
        original_pack, offered_pack = pack_info(product), pack_info(offer)
        if (original_pack is not None or offered_pack is not None) and (original_pack is None or offered_pack is None):
            return rejected("pack_size_unknown")
        if ((re.search(r"\b(?:multipack|multi pack|bundle|assorted)\b", title) and offered_pack is None)
                or (re.search(r"\b(?:multipack|multi pack|bundle|assorted)\b", original_text) and original_pack is None)):
            return rejected("pack_size_unknown")
        coverage = len(wanted_tokens & offered_tokens) / max(1, len(wanted_tokens))
        if coverage < .80:
            return rejected("product_title_mismatch")
        score = .55 + .43 * coverage
        if sizes_differ or original_pack != offered_pack:
            score = min(score, .90)
        confidence = number(product.get("confidence"))
        if confidence is not None and not product.get("reviewed"):
            score *= .95 + .05 * min(1., float(confidence))
        score = round(score, 3)
        return {
            "match_score": score,
            "match_label": "Quantity-adjusted match" if sizes_differ or original_pack != offered_pack else ("Exact Match" if score >= .95 else "Strong Match" if score >= .85 else "Similar Product"),
            "eligible": score >= self.minimum_score,
            "reason": None if score >= self.minimum_score else "insufficient_match_score",
            "quantity_adjusted": sizes_differ or original_pack != offered_pack,
            "match_score_type": "heuristic",
            "unverified_attributes": ["condition"] if not condition or not offered_condition else [],
        }

    def shopping_match(self, product, offer):
        """Discovery is separate from comparable pricing: constraints still apply."""
        strict = self.match(product, offer)
        original_identity = " ".join(str(product.get(field) or "") for field in ("name", "brand", "model", "variant"))
        original_text = normalized_text(original_identity)
        title = normalized_text(offer.get("title"))
        rejected = lambda reason: {
            "match_score": 0., "match_label": "Not comparable", "eligible": False,
            "broad_match": True, "comparable": False, "reason": reason,
        }
        if not title:
            return rejected("missing_offer_title")
        for source_label, value in (("original", product), ("offer", offer)):
            conflict = metadata_conflict(value)
            if conflict:
                return rejected(f"{source_label}_{conflict}")
        def words(value):
            result = identity_tokens({"name": _shopping_identity_title(value)})
            # Conservative Arabic spelling/article normalization for literal searches.
            translated = set()
            for word in result:
                word = word.translate(str.maketrans("أإآ", "ااا"))
                if word.startswith("ال") and len(word) > 4:
                    word = word[2:]
                translated.add(word)
            if translated & {"phone", "smartphone", "هاتف", "جوال"}:
                translated -= {"smartphone", "هاتف", "جوال"}
                translated.add("phone")
            product_text = normalized_text(_raw_title(value))
            if re.search(r"\b(?:iphone\s*\d+|galaxy\s+(?:s\d+|a\d+|z\s*(?:fold|flip))|pixel\s*\d+)\b", product_text):
                translated.add("phone")
            return translated
        wanted, offered = words({"name": original_identity}), words(offer)
        if not wanted or not wanted.issubset(offered):
            return rejected("requested_product_mismatch")
        qualifiers = {"pro", "max", "ultra", "plus", "mini", "lite", "fe", "se"}
        if wanted & qualifiers and wanted & qualifiers != offered & qualifiers:
            return rejected("model_variant_mismatch")
        capacity = lambda word: bool(re.fullmatch(r"\d+(?:gb|tb|mah|wh|w|hz|v)", word)) or word.startswith(("screen", "network", "sku", "ram", "length", "osandroid", "camera", "decimal"))
        requested_numbers = {word for word in wanted if any(c.isdigit() for c in word)}
        candidate_numbers = {word for word in offered if any(c.isdigit() for c in word)}
        requested_generation = {word for word in requested_numbers if not capacity(word)}
        candidate_generation = {word for word in candidate_numbers if not capacity(word)}
        if requested_generation and requested_generation != candidate_generation:
            return rejected("model_or_capacity_mismatch")
        for unit_group in ("gb|tb", "mah", "wh|w", "hz", "v"):
            pattern = r"\d+(?:" + unit_group + r")"
            expected = {word for word in requested_numbers if re.fullmatch(pattern, word)}
            actual = {word for word in candidate_numbers if re.fullmatch(pattern, word)}
            if expected and expected != actual:
                return rejected("model_or_capacity_mismatch")
        for prefix in ("screen", "network", "sku", "ram", "length", "osandroid", "decimal"):
            expected = {word for word in requested_numbers if word.startswith(prefix)}
            actual = {word for word in candidate_numbers if word.startswith(prefix)}
            if expected and expected != actual:
                return rejected("requested_attribute_mismatch")
        for variants in (("usb c", "lightning"), ("full fat", "low fat", "skimmed", "skim"), ("black", "white", "silver", "gold", "blue", "green", "purple", "red")):
            expected = {v for v in variants if re.search(r"\b" + v + r"\b", original_text)}
            actual = {v for v in variants if re.search(r"\b" + v + r"\b", title)}
            if expected and expected != actual:
                return rejected("variant_mismatch")
        if _ACCESSORY_RE.search(title) and not _ACCESSORY_RE.search(original_text):
            return rejected("accessory_mismatch")
        if "charging case" in title and "charging case" not in original_text:
            if not re.search(r"\b(?:with|includes?) (?:\w+ )?charging case\b|\b(?:earbuds|earphones|headphones)\b", title):
                return rejected("accessory_mismatch")
        for accessory in ("charger", "case", "cover", "screen", "ear tips", "ear pads"):
            if re.search(r"\b" + accessory + r"\b", title) and not re.search(r"\b" + accessory + r"\b", original_text):
                if not re.search(r"\b(?:with|includes?|including) (?:\w+ ){0,3}" + accessory + r"\b", title):
                    return rejected("accessory_mismatch")
        groceries = {"milk", "rice", "coffee", "tea", "water", "bread", "sugar", "حليب", "ارز", "قهوة", "شاي", "ماء", "مياه", "خبز", "سكر"}
        appliances = {"frother", "cooker", "maker", "grinder", "machine", "container", "طباخة", "الة", "ماكينة"}
        if wanted & groceries and (offered - wanted) & appliances:
            return rejected("accessory_mismatch")
        condition = normalized_text(product.get("condition"))
        offered_condition = normalized_text(offer.get("condition"))
        old_original = bool(_BAD_CONDITION_RE.search(condition + " " + original_text))
        old_offer = bool(_BAD_CONDITION_RE.search(offered_condition + " " + title))
        if old_original != old_offer or (old_original and condition and condition not in offered_condition + " " + title):
            return rejected("condition_mismatch")
        requested_size, requested_dimension = size_info(product)
        candidate_size, candidate_dimension = size_info(offer)
        if requested_size is not None and (requested_size, requested_dimension) != (candidate_size, candidate_dimension):
            return rejected("size_mismatch")
        requested_pack, candidate_pack = pack_info(product), pack_info(offer)
        if requested_pack is not None and requested_pack != candidate_pack:
            return rejected("pack_size_mismatch")
        for value, pack in ((product, requested_pack), (offer, candidate_pack)):
            if re.search(r"\b(?:multipack|multi pack|bundle|assorted)\b", normalized_text(_raw_title(value))) and pack is None:
                return rejected("pack_size_unknown")
        # A search name alone is discovery. A known identity can keep strict
        # comparison only when the candidate introduces no unspecified variants.
        meaningful, _ = meaningful_product(product)
        expected_variants = {v for v in _VARIANTS if re.search(r"\b" + re.escape(v) + r"\b", original_text)}
        candidate_variants = {v for v in _VARIANTS if re.search(r"\b" + re.escape(v) + r"\b", title)}
        has_identity = bool(product.get("brand") or product.get("model"))
        measures_known = not wanted & groceries or requested_size is not None or requested_pack is not None
        comparable = strict.get("eligible") and meaningful and has_identity and measures_known and expected_variants == candidate_variants
        if comparable:
            return dict(strict, broad_match=False, comparable=True)
        unknowns = ["product_equivalence"]
        if not condition or not offered_condition:
            unknowns.append("condition")
        if requested_size is None and candidate_size is not None:
            unknowns.append("size")
        if requested_pack is None and candidate_pack is not None:
            unknowns.append("pack_size")
        return {
            "match_score": .75, "match_label": "Search result", "match_score_type": "heuristic",
            "eligible": True, "broad_match": True, "comparable": False,
            "quantity_adjusted": False, "unverified_attributes": unknowns, "reason": None,
        }
