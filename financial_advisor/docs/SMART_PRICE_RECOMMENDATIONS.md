# Smart Price Recommendation

Smart Price Recommendation adds product-photo and invoice-item price comparison to the existing Numo Flutter app. Recognition uses the existing private Ollama/Qwen vision transport; price searches use SerpAPI Google Shopping through Flask. Expenses remain stored locally in the existing FinanceStore.

## Setup

From the Flutter project's backend directory:

~~~powershell
.\venv\Scripts\python.exe -m pip install -r requirements.txt
if (!(Test-Path .env)) { Copy-Item .env.example .env }
~~~

Edit backend/.env locally and set:

~~~dotenv
SERPAPI_KEY=your_own_serpapi_key
~~~

Get a key from your SerpAPI account. Keep it out of Flutter, screenshots, chat, and source control. The existing backend .gitignore excludes .env. No key is included with this implementation.

This integration follows the [official Google Shopping API](https://serpapi.com/google-shopping-api) and [shopping result fields](https://serpapi.com/shopping-results). Searches use the Saudi region, the configured English/Arabic language, and explicitly identified SAR prices. A regional search does not prove final delivery eligibility or stock.

Keep Ollama running on 127.0.0.1:11434 with qwen3-vl:4b-instruct installed, then run Flask:

~~~powershell
.\venv\Scripts\python.exe app.py
~~~

Restart an already-running Flask process to load the new Python code. The reloader remains disabled.

From the Flutter project root:

~~~powershell
flutter pub get
flutter run
~~~

Use a development build. The current local-only client restrictions and private/local base URL validator remain in force. Product deals open only when the user taps a deal button; Flutter does not send API requests to Ollama or SerpAPI.

On Linux, use ./venv/bin/python in place of .\venv\Scripts\python.exe. Ollama must run separately on that same server. Use the private server address in scanner settings when the server is on another machine; 10.0.2.2 points only to the Android Emulator's host.

### Configuration

The backend uses python-dotenv to read only backend/.env, then overlays process environment variables. Existing environment values take precedence; .env is not sent to the app. See [python-dotenv documentation](https://bbc2.github.io/python-dotenv/) for file syntax.

| Variable | Default | Purpose |
| --- | --- | --- |
| SERPAPI_KEY | Empty | Required to perform live shopping searches. |
| SERPAPI_LANGUAGE | en | en or ar for shopping searches. |
| SERPAPI_TIMEOUT_SECONDS | 20 | Provider request timeout, bounded by application configuration. |
| PRICE_CACHE_TTL_SECONDS | 43200 | Twelve-hour cache; configurable from 21600 to 86400 seconds. |
| PRICE_CACHE_PATH | cache/searches.sqlite3 | SQLite cache, relative to backend unless absolute. |
| RECOMMENDATION_MAX_SEARCHES | 8 | Maximum distinct product queries per comparison; configurable 1–20. |
| RECOMMENDATION_MIN_MATCH_SCORE | 0.85 | Best-price eligibility floor; configuration cannot lower it below 0.70. |
| RECOMMENDATION_MIN_SAVING_AMOUNT | 2 | SAR threshold for highlighting savings. |
| RECOMMENDATION_MIN_SAVING_PERCENTAGE | 5 | Percentage threshold for highlighting savings. |
| RECOMMENDATION_GOOD_SAVING_PERCENTAGE | 10 | Good Saving level. |
| RECOMMENDATION_EXCELLENT_SAVING_PERCENTAGE | 20 | Excellent Saving level. |
| NUMO_ALLOWED_ORIGINS | Empty | Optional exact additional browser origins; loopback ports remain allowed. |

Both amount and percentage thresholds must be met for a highlighted saving. Smaller positive differences can remain visible without a strong recommendation. Invalid settings fail startup with the setting name, without echoing secret values.

The model URL and tag remain code constants in services/ollama_service.py. SerpAPI credentials are independent of Ollama.

## User flows

### Scan Product

1. Open Smart Price Recommendation from Home.
2. Select Scan Product.
3. Capture/select the photo using the existing scanner and server settings.
4. Qwen identifies visible product attributes.
5. Review and correct the name, brand, model, variant, measurements, pack size, and optional current price.
6. Explicitly start the price comparison.
7. See the best eligible offer, alternative offers, match score, normalized prices, and potential savings.
8. Open a real product/deal link when desired.

A current price is optional. Without it, offers can be shown but a monetary saving is unknown. Model confidence is self-reported recognition confidence. Match score is a separate deterministic heuristic, not an estimated probability of correctness.

### Scan Invoice

1. Select Scan Invoice from the Smart Price feature or use the existing Home invoice scanner.
2. The existing invoice extraction service reads the receipt once.
3. The existing invoice review still supports corrections and Add Expense.
4. Select Compare prices to review extracted product identities and original item prices before shopping searches.
5. Compare the reviewed items; vague items and non-product lines are skipped.
6. Inspect per-item recommendations and the comparable-subset summary.
7. Save the invoice through the existing Add Expense flow.

Comparing prices does not itself save an expense or change account balances. It does not require a second image-recognition request when the invoice has already been extracted.

New invoice expense dates still default to today in Flutter and remain editable. Editing an existing expense preserves its stored date.

## Backend API

Existing endpoints remain available:

- GET /api/health
- POST /api/invoice/analyze

New endpoints:

| Endpoint | Request | Result |
| --- | --- | --- |
| GET /api/recommendations/status | No body | Configuration availability, SAR region, cache TTL, and search limit. No key values or live provider call. |
| POST /api/recommendations/product | Multipart image, optional optional_current_price | stage: review and one detected product. No shopping call. |
| POST /api/recommendations/invoice | Multipart image | stage: review, existing invoice result, and item identities. No shopping call. |
| POST /api/recommendations/product | Confirmed JSON product review | stage: results, offers, savings, and summary. No repeated recognition. |
| POST /api/recommendations/invoice | Confirmed JSON products plus invoice | stage: results for invoice items. No repeated recognition. |

The two-stage design is deliberate: paid shopping searches must happen after user review, even though both stages use the same mode endpoint.

### Recognition example

~~~powershell
curl.exe -F "image=@C:\path\to\product.jpg" -F "optional_current_price=849" http://127.0.0.1:5000/api/recommendations/product
~~~

The response has this shape:

~~~json
{
  "success": true,
  "stage": "review",
  "mode": "product",
  "products": [
    {
      "id": "item-1",
      "name": "Apple AirPods Pro 2 USB-C",
      "brand": "Apple",
      "model": "AirPods Pro 2",
      "variant": "USB-C",
      "category": "Shopping",
      "size_value": null,
      "size_unit": null,
      "pack_size": null,
      "condition": null,
      "confidence": 0.95,
      "quantity": 1,
      "unit_price": 849.0,
      "total_price": 849.0,
      "search_query": null
    }
  ],
  "warnings": []
}
~~~

All values above are illustrative. Unknown attributes remain null rather than guessed.

### Confirmed search example

Save a JSON request to a local file and send it after reviewing the identity:

~~~json
{
  "confirmed": true,
  "products": [
    {
      "id": "item-1",
      "name": "Apple AirPods Pro 2 USB-C",
      "brand": "Apple",
      "model": "AirPods Pro 2",
      "variant": "USB-C",
      "category": "Shopping",
      "quantity": 1,
      "unit_price": 849,
      "total_price": 849
    }
  ],
  "currency": "SAR"
}
~~~

~~~powershell
curl.exe -H "Content-Type: application/json" --data-binary "@review.json" http://127.0.0.1:5000/api/recommendations/product
~~~

Invoice mode additionally requires invoice containing the reviewed existing invoice JSON with currency SAR. A request can contain up to 200 product lines, but only the configured number of useful distinct queries is searched. Product mode accepts one product.

Omitting confirmed: true does not run shopping searches. Duplicate JSON keys, nonfinite values, invalid product values, oversized reviews, foreign currencies, and malformed requests are rejected.

### Results

The response includes:

- summary: original invoice total, comparable original total, recommended comparable total, potential savings, percentage, counts, currency, partial status, and savings basis.
- recommendations: one result per reviewed product, including its original price, best offer if any, accepted alternatives, savings level, skip/failure reason, query, and cache timestamp.
- warnings: partial comparisons, provider issues, unknown final costs, and heuristic match-score notice.
- searched_at: comparison timestamp; each offer search also keeps its original fetched_at timestamp.

Offers include reported store/rating/reviews, a real product URL, SAR price, match information, and quantity-normalization information when available. Missing stock, delivery, rating, or condition data is not fabricated.

A Google Shopping result may link to a Google product page rather than directly to a merchant checkout. The implementation keeps that real returned link instead of spending another API call to resolve stores.

## Recognition and invoice compatibility

services/ollama_service.py now exposes a shared generate(image_bytes, schema, system_prompt, user_prompt) transport. Its existing analyze(image_bytes) method continues to use the invoice prompt/schema. Both keep the fixed loopback Ollama URL, image validation, schema-shaped output, bounded response, disabled redirects/proxies, and existing error handling.

The existing invoice item schema gained optional identity metadata:

- brand, model, variant, search_query
- size_value and size_unit
- pack_size
- condition
- confidence

size_value describes one container/unit; pack_size describes the number of units in the retail pack; quantity describes the number of retail packs purchased. These must not be conflated.

The product recognition prompt forbids guessed capacities, models, conditions, and prices. A clean-looking box is not evidence of new condition. Generated search_query text is not trusted as a ready-to-send query; the engine rebuilds a query from reviewed product attributes.

Invoice expense categories remain the existing canonical list. Electronics can use Shopping without creating an incompatible expense category. Existing saved invoices without the extra fields still load and save. The metadata is retained when invoices are edited.

The JSON parser and model transport remain shared. There is no second invoice OCR engine, separate expense database, or new Flutter project.

## Product matching

Matching is deterministic and conservative. It uses reviewed identity fields and provider titles, not a model-generated claim that two prices are equivalent.

Hard checks reject contradictory or insufficiently supported distinguishing attributes, including brand, model/generation, storage, variant, condition, size dimension, and pack count. Accessory listings must not substitute for the main product. Important model suffixes and capacity/connector differences cannot be bypassed by a high general title similarity.

Only offers passing hard checks and the configured match-score floor can become Best Price. A heuristic score is displayed as a match score, not an AI certainty or merchant authenticity guarantee.

For consumables, different package sizes can be compared only with a matching brand/category and enough quantity information. For electronics, a different storage size is not normalized into an equivalent product.

Vague original descriptions can intentionally return no match. The remedy is to supply the missing identity during review, not to lower the price threshold until a different product qualifies.

User-reviewed identity takes precedence over stale low recognition confidence. This does not bypass title/specification matching.

The implementation does not certify merchant authenticity, warranty terms, fulfillment, or real-time stock. Confirm those on the linked listing.

## Quantity and financial calculations

Arithmetic uses Decimal in Python. Money totals and line prices round to two decimals; normalized per-unit rates use up to four. Flutter keeps confirmed expense totals as integer minor units.

For an original line:

- If quantity and unit price are known, line total can be calculated as quantity × unit price.
- If quantity and total are known, the original unit price can be calculated from them.
- If purchased quantity is unknown, invoice monetary savings are not calculated.
- Missing prices stay unknown.

For a comparable offer:

1. Determine the original quantity required, including pack count and physical size.
2. Determine the quantity in one retail offer.
3. Purchase enough whole offer packs using ceiling(required quantity / offer quantity).
4. Multiply offer price by packs required.
5. Include known unconditional delivery charges when available.
6. Clearly mark extra quantity or unknown/conditional delivery costs.
7. Calculate positive potential savings against the equivalent original line cost.

Unknown or conditional shipping is not silently declared free. Listed-price estimates may still exclude unknown shipping/tax; the UI states that they are potential savings rather than a checkout quote.

### Milk example

Original: 2 liters for SAR 8 → SAR 4/liter.

Alternative: 1 liter for SAR 4.50 → SAR 4.50/liter.

Two alternative bottles are needed to cover 2 liters, costing SAR 9 before any unknown delivery fee. This produces no saving, even though the price of one bottle is lower than SAR 8.

### Invoice summary

Only lines with a reliable priced match and a known original quantity/price enter the comparable summary.

~~~text
Comparable original total = sum(original line costs for comparable lines)

Recommended comparable total
    = sum(min(original line cost, equivalent alternative cost))

Potential savings
    = comparable original total - recommended comparable total

Saving percentage
    = potential savings / comparable original total × 100
~~~

The original invoice total is displayed separately. The summary never compares a complete tax-inclusive invoice against only a few searched item prices. Invoice-level tax, discounts, and unsearched lines are not invented or redistributed into savings. Keeping the original price where an alternative is more expensive means recommended_total describes the cost after potential swaps, not a quote to repurchase every line from one shop.

Per-line small positive differences may contribute to potential totals without being highlighted as significant. None of these numbers are recorded as actual savings.

## Quota usage and cache

The search cache is a small SQLite database independent of expense storage. It stores normalized public offers, normalized product queries, and fetch timestamps; it does not store API keys or uploaded receipt images.

- Successful queries, including successful empty results, are cached for 12 hours by default.
- Keys include normalized query, region, language, and a schema version.
- Unicode, case, and whitespace normalization reduce equivalent repeated searches.
- Duplicate invoice products reuse a query; purchasing three of one item does not cause three searches.
- Higher-value known lines are prioritized.
- Vague/fee/payment/total lines are skipped before provider calls.
- Requests have a distinct-query limit.
- Concurrent identical requests in one process share a single in-flight result.
- SQLite results survive Flask restarts.
- Failed provider calls are not persistently cached or automatically retried.
- Quota/auth failures stop unnecessary additional provider calls.
- A cache error is surfaced rather than silently spending quota without caching.

The database is bounded to 1000 cached queries by default, with pruning and a per-result size bound. In-flight deduplication is per process; multiple processes can still make simultaneous first-time misses before a result is stored.

Cached offers are not live checkout quotes. The fetched-at timestamp is preserved so users can see when a price was retrieved.

## History and expense storage

Recommendation results are stored separately under the numo_recommendations_v1 device preference, capped at 20 snapshots and 1 MiB of serialized history. Oldest snapshots are evicted to fit. An oversized single snapshot reports a save error and preserves the prior history. Corrupted stored history is preserved until explicitly cleared. Clearing all local app data also removes comparison history. Saved comparisons can be revisited without automatically issuing a new shopping query.

The existing invoice remains one expense containing its reviewed total and nested items. Recommendation records do not modify the invoice total, balance, charts, or budgets.

The records are a foundation for later historical analysis. This feature does not implement an Actual Savings ledger, purchases, order tracking, or automatic proof that the user used a deal.

## Errors and limits

Existing image/Ollama errors remain available. New errors include:

| Code | Meaning |
| --- | --- |
| review_required | Explicit review confirmation is missing. |
| invalid_products | Reviewed product fields or request shape are invalid. |
| unidentified_product | The photo did not produce a readable product identity. |
| unsupported_currency | This initial comparison supports SAR only. |
| serpapi_not_configured | Backend key is missing. |
| serpapi_auth_failed | Provider rejected the key/account access. |
| serpapi_quota_exceeded | Provider quota or rate limit was reached. |
| serpapi_timeout | Provider search exceeded the timeout. |
| serpapi_unavailable | Provider could not be reached. |
| serpapi_failed | Provider returned an invalid/unsuccessful response. |
| price_cache_unavailable | SQLite cache cannot be used safely. |
| price_search_busy | In-flight cache/search capacity is full. |
| invalid_search_query | A search query is empty or invalid. |
| server_busy | Another recognition/comparison holds the corresponding request slot. |

Partial provider failures preserve successful item comparisons and return per-item reasons/warnings. Missing original amounts are not replaced with zero-price purchases. No-results states distinguish vague identities, no returned offers, and rejected mismatches.

Image limits remain: Flutter attachment 1,500,000 bytes; backend upload 8 MiB and 20 million pixels; cleaned JPEG bounds 2400 × 2400. Recognition retains the existing 300-second Ollama read timeout. Reviews are limited to 512 KiB JSON and 200 product lines. SerpAPI responses are bounded to 2 MiB with at most 80 normalized offers.

## Test and validation commands

Backend:

~~~powershell
cd backend
.\venv\Scripts\python.exe -m unittest discover -s tests -v
~~~

Flutter, from the project root:

~~~powershell
flutter analyze
flutter test
flutter build apk --debug
~~~

The backend tests cover:

- Existing invoice extraction/validation behavior and compatibility.
- Recognition returning review without spending shopping quota.
- Confirmed requests performing comparison without repeated recognition.
- Currency, payload, CORS, shared recognition lock, and error-release behavior.
- Model/generation/storage/accessory mismatches.
- Quantity, measurement, pack, shipping, threshold, and partial-invoice calculations.
- Cache expiry, persistence, query deduplication, concurrent requests, and error handling.
- Exact mocked SerpAPI request fields, safe links, SAR validation, and credential-safe errors.
- Backend .env loading and environment precedence.

External requests are mocked in regular automated tests. Passing them does not establish real-model recognition accuracy or live SerpAPI account access.

For a real test, configure your key, restart Flask, scan a clear product, review its exact identity, and compare. Repeat the same product within the TTL to verify cached results without another provider search. Test a receipt with known quantities and inspect both the complete invoice total and the comparable subset. Verify Add Expense still saves exactly one expense and reopening restores its item metadata.

### Dependencies added

- Flutter: url_launcher 6.3.1 for user-initiated deal links.
- Python: python-dotenv (>=1.0,<2) for backend-only .env settings.
- SQLite uses Python's standard library. Requests, Pillow, image_picker, http, SharedPreferences, and the existing localization/theme remain reused.

## Implementation file map

Backend files modified:

- [app.py](../backend/app.py): application settings, service construction, recommendation route registration.
- [services/invoice_service.py](../backend/services/invoice_service.py): optional product identity metadata on existing invoice items.
- [services/ollama_service.py](../backend/services/ollama_service.py): shared vision transport and enriched invoice prompt.
- [requirements.txt](../backend/requirements.txt): python-dotenv.
- [.gitignore](../backend/.gitignore): private SQLite cache exclusion.

Backend files added:

- [config.py](../backend/config.py): .env/environment settings and bounded configuration.
- [.env.example](../backend/.env.example): credential-free configuration template.
- [routes/recommendation_routes.py](../backend/routes/recommendation_routes.py): review and comparison endpoints.
- [services/product_recognition_service.py](../backend/services/product_recognition_service.py): single-product recognition and reviewed product validation.
- [services/serpapi_service.py](../backend/services/serpapi_service.py): provider transport and normalized offers.
- [services/product_matching_service.py](../backend/services/product_matching_service.py): identity checks and heuristic match scoring.
- [services/price_comparison_service.py](../backend/services/price_comparison_service.py): equivalent-quantity arithmetic.
- [services/recommendation_service.py](../backend/services/recommendation_service.py): search prioritization, filtering, offers, and summaries.
- [cache/search_cache.py](../backend/cache/search_cache.py): persistent cache and per-process in-flight deduplication.
- Empty package initializers in backend/routes and backend/cache.
- [tests/test_recommendation_api.py](../backend/tests/test_recommendation_api.py), [tests/test_price_recommendations.py](../backend/tests/test_price_recommendations.py), and [tests/test_serpapi_service.py](../backend/tests/test_serpapi_service.py).

Flutter files modified:

- [lib/main.dart](../lib/main.dart): Smart Price navigation and existing saved-expense handoff.
- [lib/core/invoice.dart](../lib/core/invoice.dart): optional product metadata on invoice items and persistence round-trip.
- [lib/core/finance_store.dart](../lib/core/finance_store.dart): include comparison history when clearing all local data.
- [lib/l10n/app_language.dart](../lib/l10n/app_language.dart): Arabic feature strings and formatted dynamic messages.
- [lib/screens/home.dart](../lib/screens/home.dart): Smart Price feature entry.
- [lib/screens/scan.dart](../lib/screens/scan.dart): product mode using the existing photo picker, upload limits, and Flask settings.
- [lib/screens/invoice_review.dart](../lib/screens/invoice_review.dart): compare reviewed items while preserving Add Expense.
- [test/invoice_review_test.dart](../test/invoice_review_test.dart): existing review tests adapted to the added action.
- [pubspec.yaml](../pubspec.yaml) and [pubspec.lock](../pubspec.lock): deal-link dependency and resolved versions.

Flutter files added:

- [lib/core/recommendation.dart](../lib/core/recommendation.dart): review/result models, safe deal URLs, bounded local comparison history.
- [lib/services/recommendation_service.dart](../lib/services/recommendation_service.dart): Flask recognition, status, and comparison requests.
- [lib/screens/smart_prices.dart](../lib/screens/smart_prices.dart): product/invoice entry and recent comparisons.
- [lib/screens/recommendation_review.dart](../lib/screens/recommendation_review.dart): editable product identities, item selection, and explicit search confirmation.
- [lib/screens/recommendation_results.dart](../lib/screens/recommendation_results.dart): comparable totals, item offers, normalized quantities, match information, and deal buttons.
- [test/recommendation_test.dart](../test/recommendation_test.dart): 11 feature regression tests.

Flutter dependency resolution also updated generated URL-launcher registration files for Windows, Linux, macOS, iOS, and Android. These files are generated by Flutter, rather than separate application implementations.

Documentation updated:

- [README.md](../README.md): feature entry and setup link.
- [backend/README.md](../backend/README.md): new endpoint and setup overview.
- [backend/CODE_GUIDE.md](../backend/CODE_GUIDE.md): corrected current configuration, transport, and storage behavior with a link to this guide.
- This new guide: docs/SMART_PRICE_RECOMMENDATIONS.md.

## Verification completed

Verified on the local Windows development machine on 2026-09-08:

| Check | Result |
| --- | --- |
| Backend unittest discovery | 115 tests passed. |
| Flutter analyzer | No issues found. |
| Full Flutter test suite | 56 passed; one opt-in real-server invoice smoke test skipped. |
| Android debug build | Succeeded; output: build/app/outputs/flutter-apk/app-debug.apk. |
| Real local Qwen product recognition | HTTP 200, review stage, correct brand/model/USB-C identity on a synthetic printed product label. No SerpAPI request. |

The Qwen smoke input was an in-memory synthetic label, not a real store receipt or product photograph. The model guessed new condition without printed evidence. The final recognition pipeline therefore clears a model-supplied condition unless the recognized item name explicitly contains the corresponding condition marker; a regression test verifies this and preserves manually reviewed condition choices. This conservative filter does not prove that the model transcribed every word correctly.

Live SerpAPI searches were not run because no key was configured. The provider request/response handling, comparison arithmetic, failures, and caching were tested with deterministic mocked provider responses. Real merchant prices, account quota, final delivery/tax totals, and checkout availability still require the configured live test described above.

No Android emulator was connected during final verification, so the APK was compiled but not installed in this run. No running Flask process was restarted. Restart your manually managed Flask process and run the updated Flutter development app to load the feature.


