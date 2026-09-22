"""Persistent, bounded search results with per-process single-flight requests.

Only normalized offers and search metadata are stored. No credentials or uploaded
images are accepted. SQLite connections are short-lived and initialized lazily.
"""
from concurrent.futures import Future
from contextlib import closing
from copy import deepcopy
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import sqlite3
import threading
import time
import unicodedata

from services.errors import InvoiceError

DEFAULT_TTL_SECONDS = 12 * 60 * 60
MIN_TTL_SECONDS = 6 * 60 * 60
MAX_TTL_SECONDS = 24 * 60 * 60
MAX_CACHE_PAYLOAD_BYTES = 2 * 1024 * 1024
MAX_QUERY_LENGTH = 8000
_FLIGHTS = {}
_FLIGHTS_LOCK = threading.Lock()


def normalize_query(query):
    if not isinstance(query, str):
        raise InvoiceError("invalid_search_query", "Enter a product search query.", 400)
    query = " ".join(unicodedata.normalize("NFKC", query).split())
    if not query or len(query) > MAX_QUERY_LENGTH or any(
        unicodedata.category(char) in {"Cc", "Cs"} for char in query
    ):
        raise InvoiceError("invalid_search_query", f"Use a product query of 1 to {MAX_QUERY_LENGTH} characters.", 400)
    return query


def query_key(query, region="sa", language="en"):
    data = ["shopping-v4-currency", normalize_query(query).casefold(), region.lower(), language.lower(),
            "google.com.sa", "Saudi Arabia", 1]
    return hashlib.sha256(json.dumps(data, ensure_ascii=False).encode("utf-8")).hexdigest()


def _cache_error():
    return InvoiceError(
        "price_cache_unavailable",
        "The price cache is unavailable. Check PRICE_CACHE_PATH and its write permissions.",
        503,
    )


class SearchCache:
    def __init__(self, path=None, ttl_seconds=DEFAULT_TTL_SECONDS, clock=None, max_entries=1000):
        self.path = Path(path) if path else Path(__file__).with_name("searches.sqlite3")
        self.ttl_seconds = max(MIN_TTL_SECONDS, min(MAX_TTL_SECONDS, int(ttl_seconds)))
        self.clock = clock or time.time
        self.max_entries = max(1, min(10000, int(max_entries)))

    def _connect(self):
        self.path.parent.mkdir(parents=True, exist_ok=True)
        db = sqlite3.connect(str(self.path), timeout=5)
        try:
            db.execute(
                "CREATE TABLE IF NOT EXISTS searches ("
                "cache_key TEXT PRIMARY KEY, fetched_at REAL NOT NULL, payload TEXT NOT NULL)"
            )
        except sqlite3.Error:
            db.close()
            raise
        return db

    def get(self, key):
        try:
            with closing(self._connect()) as db, db:
                row = db.execute(
                    "SELECT fetched_at, payload FROM searches WHERE cache_key = ?", (key,)
                ).fetchone()
                if row is None:
                    return None
                fetched_at, raw = row
                now = self.clock()
                valid_age = isinstance(fetched_at, (int, float)) and 0 <= now - fetched_at < self.ttl_seconds
                payload = None
                if valid_age and isinstance(raw, str) and len(raw.encode("utf-8")) <= MAX_CACHE_PAYLOAD_BYTES:
                    try:
                        decoded = json.loads(raw)
                        if (
                            isinstance(decoded, dict)
                            and isinstance(decoded.get("offers"), list)
                            and len(decoded["offers"]) <= 100
                            and all(isinstance(offer, dict) for offer in decoded["offers"])
                            and isinstance(decoded.get("query"), str)
                            and isinstance(decoded.get("fetched_at"), str)
                            and datetime.fromisoformat(decoded["fetched_at"]).tzinfo is not None
                        ):
                            payload = decoded
                    except (ValueError, TypeError):
                        pass
                if payload is None:
                    db.execute("DELETE FROM searches WHERE cache_key = ?", (key,))
                return payload
        except (sqlite3.Error, OSError):
            raise _cache_error() from None

    def put(self, key, result):
        # All fields are allowlisted so provider metadata cannot persist API keys.
        payload = {
            "offers": result["offers"],
            "query": result["query"],
            "fetched_at": result["fetched_at"],
        }
        raw = json.dumps(payload, ensure_ascii=False, allow_nan=False, separators=(",", ":"))
        if len(raw.encode("utf-8")) > MAX_CACHE_PAYLOAD_BYTES:
            raise _cache_error()
        now = self.clock()
        try:
            with closing(self._connect()) as db, db:
                db.execute("DELETE FROM searches WHERE fetched_at <= ? OR fetched_at > ?",
                           (now - self.ttl_seconds, now))
                db.execute(
                    "INSERT OR REPLACE INTO searches(cache_key, fetched_at, payload) VALUES (?, ?, ?)",
                    (key, now, raw),
                )
                db.execute(
                    "DELETE FROM searches WHERE cache_key IN ("
                    "SELECT cache_key FROM searches ORDER BY fetched_at DESC, cache_key "
                    "LIMIT -1 OFFSET ?)", (self.max_entries,),
                )
        except (sqlite3.Error, OSError):
            raise _cache_error() from None

    def get_or_fetch(self, key, loader):
        """Concurrent equal queries share success or failure; failed calls are not cached.

        Single-flight is process-local. Multiple worker processes share SQLite
        results but may independently fetch simultaneous first-time misses.
        """
        identity = (os.path.normcase(str(self.path.resolve())), key)
        with _FLIGHTS_LOCK:
            future = _FLIGHTS.get(identity)
            owner = future is None
            if owner:
                if len(_FLIGHTS) >= 256:
                    raise InvoiceError("price_search_busy", "Price search is busy. Try again shortly.", 429)
                future = Future()
                _FLIGHTS[identity] = future
        if not owner:
            return deepcopy(future.result())
        try:
            result = self.get(key)
            if result is not None:
                result["cached"] = True
            else:
                result = loader()
                self.put(key, result)
                result["cached"] = False
            future.set_result(result)
            return deepcopy(result)
        except BaseException as error:
            future.set_exception(error)
            raise
        finally:
            with _FLIGHTS_LOCK:
                _FLIGHTS.pop(identity, None)

    def timestamp(self):
        return datetime.fromtimestamp(self.clock(), timezone.utc).isoformat()
