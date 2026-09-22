"""Two-stage recognition -> explicit review -> paid shopping search."""
import threading

from flask import Blueprint, current_app, jsonify, request

from services.errors import InvoiceError
from utils.json_utils import _load_json
from services.invoice_service import MAX_IMAGE_BYTES, _number, analyze_invoice, normalize_invoice, prepare_image
from services.product_recognition_service import (
    recognize_product, product_from_item, product_from_text, reviewed_products,
)
from services.shopping_list_service import recognize_shopping_list, validate_list_text


def register_recommendations(app, recommendation_service, settings):
    routes = Blueprint("recommendations", __name__, url_prefix="/api/recommendations")
    search_slot = threading.BoundedSemaphore(1)
    app.extensions["recommendation_service"] = recommendation_service
    app.extensions["recommendation_search_slot"] = search_slot

    @routes.get("/status")
    def status():
        return jsonify(
            success=True, configured=bool(settings["SERPAPI_KEY"]),
            country="Saudi Arabia", currency="SAR",
            cache_ttl_seconds=settings["PRICE_CACHE_TTL_SECONDS"],
            max_searches=1, search_strategy="combined", max_offers_per_item=2,
        )

    def review_text(mode, body):
        if "products" in body or "invoice" in body:
            raise InvoiceError("invalid_products", "Provide text for extraction or products for confirmation, not both.", 400)
        if mode == "product":
            product = product_from_text(body["text"], body.get("optional_current_price"))
            return jsonify(success=True, stage="review", mode=mode, products=[product], warnings=[])
        text = validate_list_text(body["text"])
        slot = current_app.extensions["invoice_analysis_slot"]
        if not slot.acquire(blocking=False):
            raise InvoiceError("server_busy", "Another list or image is being analyzed. Try again shortly.", 503)
        try:
            extracted = recognize_shopping_list(current_app.extensions["ollama_service"], text=text)
            return jsonify(success=True, stage="review", mode=mode, **extracted)
        finally:
            slot.release()

    def handle(mode):
        if request.is_json:
            # A review payload contains no receipt bytes and never triggers another AI pass.
            if request.content_length and request.content_length > 512 * 1024:
                raise InvoiceError("invalid_products", "Product review is too large.", 413)
            raw_body = request.get_data(cache=True)
            if len(raw_body) > 512 * 1024:
                raise InvoiceError("invalid_products", "Product review is too large.", 413)
            try:
                body = _load_json(raw_body)
            except (ValueError, TypeError, RecursionError):
                raise InvoiceError("invalid_products", "Product review JSON is invalid.", 400) from None
            if not isinstance(body, dict):
                raise InvoiceError("review_required", "Review the detected products before searching prices.", 400)
            if body.get("confirmed") is not True:
                if "text" in body and mode in {"product", "shopping-list"}:
                    return review_text(mode, body)
                raise InvoiceError("review_required", "Review the detected products before searching prices.", 400)
            if "text" in body:
                raise InvoiceError("invalid_products", "Confirm the reviewed products without extraction text.", 400)
            products = reviewed_products(body.get("products"), mode)
            invoice = None
            if mode == "invoice":
                if not isinstance(body.get("invoice"), dict):
                    raise InvoiceError("invalid_products", "Include the reviewed invoice information.", 400)
                invoice, _ = normalize_invoice(body["invoice"])
                if invoice.get("currency") != "SAR":
                    raise InvoiceError("unsupported_currency", "Price comparison currently supports SAR invoices only.", 422)
            elif body.get("currency", "SAR") != "SAR":
                raise InvoiceError("unsupported_currency", "Price comparison currently supports SAR only.", 422)
            if not search_slot.acquire(blocking=False):
                raise InvoiceError("server_busy", "Another price comparison is running. Try again shortly.", 503)
            try:
                comparison_options = {"invoice": invoice}
                if mode in {"product", "shopping-list"}:
                    comparison_options["shopping"] = True
                result = current_app.extensions["recommendation_service"].recommend(products, **comparison_options)
                return jsonify(success=True, stage="results", mode=mode, **result)
            finally:
                search_slot.release()

        files = request.files.getlist("image")
        if len(files) != 1 or not files[0].filename:
            raise InvoiceError("missing_image", "Please select one product or invoice image.", 400)
        current_price = request.form.get("optional_current_price")
        if current_price is not None:
            current_price = _number(current_price)
            if current_price is None or current_price <= 0:
                raise InvoiceError("invalid_products", "Enter a valid positive current price.", 400)
        slot = current_app.extensions["invoice_analysis_slot"]
        if not slot.acquire(blocking=False):
            raise InvoiceError("server_busy", "Another image is being analyzed. Try again shortly.", 503)
        try:
            image = prepare_image(files[0].read(MAX_IMAGE_BYTES + 1))
            ollama = current_app.extensions["ollama_service"]
            if mode == "shopping-list":
                extracted = recognize_shopping_list(ollama, image_bytes=image)
                return jsonify(success=True, stage="review", mode=mode, **extracted)
            if mode == "product":
                product = recognize_product(image, ollama, current_price)
                return jsonify(success=True, stage="review", mode=mode, products=[product], warnings=[])
            invoice, warnings = analyze_invoice(image, ollama)
            products = [product_from_item(item, index) for index, item in enumerate(invoice["items"])]
            return jsonify(success=True, stage="review", mode=mode,
                           invoice=invoice, products=products, warnings=warnings)
        finally:
            slot.release()

    @routes.post("/product")
    def product():
        return handle("product")

    @routes.post("/invoice")
    def invoice():
        return handle("invoice")

    @routes.post("/shopping-list")
    def shopping_list():
        return handle("shopping-list")

    app.register_blueprint(routes)
