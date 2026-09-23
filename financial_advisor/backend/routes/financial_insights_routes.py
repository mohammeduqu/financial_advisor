import threading

from flask import Blueprint, jsonify, request

from services.errors import InvoiceError
from services.financial_insights_service import prepare_expense_facts
from utils.json_utils import _load_json

MAX_INSIGHTS_BODY_BYTES = 512 * 1024


def register_financial_insights(app, service):
    routes = Blueprint("financial_insights", __name__, url_prefix="/api/insights")
    slot = threading.BoundedSemaphore(1)
    app.extensions["financial_insights_slot"] = slot
    app.extensions["financial_insights_service"] = service

    @routes.post("/expenses")
    def expense_insights():
        if not request.is_json:
            raise InvoiceError("invalid_insights_request", "Provide expense data as JSON.", 400)
        if request.content_length and request.content_length > MAX_INSIGHTS_BODY_BYTES:
            raise InvoiceError("invalid_insights_request", "Expense data is too large.", 413)
        raw = request.get_data(cache=False)
        if len(raw) > MAX_INSIGHTS_BODY_BYTES:
            raise InvoiceError("invalid_insights_request", "Expense data is too large.", 413)
        try:
            body = _load_json(raw)
        except (ValueError, TypeError, RecursionError):
            raise InvoiceError("invalid_insights_request", "Expense data is invalid.", 400) from None
        facts = prepare_expense_facts(body)
        if not slot.acquire(blocking=False):
            raise InvoiceError("server_busy", "Another insights request is running. Try again shortly.", 503)
        try:
            return jsonify(success=True, **service.generate(facts))
        except InvoiceError:
            raise
        except Exception:
            # Never include expenses, provider bodies, credentials or exception text.
            raise InvoiceError("insights_failed", "Unable to generate expense insights. Please try again.", 500) from None
        finally:
            slot.release()

    app.register_blueprint(routes)
