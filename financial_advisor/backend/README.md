# Local invoice analysis backend

Smart Price Recommendation adds reviewed product/invoice shopping comparisons. See [feature setup, endpoints, matching, cache and file map](../docs/SMART_PRICE_RECOMMENDATIONS.md). Configure SERPAPI_KEY only in backend/.env; normal invoice scanning still works without a shopping key.

For a complete walkthrough of every backend module, the API, configuration, tests, and troubleshooting, see [Flask backend code guide](CODE_GUIDE.md).

This Flask service sends real invoice images only to the local Ollama API at
`http://127.0.0.1:11434/api/chat`, using `qwen3-vl:4b-instruct` with image input
and a JSON schema. Flutter communicates with Flask, never directly with Ollama.

## Windows setup

From the Flutter project folder:

```powershell
ollama --version
ollama pull qwen3-vl:4b-instruct
ollama list
cd backend
py -3 -m venv venv
.\venv\Scripts\python.exe -m pip install -r requirements.txt
```

Terminal 1: run `ollama serve` if the Ollama desktop app is not already serving.
Keep Ollama bound to `127.0.0.1:11434`; do not set `OLLAMA_HOST` to `0.0.0.0`.

Terminal 2, from `backend`:

```powershell
.\venv\Scripts\Activate.ps1
python app.py
```

If PowerShell blocks activation, use `.\venv\Scripts\python.exe app.py` directly.
Flask listens on port 5000 on local network interfaces so an Android emulator or a
phone on the same trusted Wi-Fi can reach it. Do not forward port 5000 on your
router or expose this development server publicly. It has no account authentication.

- Android emulator Flask URL: `http://10.0.2.2:5000`
- Flutter web/desktop on the PC: `http://127.0.0.1:5000`
- Physical phone: `http://<PC-LAN-IP>:5000`

## API

`POST /api/invoice/analyze` accepts `multipart/form-data` with one `image` file.
JPEG and PNG are accepted after actual image decoding, up to 8 MiB and 20 million
pixels. Images are re-encoded in memory to remove metadata before inference.
Only one extraction runs at once. Another request receives 503 `server_busy`.
Ollama has a 5-second connection timeout and a 300-second read timeout; initial
model loading and CPU inference can take time.

```powershell
curl.exe -F "image=@C:\path\to\invoice.jpg" http://127.0.0.1:5000/api/invoice/analyze
```

Success returns `success`, `invoice`, and a `warnings` list. The invoice contains
`merchant_name`, `invoice_number`, `date`, `currency`, `subtotal`, `tax`, `discount`,
`total`, `category`, and `items`. Each item contains `name`, `quantity`, `unit_price`,
`total_price`, and `category`. Unknown values stay null. Amounts are numeric.
Dates normalize to Gregorian ISO dates only when unambiguous. Header tax/discount
and line item prices are preserved separately; no value is added to the total.

Warning codes: `no_items`, `partial_data`, `totals_mismatch`,
`items_total_mismatch`, `category_mapped`. These require review, not automatic
changes. A structurally valid response is not proof that OCR amounts are correct.

Failures return `success: false`, a safe `error` message, and a stable `code`:

| HTTP | Codes |
| --- | --- |
| 400 | `missing_image`, `invalid_image`, `invalid_request` |
| 403 | `forbidden_origin` |
| 413 | `image_too_large` |
| 415 | `unsupported_image` |
| 422 | `unreadable_invoice`, `invalid_invoice_json`, `incomplete_analysis` |
| 502 | `analysis_failed` |
| 503 | `server_busy`, `ollama_unavailable`, `model_not_installed` |
| 504 | `analysis_timeout` |
| 500 | `internal_error` |

`GET /api/health` checks Flask only; it does not claim the model is ready.

Local Flutter browser origins (localhost, 127.0.0.1, or ::1) are allowed on any valid port, including the new port VS Code chooses when Chrome restarts. Unrelated websites remain blocked. For a browser served from an explicit LAN address, set its exact origin before starting:

```powershell
$env:NUMO_ALLOWED_ORIGINS = 'http://192.168.1.163:8080'
python app.py
```

Native Flutter requests do not require an Origin header. Uploaded image content,
extracted text, and model error bodies are never logged. The Flask access log
contains only request paths/statuses. No cloud API or credential is used.

## Tests

```powershell
.\venv\Scripts\python.exe -m unittest discover -s tests -v
```

Tests use mock Ollama responses to verify validation, image limits, error handling,
and the exact outbound vision request. They do not claim real-model accuracy.
Use the curl command with a readable receipt to test the real installed model.

API and normalization are separated from the Flask route so authentication, HTTPS,
and a production server can be added later without changing the Flutter contract.
See the project setup guide for the complete camera → review → expense flow.
