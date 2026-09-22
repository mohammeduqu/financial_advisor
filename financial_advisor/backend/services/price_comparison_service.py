"""Money/quantity arithmetic for comparable retail offers; no invoice-level tax math."""
import re
from decimal import Decimal, ROUND_CEILING, ROUND_HALF_UP

from services.product_matching_service import number, pack_info, size_info

_CENT = Decimal(".01")


def money(value):
    return float(value.quantize(_CENT, rounding=ROUND_HALF_UP)) if value is not None else None


def original_prices(product):
    quantity = number(product.get("quantity"), positive=True)
    unit = number(product.get("unit_price"), positive=True)
    total = number(product.get("total_price"), positive=True)
    # An unknown quantity never becomes one for invoice savings calculations.
    if quantity is None:
        return {"unit_price": money(unit), "total_price": money(total)}, None, None
    if total is None and unit is not None:
        total = unit * quantity
    if unit is None and total is not None:
        unit = total / quantity
    return {"unit_price": money(unit), "total_price": money(total)}, quantity, total


def _shipping_cost(offer):
    raw = offer.get("shipping")
    if isinstance(raw, (int, float)) and not isinstance(raw, bool):
        return number(raw)
    text = str(raw or "").lower().strip()
    # Thresholds, first-order/member promotions, and per-item charges are not
    # unconditional order shipping. Keep them explicitly unknown.
    if re.search(r"\b(?:over|above|minimum|first|member|prime|subscription|spend|from|estimated|per item|per unit)\b|حد ادنى|أكثر|اكثر|أول|اول|اشتراك", text):
        return None
    if re.search(r"\d\s*(?:-|–|to)\s*\d", text):
        return None
    if re.search(r"\bfree\b|مجاني", text):
        return Decimal(0)
    found = re.search(r"(?:sar|sr|ر\.س)\s*(\d+(?:\.\d{1,2})?)(?![\d.,٬٫])|(?<![\d.,٬٫])(\d+(?:\.\d{1,2})?)\s*(?:sar|sr|ر\.س)", text)
    return number(next((n for n in found.groups() if n), None)) if found else None


