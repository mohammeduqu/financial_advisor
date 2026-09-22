# Local invoice scanning: Windows + VS Code

The existing Numo Flutter app now uses **Flutter → Flask → local Ollama → qwen3-vl:4b-instruct**.
The model analyzes the actual selected image. No demo response or paid/cloud API is used.
This is a local development service, with no public deployment or authentication yet.

## Project folder

Open this folder in VS Code (the inner folder containing pubspec.yaml):

```text
C:\Users\moham\Desktop\flutter_projects\financial_advisor\financial_advisor
```

## One-time setup

Install [Ollama for Windows](https://ollama.com/download/windows), or use PowerShell:

```powershell
winget install --id Ollama.Ollama --exact --source winget
```

Ollama and the required model have already been installed on this development PC.
Open a new terminal after installation for PATH changes, or use
`C:\Users\moham\AppData\Local\Programs\Ollama\ollama.exe` directly.

With Ollama running:

```powershell
ollama --version
ollama pull qwen3-vl:4b-instruct
ollama list
```

The required 4-bit model download is about 3.3 GB. Ollama must remain bound to
127.0.0.1:11434. Never forward this port or make Flutter call it directly.

From the Flutter project folder:

```powershell
py -3.13 -m venv backend\venv
.\backend\venv\Scripts\python.exe -m pip install -r backend\requirements.txt
flutter pub get
```

The virtual environment and dependencies have already been created here.
If Flutter is not on PATH, use `C:\Users\moham\Desktop\flutter\bin\flutter.bat`.

## Start everything

### Terminal 1 — Ollama

If Ollama is already running on 11434, use that process; do not start a second
server. To apply these settings, first quit the Ollama tray application/server.

```powershell
$env:OLLAMA_HOST = "127.0.0.1:11434"
$env:OLLAMA_NO_CLOUD = "1"
$env:OLLAMA_NUM_PARALLEL = "1"
$env:OLLAMA_CONTEXT_LENGTH = "8192"
ollama serve
```

### Terminal 2 — Flask

From the Flutter project folder:

```powershell
cd backend
.\venv\Scripts\Activate.ps1
python app.py
```

If PowerShell blocks script activation, use `.\venv\Scripts\python.exe app.py`
directly; changing execution policy is unnecessary.

Flask listens on 0.0.0.0:5000 so an emulator or a phone on the same trusted Wi-Fi
can reach it. It is a development server. Do not configure router port forwarding
or expose it to the internet. No firewall rule has been added by this feature.
For a physical phone, Windows may require a Private-network-only Python firewall
permission; keep Public-network access disabled.

Health check in another terminal:

```powershell
Invoke-RestMethod http://127.0.0.1:5000/api/health
```

This checks Flask availability, not whether Qwen is loaded.

### Terminal 3 — Flutter

Start the Android Emulator from Android Studio or VS Code, then run:

```powershell
flutter devices
flutter run
```

Android Emulator defaults to `http://10.0.2.2:5000`.
Open **Scan Invoice → server settings icon** to change the saved base URL.
For a physical phone, enter your PC's private LAN IP, for example
`http://192.168.1.100:5000`, while both devices are on the same Wi-Fi.
The model remains on the PC's loopback address regardless.

An optional build-time default is:

```powershell
flutter run --dart-define=INVOICE_API_URL=http://192.168.1.100:5000
```

A saved scanner setting overrides the build-time default.
Use debug builds for local HTTP. Android cleartext is enabled only by the debug
manifest; release builds disable this local-only analysis client.

Browser development also works using gallery uploads:

```powershell
flutter run -d web-server --web-port 8080
```

The browser defaults to 127.0.0.1:5000. Flask accepts local browser origins on
localhost, 127.0.0.1, and ::1 with any valid port. Closing/reopening a VS Code
Chrome run can change its port; this is supported automatically. Unrelated
websites remain blocked. A browser served from a LAN address needs its explicit
origin in NUMO_ALLOWED_ORIGINS; never use a wildcard.

## Test an invoice

1. Start Ollama, Flask, and the Android Emulator.
2. Run Flutter and open **Scan Invoice** on Home.
3. Take a photo or choose a JPG/PNG. Capture the entire invoice clearly.
4. Review the photo; press **Analyze Invoice**.
5. Wait for real Qwen extraction. CPU-only machines can take several minutes.
6. Check merchant, invoice number, date, currency, subtotal, tax, discount, total,
   category, and every item. Missing fields remain blank.
7. Edit values, add/remove items if necessary. Retake Photo and Analyze Again
   are available before saving.
8. Press **Add Expense**. If amounts conflict, confirm that you checked them.
9. Open Expenses and select the saved invoice to view/edit its complete item list.
10. Restart the app and check that the invoice and its items remain saved.

A receipt is saved as **one existing Entry**, with nested invoice metadata and all
items, using the existing SharedPreferences store. Only its final total affects
balance, charts, and budgets. Tax and item totals are not posted as extra expenses.
The header category controls budget allocation; item categories are preserved.
Currency must match the account. No currency conversion is performed.

No-items results can still be reviewed and saved by total. Partial/unreadable
results are flagged or rejected. The user must supply missing required values;
new invoice reviews default the date to today on the user's device, even if an older date was extracted. The date remains editable, and editing an existing expense preserves its saved date. An unknown total is never replaced with zero.

Flutter resizes camera photos to 1600px width and limits attachments to 1.5MB to
fit the existing local store. Flask accepts JPG/PNG up to 8MB and 20MP, validates
the actual content, strips metadata before model inference, and processes images
in memory. No invoice upload files are retained on the backend. The app retains
the attached receipt locally with the expense, as before.

## API

`POST /api/invoice/analyze` accepts multipart field `image`.
Success: `{"success":true,"invoice":{...},"warnings":[...]}`.
Failure: `{"success":false,"error":"Safe message","code":"stable_code"}`.

The response invoice contains merchant_name, invoice_number, date, currency,
subtotal, tax, discount, total, category, and items. Each item contains name,
quantity, unit_price, total_price, category. Unknown extracted values are null;
prices/quantities are JSON numbers. The backend maps categories to Numo's
existing list, rejects invalid/nonfinite values, and never adds tax twice.

The backend has a 300s Ollama read timeout and one inference slot.
Flutter has a 330s whole-request timeout and disables duplicate submissions.
A timed-out request can leave Ollama busy until its local generation ends;
wait before retrying. Existing invoices are never saved automatically after errors.

## Validation commands

```powershell
Push-Location backend
.\venv\Scripts\python.exe -m unittest discover -s tests -v
Pop-Location
flutter analyze
flutter test
flutter build apk --debug
```

Backend tests can also be run from backend with `python -m unittest discover -s tests -v`.
If running from project root requires backend imports, use the backend working
directory as shown in its README.

The opt-in real-model Dart smoke test requires both services and the supplied
test invoice image path:

```powershell
flutter test test/invoice_local_smoke_test.dart --dart-define=RUN_LOCAL_INVOICE_TEST=true --dart-define=INVOICE_TEST_IMAGE=C:/Users/moham/AppData/Local/Ollama/numo-test-invoice.png
```

This uses a synthetic invoice image as test input but makes a real multipart
request through the Flutter API client → Flask → Ollama, then saves and reloads
the returned items using the existing FinanceStore. Normal tests use isolated
fixtures and never access private receipts or require a running model.

## Files

Modified: lib/screens/scan.dart, lib/screens/transactions.dart,
lib/core/finance_store.dart, lib/l10n/app_language.dart, pubspec.yaml/pubspec.lock,
android/app/src/main/AndroidManifest.xml, android/app/src/debug/AndroidManifest.xml,
README.md, .gitignore.

Added: lib/core/invoice.dart, lib/services/invoice_service.dart,
lib/screens/invoice_review.dart, backend/app.py, backend/requirements.txt,
backend/services/{errors,invoice_service,ollama_service}.py,
backend/utils/json_utils.py, backend/tests/test_invoice_backend.py,
backend/README.md, backend/.gitignore, this guide, and invoice Dart tests.

## Limits

This implementation is for local development. Authentication, HTTPS, per-user
authorization, encrypted expense storage, production hosting and Linux deployment
are future work. Existing expense data continues using local preferences.
No API credential is embedded in Flutter. Arabic OCR quality still needs broader
testing against actual invoice layouts; review all extracted values.

## Verified in this workspace — 2026-09-08

- Ollama 0.33.3 installed; qwen3-vl:4b-instruct ee4b975b58c1 downloaded.
- Ollama bound only to 127.0.0.1:11434; cloud features disabled for the running process.
- Flask is running on port 5000; the browser preview on port 8080.
- 32 backend tests and 41 Flutter tests passed; Flutter analysis has no issues.
- Separate real Flutter API → Flask → Ollama → save/reload smoke test passed.
- Real Arabic and English synthetic images returned correct names, two items,
  subtotal 100, VAT 15, and total 115 SAR. Warm requests took about 4–6 seconds on this
  Windows PC's RTX 4060 GPU. This is not a CPU-only Linux performance measurement.
- Actual browser gallery upload and Arabic review screen verified. Test invoice
  is left unsaved; existing user expense data was not changed by the browser test.
- Android debug APK installed/launched on emulator-5556; no startup Flutter error.
  Physical camera capture and iOS remain device-specific checks.

The real smoke test writes to mocked preference storage only, so it does not
insert fixture expenses into your real app data.
