import json
import unittest

from services.errors import InvoiceError
from services.product_matching_service import ProductMatchingService
from services.recommendation_service import RecommendationService, combined_search_query


def product(**values):
    result = {
        "id": "p1", "name": "Apple AirPods Pro 2 USB-C", "brand": "Apple",
        "model": "AirPods Pro 2", "variant": "USB-C", "category": "Electronics",
        "condition": None, "confidence": .96, "quantity": 1,
        "unit_price": 849, "total_price": 849,
    }
    result.update(values)
    return result


def offer(**values):
    result = {
        "title": "Apple AirPods Pro 2 USB-C", "store": "Example Store",
        "price": 749, "currency": "SAR", "product_url": "https://example.com/airpods",
        "image_url": None, "rating": None, "reviews": None, "availability": "In Stock",
        "shipping": None,
    }
    result.update(values)
    return result


def milk(**values):
    result = {
        "id": "milk", "name": "Almarai Full Fat Milk 2L", "brand": "Almarai",
        "model": None, "variant": "Full Fat", "category": "Food",
        "size_value": 2, "size_unit": "l", "quantity": 1,
        "unit_price": 8, "total_price": 8,
    }
    result.update(values)
    return result


class Shopping:
    def __init__(self, results=None):
        self.results = results if results is not None else [offer()]
        self.calls = []

    def search_products(self, query):
        self.calls.append(query)
        results = self.results(query) if callable(self.results) else self.results
        if isinstance(results, Exception):
            raise results
        return {"offers": results, "cached": False, "fetched_at": "2026-09-08T12:00:00+00:00", "query": query}


