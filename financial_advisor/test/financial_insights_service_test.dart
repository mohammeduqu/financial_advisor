import 'dart:async';
import 'dart:convert';

import 'package:financial_advisor/core/finance_store.dart';
import 'package:financial_advisor/core/financial_insights.dart';
import 'package:financial_advisor/services/financial_insights_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

Entry expense(
  String id,
  DateTime date, {
  bool income = false,
  int cents = 500,
}) => Entry(
  id: id,
  merchant: 'Grocer $id',
  cents: cents,
  date: date,
  category: 'Food',
  income: income,
  note: 'Private note',
  receipt: 'Private receipt contents',
);

String dayText(DateTime date) =>
    '${monthKey(date)}-${date.day.toString().padLeft(2, '0')}';

Map<String, dynamic> insightsResponse(FinancialInsightsRequest request) => {
  'success': true,
  'month': request.month,
  'currency': request.currency,
  'language': request.language,
  'generated_at': '2026-09-23T12:00:00Z',
  'summary': 'Review food purchases before setting next month’s budget.',
  'insights': [
    <String, dynamic>{
      'title': 'Plan grocery purchases',
      'observation': 'Food is represented in your recorded expenses.',
      'action': 'Make a weekly shopping list and review prices before buying.',
      'category': 'Food',
    },
  ],
  'based_on': {
    'period_start': dayText(request.periodStart),
    'period_end': dayText(request.periodEnd),
    'comparison_end': dayText(request.comparisonEnd),
    'expense_count': request.expenseCount,
    'total_expense_cents': request.totalExpenseCents,
    'comparison_expense_count': request.comparisonExpenseCount,
    'comparison_total_expense_cents': request.comparisonTotalExpenseCents,
  },
};

Matcher insightError(String code) => isA<FinancialInsightsException>().having(
  (error) => error.code,
  'code',
  code,
);

class ClosingClient extends MockClient {
  bool closed = false;
  ClosingClient(super.fn);

  @override
  void close() {
    closed = true;
    super.close();
  }
}

