import 'dart:convert';

import 'finance_store.dart';

const financialInsightsMaxExpenses = 2000;
const financialInsightsMaxRequestBytes = 512 * 1024;

class FinancialInsightsException implements Exception {
  final String code;
  const FinancialInsightsException(this.code);

  String get message => switch (code) {
    'no_expenses' =>
      'Add an expense for this month before requesting insights.',
    'insights_too_large' =>
      'There are too many expenses to analyze in one request. Choose another month.',
    'invalid_insights_request' =>
      'Some expense details could not be analyzed. Check your expenses and try again.',
    'invalid_insights_response' || 'invalid_response' =>
      'AI returned an incomplete insight. Please try again.',
    'ai_not_configured' =>
      'AI insights have not been set up yet. Please contact support.',
    'ai_authentication_failed' || 'ai_configuration_error' || 'invalid_url' =>
      'AI insights are not configured correctly. Please contact support.',
    'ai_rate_limited' =>
      'AI insights have reached their usage limit. Please try again later.',
    'ai_model_unavailable' =>
      'The selected AI model is unavailable. Please contact support.',
    'server_busy' => 'AI insights are busy. Please try again shortly.',
    'insights_timeout' ||
    'analysis_timeout' => 'AI insights took too long. Please try again later.',
    'connection_error' =>
      'Could not connect to the insights service. Check your connection and try again.',
    'wrong_server_url' =>
      'The insights service returned an unexpected response. Please try again later.',
    'analysis_refused' =>
      'These expenses could not be analyzed. Please try again later.',
    'cancelled' => 'The insights request was cancelled.',
    _ => 'AI insights are temporarily unavailable. Please try again later.',
  };

  @override
  String toString() => message;
}

DateTime _day(DateTime value) => DateTime(value.year, value.month, value.day);

String _dateText(DateTime value) =>
    '${monthKey(value)}-${value.day.toString().padLeft(2, '0')}';

/// A minimal, immutable snapshot of posted expenses, without receipt or account data.
class FinancialInsightsRequest {
  final String month, asOf, currency, language;
  final DateTime periodStart, periodEnd, comparisonEnd;
  final List<Map<String, Object>> expenses, budgets;
  final int expenseCount, totalExpenseCents;
  final int comparisonExpenseCount, comparisonTotalExpenseCents;
  final bool isFutureMonth;

  FinancialInsightsRequest._({
    required this.month,
    required this.asOf,
    required this.currency,
    required this.language,
    required this.periodStart,
    required this.periodEnd,
    required this.comparisonEnd,
    required this.expenses,
    required this.budgets,
    required this.expenseCount,
    required this.totalExpenseCents,
    required this.comparisonExpenseCount,
    required this.comparisonTotalExpenseCents,
    required this.isFutureMonth,
  });

  factory FinancialInsightsRequest.fromStore(
    FinanceStore store,
    DateTime selectedMonth, {
    required String language,
    DateTime? now,
  }) {
    final today = _day(now ?? DateTime.now());
    final start = DateTime(selectedMonth.year, selectedMonth.month);
    final previous = DateTime(start.year, start.month - 1);
    final lastDay = DateTime(start.year, start.month + 1, 0);
    final previousLastDay = DateTime(start.year, start.month, 0);
    final future = start.isAfter(today);
    final current = monthKey(start) == monthKey(today);
    final end = current ? today : lastDay;
    final comparisonEnd =
        current
            ? DateTime(
              previous.year,
              previous.month,
              today.day.clamp(1, previousLastDay.day),
            )
            : previousLastDay;
    if (start.year < 2000 ||
        start.year > 9999 ||
        !['en', 'ar'].contains(language) ||
        !RegExp(r'^[A-Z]{3}$').hasMatch(store.currency)) {
      throw const FinancialInsightsException('invalid_insights_request');
    }

    final rows = <Map<String, Object>>[];
    var expenseCount = 0, total = 0, comparisonCount = 0, comparisonTotal = 0;
    if (!future) {
      // Recurring schedules are deliberately excluded until they post to entries.
      for (final entry in store.entries) {
        final date = _day(entry.date);
        if (entry.income ||
            date.isBefore(previous) ||
            date.isAfter(end) ||
            date.isAfter(today)) {
          continue;
        }
        if (entry.cents <= 0 ||
            entry.cents >= 100000000000 ||
            !categories.contains(entry.category) ||
            entry.merchant.trim().isEmpty) {
          throw const FinancialInsightsException('invalid_insights_request');
        }
        rows.add(
          Map<String, Object>.unmodifiable({
            'date': _dateText(date),
            'category': entry.category,
            'amount_cents': entry.cents,
            'merchant': String.fromCharCodes(
              entry.merchant
                  .trim()
                  .replaceAll(RegExp(r'\s+'), ' ')
                  .runes
                  .take(160),
            ),
          }),
        );
        if (rows.length > financialInsightsMaxExpenses) {
          throw const FinancialInsightsException('insights_too_large');
        }
        if (!date.isBefore(start)) {
          expenseCount++;
          total += entry.cents;
        } else if (!date.isAfter(comparisonEnd)) {
          comparisonCount++;
          comparisonTotal += entry.cents;
        }
      }
    }
    // A changed list order alone does not invalidate an otherwise identical result.
    rows.sort((a, b) => jsonEncode(a).compareTo(jsonEncode(b)));
    final budgetRows = <Map<String, Object>>[];
    final monthBudgets = store.budgets[monthKey(start)] ?? const {};
    for (final category in ['Overall', ...categories]) {
      final amount = monthBudgets[category] ?? 0;
      if (amount <= 0) continue;
      if (amount >= 100000000000) {
        throw const FinancialInsightsException('invalid_insights_request');
      }
      budgetRows.add(
        Map<String, Object>.unmodifiable({
          'category': category,
          'amount_cents': amount,
        }),
      );
    }
    final snapshot = FinancialInsightsRequest._(
      month: monthKey(start),
      asOf: _dateText(today),
      currency: store.currency,
      language: language,
      periodStart: start,
      periodEnd: end,
      comparisonEnd: comparisonEnd,
      expenses: List.unmodifiable(rows),
      budgets: List.unmodifiable(budgetRows),
      expenseCount: expenseCount,
      totalExpenseCents: total,
      comparisonExpenseCount: comparisonCount,
      comparisonTotalExpenseCents: comparisonTotal,
      isFutureMonth: future,
    );
    if (utf8.encode(jsonEncode(snapshot.toJson())).length >
        financialInsightsMaxRequestBytes) {
      throw const FinancialInsightsException('insights_too_large');
    }
    return snapshot;
  }