class RecommendationTests(unittest.TestCase):
    def calculate(self, items=None, offers=None, invoice=None, config=None):
        service = RecommendationService(Shopping(offers), config or {})
        return service.recommend(items if items is not None else [product()], invoice)

    def test_exact_product_saving_and_confidence_are_not_invented(self):
        result = self.calculate()
        rec = result["recommendations"][0]
        self.assertEqual(rec["saving"], {"amount": 100., "percentage": 11.78, "level": "Good Saving"})
        self.assertEqual(rec["best_offer"]["match_label"], "Exact Match")
        self.assertNotIn("confidence", rec["best_offer"])
        self.assertIn("match_scores_are_heuristic", result["warnings"])

    def test_wrong_model_generation_and_variant_are_rejected(self):
        for title in ("Apple AirPods Pro 3 USB-C", "Apple AirPods Pro 2 Lightning", "Apple AirPods 2 USB-C"):
            with self.subTest(title=title):
                rec = self.calculate(offers=[offer(title=title, price=20)])["recommendations"][0]
                self.assertIsNone(rec["best_offer"])

    def test_storage_256_and_mixed_variant_listing_are_rejected(self):
        phone = product(name="Samsung Galaxy S26 Ultra 512GB", brand="Samsung", model="Galaxy S26 Ultra", variant=None)
        for title in ("Samsung Galaxy S26 Ultra 256GB", "Samsung Galaxy S26 Ultra 256GB 512GB"):
            with self.subTest(title=title):
                rec = self.calculate([phone], [offer(title=title)])["recommendations"][0]
                self.assertIsNone(rec["best_offer"])

    def test_colour_and_used_condition_are_rejected(self):
        original = product(name="Apple AirPods Pro 2 USB-C White", condition="new")
        for title in ("Apple AirPods Pro 2 USB-C Black", "Used Apple AirPods Pro 2 USB-C White"):
            with self.subTest(title=title):
                self.assertIsNone(self.calculate([original], [offer(title=title)])["recommendations"][0]["best_offer"])

    def test_accessory_for_product_is_not_same_product(self):
        rec = self.calculate(offers=[offer(title="Protective case for Apple AirPods Pro 2 USB-C", price=10)])["recommendations"][0]
        self.assertIsNone(rec["best_offer"])

    def test_premium_suffix_in_name_is_mandatory_even_without_model(self):
        phone = product(name="Samsung Galaxy S26 Ultra 512GB", brand="Samsung", model=None, variant=None)
        rec = self.calculate([phone], [offer(title="Samsung Galaxy S26 512GB")])["recommendations"][0]
        self.assertIsNone(rec["best_offer"])
        base = product(name="Samsung Galaxy S26 512GB", brand="Samsung", model=None, variant=None)
        rec = self.calculate([base], [offer(title="Samsung Galaxy S26 Ultra 512GB")])["recommendations"][0]
        self.assertIsNone(rec["best_offer"])

    def test_standalone_charging_case_is_not_an_airpods_purchase(self):
        rec = self.calculate(offers=[offer(title="Apple AirPods Pro 2 USB-C Charging Case", price=25)])["recommendations"][0]
        self.assertIsNone(rec["best_offer"])
        rec = self.calculate(offers=[offer(title="Apple AirPods Pro 2 USB-C with Charging Case")])["recommendations"][0]
        self.assertIsNotNone(rec["best_offer"])

    def test_unknown_storage_connector_capacity_or_generation_requires_review(self):
        cases = (
            (product(name="Apple iPhone 15", brand="Apple", model="iPhone 15", variant=None), "Apple iPhone 15 128GB"),
            (product(name="Apple AirPods Pro 2", variant=None), "Apple AirPods Pro 2 USB-C"),
            (product(name="Apple AirPods Pro", model="AirPods Pro", variant=None), "Apple AirPods Pro 2"),
            (product(name="Anker Power Bank", brand="Anker", model=None, variant=None), "Anker Power Bank 5000mAh"),
        )
        for original, candidate in cases:
            with self.subTest(candidate=candidate):
                rec = self.calculate([original], [offer(title=candidate)])["recommendations"][0]
                self.assertIsNone(rec["best_offer"])

    def test_phone_charger_and_ear_tips_do_not_match_whole_product(self):
        phone = product(name="Samsung Galaxy S26 Ultra 512GB", brand="Samsung", model=None, variant=None)
        rec = self.calculate([phone], [offer(title="Samsung Galaxy S26 Ultra 512GB Fast Charger")])["recommendations"][0]
        self.assertIsNone(rec["best_offer"])
        rec = self.calculate(offers=[offer(title="Apple AirPods Pro 2 USB-C Ear Tips")])["recommendations"][0]
        self.assertIsNone(rec["best_offer"])

    def test_metadata_model_numbers_are_part_of_identity(self):
        original = product(name="Apple AirPods Pro", model="AirPods Pro 2")
        rec = self.calculate([original])["recommendations"][0]
        self.assertIsNotNone(rec["best_offer"])
        self.assertEqual(rec["best_offer"]["match_score_type"], "heuristic")
        self.assertIn("condition", rec["best_offer"]["unverified_attributes"])

    def test_two_liters_vs_one_liter_is_not_cheaper(self):
        result = self.calculate([milk()], [offer(title="Almarai Full Fat Milk 1L", price=4.5)])
        rec = result["recommendations"][0]
        self.assertEqual(rec["best_offer"]["purchase_quantity"], 2)
        self.assertEqual(rec["best_offer"]["total_price"], 9)
        self.assertEqual(rec["best_offer"]["normalized_price"], 4.5)
        self.assertEqual(rec["best_offer"]["original_normalized_price"], 4)
        self.assertEqual(rec["best_offer"]["normalized_unit"], "SAR/liter")
        self.assertEqual(rec["best_offer"]["match_label"], "Quantity-adjusted match")
        self.assertEqual(result["summary"]["potential_savings"], 0)
        self.assertEqual(result["summary"]["recommended_total"], 8)

    def test_same_brand_required_for_different_grocery_sizes(self):
        rec = self.calculate([milk(brand=None)], [offer(title="Almarai Full Fat Milk 1L", price=2)])["recommendations"][0]
        self.assertIsNone(rec["best_offer"])

    def test_grocery_variants_must_match(self):
        rec = self.calculate([milk()], [offer(title="Almarai Low Fat Milk 2L", price=2)])["recommendations"][0]
        self.assertIsNone(rec["best_offer"])

    def test_grams_and_kilograms_are_equivalent(self):
        coffee = milk(name="Acme Coffee 1000g", brand="Acme", variant=None, size_value=1000, size_unit="g", unit_price=40, total_price=40)
        rec = self.calculate([coffee], [offer(title="Acme Coffee 1kg", price=30)])["recommendations"][0]
        self.assertEqual(rec["best_offer"]["normalized_unit"], "SAR/kg")
        self.assertEqual(rec["saving"]["amount"], 10)

    def test_quantity_three_multiplies_full_offer_cost(self):
        rec = self.calculate([product(quantity=3, total_price=2547)])["recommendations"][0]
        self.assertEqual(rec["best_offer"]["purchase_quantity"], 3)
        self.assertEqual(rec["best_offer"]["total_price"], 2247)
        self.assertEqual(rec["saving"]["amount"], 300)

    def test_water_twelve_pack_cannot_use_single_bottle_price(self):
        water = milk(name="Nestle Water 500ml", brand="Nestle", variant=None, size_value=500, size_unit="ml", pack_size=12, unit_price=10, total_price=10)
        rec = self.calculate([water], [offer(title="Nestle Water 500ml", pack_size=1, price=1)])["recommendations"][0]
        self.assertEqual(rec["best_offer"]["purchase_quantity"], 12)
        self.assertEqual(rec["best_offer"]["total_price"], 12)
        self.assertEqual(rec["saving"]["amount"], 0)

    def test_unknown_pack_size_cannot_be_assumed_to_be_single(self):
        water = milk(name="Nestle Water 500ml", brand="Nestle", variant=None, size_value=500, size_unit="ml", pack_size=12)
        rec = self.calculate([water], [offer(title="Nestle Water 500ml", price=1)])["recommendations"][0]
        self.assertIsNone(rec["best_offer"])
        self.assertIn("pack_size_unknown", rec["rejected_offer_reasons"])

    def test_compact_pack_volume_is_normalized_not_treated_as_item_count(self):
        original = milk(name="Almarai Full Fat Milk 2x500ml", size_value=None, size_unit=None, unit_price=8, total_price=8)
        rec = self.calculate([original], [offer(title="Almarai Full Fat Milk 1x250ml", price=2.5)])["recommendations"][0]
        self.assertEqual(rec["best_offer"]["purchase_quantity"], 4)
        self.assertEqual(rec["best_offer"]["total_price"], 10)
        self.assertEqual(rec["saving"]["amount"], 0)
        self.assertEqual(rec["best_offer"]["normalized_unit"], "SAR/liter")

    def test_original_ambiguous_multipack_is_rejected(self):
        original = milk(name="Almarai Full Fat Fresh Milk Multipack 2L")
        rec = self.calculate([original], [offer(title="Almarai Full Fat Fresh Milk 2L", price=2)])["recommendations"][0]
        self.assertIsNone(rec["best_offer"])

    def test_whole_pack_purchase_rounds_up_and_labels_excess(self):
        water = milk(name="Nestle Water 500ml", brand="Nestle", variant=None, size_value=500, size_unit="ml", pack_size=1, quantity=3, unit_price=5, total_price=15)
        rec = self.calculate([water], [offer(title="Nestle Water 500ml", pack_size=2, price=6)])["recommendations"][0]
        self.assertEqual(rec["best_offer"]["purchase_quantity"], 2)
        self.assertEqual(rec["best_offer"]["total_price"], 12)
        self.assertIn("extra quantity", rec["best_offer"]["price_basis"])

    def test_vat_not_double_counted_and_summary_uses_comparable_subset(self):
        known = product(unit_price=100, total_price=100)
        unknown = {"id": "vague", "name": "Milk", "quantity": 1, "unit_price": 30, "total_price": 30}
        result = self.calculate([known, unknown], [offer(price=80)], invoice={"total": 149.5, "subtotal": 130, "tax": 19.5, "currency": "SAR"})
        self.assertEqual(result["summary"]["original_total"], 149.5)
        self.assertEqual(result["summary"]["comparable_original_total"], 100)
        self.assertEqual(result["summary"]["recommended_total"], 80)
        self.assertEqual(result["summary"]["potential_savings"], 20)
        self.assertEqual(result["summary"]["saving_percentage"], 20)
        self.assertTrue(result["summary"]["partial"])

    def test_foreign_currency_offers_and_invoices_are_rejected(self):
        rec = self.calculate(offers=[offer(price=5, currency="USD")])["recommendations"][0]
        self.assertIsNone(rec["best_offer"])
        with self.assertRaises(InvoiceError) as caught:
            self.calculate(invoice={"total": 100, "currency": "USD"})
        self.assertEqual(caught.exception.code, "unsupported_currency")

    def test_product_without_current_price_still_returns_real_offers(self):
        result = self.calculate([product(unit_price=None, total_price=None)])
        rec = result["recommendations"][0]
        self.assertEqual(rec["best_offer"]["price"], 749)
        self.assertIsNone(rec["saving"]["amount"])
        self.assertIsNone(result["summary"]["original_total"])
        self.assertEqual(result["summary"]["compared_items"], 0)

    def test_unknown_quantity_never_becomes_one_for_invoice_savings(self):
        result = self.calculate([product(quantity=None)])
        rec = result["recommendations"][0]
        self.assertIsNotNone(rec["best_offer"])
        self.assertIsNone(rec["best_offer"]["total_price"])
        self.assertIsNone(rec["saving"]["amount"])
        self.assertEqual(result["summary"]["compared_items"], 0)

    def test_duplicate_product_search_runs_only_once(self):
        shopping = Shopping()
        result = RecommendationService(shopping, {}).recommend([product(), product(id="p2", quantity=2, total_price=1698)])
        self.assertEqual(len(shopping.calls), 1)
        self.assertEqual(result["recommendations"][1]["saving"]["amount"], 200)

    def test_generic_and_fee_lines_skip_before_api_quota(self):
        shopping = Shopping()
        items = [{"id": str(i), "name": name} for i, name in enumerate(("Milk", "Milk 2L", "Water", "VAT", "Tax", "Discount", "Subtotal", "Total", "Shipping", "Service Fee", "Payment", "Change", "ضريبة القيمة المضافة", "VAT amount", "Total SAR100", "الإجمالي ر.س 100"))]
        result = RecommendationService(shopping, {}).recommend(items)
        self.assertEqual(shopping.calls, [])
        self.assertEqual(result["summary"]["skipped_items"], len(items))

    def test_one_combined_search_keeps_every_identity_despite_old_per_item_limit(self):
        low = product(id="low", name="Acme Budget Lamp", brand="Acme", model="Budget Lamp", variant=None, unit_price=10, total_price=10)
        high = product(id="high")
        shopping = Shopping([offer(), offer(title="Acme Budget Lamp", price=8)])
        result = RecommendationService(shopping, {"RECOMMENDATION_MAX_SEARCHES": 1}).recommend([low, high])
        self.assertEqual(len(shopping.calls), 1)
        self.assertIn("airpods", shopping.calls[0])
        self.assertIn("budget lamp", shopping.calls[0])
        self.assertIn('" OR "', shopping.calls[0])
        self.assertIsNotNone(result["recommendations"][0]["best_offer"])
        self.assertEqual(result["recommendations"][1]["saving"]["amount"], 100)
        self.assertIn("combined_search_limited_coverage", result["warnings"])

    def test_minimum_amount_and_percentage_are_both_required(self):
        rec = self.calculate([product(unit_price=100, total_price=100)], [offer(price=99)])["recommendations"][0]
        self.assertEqual(rec["status"], "no_significant_saving")
        self.assertEqual(rec["saving"]["level"], "No significant saving")
        rec = self.calculate([product(unit_price=100, total_price=100)], [offer(price=90)], config={"RECOMMENDATION_MIN_SAVING_AMOUNT": 11})["recommendations"][0]
        self.assertEqual(rec["status"], "no_significant_saving")

    def test_configurable_saving_levels(self):
        for price, label in ((95, "Small Saving"), (90, "Good Saving"), (80, "Excellent Saving")):
            with self.subTest(price=price):
                rec = self.calculate([product(unit_price=100, total_price=100)], [offer(price=price)])["recommendations"][0]
                self.assertEqual(rec["saving"]["level"], label)
        rec = self.calculate([product(unit_price=100, total_price=100)], [offer(price=85)], config={"RECOMMENDATION_EXCELLENT_SAVING_PERCENTAGE": 15})["recommendations"][0]
        self.assertEqual(rec["saving"]["level"], "Excellent Saving")

    def test_no_result_never_invents_a_recommendation(self):
        result = self.calculate(offers=[])
        self.assertIsNone(result["recommendations"][0]["best_offer"])
        self.assertEqual(result["recommendations"][0]["reason_code"], "no_shopping_results")
        self.assertIsNone(result["summary"]["recommended_total"])

    def test_low_recognition_confidence_skips_request(self):
        shopping = Shopping()
        result = RecommendationService(shopping, {}).recommend([product(confidence=.6)])
        self.assertEqual(shopping.calls, [])
        self.assertEqual(result["recommendations"][0]["reason_code"], "insufficient_recognition_confidence")

    def test_manual_review_overrides_old_ai_confidence_but_not_generic_identity(self):
        shopping = Shopping()
        result = RecommendationService(shopping, {}).recommend([product(confidence=.2, reviewed=True)])
        self.assertEqual(len(shopping.calls), 1)
        self.assertEqual(result["recommendations"][0]["saving"]["amount"], 100)
        result = RecommendationService(shopping, {}).recommend([{"name": "Milk", "reviewed": True}])
        self.assertEqual(len(shopping.calls), 1)
        self.assertEqual(result["recommendations"][0]["reason_code"], "product_too_generic")

    def test_missing_config_raises_actionable_error(self):
        shopping = Shopping(InvoiceError("serpapi_not_configured", "Configure SERPAPI_KEY.", 503))
        with self.assertRaises(InvoiceError) as caught:
            RecommendationService(shopping, {}).recommend([product()])
        self.assertEqual(caught.exception.code, "serpapi_not_configured")

    def test_failed_combined_search_does_not_retry_individual_products(self):
        shopping = Shopping(InvoiceError("serpapi_timeout", "Search timed out.", 504))
        second = product(id="second", name="Acme Budget Lamp", brand="Acme", model="Budget Lamp", variant=None, unit_price=100, total_price=100)
        result = RecommendationService(shopping, {}).recommend([product(), second])
        self.assertEqual(len(shopping.calls), 1)
        self.assertEqual(result["recommendations"][0]["status"], "search_failed")
        self.assertEqual(result["recommendations"][1]["status"], "search_failed")
        self.assertIsNone(result["recommendations"][1]["saving"]["amount"])
        self.assertEqual(result["summary"]["compared_items"], 0)
        self.assertIn("serpapi_timeout", result["warnings"])

    def test_known_shipping_is_added_once_for_whole_order_quantity(self):
        rec = self.calculate([product(quantity=3, total_price=2547)], [offer(shipping="SAR 20 delivery")])["recommendations"][0]
        self.assertEqual(rec["best_offer"]["total_price"], 2267)
        self.assertTrue(rec["best_offer"]["shipping_included"])
        self.assertEqual(rec["saving"]["amount"], 280)

    def test_conditional_free_shipping_is_not_claimed_as_included(self):
        for delivery in ("SAR 20 delivery; free on orders over SAR 200", "Free delivery on first order", "Free Prime member shipping"):
            with self.subTest(delivery=delivery):
                rec = self.calculate(offers=[offer(shipping=delivery)])["recommendations"][0]
                self.assertFalse(rec["best_offer"]["shipping_included"])
                self.assertIsNone(rec["best_offer"]["shipping_cost"])

    def test_unavailable_and_unlinked_offers_are_not_recommended(self):
        for changes in ({"availability": "Out of stock"}, {"product_url": None}, {"store": None}):
            with self.subTest(changes=changes):
                self.assertIsNone(self.calculate(offers=[offer(**changes)])["recommendations"][0]["best_offer"])

    def test_reviewed_fields_build_query_instead_of_unrelated_ai_query(self):
        shopping = Shopping()
        RecommendationService(shopping, {}).recommend([product(search_query="Unrelated cheap headphones")])
        self.assertIn("AirPods Pro 2", shopping.calls[0])
        self.assertNotIn("Unrelated", shopping.calls[0])


    def test_conflicting_original_size_metadata_cannot_inflate_quantity(self):
        original = milk(name="Almarai Full Fat Milk 500ml", size_value=2, size_unit="l")
        rec = self.calculate([original], [offer(title="Almarai Full Fat Milk 500ml", price=2)])["recommendations"][0]
        self.assertIsNone(rec["best_offer"])
        self.assertIn("original_size_metadata_conflict", rec["rejected_offer_reasons"])
        corrected = milk(name="Almarai Full Fat Milk 500ml", size_value=500, size_unit="ml")
        rec = self.calculate([corrected], [offer(title="Almarai Full Fat Milk 500ml", price=2)])["recommendations"][0]
        self.assertIsNotNone(rec["best_offer"])

    def test_conflicting_original_pack_metadata_cannot_inflate_quantity(self):
        original = milk(name="Almarai Full Fat Milk 2L pack of 6", pack_size=12)
        rec = self.calculate([original], [offer(title="Almarai Full Fat Milk 2L pack of 6", price=20)])["recommendations"][0]
        self.assertIsNone(rec["best_offer"])
        self.assertIn("original_pack_metadata_conflict", rec["rejected_offer_reasons"])

    def test_equivalent_metadata_units_and_corrected_packs_are_allowed(self):
        original = milk(name="Almarai Full Fat Milk 1000ml", size_value=1, size_unit="l")
        rec = self.calculate([original], [offer(title="Almarai Full Fat Milk 1L", price=2)])["recommendations"][0]
        self.assertIsNotNone(rec["best_offer"])
        original = milk(name="Almarai Full Fat Milk 2L pack of 6", pack_size=6)
        rec = self.calculate([original], [offer(title="Almarai Full Fat Milk 2L pack of 6", price=5)])["recommendations"][0]
        self.assertIsNotNone(rec["best_offer"])

    def test_conflicting_offer_measure_metadata_is_also_rejected(self):
        for changes, reason in (({"size_value": 500, "size_unit": "ml"}, "offer_size_metadata_conflict"),
                                ({"title": "Almarai Full Fat Milk 2L pack of 6", "pack_size": 12}, "offer_pack_metadata_conflict")):
            with self.subTest(changes=changes):
                candidate = offer(title="Almarai Full Fat Milk 2L", price=2)
                candidate.update(changes)
                rec = self.calculate([milk()], [candidate])["recommendations"][0]
                self.assertIsNone(rec["best_offer"])
                self.assertIn(reason, rec["rejected_offer_reasons"])


    def test_condition_is_unverified_when_either_side_has_no_explicit_condition(self):
        for original_condition, offer_condition in (("new", None), (None, "new"), (None, None)):
            with self.subTest(original=original_condition, candidate=offer_condition):
                rec = self.calculate([product(condition=original_condition)], [offer(condition=offer_condition)])["recommendations"][0]
                self.assertIsNotNone(rec["best_offer"])
                self.assertIn("condition", rec["best_offer"]["unverified_attributes"])
        rec = self.calculate([product(condition="new")], [offer(condition="new")])["recommendations"][0]
        self.assertNotIn("condition", rec["best_offer"]["unverified_attributes"])

    def test_input_count_is_bounded(self):
        with self.assertRaises(InvoiceError):
            self.calculate(items=[])
        with self.assertRaises(InvoiceError):
            self.calculate(items=[product()] * 201)