void main() {
  late FinanceStore store;
  final now = DateTime(2026, 9, 23, 14);

  FinancialInsightsRequest snapshot({
    DateTime? month,
    String language = 'en',
  }) => FinancialInsightsRequest.fromStore(
    store,
    month ?? now,
    language: language,
    now: now,
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = FinanceStore(await SharedPreferences.getInstance());
    store.entries = [expense('today', now)];
  });

  test('snapshot minimizes data, excludes income and future postings', () {
    store.name = 'Private account name';
    store.entries = [
      expense('old', DateTime(2026, 7, 31)),
      expense('previous-early', DateTime(2026, 8, 5), cents: 100),
      expense('previous-late', DateTime(2026, 8, 31), cents: 200),
      expense('current', DateTime(2026, 9, 1), cents: 300),
      expense('today', now, cents: 400),
      expense('future', DateTime(2026, 9, 24)),
      expense('income', now, income: true),
    ];
    store.recurringTransactions = [
      RecurringTransaction(
        id: 'unposted',
        merchant: 'Unposted recurring purchase',
        category: 'Food',
        cents: 900,
        income: false,
        startDate: DateTime(2026, 9, 1),
        frequency: RepeatFrequency.monthly,
      ),
    ];
    store.budgets = {
      '2026-08': {'Food': 70000},
      '2026-09': {'Food': 60000, 'Overall': 120000, 'Shopping': 0},
    };
    final request = snapshot();
    final data = request.toJson();

    expect(data.keys.toSet(), {
      'month',
      'as_of',
      'currency',
      'language',
      'expenses',
      'budgets',
    });
    expect(request.expenses, hasLength(4));
    expect(request.expenseCount, 2);
    expect(request.totalExpenseCents, 700);
    expect(request.comparisonExpenseCount, 1);
    expect(request.comparisonTotalExpenseCents, 100);
    expect(request.periodEnd, DateTime(2026, 9, 23));
    expect(request.comparisonEnd, DateTime(2026, 8, 23));
    expect(request.budgets, [
      {'category': 'Overall', 'amount_cents': 120000},
      {'category': 'Food', 'amount_cents': 60000},
    ]);
    for (final row in request.expenses) {
      expect(row.keys.toSet(), {
        'date',
        'category',
        'amount_cents',
        'merchant',
      });
    }
    final encoded = jsonEncode(data);
    for (final privateValue in [
      'Private account name',
      'Private note',
      'Private receipt contents',
      'Unposted recurring purchase',
      'recurringId',
      'invoice',
    ]) {
      expect(encoded, isNot(contains(privateValue)));
    }
  });

  test(
    'past periods include full months and January crosses year boundary',
    () {
      store.entries = [
        expense('last-year', DateTime(2025, 12, 31), cents: 300),
        expense('january', DateTime(2026, 1, 31), cents: 400),
        expense('february', DateTime(2026, 2, 1)),
      ];
      final request = snapshot(month: DateTime(2026, 1));
      expect(request.expenseCount, 1);
      expect(request.totalExpenseCents, 400);
      expect(request.comparisonTotalExpenseCents, 300);
      expect(request.periodEnd, DateTime(2026, 1, 31));
      expect(request.comparisonEnd, DateTime(2025, 12, 31));
      expect(request.canGenerate, isTrue);
    },
  );

  test('current month comparison clamps to leap February end', () {
    final request = FinancialInsightsRequest.fromStore(
      store,
      DateTime(2024, 3),
      language: 'en',
      now: DateTime(2024, 3, 31),
    );
    expect(request.comparisonEnd, DateTime(2024, 2, 29));
  });

  test('future months and previous-month-only data cannot generate', () {
    expect(snapshot(month: DateTime(2026, 10)).canGenerate, isFalse);
    expect(snapshot(month: DateTime(2026, 10)).expenses, isEmpty);
    store.entries = [expense('previous', DateTime(2026, 8, 1))];
    expect(snapshot().canGenerate, isFalse);
  });

  test(
    'snapshots stay immutable and reorderings do not change fingerprint',
    () {
      store.entries.add(expense('other', DateTime(2026, 9, 1), cents: 800));
      final captured = snapshot();
      store.entries = store.entries.reversed.toList();
      expect(snapshot().fingerprint, captured.fingerprint);
      expect(
        () => captured.expenses.first['merchant'] = 'Changed',
        throwsUnsupportedError,
      );
      expect(() => captured.expenses.clear(), throwsUnsupportedError);
      store.entries.add(expense('new', now));
      expect(captured.expenseCount, 2);
      expect(snapshot().fingerprint, isNot(captured.fingerprint));
      expect(
        snapshot(language: 'ar').fingerprint,
        isNot(snapshot().fingerprint),
      );
      store.currency = 'USD';
      expect(snapshot().fingerprint, isNot(captured.fingerprint));
    },
  );

  test('merchant whitespace is normalized without changing stored data', () {
    store.entries = [
      Entry(
        id: 'multiline',
        merchant: '  Local\nmarket\tbranch  ',
        cents: 100,
        date: now,
        category: 'Food',
      ),
    ];
    expect(snapshot().expenses.single['merchant'], 'Local market branch');
    expect(store.entries.single.merchant, '  Local\nmarket\tbranch  ');
  });

  test('merchant length is bounded and oversized data is never truncated', () {
    store.entries = [
      Entry(
        id: 'long',
        merchant: 'م' * 200,
        cents: 100,
        date: now,
        category: 'Food',
      ),
    ];
    expect((snapshot().expenses.single['merchant'] as String).length, 160);
    store.entries = List.generate(2001, (index) => expense('$index', now));
    expect(snapshot, throwsA(insightError('insights_too_large')));
    store.entries = List.generate(
      1500,
      (index) => Entry(
        id: '$index',
        merchant: 'م' * 160,
        cents: 100,
        date: now,
        category: 'Food',
      ),
    );
    expect(snapshot, throwsA(insightError('insights_too_large')));
  });

  test(
    'one POST sends captured data and parses a valid Arabic response',
    () async {
      final request = snapshot(language: 'ar');
      final sent = <http.Request>[];
      final client = ClosingClient((incoming) async {
        sent.add(incoming);
        return http.Response.bytes(
          utf8.encode(jsonEncode(insightsResponse(request))),
          200,
        );
      });
      final service = FinancialInsightsService(
        baseUrl: 'http://127.0.0.1:5000',
        clientFactory: () => client,
      );
      final result = await service.generate(request);
      expect(sent, hasLength(1));
      expect(sent.single.method, 'POST');
      expect(sent.single.url.path, '/api/insights/expenses');
      expect(jsonDecode(sent.single.body), request.toJson());
      expect(result.language, 'ar');
      expect(result.insights.single.category, 'Food');
      expect(result.basedOn.totalExpenseCents, 500);
      expect(result.generatedAt.isUtc, isTrue);
      expect(client.closed, isTrue);
    },
  );

  test('empty data and invalid URL fail before creating a client', () async {
    var calls = 0;
    final service = FinancialInsightsService(
      baseUrl: 'http://127.0.0.1:5000/api',
      clientFactory: () {
        calls++;
        return MockClient((_) async => http.Response('', 200));
      },
    );
    await expectLater(
      service.generate(snapshot()),
      throwsA(insightError('invalid_url')),
    );
    store.entries.clear();
    await expectLater(
      service.generate(snapshot()),
      throwsA(insightError('no_expenses')),
    );
    expect(calls, 0);
  });

  test('timeouts close the client without a retry', () async {
    var calls = 0;
    final pending = Completer<http.Response>();
    final client = ClosingClient((_) {
      calls++;
      return pending.future;
    });
    final service = FinancialInsightsService(
      baseUrl: 'http://127.0.0.1:5000',
      timeout: const Duration(milliseconds: 1),
      clientFactory: () => client,
    );
    await expectLater(
      service.generate(snapshot()),
      throwsA(insightError('insights_timeout')),
    );
    expect(calls, 1);
    expect(client.closed, isTrue);
    pending.complete(http.Response('{}', 200));
  });

  test(
    'concurrent generate is guarded and close discards a late response',
    () async {
      final pending = Completer<http.Response>();
      final request = snapshot();
      final client = ClosingClient((_) => pending.future);
      final service = FinancialInsightsService(
        baseUrl: 'http://127.0.0.1:5000',
        clientFactory: () => client,
      );
      final first = service.generate(request);
      await expectLater(
        service.generate(request),
        throwsA(insightError('server_busy')),
      );
      service.close();
      expect(client.closed, isTrue);
      pending.complete(
        http.Response.bytes(
          utf8.encode(jsonEncode(insightsResponse(request))),
          200,
        ),
      );
      await expectLater(first, throwsA(insightError('cancelled')));
    },
  );

  test('server and network errors never expose raw messages or keys', () async {
    for (final networkError in [false, true]) {
      final service = FinancialInsightsService(
        baseUrl: 'http://127.0.0.1:5000',
        clientFactory:
            () => MockClient((_) async {
              if (networkError) {
                throw http.ClientException('secret-key raw server URL');
              }
              return http.Response(
                jsonEncode({
                  'success': false,
                  'code': 'unknown secret-key',
                  'message': 'secret-key raw provider error',
                }),
                503,
              );
            }),
      );
      try {
        await service.generate(snapshot());
        fail('Expected an insights error');
      } on FinancialInsightsException catch (error) {
        expect(error.code, isNot(contains('secret-key')));
        expect(error.message, isNot(contains('secret-key')));
        expect(error.toString(), isNot(contains('raw')));
      }
    }
  });

  test('HTML, non-JSON and malformed insight responses are rejected', () async {
    for (final raw in [
      '<!doctype html><html>Flutter</html>',
      'not json',
      '[]',
    ]) {
      final service = FinancialInsightsService(
        baseUrl: 'http://127.0.0.1:5000',
        clientFactory: () => MockClient((_) async => http.Response(raw, 200)),
      );
      await expectLater(
        service.generate(snapshot()),
        throwsA(isA<FinancialInsightsException>()),
      );
    }
    final request = snapshot();
    final mutations = <void Function(Map<String, dynamic>)>[
      (body) => body['month'] = '2026-08',
      (body) => body['currency'] = 'USD',
      (body) => body['language'] = 'ar',
      (body) => body['summary'] = '',
      (body) => body['generated_at'] = '2026-09-23',
      (body) => body['insights'] = [],
      (body) => body['insights'][0]['category'] = 'Investments',
      (body) => body['insights'][0]['action'] = 42,
      (body) => body['based_on']['expense_count'] = 1.0,
      (body) => body['based_on']['total_expense_cents'] = 999,
      (body) => body['based_on']['comparison_end'] = '2026-08-31',
    ];
    for (final mutate in mutations) {
      final body = insightsResponse(request);
      mutate(body);
      expect(
        () => FinancialInsightsResult.fromJson(body, request: request),
        throwsA(insightError('invalid_insights_response')),
      );
    }
  });
}
