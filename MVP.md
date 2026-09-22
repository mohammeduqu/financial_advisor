# MVP Product Scope — AI Personal Finance & Investment Assistant

**Status:** Proposed scope for founder review  
**Version:** 1.0  
**Date:** 2026-09-06  
**Platform:** Flutter mobile app for iOS and Android  
**Working name:** Financial Advisor (final brand TBD)

## 1. Product vision

Help people turn everyday spending into practical financial decisions by connecting expenses, income, budgeting, saving, and investment understanding in one application.

The MVP proves one core promise: **Scan a receipt, understand your spending, and identify a realistic next step toward a savings goal.**

The full vision includes personalized investment discovery and portfolio analysis. These require a separate phase; the first release establishes reliable personal finance data and validates repeat usage.

## 2. Target users and problem

**Initial audience hypothesis:** Individuals with regular income who want to manage spending and save consistently but find manual expense tracking tedious. Validate this audience through pilot interviews before expanding to multiple segments.

Users need to:

- Capture everyday expenses with less typing.
- See where their recorded money goes each month.
- Set budgets and understand remaining amounts.
- Track progress toward a concrete savings goal.
- Understand basic investment concepts before researching products.

**Positioning:** A receipt-first personal finance companion with clear, evidence-backed explanations.

## 3. Working assumptions and decisions

These are planning assumptions, not confirmed business requirements:

| Topic | MVP assumption |
|---|---|
| Launch region | One country; founder selects it before pilot recruitment |
| Currency | One user-selected currency per account; no conversion or mixed-currency totals |
| Language | One launch language; select before UI and OCR evaluation |
| Data entry | Receipt capture plus manual expenses and income; no bank connection |
| Storage | Authenticated cloud storage and sync; online saving for the pilot |
| Pricing | Free closed pilot; paid plans are a later validation question |
| Investment scope | Educational asset-class discovery; no personalized security ranking or trading |
| Delivery | One Flutter codebase; validate on physical iOS and Android devices |

Currency changes after transactions exist require a later migration design; disable them in the MVP. If Arabic is selected, RTL layouts and representative Arabic receipts become launch acceptance requirements.

## 4. Release scope

### 4.1 Account and onboarding — must have

- Email authentication using a managed identity provider, including verification and password recovery.
- Select currency and complete a short onboarding flow.
- Explain that the dashboard represents recorded entries and may omit spending or income.
- Request camera access when scanning; explain receipt processing before sending images to an external processor.
- Offer an empty-state action to scan a receipt or add an entry.

**Acceptance:** A new user can create an account, return through sign-in, recover access, and reach the dashboard. One account cannot access another account's records or receipt images.

### 4.2 Receipt scanning and review — must have

- Capture a photo or select an existing image.
- Extract merchant, transaction date, total, currency when present, and a suggested category.
- Treat VAT and discounts as optional metadata; save the receipt total as the expense amount.
- Present the source image beside editable extracted fields.
- Require confirmation before creating an expense.
- Flag uncertain or missing fields and reject invalid amounts or dates.
- Warn about potential duplicates using image fingerprinting and merchant/date/amount matches; allow legitimate repeated purchases.
- Provide retry and manual entry when extraction fails.

**Acceptance:** A supported receipt can become one confirmed expense with no mandatory retyping when extraction is correct. Failed extraction creates no transaction. Retrying a save creates no duplicate. VAT is not added again to a tax-inclusive total.

**Deferred:** Item-level extraction, quantities, unit prices, split-category receipts, multipage invoices, handwritten receipts, and guaranteed support for every merchant format.

### 4.3 Transactions and categories — must have

- Add, edit, and delete expenses and income manually.
- Store amount, date, category, optional merchant, note, and receipt reference.
- Search and filter by date, category, and transaction type.
- Use fixed expense categories: food, transportation, housing, utilities, shopping, healthcare, entertainment, education, subscriptions, travel, and other.
- Suggest categories using merchant rules or classification; user corrections always take precedence.

**Acceptance:** Confirmed changes update all dependent totals. Amounts use integer minor units or fixed-precision decimals, never binary floating-point arithmetic. Unsupported receipt currencies require correction or cancellation before saving.

### 4.4 Dashboard and budgeting — must have

- Show monthly recorded income, expenses, net cash flow, and savings rate.
- Show spending by category and comparison with the previous month.
- Support one overall monthly expense budget and optional category budgets.
- Display amount used, amount remaining, and in-app alerts at 80% and 100% of a budget.
- Identify a partial current month and compare month-to-date with the equivalent prior-month period.

**Calculation rules:** Net cash flow = recorded income minus recorded expenses. Savings rate = net cash flow / recorded income, shown only when income is positive. Category budgets overlap the overall budget; do not add both together. Calendar months follow the user's stored timezone.