class ShoppingDiscoveryTests(unittest.TestCase):
    def recommend(self, products, offers, **kwargs):
        shopping = Shopping(offers)
        result = RecommendationService(shopping, {}).recommend(products, shopping=True, **kwargs)
        return result, shopping

    def test_literal_specific_product_name_needs_no_structured_identity_or_price(self):
        result, _ = self.recommend([{"name": "Apple AirPods Pro 2 USB-C", "quantity": 1}], [offer()])
        rec = result["recommendations"][0]
        self.assertIsNotNone(rec["best_offer"])
        self.assertEqual(result["summary"]["shopping_total"], 749)
        self.assertIsNone(rec["saving"]["amount"])

    def test_broad_samsung_phone_preserves_brand_word(self):
        result, _ = self.recommend([{"name": "Samsung phone", "quantity": 1}], [
            offer(title="Apple iPhone 15 128GB", price=1),
            offer(title="Samsung Galaxy S26 Ultra 512GB", price=4000),
            offer(title="Samsung Galaxy S26 Ultra 512GB Phone Case", price=5)])
        rec = result["recommendations"][0]
        self.assertEqual(len(rec["offers"]), 1)
        self.assertTrue(rec["best_offer"]["broad_match"])
        self.assertEqual(rec["best_offer"]["price"], 4000)

    def test_generic_milk_returns_visible_search_results_without_savings(self):
        result, shopping = self.recommend(
            [{"name": "Milk", "quantity": 3, "unit_price": 10, "total_price": 30}],
            [offer(title="Almarai Full Fat Milk 2L", price=8)])
        rec = result["recommendations"][0]
        self.assertEqual(len(shopping.calls), 1)
        self.assertEqual(rec["status"], "search_result")
        self.assertTrue(rec["best_offer"]["broad_match"])
        self.assertFalse(rec["best_offer"]["comparable"])
        self.assertEqual(rec["best_offer"]["match_label"], "Search result")
        self.assertIsNone(rec["saving"]["amount"])
        self.assertEqual(rec["best_offer"]["purchase_quantity"], 3)
        self.assertEqual(rec["best_offer"]["total_price"], 24)
        self.assertEqual(result["summary"]["shopping_total"], 24)
        self.assertEqual(result["summary"]["found_items"], 1)
        self.assertFalse(result["summary"]["shopping_partial"])
        self.assertEqual(result["summary"]["compared_items"], 0)
        self.assertEqual(result["summary"]["potential_savings"], 0)

    def test_arabic_rice_search_accepts_literal_arabic_product_title(self):
        result, _ = self.recommend(
            [{"name": "أرز", "quantity": 2}],
            [offer(title="الأرز البسمتي 1kg", price=12)])
        self.assertEqual(result["summary"]["shopping_total"], 24)
        self.assertTrue(result["recommendations"][0]["best_offer"]["broad_match"])

    def test_generic_rice_does_not_select_rice_cooker(self):
        result, _ = self.recommend(
            [{"name": "Rice", "quantity": 1}],
            [offer(title="Rice cooker machine", price=10), offer(title="Basmati Rice 1kg", price=20)])
        rec = result["recommendations"][0]
        self.assertEqual(len(rec["offers"]), 1)
        self.assertEqual(rec["best_offer"]["title"], "Basmati Rice 1kg")

    def test_explicit_brand_size_and_pack_constraints_are_preserved(self):
        original = {"name": "Almarai Milk 2L pack of 6", "brand": "Almarai", "size_value": 2, "size_unit": "l", "pack_size": 6, "quantity": 1}
        candidates = [
            offer(title="Nadec Milk 2L pack of 6", price=1),
            offer(title="Almarai Milk 1L pack of 6", price=2),
            offer(title="Almarai Milk 2L pack of 12", price=3),
            offer(title="Almarai Milk 2L pack of 6", price=40),
        ]
        result, _ = self.recommend([original], candidates)
        rec = result["recommendations"][0]
        self.assertEqual(len(rec["offers"]), 1)
        self.assertEqual(rec["best_offer"]["price"], 40)

    def test_known_generation_and_storage_reject_wrong_or_ambiguous_options(self):
        original = {"name": "Samsung Galaxy S26 Ultra 512GB", "quantity": 1}
        result, _ = self.recommend([original], [
            offer(title="Samsung Galaxy S25 Ultra 512GB", price=1),
            offer(title="Samsung Galaxy S26 Ultra 256GB", price=2),
            offer(title="Samsung Galaxy S26 Ultra 256GB 512GB", price=3),
            offer(title="Samsung Galaxy S26 Ultra 512GB", price=4000),
        ])
        self.assertEqual(len(result["recommendations"][0]["offers"]), 1)

    def test_unspecified_storage_is_discovery_and_cannot_generate_savings(self):
        result, _ = self.recommend(
            [{"name": "Apple iPhone 15", "quantity": 1, "unit_price": 4000}],
            [offer(title="Apple iPhone 15 128GB", price=2000)])
        rec = result["recommendations"][0]
        self.assertIsNotNone(rec["best_offer"])
        self.assertTrue(rec["best_offer"]["broad_match"])
        self.assertIsNone(rec["saving"]["amount"])

    def test_generic_quantities_count_listed_packs_without_equivalence_claim(self):
        result, _ = self.recommend(
            [{"name": "Water", "quantity": 3}],
            [offer(title="Nestle Water 500ml pack of 12", price=10)])
        best = result["recommendations"][0]["best_offer"]
        self.assertEqual(best["purchase_quantity"], 3)
        self.assertEqual(best["total_price"], 30)
        self.assertEqual(best["covered_quantity"], 18)
        self.assertEqual(best["covered_unit"], "liter")
        self.assertIn("listed offers", best["price_basis"])
        self.assertFalse(best["comparable"])

    def test_unknown_quantity_has_offer_but_no_invented_shopping_total(self):
        result, _ = self.recommend([{"name": "Milk", "quantity": None}], [offer(title="Almarai Milk 2L", price=8)])
        self.assertEqual(result["summary"]["found_items"], 1)
        self.assertIsNone(result["summary"]["shopping_total"])
        self.assertEqual(result["summary"]["shopping_estimated_items"], 0)
        self.assertTrue(result["summary"]["shopping_estimate_partial"])
        self.assertIsNone(result["recommendations"][0]["best_offer"]["purchase_quantity"])

    def test_partial_list_sums_only_found_items(self):
        result, shopping = self.recommend([{"name": "Milk", "quantity": 2}, {"name": "Rice", "quantity": 1}], [offer(title="Almarai Milk 2L", price=8)])
        self.assertEqual(len(shopping.calls), 1)
        self.assertEqual(result["summary"]["shopping_total"], 16)
        self.assertEqual(result["summary"]["found_items"], 1)
        self.assertTrue(result["summary"]["shopping_partial"])

    def test_shopping_fees_and_placeholder_lines_never_consume_quota(self):
        result, shopping = self.recommend(
            [{"name": name, "quantity": 1} for name in ("VAT", "Shipping", "Total SAR100", "ضريبة", "Product 1")],
            [offer()])
        self.assertEqual(shopping.calls, [])
        self.assertEqual(result["summary"]["found_items"], 0)

    def test_shopping_discovery_reuses_duplicate_query(self):
        result, shopping = self.recommend(
            [{"id": "a", "name": "Milk", "quantity": 2}, {"id": "b", "name": "Milk", "quantity": 3}],
            [offer(title="Almarai Milk 2L", price=8)])
        self.assertEqual(len(shopping.calls), 1)
        self.assertEqual(result["summary"]["shopping_total"], 40)

    def test_known_exact_identity_can_still_calculate_safe_savings(self):
        result, _ = self.recommend([product()], [offer()])
        best = result["recommendations"][0]["best_offer"]
        self.assertFalse(best["broad_match"])
        self.assertTrue(best["comparable"])
        self.assertEqual(result["recommendations"][0]["saving"]["amount"], 100)
        self.assertEqual(result["summary"]["shopping_total"], 749)

    def test_invoice_always_keeps_strict_matching_even_when_shopping_flag_supplied(self):
        result, shopping = self.recommend(
            [{"name": "Milk", "quantity": 1, "unit_price": 20}],
            [offer(title="Almarai Milk 2L", price=8)],
            invoice={"currency": "SAR", "total": 20})
        self.assertEqual(shopping.calls, [])
        self.assertNotIn("shopping_total", result["summary"])
        self.assertIsNone(result["recommendations"][0]["best_offer"])


    def test_galaxy_search_accepts_optional_ram_screen_network_and_regional_sku(self):
        titles = [
            "Samsung Galaxy S26 Ultra 256GB",
            "Samsung Galaxy S26 Ultra 512GB 12GB RAM 5G",
            "Samsung Galaxy S26 Ultra 256GB RAM 12GB 6.9 inch SM-S948B",
            'Samsung Galaxy S26 Ultra 512GB 12GB RAM 5G 6.9" SM-S948B/DS',
            "Samsung Galaxy S26 Ultra 512GB 6.90-inch SM-S948BLBGC",
        ]
        result, _ = self.recommend(
            [{"name": "galaxy s26 ultra", "quantity": 1}],
            [offer(title=title, price=3000 + index) for index, title in enumerate(titles)])
        self.assertEqual(len(result["recommendations"][0]["offers"]), 2)
        for title in titles:
            self.assertTrue(ProductMatchingService().shopping_match({"name": "galaxy s26 ultra"}, offer(title=title))["eligible"])
        self.assertTrue(all(value["broad_match"] for value in result["recommendations"][0]["offers"]))
        self.assertIsNone(result["recommendations"][0]["saving"]["amount"])

    def test_optional_phone_attributes_do_not_allow_wrong_family_suffix_or_accessory(self):
        titles = [
            "Samsung Galaxy S25 Ultra 512GB 12GB RAM 5G 6.9 inch SM-S938B",
            "Samsung Galaxy S26 512GB 12GB RAM 5G 6.9 inch SM-S942B",
            "Samsung Galaxy S26 Plus 512GB 12GB RAM 5G 6.9 inch SM-S946B",
            "Samsung Galaxy S26 Ultra 512GB 12GB RAM 5G Phone Case",
            "Samsung Galaxy S26 Ultra S25 Ultra 512GB 12GB RAM 5G",
        ]
        result, _ = self.recommend(
            [{"name": "galaxy s26 ultra", "quantity": 1}],
            [offer(title=title, price=100) for title in titles])
        self.assertEqual(result["summary"]["found_items"], 0)

    def test_explicit_storage_is_not_confused_with_additional_ram(self):
        result, _ = self.recommend(
            [{"name": "galaxy s26 ultra 512GB", "quantity": 1}],
            [offer(title="Samsung Galaxy S26 Ultra 512GB 12GB RAM 5G 6.9 inch SM-S948B"),
             offer(title="Samsung Galaxy S26 Ultra 256GB 12GB RAM 5G 6.9 inch SM-S948B")])
        self.assertEqual(len(result["recommendations"][0]["offers"]), 1)
        self.assertIn("512GB", result["recommendations"][0]["best_offer"]["title"])

    def test_explicit_ram_screen_network_and_sku_constraints_still_match(self):
        choices = (
            ("galaxy s26 ultra 12GB RAM", "Samsung Galaxy S26 Ultra 512GB 8GB RAM 5G"),
            ("galaxy s26 ultra 6.9 inch", "Samsung Galaxy S26 Ultra 512GB 6.8 inch"),
            ("galaxy s26 ultra 5G", "Samsung Galaxy S26 Ultra 512GB 4G"),
            ("galaxy s26 ultra SM-S948B", "Samsung Galaxy S26 Ultra 512GB SM-S948U"),
        )
        for requested, title in choices:
            with self.subTest(requested=requested):
                result, _ = self.recommend([{"name": requested, "quantity": 1}], [offer(title=title)])
                self.assertEqual(result["summary"]["found_items"], 0)

    def test_phone_5g_is_not_five_grams_but_food_5g_remains_a_weight(self):
        from services.product_matching_service import size_info
        self.assertEqual(size_info({"name": "Samsung Galaxy S26 Ultra 5G"}), (None, None))
        self.assertEqual(size_info({"name": "Acme Saffron 5g"})[1], "kg")
        self.assertEqual(float(size_info({"name": "Acme Saffron 5g"})[0]), .005)
        result, _ = self.recommend(
            [{"name": "galaxy s26 ultra", "quantity": 1}],
            [offer(title="Samsung Galaxy S26 Ultra 512GB 5G")])
        best = result["recommendations"][0]["best_offer"]
        self.assertNotEqual(best["covered_unit"], "kg")
        self.assertNotEqual(best["normalized_unit"], "SAR/kg")


    def test_saved_real_galaxy_title_shapes_keep_descriptive_numbers_separate(self):
        # Literal public titles copied from the single approved diagnostic;
        # offers/prices below are synthetic and this test makes no network call.
        titles = [
            "Samsung Galaxy S26 Ultra 17.5 cm Dual SIM Android 16.0 5G USB Type-C 12 GB 512 GB 5000 mAh Black",
            "Samsung Galaxy S26 Ultra 6.9 12GB RAM 512GB ROM 200MP 5000mAh",
            "Samsung Galaxy S26 Ultra Enterprise Edition 17.5 cm Dual SIM Android 16.0 5G USB Type-C 12 GB 5000 mAh Black",
        ]
        result, _ = self.recommend(
            [{"name": "galaxy s26 ultra", "quantity": 1}],
            [offer(title=title, price=4000 + index) for index, title in enumerate(titles)])
        self.assertEqual(len(result["recommendations"][0]["offers"]), 2)
        for title in titles:
            self.assertTrue(ProductMatchingService().shopping_match({"name": "galaxy s26 ultra"}, offer(title=title))["eligible"])
        self.assertTrue(all(value["broad_match"] for value in result["recommendations"][0]["offers"]))
        self.assertIsNone(result["recommendations"][0]["saving"]["amount"])

    def test_explicit_optional_numeric_phone_attributes_are_not_discarded(self):
        choices = (
            ("galaxy s26 ultra android 16.0", "Samsung Galaxy S26 Ultra Android 15.0"),
            ("galaxy s26 ultra 200MP", "Samsung Galaxy S26 Ultra 100MP"),
            ("galaxy s26 ultra 17.5cm", "Samsung Galaxy S26 Ultra 16.5cm"),
            ("galaxy s26 ultra 6.9", "Samsung Galaxy S26 Ultra 6.8 12GB RAM"),
            ("galaxy s26 ultra", "Samsung Galaxy S26 Ultra S25 Ultra 6.9 200MP Android 16.0"),
        )
        for requested, title in choices:
            with self.subTest(requested=requested):
                result, _ = self.recommend([{"name": requested, "quantity": 1}], [offer(title=title)])
                self.assertEqual(result["summary"]["found_items"], 0)

    def test_broad_offer_preserves_shop_resolution_metadata(self):
        result, _ = self.recommend(
            [{"name": "Milk", "quantity": 1}],
            [offer(title="Almarai Milk 2L", price=8, shop_lookup_token="opaque-token", link_kind="shopping")])
        best = result["recommendations"][0]["best_offer"]
        self.assertEqual(best["shop_lookup_token"], "opaque-token")
        self.assertEqual(best["link_kind"], "shopping")

    def test_discovery_does_not_bypass_accessory_condition_or_invalid_price_checks(self):
        result, _ = self.recommend(
            [{"name": "Apple iPhone 15", "quantity": 1}],
            [offer(title="Apple iPhone 15 128GB Fast Charger", price=1),
             offer(title="Used Apple iPhone 15 128GB", price=2),
             offer(title="Apple iPhone 15 128GB", price=None, currency="USD")])
        self.assertIsNone(result["recommendations"][0]["best_offer"])


