"""Search orchestration and conservative potential savings (never actual savings)."""
import json
import os
import unicodedata
from datetime import datetime, timezone
from decimal import Decimal

from cache.search_cache import MAX_QUERY_LENGTH
from services.errors import InvoiceError
from services.price_comparison_service import PriceComparisonService, money, original_prices
from services.product_matching_service import (
    ProductMatchingService, build_search_query, meaningful_product, normalized_text, number,
)

_REASONS = {
    "broad_shopping_result": "Shopping options found. Check the listed brand, model, size, and pack before buying; these are not confirmed equivalent products.",
    "non_product_line": "This is a total, fee, or payment line, not a product.",
    "product_too_generic": "Add the brand, model, or a more specific product name.",
    "insufficient_recognition_confidence": "The detected product is uncertain. Review its identity before comparing.",
    "no_shopping_results": "No shopping offers were returned for this product.",
    "no_reliable_match": "No reliable matching alternative was found.",
    "missing_original_price_or_quantity": "Offers found; enter the original price and quantity to calculate savings.",
    "saving_found": "A matching offer could reduce the cost of an equivalent quantity.",
    "no_significant_saving": "The price difference is below your minimum savings thresholds.",
    "no_better_price": "No lower price was found for an equivalent quantity.",
    "unsupported_currency": "Only SAR prices can be compared.",
    "search_failed": "The combined price search could not finish. Please try again.",
}

MAX_OFFERS_PER_ITEM = 2


def combined_search_query(queries):
    """Canonical OR terms share one cached search without dropping an item."""
    distinct = {}
    for query in queries:
        canonical = " ".join(unicodedata.normalize("NFKC", query).split()).casefold()
        distinct.setdefault(canonical, query)
    if not distinct:
        return None, 0
    if len(distinct) == 1:
        # Preserve the established query for a single identity and duplicate lines.
        combined = next(iter(distinct.values()))
    else:
        # Queries contain only the reviewed identity. Preserve every word,
        # including geographic words that are part of the actual product name.
        combined = " OR ".join(json.dumps(query, ensure_ascii=False) for query in sorted(distinct))
    if len(combined) > MAX_QUERY_LENGTH:
        raise InvoiceError(
            "combined_query_too_long",
            "This list is too long for one price search. Shorten the list or product descriptions and try again.",
            400,
        )
    return combined, len(distinct)


