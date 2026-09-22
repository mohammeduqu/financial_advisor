# Tadbeer — local Flutter MVP

A premium dark-mode personal-finance app with deep navy surfaces, restrained emerald and gold accents, thin borders, refined charts, and Home / Expenses / Analysis / Investments / Profile navigation.

## Smart Price Recommendation

Compare a product photo or reviewed invoice items with Saudi shopping offers. Recognition reuses local Qwen; searches, matching, quantities and caching run in Flask. See [setup and implementation guide](docs/SMART_PRICE_RECOMMENDATIONS.md). Potential savings stay separate from expenses.

## Local invoice scanning

See [Windows setup and testing](docs/LOCAL_INVOICES.md) for the real Flutter → Flask → Ollama invoice feature, configurable local URLs, editable item review, and existing expense storage integration.

New scanned invoices default to today's device-local date, which remains editable. Existing expenses keep their saved date when edited. After **Add Expense** succeeds, Expenses opens in the selected date's month, clears search/type/category filters, and places that invoice first. The reviewed date and item details are preserved.

## Run

Use Flutter 3.29.3 / Dart 3.7 or a compatible newer stable SDK.

```sh
flutter pub get
flutter run
```

For a browser preview: `flutter run -d web-server --web-port 8080`.
Start with an empty workspace or choose **Explore with sample data**. Sample entries are created in the current month and reconcile to income 12,000, expenses 7,750, and cash flow 4,250. Currency is selected once during onboarding.

## Language

The app follows the primary device language automatically: Arabic (including regional variants such as ar-SA and ar-EG) uses Arabic text and right-to-left layout; other languages use English. Choose Automatic, English, or العربية using Language in Profile or on the welcome screen. Manual choices take effect immediately and are saved locally. Automatic follows system-language changes while the app is running. In the web preview, the browser's preferred language is used.

Dates and Material controls are localized. Arabic and Persian digit input is accepted for amounts, while saved amounts and category identifiers remain unchanged. The invoice scanner uses the local Qwen vision model for Arabic/English extraction; review all fields because accuracy varies by invoice layout.

## Implemented

- Onboarding, persistent local workspace, month navigation and data clearing.
- Dashboard with a recorded-balance overview, spending/highest-expense/daily-average/savings summary cards, cumulative spending line chart, expense bars, category-budget donut, invoice scanning, local notification alerts, illustrative investment previews, and recorded cash flow, income, expenses, savings rate, category spending, equivalent-period month comparisons and deterministic insight text.
- Add/edit/delete income and expenses, exact integer-minor-unit money arithmetic, validation, search and category/type filters.
- Local invoice image capture/selection, preview, real Flask/Ollama extraction, editable header and item review, duplicate warnings, and persistent invoice details attached to the existing expense record.
- Monthly overall and category budgets derived from the same transactions as the dashboard. 80%/100% in-app status warnings. Category budgets do not double-count the overall budget. Copy missing budgets from the previous month without replacing existing limits, or remove an individual limit.
- Create and edit savings goals, optional deadlines, contribution history, dated contribution entry and correction, illustrative monthly targets and goal deletion. Contributions do not change expenses.
- Opportunities: fictional examples, asset/risk filters, search, persisted watchlist, detail views and side-by-side comparison of two examples.
- Loading, error and empty states. Save failures are surfaced with retry. Corrupt stored data is preserved for explicit recovery.

## Local-first scope and limits

The founder selected a local app first. A local Flask invoice analysis backend is now included; expense storage remains on the device. This is a functional local development MVP, not the complete production release described in the parent MVP.md.

- There is no authentication, cloud synchronization, bank connection, live market feed, trading or money movement.
- SharedPreferences stores JSON and compressed receipt images locally **without encryption**. Use sample data for evaluation. Migrate to encrypted transactional storage before a sensitive-data pilot; uninstall/clear-app-data can lose records. Preference writes are serialized, but this is not a production financial database.
- Invoice analysis runs through the local Flask service and Qwen3-VL. Camera images are resized and capped at 1.5 MB. Header and item data require review and are saved as one expense without double-counting tax.
- Insights are deterministic and explain their calculation; the vision model is used for receipt and product identification. Investment expected return and confidence are explicitly unavailable, not fabricated forecasts.
- Opportunity names, minima and product characteristics are explicitly fictional. No real investment offers or suitability decisions are made.
- Receipt capture on physical Android/iOS devices and iOS builds require device/Mac validation. iOS minimum is 15.5. Camera/photo descriptions and the Podfile are configured.
- Android still has the starter app identifier and debug release signing. Set the final app ID and release signing before store submission.

## Structure

- `lib/core/finance_store.dart`: models, exact amounts, persistence, calculations.
- `lib/core/receipt.dart`: conservative extraction and category suggestion.
- `lib/widgets/design.dart`: shared visual language and UI helpers.
- `lib/screens/`: dashboard, transactions, scanning, planning and opportunities.
- `lib/main.dart`: bootstrap, onboarding, navigation and settings.

## Validation

```sh
flutter analyze
flutter test
flutter build web
```

Tests cover strict monetary parsing, budget copying across year boundaries, goal and contribution editing, invalid saved amounts, month boundaries, mutations, idempotent saves, receipt extraction, goals/cash-flow separation, persistence, corrupt data handling, onboarding and mobile navigation.

## Next backend milestone

Choose a backend, then add verified accounts, ownership authorization, encrypted receipt storage, sync/conflict rules, account deletion, backups, and production logging/retention. Add licensed market data only after defining the supported investment scope. Keep credentials out of Flutter source.

Latest invoice verification (2026-09-08): 41 Flutter tests passed, 32 backend tests passed, and the opt-in real Flutter client → Flask → Ollama → expense-store smoke test passed. Flutter analysis is clean. The Android debug APK built, installed, and launched on Numo_API_36. The browser preview successfully uploaded an Arabic test receipt and displayed the real editable extraction. Clean synthetic Arabic and English invoices produced correct items and totals. Kotlin compilation remains in-process. No physical-device camera test or iOS build was performed on this Windows machine.






## Android emulator troubleshooting

Use **Numo_API_36** in the device selector. The original Medium_Phone_API_36 emulator was unable to install the app because its 6 GB internal disk was 96% full (`Requested internal only, but not enough space`). Numo_API_36 has a 12 GB data partition; the original emulator and its installed apps were preserved. The debug APK was installed and launched successfully on Numo_API_36.

Keep `supportedLocales` and `GlobalMaterialLocalizations.delegates` in `TadbeerApp`; removing them leaves the localization import unused and disables Arabic Material controls. Manual language UI lives in `lib/widgets/language_selector.dart`.

## App logo

Tadbeer uses the approved filled mint-and-gold wallet logo with a blue-to-teal background on the welcome screen, dashboard, Android launcher, iOS app icons and web/PWA icons. See [logo assets and regeneration](docs/BRANDING.md).
