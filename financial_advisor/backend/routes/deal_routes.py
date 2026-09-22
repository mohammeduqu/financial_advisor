"""Compatibility endpoint for old clients; paid seller lookups are disabled."""
from flask import Blueprint, request

from services.deal_service import resolve_shop_link
from services.errors import InvoiceError
from utils.json_utils import _load_json


def register_deal_routes(app, shopping):
    routes = Blueprint("shopping_deals", __name__)

    @routes.post("/api/recommendations/deal")
    def resolve_deal():
        if not request.is_json:
            raise InvoiceError("invalid_deal", "Select a valid shopping offer.", 400)
        if request.content_length and request.content_length > 24 * 1024:
            raise InvoiceError("invalid_deal", "The shopping offer is too large.", 413)
        raw = request.get_data(cache=True)
        if len(raw) > 24 * 1024:
            raise InvoiceError("invalid_deal", "The shopping offer is too large.", 413)
        try:
            body = _load_json(raw)
        except (ValueError, TypeError, RecursionError):
            raise InvoiceError("invalid_deal", "The shopping offer is invalid.", 400) from None
        if not isinstance(body, dict):
            raise InvoiceError("invalid_deal", "The shopping offer is invalid.", 400)
        # No search lock, provider reference, credentials or cache are needed.
        # Every well-formed object gets the same retirement response.
        return resolve_shop_link(None, body)

    app.register_blueprint(routes)