class RecommendationService:
    def __init__(self, shopping, config=None):
        self.shopping = shopping
        self.config = os.environ if config is None else config
        self.minimum_amount = Decimal(str(self._setting("RECOMMENDATION_MIN_SAVING_AMOUNT", 2, 0, 1000000)))
        self.minimum_percentage = self._setting("RECOMMENDATION_MIN_SAVING_PERCENTAGE", 5, 0, 100)
        self.good_percentage = max(self.minimum_percentage, self._setting("RECOMMENDATION_GOOD_SAVING_PERCENTAGE", 10, 0, 100))
        self.excellent_percentage = max(self.good_percentage, self._setting("RECOMMENDATION_EXCELLENT_SAVING_PERCENTAGE", 20, 0, 100))
        self.matcher = ProductMatchingService(self._setting("RECOMMENDATION_MIN_MATCH_SCORE", .85, .70, 1))
        self.comparator = PriceComparisonService()

    def _setting(self, key, default, low, high):
        value = number(self.config.get(key, default))
        return max(low, min(high, float(value))) if value is not None else default

    def _saving(self, original, candidate):
        difference = max(Decimal(0), original - candidate)
        percentage = float(difference / original * 100) if original > 0 else 0.
        significant = difference >= self.minimum_amount and percentage >= self.minimum_percentage and difference > 0
        level = "No significant saving"
        if significant:
            level = ("Excellent Saving" if percentage >= self.excellent_percentage else
                     "Good Saving" if percentage >= self.good_percentage else "Small Saving")
        elif difference == 0:
            level = "No Better Price Found"
        return {"amount": money(difference), "percentage": round(percentage, 2), "level": level}, significant

    @staticmethod
    def _reason(result, code, status):
        result.update(reason_code=code, reason=_REASONS.get(code, _REASONS["search_failed"]), status=status)

    def recommend(self, products, invoice=None, shopping=False):
        if not isinstance(products, list) or not 1 <= len(products) <= 200 or not all(isinstance(p, dict) for p in products):
            raise InvoiceError("invalid_products", "Provide between 1 and 200 reviewed products.", 400)
        if invoice and str(invoice.get("currency") or "").upper() != "SAR":
            raise InvoiceError("unsupported_currency", "Price comparisons currently support SAR invoices only.", 422)
        # An invoice is always compared under the original strict rules.
        shopping = bool(shopping and invoice is None)
        now = datetime.now(timezone.utc).isoformat()
        warnings = ["listed_prices_may_exclude_shipping_or_tax", "match_scores_are_heuristic"]
        results = []
        for index, product in enumerate(products):
            original, _, _ = original_prices(product)
            results.append({
                "item_id": str(product.get("id") or index), "item_name": str(product.get("name") or ""),
                "quantity": product.get("quantity"), "original": original,
                "best_offer": None, "offers": [],
                "saving": {"amount": None, "percentage": None, "level": "No Better Price Found"},
                "status": "skipped", "reason": None, "reason_code": None, "query": None,
                "cached": False, "fetched_at": None,
            })
        eligible = []
        for index in range(len(products)):
            product, result = products[index], results[index]
            meaningful, reason = meaningful_product(product, shopping=shopping)
            if not meaningful:
                self._reason(result, reason, "skipped")
                continue
            if product.get("currency") and str(product["currency"]).upper() != "SAR":
                self._reason(result, "unsupported_currency", "skipped")
                continue
            query = build_search_query(product, truncate=False, include_location=False)
            result["query"] = query
            eligible.append(index)
        shared_query, distinct_queries = combined_search_query(results[index]["query"] for index in eligible)
        if distinct_queries > 1:
            warnings.append("combined_search_limited_coverage")
        search = None
        if shared_query is not None:
            try:
                # Exactly one call: no per-item retries, pagination, or fallback.
                search = self.shopping.search_products(shared_query)
            except InvoiceError as error:
                if error.code in {"serpapi_not_configured", "serpapi_auth_failed", "price_cache_unavailable"}:
                    raise
                search = error
                warnings.append(error.code)
        comparable_original = Decimal(0)
        recommended_total = Decimal(0)
        compared = 0
        for index in eligible:
            product, result = products[index], results[index]
            if isinstance(search, InvoiceError):
                self._reason(result, "search_failed", "search_failed")
                result["error_code"] = search.code
                continue
            result.update(cached=bool(search.get("cached")), fetched_at=search.get("fetched_at"))
            offers = search.get("offers") or []
            rejected = {}
            accepted = []
            seen_offers = set()
            for offer in offers:
                if not isinstance(offer, dict):
                    continue
                match = self.matcher.shopping_match(product, offer) if shopping else self.matcher.match(product, offer)
                compared_offer = self.comparator.compare(product, offer, match, shopping=shopping)
                if compared_offer is None:
                    rejection = match.get("reason") or "invalid_price_currency_or_availability"
                    rejected[rejection] = rejected.get(rejection, 0) + 1
                    continue
                # Merchant link + title + price avoids duplicate cards without conflating shops.
                offer_key = (normalized_text(offer.get("store")), str(offer.get("product_url")), normalized_text(offer.get("title")), compared_offer["total_price"], compared_offer["price"], compared_offer["currency"], offer.get("price_label") if not compared_offer["currency"] else None)
                if offer_key not in seen_offers:
                    accepted.append(compared_offer)
                    seen_offers.add(offer_key)
            # Cards show the two lowest listed prices, not a global market or
            # equivalent-quantity minimum. Financial math still uses whole packs.
            for priced_offer in accepted:
                priced_offer["extracted_price"] = priced_offer["price"]
                priced_offer.setdefault("product_link", priced_offer["product_url"])
                priced_offer.setdefault("source", priced_offer["store"])
                priced_offer.setdefault("source_icon", None)
            # Numeric prices are ordered only within a confirmed currency.
            # Cross-currency groups retain provider order; unknown currencies
            # cannot be treated as one comparable group (a bare '$' is ambiguous).
            currency_groups = {}
            ordered = []
            for position, priced_offer in enumerate(accepted):
                currency = priced_offer.get("currency")
                key = currency if currency else ("unknown", position)
                group = currency_groups.setdefault(key, len(currency_groups))
                ordered.append((group, priced_offer["extracted_price"] if currency else 0, -priced_offer["match_score"], position, priced_offer))
            accepted = [entry[-1] for entry in sorted(ordered, key=lambda entry: entry[:4])]
            result["offers"] = accepted[:MAX_OFFERS_PER_ITEM]
            result["rejected_offer_reasons"] = rejected
            if not accepted:
                self._reason(result, "no_shopping_results" if not offers else "no_reliable_match", "no_match")
                continue
            best = accepted[0]
            result["best_offer"] = best
            result["broad_match"] = bool(best.get("broad_match"))
            if best.get("broad_match"):
                self._reason(result, "broad_shopping_result", "search_result")
                continue
            _, quantity, original_total = original_prices(product)
            candidate = number(best.get("total_price"), positive=True)
            if quantity is None or original_total is None or candidate is None:
                self._reason(result, "missing_original_price_or_quantity", "offers_found")
                continue
            saving, significant = self._saving(original_total, candidate)
            result["saving"] = saving
            self._reason(result, "saving_found" if significant else "no_significant_saving" if saving["amount"] > 0 else "no_better_price", "saving" if significant else "no_significant_saving" if saving["amount"] > 0 else "no_better_price")
            comparable_original += original_total
            # Keep the current purchase when the matching alternative costs more.
            recommended_total += min(original_total, candidate)
            compared += 1
        known_totals = [original_prices(product)[2] for product in products]
        original_total = number(invoice.get("total"), positive=True) if invoice else None
        if original_total is None:
            existing = [value for value in known_totals if value is not None]
            original_total = sum(existing, Decimal(0)) if existing else None
        potential = max(Decimal(0), comparable_original - recommended_total)
        if compared < len(products):
            warnings.append("partial_comparison")
        found = [result for result in results if result["best_offer"] is not None]
        estimates = [number(result["best_offer"].get("total_price"), positive=True) for result in found]
        known_estimates = [value for value in estimates if value is not None]
        currency_not_comparable = shopping and any(
            value.get("currency") != "SAR" for result in results for value in result["offers"])
        if currency_not_comparable:
            warnings.append("shopping_currency_not_comparable")
        if shopping and any(result.get("broad_match") for result in results):
            warnings.append("shopping_options_are_not_confirmed_equivalents")
        return {
            "summary": {
                "original_total": money(original_total),
                "comparable_original_total": money(comparable_original),
                "recommended_total": money(recommended_total) if compared else None,
                "potential_savings": money(potential),
                "saving_percentage": round(float(potential / comparable_original * 100), 2) if comparable_original else 0.,
                "compared_items": compared, "total_items": len(products),
                "skipped_items": sum(result["status"] in {"skipped", "search_failed", "no_match"} for result in results),
                "currency": "SAR", "partial": compared < len(products),
                "savings_basis": "Comparable product lines only; invoice-level tax, discounts, and unknown shipping are excluded.",
                "savings_type": "potential",
                "offer_selection_basis": "Up to two matching returned offers, ordered by listed price within each confirmed currency; different or unconfirmed currencies retain provider group order. Estimates use the first displayed offer's purchase quantity and known costs; this is not a full-market price comparison.",
                **({"shopping_total": money(sum(known_estimates, Decimal(0))) if known_estimates and not currency_not_comparable else None,
                    "found_items": len(found), "shopping_partial": len(found) < len(products),
                    "shopping_estimated_items": len(known_estimates),
                    "shopping_estimate_partial": currency_not_comparable or len(known_estimates) < len(products),
                    "shopping_basis": "Estimated cost of selected listed offers at the requested quantities; check each package and shipping."} if shopping else {}),
            },
            "recommendations": results, "warnings": warnings, "searched_at": now,
            "search_query": shared_query,
        }