  bool get canGenerate => !isFutureMonth && expenseCount > 0;

  Map<String, Object> toJson() => Map.unmodifiable({
    'month': month,
    'as_of': asOf,
    'currency': currency,
    'language': language,
    'expenses': expenses,
    'budgets': budgets,
  });

  String get fingerprint => jsonEncode(toJson());
}

class FinancialInsight {
  final String title, observation, action;
  final String? category;

  const FinancialInsight({
    required this.title,
    required this.observation,
    required this.action,
    required this.category,
  });
}

class FinancialInsightsBasis {
  final DateTime periodStart, periodEnd, comparisonEnd;
  final int expenseCount, totalExpenseCents;
  final int comparisonExpenseCount, comparisonTotalExpenseCents;

  const FinancialInsightsBasis({
    required this.periodStart,
    required this.periodEnd,
    required this.comparisonEnd,
    required this.expenseCount,
    required this.totalExpenseCents,
    required this.comparisonExpenseCount,
    required this.comparisonTotalExpenseCents,
  });
}

class FinancialInsightsResult {
  final String month, currency, language, summary;
  final DateTime generatedAt;
  final List<FinancialInsight> insights;
  final FinancialInsightsBasis basedOn;

  const FinancialInsightsResult({
    required this.month,
    required this.currency,
    required this.language,
    required this.summary,
    required this.generatedAt,
    required this.insights,
    required this.basedOn,
  });

  factory FinancialInsightsResult.fromJson(
    Map<String, dynamic> json, {
    required FinancialInsightsRequest request,
  }) {
    Never invalid() =>
        throw const FinancialInsightsException('invalid_insights_response');
    String text(Object? value, int maxLength) {
      if (value is! String ||
          value.trim().isEmpty ||
          value.runes.length > maxLength) {
        invalid();
      }
      return value.trim();
    }

    if (json['success'] != true ||
        json['month'] != request.month ||
        json['currency'] != request.currency ||
        json['language'] != request.language) {
      invalid();
    }
    final generated = json['generated_at'];
    final generatedAt =
        generated is String ? DateTime.tryParse(generated) : null;
    if (generated is! String ||
        !RegExp(
          r'^\d{4}-\d{2}-\d{2}T(?:[01]\d|2[0-3]):[0-5]\d:[0-5]\d'
          r'(?:\.\d{1,6})?(?:Z|\+00:00)$',
        ).hasMatch(generated) ||
        generatedAt == null ||
        !generatedAt.isUtc ||
        _dateText(generatedAt) != generated.substring(0, 10)) {
      invalid();
    }
    final rawInsights = json['insights'];
    if (rawInsights is! List || rawInsights.isEmpty || rawInsights.length > 5) {
      invalid();
    }
    final insights = <FinancialInsight>[];
    for (final raw in rawInsights) {
      if (raw is! Map<String, dynamic>) invalid();
      final row = raw;
      final category = row['category'];
      if (!row.containsKey('category') ||
          (category != null &&
              (category is! String || !categories.contains(category)))) {
        invalid();
      }
      insights.add(
        FinancialInsight(
          title: text(row['title'], 100),
          observation: text(row['observation'], 600),
          action: text(row['action'], 600),
          category: category as String?,
        ),
      );
    }
    final rawBasis = json['based_on'];
    if (rawBasis is! Map<String, dynamic>) invalid();
    final basis = rawBasis;
    final expected = <String, Object>{
      'period_start': _dateText(request.periodStart),
      'period_end': _dateText(request.periodEnd),
      'comparison_end': _dateText(request.comparisonEnd),
      'expense_count': request.expenseCount,
      'total_expense_cents': request.totalExpenseCents,
      'comparison_expense_count': request.comparisonExpenseCount,
      'comparison_total_expense_cents': request.comparisonTotalExpenseCents,
    };
    for (final entry in expected.entries) {
      if (basis[entry.key] != entry.value ||
          (entry.value is int && basis[entry.key] is! int)) {
        invalid();
      }
    }
    return FinancialInsightsResult(
      month: request.month,
      currency: request.currency,
      language: request.language,
      summary: text(json['summary'], 600),
      generatedAt: generatedAt,
      insights: List.unmodifiable(insights),
      basedOn: FinancialInsightsBasis(
        periodStart: request.periodStart,
        periodEnd: request.periodEnd,
        comparisonEnd: request.comparisonEnd,
        expenseCount: request.expenseCount,
        totalExpenseCents: request.totalExpenseCents,
        comparisonExpenseCount: request.comparisonExpenseCount,
        comparisonTotalExpenseCents: request.comparisonTotalExpenseCents,
      ),
    );
  }
}
