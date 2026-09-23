import copy
import json
import unittest
from datetime import datetime
from unittest.mock import Mock, patch

from app import create_app
from config import load_settings
from services.errors import InvoiceError
from services.financial_insights_service import (
    FinancialInsightsService, INSIGHTS_SCHEMA, MAX_MODEL_BYTES,
    prepare_expense_facts, validate_insights,
)


def expense(date="2026-09-02", amount=1500, category="Food", merchant="Cafe"):
    return {"date": date, "amount_cents": amount, "category": category, "merchant": merchant}


def body():
    return {
        "month": "2026-09", "as_of": "2026-09-23", "currency": "SAR", "language": "en",
        "expenses": [expense()], "budgets": [],
    }


def output():
    return {"summary": "Food spending is 15 SAR this month.", "insights": [{
        "title": "Plan food spending", "observation": "Recorded food spending is 15 SAR.",
        "action": "Set a food spending limit for the rest of the month.", "category": "Food",
    }]}


class FinancialInsightsTests(unittest.TestCase):
    def setUp(self):
        self.settings = load_settings({"OPENAI_API_KEY": "synthetic-test-key", "OPENAI_INSIGHTS_MODEL": "gpt-4.1-mini"})
        self.ai = Mock()
        self.ai.generate.return_value = json.dumps(output())
        self.service = FinancialInsightsService(self.settings, ai_service=self.ai)
        self.shopping = Mock()
        self.invoice_ai = Mock()
        self.app = create_app(
            ai_service=self.invoice_ai, shopping=self.shopping,
            insights_service=self.service, recommendation_config=self.settings,
        )
        self.client = self.app.test_client()

    def post(self, value=None):
        return self.client.post("/api/insights/expenses", json=body() if value is None else value)

    def test_valid_request_uses_one_text_only_ai_call_and_backend_owned_metadata(self):
        response = self.post()
        self.assertEqual(response.status_code, 200, response.json)
        self.ai.generate.assert_called_once()
        image, schema, system, prompt = self.ai.generate.call_args.args
        self.assertIsNone(image)
        self.assertEqual(schema, INSIGHTS_SCHEMA)
        self.assertIn("English", prompt)
        self.assertIn("untrusted data", system)
        self.assertIn("never guarantee savings", system)
        self.assertIn("Do not invent", system)
        self.assertEqual(response.json["summary"], output()["summary"])
        self.assertEqual(response.json["based_on"], {
            "period_start": "2026-09-01", "period_end": "2026-09-23", "expense_count": 1,
            "total_expense_cents": 1500, "comparison_expense_count": 0,
            "comparison_total_expense_cents": 0, "comparison_end": "2026-08-23",
        })
        self.assertEqual(response.json["month"], "2026-09")
        self.assertEqual(response.json["currency"], "SAR")
        self.assertEqual(datetime.fromisoformat(response.json["generated_at"].replace("Z", "+00:00")).utcoffset().total_seconds(), 0)
        self.assertEqual(response.headers["Cache-Control"], "no-store")
        self.assertEqual(self.shopping.mock_calls, [])
        self.assertEqual(self.invoice_ai.mock_calls, [])

    def test_arabic_and_user_currency_are_passed_without_inventing_income(self):
        value = body()
        value.update(language="ar", currency="AED")
        value["expenses"][0]["merchant"] = "مقهى"
        self.assertEqual(self.post(value).status_code, 200)
        prompt = self.ai.generate.call_args.args[3]
        self.assertIn("Arabic", prompt)
        self.assertIn('"currency":"AED"', prompt)
        self.assertIn("مقهى", prompt)
        self.assertNotIn('"income"', prompt)

    def test_current_comparison_excludes_later_previous_month_records(self):
        value = body()
        value["expenses"] += [
            expense("2026-09-23", 999, "Shopping"), expense("2026-08-01", 1001),
            expense("2026-08-23", 400), expense("2026-08-24", 100000),
        ]
        value["budgets"] = [{"category": "Food", "amount_cents": 1000}, {"category": "Overall", "amount_cents": 5000}]
        facts = prepare_expense_facts(value)
        self.assertEqual(facts["based_on"]["total_expense_cents"], 2499)
        self.assertEqual(facts["based_on"]["comparison_total_expense_cents"], 1401)
        self.assertEqual(facts["based_on"]["comparison_expense_count"], 2)
        self.assertEqual(facts["categories"][0]["remaining_monthly_budget_cents"], -500)
        self.assertEqual(facts["remaining_overall_monthly_budget_cents"], 2501)
        self.assertEqual(facts["highest_expense"], {"category": "Food", "amount_cents": 1500})
        self.assertEqual(facts["top_merchants"], [{"merchant": "Cafe", "expense_count": 2, "total_expense_cents": 2499}])

    def test_full_historical_month_compares_full_previous_month(self):
        value = body()
        value["month"] = "2026-02"
        value["expenses"] = [expense("2026-02-28", 10), expense("2026-01-31", 20)]
        facts = prepare_expense_facts(value)
        self.assertEqual(facts["based_on"]["period_end"], "2026-02-28")
        self.assertEqual(facts["based_on"]["comparison_end"], "2026-01-31")
        self.assertEqual(facts["based_on"]["comparison_total_expense_cents"], 20)
        self.assertEqual((facts["covered_days"], facts["comparison_covered_days"]), (28, 31))

    def test_shorter_previous_month_and_leap_year_and_year_rollover(self):
        for month, as_of, previous in (
            ("2026-03", "2026-03-31", "2026-02-28"),
            ("2024-03", "2024-03-30", "2024-02-29"),
            ("2026-01", "2026-01-15", "2025-12-15"),
        ):
            with self.subTest(month=month):
                value = body()
                value.update(month=month, as_of=as_of)
                value["expenses"] = [expense(month + "-01")]
                self.assertEqual(prepare_expense_facts(value)["based_on"]["comparison_end"], previous)

    def test_prompt_contains_aggregates_not_full_ledger(self):
        value = body()
        value["expenses"] = [expense(merchant=f"Shop {i}", amount=i + 1) for i in range(20)]
        self.assertEqual(self.post(value).status_code, 200)
        prompt = self.ai.generate.call_args.args[3]
        facts = json.loads(prompt.split("\n", 1)[1])
        self.assertNotIn("expenses", facts)
        self.assertNotIn("as_of", facts)
        self.assertEqual(len(facts["top_merchants"]), 8)
        self.assertEqual(facts["top_merchants"][0]["merchant"], "Shop 19")
        self.assertNotIn('"date"', prompt)
        self.assertNotIn('"merchant":"Shop 0"', prompt)
        self.assertEqual(self.shopping.mock_calls, [])

    def test_no_expenses_or_previous_month_only_do_not_call_ai(self):
        for expenses in ([], [expense("2026-08-01")]):
            value = body()
            value["expenses"] = expenses
            response = self.post(value)
            self.assertEqual(response.status_code, 400)
            self.assertEqual(response.json["code"], "no_expenses")
        self.ai.generate.assert_not_called()

    def test_invalid_request_fields_and_dates_do_not_call_ai(self):
        cases = [None, [], "x", {}, {**body(), "notes": "private"}]
        for field, invalid_values in {
            "month": [None, 1, "2026-13", "2026-10", "2026-9", "0001-01"],
            "as_of": [None, "2026-02-30", "2026-09-23T00:00:00", "2025-01-01"],
            "currency": [None, "sar", "SAR ", "123", "Saudi Riyal"],
            "language": [None, [], "fr", "AR"],
            "expenses": [None, {}, [expense()] * 2001],
            "budgets": [None, {}, [{"category": "Food", "amount_cents": 100}] * 2],
        }.items():
            for invalid in invalid_values:
                cases.append({**body(), field: invalid})
        for value in cases:
            with self.subTest(value=str(value)[:90]):
                response = self.client.post("/api/insights/expenses", data=json.dumps(value), content_type="application/json")
                self.assertEqual(response.status_code, 400, response.json)
                self.assertEqual(response.json["code"], "invalid_insights_request")
        self.ai.generate.assert_not_called()

    def test_invalid_expense_and_budget_values_do_not_call_ai(self):
        invalid_expenses = [None, {**expense(), "notes": "private"}, {"date": "2026-09-02"}]
        for key, invalids in {
            "date": ["2026-07-31", "2026-10-01", "2026-09-24", "bad", 1],
            "amount_cents": [True, False, 0, -1, 1.1, "100", 100_000_000_000],
            "category": ["Income", "food", None, {}],
            "merchant": [None, [], "x" * 161, "Cafe\nprivate"],
        }.items():
            invalid_expenses += [{**expense(), key: invalid} for invalid in invalids]
        for invalid in invalid_expenses:
            value = body()
            value["expenses"] = [invalid]
            self.assertEqual(self.post(value).status_code, 400)
        for invalid in (None, {}, {"category": "Other", "amount_cents": 0}, {"category": "no", "amount_cents": 10}):
            value = body()
            value["budgets"] = [invalid]
            self.assertEqual(self.post(value).status_code, 400)
        self.ai.generate.assert_not_called()

    def test_json_limits_duplicates_and_nonfinite_values(self):
        for raw, expected in (
            (b"{}" + b" " * (512 * 1024), 413),
            (b'{"month":"2026-09","month":"2026-08"}', 400),
            (b'{"amount":NaN}', 400),
            (b"invalid", 400),
        ):
            response = self.client.post("/api/insights/expenses", data=raw, content_type="application/json")
            self.assertEqual(response.status_code, expected)
            self.assertEqual(response.json["code"], "invalid_insights_request")
        self.assertEqual(self.client.post("/api/insights/expenses", data="{}").status_code, 400)
        self.ai.generate.assert_not_called()

    def test_busy_requests_do_not_call_ai_and_slot_released_after_failure(self):
        slot = self.app.extensions["financial_insights_slot"]
        slot.acquire()
        try:
            response = self.post()
            self.assertEqual(response.status_code, 503)
            self.assertEqual(response.json["code"], "server_busy")
            self.assertEqual(response.headers["Retry-After"], "5")
            self.ai.generate.assert_not_called()
        finally:
            slot.release()
        self.ai.generate.side_effect = RuntimeError("private ledger and secret")
        response = self.post()
        self.assertEqual(response.status_code, 500)
        self.assertNotIn("private", response.text)
        self.ai.generate.side_effect = None
        self.assertEqual(self.post().status_code, 200)

    def test_transport_failures_are_safe_and_no_retries(self):
        for code, status in (
            ("ai_not_configured", 503), ("ai_rate_limited", 429), ("analysis_timeout", 504),
            ("analysis_failed", 502), ("incomplete_analysis", 422), ("analysis_refused", 422),
            ("ai_model_unavailable", 503), ("ai_authentication_failed", 503),
        ):
            with self.subTest(code=code):
                self.ai.generate.reset_mock()
                self.ai.generate.side_effect = InvoiceError(code, "private secret", status)
                response = self.post()
                self.assertEqual(response.status_code, status)
                self.assertEqual(response.json["code"], code)
                self.assertNotIn("private", response.text)
                self.assertNotIn("invoice", response.text.lower())
                self.ai.generate.assert_called_once()

    def test_model_output_is_strictly_validated_and_cannot_replace_metadata(self):
        invalid = [None, "[]", "```json\n{}\n```", "x" * (MAX_MODEL_BYTES + 1), '{"summary":"a","summary":"b"}']
        for key, values in {
            "summary": ["", "  ", "x" * 601, None, "x\x00"],
            "insights": [None, [], [output()["insights"][0]] * 6, [None]],
            "based_on": [{"total_expense_cents": 0}],
        }.items():
            invalid += [json.dumps({**output(), key: value}) for value in values]
        for key, values in {
            "title": ["", "x" * 101, 1], "observation": [None, "x" * 601],
            "action": ["", []], "category": [[], "Food ", "Housing", "Overall"], "savings": [100],
        }.items():
            for value in values:
                changed = output()
                changed["insights"][0][key] = value
                invalid.append(json.dumps(changed))
        for text in invalid:
            with self.subTest(text=str(text)[:80]):
                self.ai.generate.return_value = text
                response = self.post()
                self.assertEqual(response.status_code, 502, response.json)
                self.assertEqual(response.json["code"], "invalid_insights_response")
                self.assertNotIn("Food spending", response.text)

    def test_empty_merchant_general_category_and_exact_cents_are_supported(self):
        value = body()
        value["expenses"] = [expense(amount=1, merchant=""), expense(amount=2, merchant=" ")]
        self.assertEqual(prepare_expense_facts(value)["based_on"]["total_expense_cents"], 3)
        answer = output()
        answer["insights"][0]["category"] = None
        self.assertEqual(validate_insights(json.dumps(answer), prepare_expense_facts(value)), answer)

    def test_multiline_model_body_text_is_allowed_but_other_controls_are_rejected(self):
        answer = output()
        answer["summary"] = "Food spending is 15 SAR.\nReview the food budget."
        answer["insights"][0]["observation"] = "Recorded expenses:\r\nFood spending is 15 SAR."
        answer["insights"][0]["action"] = "Plan meals.\n\tCompare store prices before shopping."
        self.ai.generate.return_value = json.dumps(answer)
        response = self.post()
        self.assertEqual(response.status_code, 200, response.json)
        self.assertEqual(response.json["summary"], answer["summary"])
        self.assertEqual(response.json["insights"], answer["insights"])
        for field in ("summary", "observation", "action", "title"):
            invalid = copy.deepcopy(answer)
            target = invalid if field == "summary" else invalid["insights"][0]
            target[field] += "\x00"
            self.ai.generate.return_value = json.dumps(invalid)
            self.assertEqual(self.post().json["code"], "invalid_insights_response")
        for control in ("\n", "\r", "\t"):
            invalid = copy.deepcopy(answer)
            invalid["insights"][0]["title"] += control
            self.ai.generate.return_value = json.dumps(invalid)
            self.assertEqual(self.post().json["code"], "invalid_insights_response")
            value = body()
            value["expenses"][0]["merchant"] += control
            self.assertEqual(self.post(value).json["code"], "invalid_insights_request")

    def test_insights_model_defaults_and_override_do_not_change_invoice_model(self):
        settings = load_settings({"OPENAI_MODEL": "gpt-4.1", "OPENAI_INSIGHTS_MODEL": ""})
        self.assertEqual(settings["OPENAI_INSIGHTS_MODEL"], "gpt-4.1")
        settings = load_settings({"OPENAI_MODEL": "gpt-4.1", "OPENAI_INSIGHTS_MODEL": "gpt-4.1-mini"})
        before = copy.deepcopy(settings)
        service = FinancialInsightsService(settings)
        self.assertEqual(settings, before)
        self.assertEqual(service.ai.model, "gpt-4.1-mini")
        self.assertEqual(service.ai.api_key, settings["OPENAI_API_KEY"])
        self.assertEqual(service.ai.timeout_seconds, settings["OPENAI_TIMEOUT_SECONDS"])
        self.assertLessEqual(service.ai.max_output_tokens, 4096)
        for model in ("bad model", "bad\nmodel", "x" * 201):
            with self.assertRaisesRegex(ValueError, "OPENAI_INSIGHTS_MODEL"):
                load_settings({"OPENAI_INSIGHTS_MODEL": model})

    def test_real_transport_payload_is_text_only_strict_no_store_and_one_call(self):
        service = FinancialInsightsService(self.settings)
        from tests.test_openai_service import completed
        with patch("services.openai_service.requests.Session") as session_type:
            session = session_type.return_value.__enter__.return_value
            response = session.post.return_value.__enter__.return_value
            response.status_code = 200
            response.iter_content.return_value = [json.dumps(completed(json.dumps(output()))).encode()]
            service.generate(prepare_expense_facts(body()))
            session.post.assert_called_once()
            kwargs = session.post.call_args.kwargs
            payload = kwargs["json"]
            self.assertFalse(payload["store"])
            self.assertFalse(kwargs["allow_redirects"])
            self.assertFalse(session.trust_env)
            self.assertTrue(payload["text"]["format"]["strict"])
            self.assertEqual(payload["model"], "gpt-4.1-mini")
            self.assertEqual(len(payload["input"][1]["content"]), 1)
            self.assertEqual(payload["input"][1]["content"][0]["type"], "input_text")


if __name__ == "__main__":
    unittest.main()