**Acceptance:** Dashboard values reconcile exactly with confirmed entries. Zero income shows an unavailable savings rate. Budget alerts are not repeated on every app opening. Net cash flow is never labeled as a verified bank balance.

### 4.5 Savings goals — must have

- Create a goal with a name, target amount, optional target date, and manually recorded contributions.
- Show progress and the remaining amount.
- When a future deadline exists, calculate an illustrative monthly contribution needed to reach it.
- Allow contributions to be corrected or removed.

**Acceptance:** Contributions update goal progress without creating expenses or changing cash flow. Explain that progress is user-recorded and the app does not hold or move money. Past deadlines prompt the user to update the goal.

### 4.6 Explainable financial insights — must have

Provide a small set of useful insights:

1. Highest-spending category this month.
2. Material category spending changes versus the equivalent previous-month period.
3. Budget usage and remaining allowance.
4. An illustrative saving scenario, such as the effect of reducing a selected category by 10%.

Compute amounts and comparisons in application services. AI may turn these verified facts into concise explanations; it must not invent transactions, change numbers, or perform authoritative financial calculations.

**Acceptance:** Each insight identifies its time period and supporting amounts. Sparse data produces an insufficient-data state. When AI is unavailable or output validation fails, a deterministic text template is shown. Receipt text is treated as data, never as instructions to the AI.

### 4.7 Investment learning — limited MVP feature

- Provide curated educational cards for stocks, ETFs, funds, sukuk, commodities, and real estate investment products.
- Explain general risk, liquidity, time horizon, diversification, and uncertainty in plain language.
- Let users bookmark topics for further learning.
- Label content as education and display its review date and source references.

**Acceptance:** No live quotes, projected personal returns, buy/sell prompts, suitability scores, or personalized product recommendations appear in the MVP. Educational content receives subject-matter review before launch.

This is a deliberate reduction from the full investment discovery vision, not a claim that the MVP delivers that complete capability.

## 5. Explicitly out of scope

- Banking integrations, automatic account aggregation, and payments.
- Brokerage connections, order execution, and custody.
- Live market feeds, specific investment opportunity matching, and security recommendations.
- Portfolio performance, allocation, and concentration analysis.
- Automatic recurring subscription detection and unusual transaction detection.
- Advanced forecasting, debt optimization, and a composite financial health score.
- Open-ended AI chat, push notifications, family accounts, and custom categories.
- Web/desktop releases, offline write synchronization, and multiple currencies.

## 6. Main user flows and screens

**First value:** Register → select currency → scan receipt → review/correct → confirm → see expense on dashboard.

**Budget habit:** Open monthly summary → set overall/category budget → record expenses → review remaining amounts and alerts.

**Savings habit:** Create goal → record contribution → review progress and illustrative monthly target.

**Learning:** Open investment learning → read asset-class explanation → bookmark topic.

**Navigation:** Home, Transactions, Plan, Learn, and Settings, with a prominent Scan action. Plan contains Budgets and Goals. Supporting screens cover authentication, receipt capture/review, transaction editing, and goal editing.

## 7. Proposed technical foundation

Choose providers after comparing regional availability, data processing terms, supported receipt languages, and costs.

- **Client:** Flutter with feature-based modules and a single consistent state-management approach.
- **Backend:** Managed authentication, relational database, private object storage, and server-side endpoints for OCR/AI.
- **Receipt pipeline:** Upload → validate image → extract structured fields → validate schema → return draft → user confirms → save transaction.
- **Calculation layer:** Shared, deterministic services for totals, comparisons, budgets, and goal calculations.
- **Reliability:** Idempotent confirmation requests, bounded processor retries, recoverable error states, and visible loading states.
- **Observability:** Capture error codes, processing latency, and provider usage without receipt content or transaction descriptions in logs.

Provider secrets stay on the server. OCR and AI requests use the minimum required data. Rate limits and per-account processing quotas control abuse and pilot costs.

## 8. Minimum data model

| Entity | Essential fields |
|---|---|
| User profile | user_id, currency, timezone, language, created_at |
| Transaction | id, user_id, type, amount_minor, currency, date, category_id, merchant, note, receipt_id, source |
| Receipt | id, user_id, private_storage_key, fingerprint, processing_status, extracted_draft, uncertainty_flags |
| Category | id, name, transaction_type |
| Budget | id, user_id, month, category_id (optional), limit_minor |
| Goal | id, user_id, name, target_minor, target_date (optional) |
| Goal contribution | id, goal_id, user_id, amount_minor, date |
| Insight | id, user_id, period, type, supporting_metrics, rendered_text |
| Learning bookmark | user_id, content_id |

