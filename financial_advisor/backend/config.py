"""Backend-only environment settings. Never expose key values in API responses."""
import math
import os
from pathlib import Path

from dotenv import dotenv_values

BACKEND_DIR = Path(__file__).resolve().parent


def load_settings(overrides=None):
    # Read only this backend's .env; real process environment takes precedence.
    values = {**dotenv_values(BACKEND_DIR / ".env"), **os.environ, **(overrides or {})}
    result = {
        "SERPAPI_KEY": str(values.get("SERPAPI_KEY") or "").strip(),
        "SERPAPI_LANGUAGE": str(values.get("SERPAPI_LANGUAGE") or "en").lower(),
        "PRICE_CACHE_PATH": str(values.get("PRICE_CACHE_PATH") or BACKEND_DIR / "cache" / "searches.sqlite3"),
        "NUMO_ALLOWED_ORIGINS": str(values.get("NUMO_ALLOWED_ORIGINS") or ""),
    }
    limits = {
        "PRICE_CACHE_TTL_SECONDS": (43200, 21600, 86400, int),
        "SERPAPI_TIMEOUT_SECONDS": (20, 1, 30, float),
        "RECOMMENDATION_MAX_SEARCHES": (8, 1, 20, int),
        "RECOMMENDATION_MIN_MATCH_SCORE": (0.85, 0.70, 1, float),
        "RECOMMENDATION_MIN_SAVING_AMOUNT": (2, 0, 1000000, float),
        "RECOMMENDATION_MIN_SAVING_PERCENTAGE": (5, 0, 100, float),
        "RECOMMENDATION_GOOD_SAVING_PERCENTAGE": (10, 0, 100, float),
        "RECOMMENDATION_EXCELLENT_SAVING_PERCENTAGE": (20, 0, 100, float),
    }
    for name, (default, minimum, maximum, converter) in limits.items():
        try:
            value = converter(values.get(name, default))
            if not math.isfinite(value) or not minimum <= value <= maximum:
                raise ValueError()
        except (TypeError, ValueError, OverflowError):
            raise ValueError(f"Invalid setting {name}; expected {minimum} through {maximum}.") from None
        result[name] = value
    if result["SERPAPI_LANGUAGE"] not in {"en", "ar"}:
        raise ValueError("SERPAPI_LANGUAGE must be en or ar.")
    if not (result["RECOMMENDATION_MIN_SAVING_PERCENTAGE"] <=
            result["RECOMMENDATION_GOOD_SAVING_PERCENTAGE"] <=
            result["RECOMMENDATION_EXCELLENT_SAVING_PERCENTAGE"]):
        raise ValueError("Saving percentage levels must be in ascending order.")
    cache_path = Path(result["PRICE_CACHE_PATH"])
    result["PRICE_CACHE_PATH"] = str(cache_path if cache_path.is_absolute() else BACKEND_DIR / cache_path)
    return result
