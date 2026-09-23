"""Direct product-name searches, separate from invoice recognition/comparison."""
import threading

from flask import Blueprint, jsonify, request

from services.errors import InvoiceError
from services.serpapi_service import direct_search_parameters
from utils.json_utils import _load_json

MAX_SEARCH_BODY_BYTES = 24 * 1024


def register_product_search(app, shopping):
    routes = Blueprint("product_search", __name__, url_prefix="/api/recommendations")
    slot = threading.BoundedSemaphore(1)
    app.extensions["product_search_slot"] = slot

    @routes.post("/search")
    def search():
        if not request.is_json:
            raise InvoiceError("invalid_search_text", "Provide a product name as JSON.", 400)
        if request.content_length and request.content_length > MAX_SEARCH_BODY_BYTES:
            raise InvoiceError("invalid_search_text", "Product search is too large.", 413)
        raw = request.get_data(cache=True)
        if len(raw) > MAX_SEARCH_BODY_BYTES:
            raise InvoiceError("invalid_search_text", "Product search is too large.", 413)
        try:
            body = _load_json(raw)
        except (ValueError, TypeError, RecursionError):
            raise InvoiceError("invalid_search_text", "Product search JSON is invalid.", 400) from None
        if not isinstance(body, dict):
            raise InvoiceError("invalid_search_text", "Enter one product name.", 400)
        allowed = {"q", "gl", "location", "google_domain", "hl", "max_price"}
        if set(body) - allowed:
            raise InvoiceError("invalid_search_options", "Use the supported product search settings.", 400)
        query, parameters = direct_search_parameters(
            body.get("q"), **{key: value for key, value in body.items() if key != "q"},
        )
        if not slot.acquire(blocking=False):
            raise InvoiceError("server_busy", "Another price search is running. Try again shortly.", 503)
        try:
            result = shopping.search_listings(query, **parameters)
            return jsonify(
                success=True, stage="results", mode="product", direct_search=True,
                query=query, search_parameters=parameters,
                shopping_results=result["offers"], summary={"total_results": len(result["offers"])},
                recommendations=[], searched_at=result["fetched_at"], cached=result["cached"],
            )
        finally:
            slot.release()

    app.register_blueprint(routes)