class ShoppingCurrencyTests(unittest.TestCase):
    def recommend(self, offers, products=None):
        shopping = Shopping(offers)
        result = RecommendationService(shopping, {}).recommend(
            products or [{"name": "iPhone", "quantity": 2}], shopping=True)
        self.assertEqual(len(shopping.calls), 1)
        return result

    def test_unconfirmed_dollar_listing_is_visible_without_sar_totals(self):
        result = self.recommend([offer(title="Apple iPhone 17 256GB", price=444.99,
                                      currency=None, price_label="$444.99")])
        rec = result["recommendations"][0]
        best = rec["best_offer"]
        self.assertIsNone(best["currency"])
        self.assertEqual(best["price_label"], "$444.99")
        self.assertEqual(best["extracted_price"], 444.99)
        self.assertTrue(best["broad_match"])
        self.assertFalse(best["comparable"])
        self.assertIsNone(best["total_price"])
        self.assertIsNone(best["normalized_unit"])
        self.assertIsNone(rec["saving"]["amount"])
        self.assertIsNone(result["summary"]["shopping_total"])
        self.assertEqual(result["summary"]["found_items"], 1)
        self.assertIn("shopping_currency_not_comparable", result["warnings"])

    def test_known_foreign_currency_has_own_quantity_estimate_without_sar_shipping(self):
        result = self.recommend([offer(title="Apple iPhone 17 256GB", price=100,
                                      currency="USD", price_label="US$100", shipping="SAR 20 delivery")])
        best = result["recommendations"][0]["best_offer"]
        self.assertEqual(best["currency"], "USD")
        self.assertEqual(best["purchase_quantity"], 2)
        self.assertEqual(best["total_price"], 200)
        self.assertFalse(best["shipping_included"])
        self.assertIsNone(result["summary"]["shopping_total"])

    def test_exact_identity_in_foreign_currency_never_claims_savings(self):
        result = self.recommend([offer(price=10, currency="USD", price_label="US$10")], [product()])
        rec = result["recommendations"][0]
        self.assertTrue(rec["best_offer"]["broad_match"])
        self.assertFalse(rec["best_offer"]["comparable"])
        self.assertEqual(rec["best_offer"]["match_label"], "Search result")
        self.assertIsNone(rec["saving"]["amount"])
        self.assertEqual(result["summary"]["compared_items"], 0)
        self.assertEqual(result["summary"]["potential_savings"], 0)

    def test_foreign_and_unknown_currency_remain_rejected_for_invoices(self):
        shopping = Shopping([offer(price=10, currency="USD"), offer(price=2, currency=None)])
        result = RecommendationService(shopping, {}).recommend(
            [product()], invoice={"currency": "SAR", "total": 849}, shopping=True)
        self.assertIsNone(result["recommendations"][0]["best_offer"])
        self.assertEqual(result["summary"]["compared_items"], 0)
        self.assertNotIn("shopping_total", result["summary"])

    def test_known_currency_prices_sort_only_within_provider_ordered_groups(self):
        result = self.recommend([
            offer(title="Apple iPhone 17", price=400, currency="USD"),
            offer(title="Apple iPhone 17", price=10, currency="SAR"),
            offer(title="Apple iPhone 17", price=300, currency="USD"),
            offer(title="Apple iPhone 17", price=500, currency="USD"),
        ])
        cards = result["recommendations"][0]["offers"]
        self.assertEqual([(card["currency"], card["price"]) for card in cards], [("USD", 300), ("USD", 400)])

    def test_unconfirmed_currency_prices_retain_provider_order(self):
        result = self.recommend([
            offer(title="Apple iPhone 17", price=400, currency=None, price_label="$400"),
            offer(title="Apple iPhone 17", price=20, currency=None, price_label="$20"),
            offer(title="Apple iPhone 17", price=10, currency=None, price_label="$10"),
        ])
        self.assertEqual([card["price"] for card in result["recommendations"][0]["offers"]], [400, 20])

    def test_any_selected_foreign_card_disables_sar_aggregate_even_if_best_is_sar(self):
        result = self.recommend([
            offer(title="Apple iPhone 17", price=400, currency="SAR"),
            offer(title="Apple iPhone 17", price=100, currency="USD"),
        ])
        self.assertEqual(result["recommendations"][0]["best_offer"]["currency"], "SAR")
        self.assertIsNone(result["summary"]["shopping_total"])
        self.assertTrue(result["summary"]["shopping_estimate_partial"])

    def test_list_does_not_add_known_foreign_totals_into_sar(self):
        result = self.recommend([
            offer(title="Apple iPhone 17", price=100, currency="USD"),
            offer(title="Almarai Milk 1L", price=5, currency="SAR"),
        ], [{"name": "iPhone", "quantity": 2}, {"name": "Milk", "quantity": 3}])
        self.assertEqual(result["summary"]["found_items"], 2)
        self.assertIsNone(result["summary"]["shopping_total"])
        self.assertEqual([item["best_offer"]["total_price"] for item in result["recommendations"]], [200, 15])


