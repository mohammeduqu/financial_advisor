import io
import threading

from flask import Flask, Request, jsonify, request
from flask_cors import CORS
from werkzeug.exceptions import HTTPException, RequestEntityTooLarge

from utils.origin_policy import allowed_origin_patterns, origin_is_allowed
from services.errors import InvoiceError
from services.invoice_service import MAX_IMAGE_BYTES, analyze_invoice, prepare_image
from services.ollama_service import OllamaService
from ollama_config import OllamaConfig, get_ollama_config
from config import load_settings
from cache.search_cache import SearchCache
from services.serpapi_service import SerpApiService
from services.recommendation_service import RecommendationService
from routes.recommendation_routes import register_recommendations
from routes.deal_routes import register_deal_routes


class InMemoryUploadRequest(Request):
    def _get_file_stream(self, total_content_length, content_type, filename=None, content_length=None):
        return io.BytesIO()


def create_app(ollama=None, shopping=None, recommendation_config=None):
    settings = load_settings(recommendation_config)
    app = Flask(__name__)
    app.request_class = InMemoryUploadRequest
    app.config.update(
        MAX_CONTENT_LENGTH=MAX_IMAGE_BYTES + 64 * 1024,
        MAX_FORM_MEMORY_SIZE=MAX_IMAGE_BYTES + 64 * 1024,
        MAX_FORM_PARTS=8,
    )
    origins = allowed_origin_patterns(settings["NUMO_ALLOWED_ORIGINS"])
    CORS(app, resources={r"/api/*": {"origins": origins}},
         supports_credentials=False, methods=["GET", "POST", "OPTIONS"],
         allow_headers=["Content-Type"], always_send=False)
    analysis_slot = threading.BoundedSemaphore(1)
    app.extensions["invoice_analysis_slot"] = analysis_slot
    app.extensions["ollama_service"] = ollama if ollama is not None else OllamaService()
    shopping = shopping if shopping is not None else SerpApiService(
        api_key=settings["SERPAPI_KEY"],
        cache=SearchCache(settings["PRICE_CACHE_PATH"], ttl_seconds=settings["PRICE_CACHE_TTL_SECONDS"]),
        ttl_seconds=settings["PRICE_CACHE_TTL_SECONDS"],
        language=settings["SERPAPI_LANGUAGE"],
        timeout_seconds=settings["SERPAPI_TIMEOUT_SECONDS"],
    )
    register_recommendations(app, RecommendationService(shopping, settings), settings)
    register_deal_routes(app, shopping)

    @app.before_request
    def check_browser_origin():
        # CORS headers alone do not prevent another website submitting a multipart form.
        origin = request.headers.get("Origin")
        if request.path.startswith("/api/") and origin and not origin_is_allowed(origin, origins):
            raise InvoiceError("forbidden_origin", "This browser origin is not allowed.", 403)

    @app.after_request
    def prevent_invoice_caching(response):
        response.headers["Cache-Control"] = "no-store"
        response.headers["X-Content-Type-Options"] = "nosniff"
        return response

    @app.get("/api/health")
    def health():
        # This reports Flask availability, not model readiness or inference success.
        model_config = getattr(app.extensions["ollama_service"], "config", None)
        if not isinstance(model_config, OllamaConfig):
            model_config = get_ollama_config()
        return jsonify(success=True, service="numo-local-invoice", model=model_config.model)

    @app.post("/api/invoice/analyze")
    def analyze():
        files = request.files.getlist("image")
        if len(files) != 1 or not files[0].filename:
            raise InvoiceError("missing_image", "Please select one invoice image.", 400)
        if not analysis_slot.acquire(blocking=False):
            raise InvoiceError("server_busy", "Another invoice is being analyzed. Please try again shortly.", 503)
        try:
            image_bytes = prepare_image(files[0].read(MAX_IMAGE_BYTES + 1))
            invoice, warning_codes = analyze_invoice(image_bytes, app.extensions["ollama_service"])
            return jsonify(success=True, invoice=invoice, warnings=warning_codes)
        finally:
            analysis_slot.release()

    @app.errorhandler(InvoiceError)
    def handle_invoice_error(error):
        response = jsonify(success=False, error=error.message, code=error.code)
        if error.code == "server_busy":
            response.headers["Retry-After"] = "5"
        return response, error.status

    @app.errorhandler(RequestEntityTooLarge)
    def handle_large_upload(_error):
        return jsonify(success=False, error="The image must be 8 MB or smaller.", code="image_too_large"), 413

    @app.errorhandler(HTTPException)
    def handle_http_error(error):
        return jsonify(success=False, error=error.name, code="invalid_request"), error.code

    @app.errorhandler(Exception)
    def handle_unexpected_error(_error):
        # Do not log uploaded images, extracted values, model output, or exception bodies.
        app.logger.error("Invoice request failed unexpectedly.")
        return jsonify(success=False, error="Invoice analysis failed. Please try again.", code="internal_error"), 500

    return app


app = create_app()

if __name__ == "__main__":
    # Development server. Configure the model target in ollama_config.py.
    app.run(host="0.0.0.0", port=5000, debug=False, use_reloader=False, threaded=True)