class PriceComparisonService:
    def compare(self, product, offer, match, shopping=False):
        """Return a priced offer or None; total_price buys enough whole offer packs."""
        currency = str(offer.get("currency") or "").strip().upper() or None
        if not match.get("eligible") or (currency != "SAR" and not shopping):
            return None
        price = number(offer.get("price"), positive=True)
        if price is None or not str(offer.get("store") or "").strip() or not str(offer.get("product_url") or "").startswith(("https://", "http://")):
            return None
        if re.search(r"out of stock|sold out|unavailable|غير متوفر|نفد", str(offer.get("availability") or ""), re.I):
            return None
        if currency != "SAR":
            match = dict(match, broad_match=True, comparable=False,
                         unverified_attributes=list(dict.fromkeys([*match.get("unverified_attributes", []), "currency_comparability"])))
        if match.get("broad_match"):
            return self._shopping_offer(product, offer, match, price)
        _, quantity, original_total = original_prices(product)
        original_size, dimension = size_info(product)
        offered_size, offered_dimension = size_info(offer)
        original_pack = pack_info(product)
        offered_pack = pack_info(offer)
        # Matching has rejected partial/ambiguous pack metadata. Absence on both
        # sides means the ordinary listed item, not a silently inferred multipack.
        if (original_pack is None) != (offered_pack is None):
            return None
        original_pack = original_pack if original_pack is not None else Decimal(1)
        offered_pack = offered_pack if offered_pack is not None else Decimal(1)
        if original_size is None:
            original_measure, offered_measure, dimension = original_pack, offered_pack, "item"
        else:
            if offered_size is None or dimension != offered_dimension:
                return None
            original_measure = original_size * original_pack
            offered_measure = offered_size * offered_pack
        if offered_measure <= 0:
            return None
        normalized = price / offered_measure
        shipping = _shipping_cost(offer)
        units_to_buy = None
        total = None
        effective_unit = price
        coverage = None
        if quantity is not None:
            if dimension == "item" and quantity != quantity.to_integral_value():
                return None
            required_measure = original_measure * quantity
            units_to_buy = (required_measure / offered_measure).to_integral_value(rounding=ROUND_CEILING)
            if units_to_buy <= 0 or units_to_buy > 100000:
                return None
            total = price * units_to_buy + (shipping or Decimal(0))
            effective_unit = total / quantity
            coverage = offered_measure * units_to_buy
        result = dict(offer)
        result.update(
            currency="SAR", price=money(price),
            unit_price=money(effective_unit), total_price=money(total),
            match_score=match["match_score"], match_label=match["match_label"],
            broad_match=False, comparable=bool(match.get("comparable", True)),
            match_score_type=match.get("match_score_type", "heuristic"), unverified_attributes=match.get("unverified_attributes", []),
            normalized_price=round(float(normalized), 4),
            normalized_unit=f"SAR/{dimension}",
            original_normalized_price=(round(float(original_total / (original_measure * quantity)), 4) if original_total is not None and quantity is not None else None),
            purchase_quantity=int(units_to_buy) if units_to_buy is not None else None,
            quantity_adjusted=bool(match.get("quantity_adjusted")),
            covered_quantity=float(coverage) if coverage is not None else None,
            covered_unit=dimension,
            shipping_included=shipping is not None,
            shipping_cost=money(shipping),
            price_basis="Equivalent quantity including known shipping" if shipping is not None else "Equivalent quantity; shipping not provided",
        )
        if quantity is None:
            result["price_basis"] = "Listed offer price; original quantity unknown"
        elif coverage > original_measure * quantity:
            result["price_basis"] += "; extra quantity must be purchased"
        return result

    def _shopping_offer(self, product, offer, match, price):
        """Estimate listed packs, never silently assert equivalent products."""
        quantity = number(product.get("quantity"), positive=True)
        currency = str(offer.get("currency") or "").strip().upper() or None
        purchase_quantity = None
        total = None
        shipping = _shipping_cost(offer)
        # Shipping amounts parsed by this module are SAR. Only an explicitly
        # free delivery cost is usable with a different confirmed currency.
        if currency != "SAR" and shipping != Decimal(0):
            shipping = None
        if quantity is not None:
            purchase_quantity = quantity.to_integral_value(rounding=ROUND_CEILING)
            if purchase_quantity > 100000:
                return None
            if currency is not None:
                total = price * purchase_quantity + (shipping or Decimal(0))
        size, dimension = size_info(offer)
        pack = pack_info(offer)
        measure = size * (pack or Decimal(1)) if size is not None else pack
        if size is None and pack is not None:
            dimension = "item"
        result = dict(offer)
        result.update(
            currency=currency, price=money(price), unit_price=money(price), total_price=money(total),
            match_score=match["match_score"], match_label="Search result",
            match_score_type="heuristic", broad_match=True, comparable=False,
            unverified_attributes=match.get("unverified_attributes", []),
            purchase_quantity=int(purchase_quantity) if purchase_quantity is not None else None,
            quantity_adjusted=False, original_normalized_price=None,
            normalized_price=round(float(price / measure), 4) if measure and currency else None,
            normalized_unit=f"{currency}/{dimension}" if measure and currency else None,
            covered_quantity=float(measure * purchase_quantity) if measure and purchase_quantity is not None else None,
            covered_unit=dimension if measure else None,
            shipping_included=shipping is not None, shipping_cost=money(shipping),
            price_basis="Shopping estimate for the requested number of listed offers; brands, sizes, and packs may differ.",
        )
        if quantity is None:
            result["price_basis"] = "Listed offer price; enter a quantity for a shopping estimate."
        elif quantity != purchase_quantity:
            result["price_basis"] += " Whole listed packs must be purchased."
        if shipping is None:
            result["price_basis"] += " Shipping not provided."
        if currency is None:
            result["price_basis"] += " Listing currency is unconfirmed; no monetary total or SAR comparison is available."
        elif currency != "SAR":
            result["price_basis"] += f" Amounts are in {currency}; no SAR conversion or savings comparison is available."
        return result