class CombinedSearchTests(unittest.TestCase):
    def test_shared_pool_is_matched_per_item_then_limited_to_two_numeric_prices(self):
        pool = [
            offer(title="Almarai Milk 2L", price=100, source_icon="https://example.com/milk.png"),
            offer(title="Almarai Milk 2L", price=8),
            offer(title="Almarai Milk 2L", price=12),
            offer(title="Basmati Rice 1kg", price=30),
            offer(title="Basmati Rice 1kg", price=5),
            offer(title="Basmati Rice 1kg", price=20),
            offer(title="Milk frother", price=1),
        ]
        shopping = Shopping(pool)
        result = RecommendationService(shopping, {}).recommend([
            {"name": "Milk", "quantity": 2}, {"name": "Rice", "quantity": 3},
            {"name": "Bread", "quantity": 1},
        ], shopping=True)
        self.assertEqual(len(shopping.calls), 1)
        self.assertEqual(shopping.calls[0], '"bread" OR "milk" OR "rice"')
        self.assertEqual([[o["extracted_price"] for o in item["offers"]] for item in result["recommendations"]], [[8, 12], [5, 20], []])
        self.assertEqual(result["summary"]["shopping_total"], 31)
        self.assertEqual(result["summary"]["found_items"], 2)
        self.assertTrue(result["summary"]["shopping_partial"])
        self.assertIn("combined_search_limited_coverage", result["warnings"])
        for item in result["recommendations"][:2]:
            self.assertEqual(item["best_offer"], item["offers"][0])
            for card in item["offers"]:
                for field in ("title", "product_link", "source", "source_icon", "extracted_price"):
                    self.assertIn(field, card)

    def test_listed_price_order_does_not_claim_false_equivalent_quantity_savings(self):
        shopping = Shopping([
            offer(title="Almarai Full Fat Milk 2L", price=7.5),
            offer(title="Almarai Full Fat Milk 1L", price=4.5),
            offer(title="Almarai Full Fat Milk 2L", price=7),
        ])
        result = RecommendationService(shopping, {}).recommend([milk()], invoice={"currency": "SAR", "total": 8})
        rec = result["recommendations"][0]
        self.assertEqual([o["extracted_price"] for o in rec["offers"]], [4.5, 7])
        self.assertEqual(rec["best_offer"]["purchase_quantity"], 2)
        self.assertEqual(rec["best_offer"]["total_price"], 9)
        self.assertEqual(rec["saving"]["amount"], 0)
        self.assertEqual(result["summary"]["recommended_total"], 8)
        self.assertIn("first displayed offer", result["summary"]["offer_selection_basis"])

    def test_single_item_is_unquoted_and_also_gets_only_two_offers(self):
        shopping = Shopping([offer(price=100), offer(price=20), offer(price=3)])
        result = RecommendationService(shopping, {}).recommend([product()])
        self.assertEqual(shopping.calls, ["Apple AirPods Pro 2 USB-C"])
        self.assertEqual([value["price"] for value in result["recommendations"][0]["offers"]], [3, 20])
        self.assertNotIn("combined_search_limited_coverage", result["warnings"])

    def test_combined_query_is_order_case_quantity_and_duplicate_invariant(self):
        first = [{"name": "Milk", "quantity": 1}, {"name": "Rice", "quantity": 2}]
        second = [{"name": "RICE", "quantity": 4}, {"name": "milk", "quantity": 3}, {"name": "Milk", "quantity": 8}]
        shopping = Shopping([])
        service = RecommendationService(shopping, {})
        service.recommend(first, shopping=True)
        service.recommend(second, shopping=True)
        self.assertEqual(shopping.calls[0], shopping.calls[1])
        self.assertEqual(shopping.calls[0], '"milk" OR "rice"')

    def test_quote_escaping_preserves_geography_in_product_identity(self):
        name = 'Acme "Deluxe" lamp \\ special'
        query, count = combined_search_query([name, "Map of Saudi Arabia"])
        self.assertEqual(count, 2)
        self.assertEqual(query, json.dumps(name.casefold()) + ' OR "map of saudi arabia"')
        self.assertIn('\\"deluxe\\"', query)

    def test_single_product_query_does_not_append_location(self):
        shopping = Shopping([offer(title="Apple iPhone 17 256GB Black", price=4000)])
        result = RecommendationService(shopping, {}).recommend([
            {"name": "iPhone", "quantity": 1},
        ], shopping=True)
        self.assertEqual(shopping.calls, ["iPhone"])
        self.assertEqual(result["search_query"], "iPhone")
        self.assertEqual(result["summary"]["found_items"], 1)

    def test_combined_engine_query_preserves_user_supplied_geography(self):
        shopping = Shopping([])
        RecommendationService(shopping, {}).recommend([
            {"name": "Map of Saudi Arabia", "quantity": 1},
            {"name": "iPhone", "quantity": 1},
        ], shopping=True)
        self.assertEqual(shopping.calls, ['"iphone" OR "map of saudi arabia"'])

    def test_name_and_model_overlap_is_not_duplicated_in_quoted_identity(self):
        shopping = Shopping([])
        RecommendationService(shopping, {}).recommend([
            product(name="Apple AirPods", model="AirPods Pro 2", variant="USB-C"),
            {"name": "Milk", "quantity": 1},
        ], shopping=True)
        self.assertEqual(shopping.calls[0], '"apple airpods pro 2 usb-c" OR "milk"')

    def test_oversized_combined_query_rejects_all_before_any_search(self):
        shopping = Shopping([])
        items = [{"name": f"Acme item {index} " + "x" * 300, "quantity": 1} for index in range(30)]
        with self.assertRaises(InvoiceError) as caught:
            RecommendationService(shopping, {}).recommend(items, shopping=True)
        self.assertEqual(caught.exception.code, "combined_query_too_long")
        self.assertEqual(caught.exception.status, 400)
        self.assertIn("Shorten the list", caught.exception.message)
        self.assertEqual(shopping.calls, [])

    def test_full_reviewed_identity_is_not_truncated_at_old_400_character_limit(self):
        distinctive_variant = "final-variant-" + "v" * 100
        original = {"name": "Acme " + "n" * 330, "model": "m" * 100, "variant": distinctive_variant, "quantity": 1}
        shopping = Shopping([])
        RecommendationService(shopping, {}).recommend([original, {"name": "Milk", "quantity": 1}], shopping=True)
        self.assertEqual(len(shopping.calls), 1)
        self.assertGreater(len(shopping.calls[0]), 400)
        self.assertIn(distinctive_variant, shopping.calls[0])

    def test_every_eligible_item_beyond_old_eight_search_limit_is_in_one_query(self):
        names = ["Milk", "Rice", "Bread", "Coffee", "Tea", "Sugar", "Eggs", "Butter", "Cheese", "Apples", "Bananas", "Juice"]
        shopping = Shopping([])
        result = RecommendationService(shopping, {}).recommend([{"name": name, "quantity": 1} for name in names], shopping=True)
        self.assertEqual(len(shopping.calls), 1)
        for name in names:
            self.assertIn(json.dumps(name.casefold()), shopping.calls[0])
        self.assertTrue(all(item["reason_code"] == "no_shopping_results" for item in result["recommendations"]))

    def test_punctuation_distinct_identities_are_not_merged(self):
        query, count = combined_search_query(["Acme C++", "Acme C"])
        self.assertEqual(count, 2)
        self.assertEqual(query, '"acme c" OR "acme c++"')

    def test_cached_shared_results_and_timestamp_propagate_to_every_item(self):
        class CachedShopping(Shopping):
            def search_products(self, query):
                return dict(super().search_products(query), cached=True)
        shopping = CachedShopping([offer(title="Almarai Milk 2L", price=8)])
        result = RecommendationService(shopping, {}).recommend([{"name": "Milk", "quantity": 1}, {"name": "Rice", "quantity": 1}], shopping=True)
        self.assertEqual(len(shopping.calls), 1)
        self.assertTrue(all(item["cached"] for item in result["recommendations"]))
        self.assertEqual(len({item["fetched_at"] for item in result["recommendations"]}), 1)


if __name__ == "__main__":
    unittest.main()