Add timestamps to mutable records. Recompute or invalidate insights when relevant transactions change. Enforce ownership checks on every read and mutation, including goals, contributions, and receipt access.

## 9. Privacy, security, and release preparation

- Encrypt transport and stored financial data using supported platform services.
- Use private receipt storage and short-lived authorized access links.
- Offer account deletion covering database records and stored receipts; document backup expiry behavior.
- Define receipt retention and processor retention before the pilot.
- Provide a privacy notice describing data collection, processors, and deletion.
- Keep financial data out of analytics events and crash-report payloads.
- Validate backup and restore procedures before inviting users.
- Confirm launch-country requirements and permitted investment feature scope with qualified local advisers before public release; this document does not determine legal obligations.

## 10. Validation and pilot success criteria

These are proposed targets, not measured performance or industry benchmarks. Refine after the first usability sessions.

| Metric | Proposed pilot target | Definition |
|---|---|---|
| Activation | At least 60% | New pilot users confirming one expense within 24 hours |
| Capture speed | Median under 60 seconds | Time from selecting/capturing an image to confirmed save |
| OCR total accuracy | At least 90% | Supported test receipts with an exactly correct extracted total before edits |
| Weekly habit | At least 40% | Activated users recording expenses on 3 distinct days in week two |
| Budget adoption | At least 30% | Activated users creating a monthly budget in their first week |
| Stability | At least 99% | Crash-free sessions during the pilot |

Evaluate OCR on at least 100 representative receipts from the selected language, currency, and common merchants. Record date and merchant accuracy separately from total accuracy. Recruit a proposed 20–30 pilot users and interview users who stop recording expenses.

## 11. Build sequence and exit gates

1. **Scope and design:** Select region, language, currency defaults, providers, and launch audience. Prototype receipt review and dashboard. Exit when representative users can understand and complete the main flow.
2. **Core finance:** Build authentication, manual entries, categories, and dashboard calculations. Exit when totals reconcile and account isolation passes verification.
3. **Receipt capture:** Add image handling, OCR, editable review, duplicate handling, and failure recovery. Exit when the representative receipt benchmark and reliable confirmation flow pass.
4. **Planning and insight:** Add budgets, goals, deterministic insights, optional AI wording, and reviewed learning content. Exit when calculations and explanations agree across normal and edge cases.
5. **Pilot readiness:** Verify deletion, backups, accessibility, processor failures, and physical-device behavior; instrument pilot metrics and release to the closed cohort.

Estimate dates after confirming team capacity and evaluating OCR providers. The sequence is a delivery plan, not a fixed-time commitment.

## 12. Definition of done

- All must-have acceptance criteria pass on the supported iOS and Android versions.
- End-to-end flow works: sign up → scan → correct → save → dashboard → budget → goal.
- Tests cover financial arithmetic, month boundaries, zero income, duplicate saves, edits/deletions, and access isolation.
- OCR timeouts and AI failures leave the app usable through manual entry and template insights.
- Loading, empty, error, and insufficient-data states are implemented.
- Text scaling, screen-reader labels, and contrast are checked on primary flows.
- Account deletion and private receipt access are verified.
- Pilot metrics and support/feedback channels are ready.
- No unresolved defects compromise financial totals, account access, or confirmed transaction persistence.

## 13. Roadmap after validation

**Phase 2 — Better money management:** Recurring expense detection, anomaly explanations, richer comparisons, export, push alerts, and simple forecasts with stated assumptions.

**Phase 3 — Investment discovery:** Select supported markets, evaluate data licensing and freshness, confirm the permitted advisory model, and design risk/horizon/liquidity profiling before introducing product comparisons and personalized matching.

**Phase 4 — Connected financial platform:** Bank connections, portfolio tracking, diversification analysis, multi-device/offline improvements, and a broader AI assistant.

Prioritize expansion using pilot retention, user interviews, OCR correction rates, and processing cost per active user. The MVP succeeds when users repeatedly record expenses and use that information to plan their money.

## Implementation update — 2026-09-06

The founder approved building a local Flutter app before selecting a backend and requested Opportunities in place of Learn. The local implementation is in `financial_advisor/` with run instructions and limitations in its README.

The current slice includes local onboarding/storage, transaction management, receipt capture and review, shared dashboard/budget calculations, month comparisons, savings goals and fictional opportunity discovery/comparison/watchlists. The visual direction is navy and blue with clean sans-serif typography.

Cloud authentication/sync, production encrypted storage, live product data and personalized recommendations remain pending. This update narrows the implementation milestone; it does not claim that all original public-release requirements are complete.
