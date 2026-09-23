import 'dart:async';
import 'dart:convert';

import 'package:financial_advisor/core/finance_store.dart';
import 'package:financial_advisor/services/financial_insights_service.dart';
import 'package:financial_advisor/widgets/design.dart';
import 'package:financial_advisor/widgets/financial_insights_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

final insightMonth = DateTime(2026, 9);
final insightNow = DateTime(2026, 9, 23);
final insightButton = find.byKey(const Key('generate-financial-insights'));

Map<String, dynamic> responseFor(String language) => {
  'success': true,
  'month': '2026-09',
  'currency': 'SAR',
  'language': language,
  'generated_at': '2026-09-23T12:00:00Z',
  'summary':
      language == 'ar'
          ? 'راجع إنفاقك على الطعام هذا الشهر.'
          : 'Review your food spending this month.',
  'insights': [
    {
      'title': language == 'ar' ? 'خطط لوجبات الأسبوع' : 'Plan your meals',
      'observation':
          language == 'ar'
              ? 'سجلت مصروفاً للطعام بقيمة ٣٠ ريالاً.'
              : 'Your recorded food expense is SAR 30.',
      'action':
          language == 'ar'
              ? 'اكتب قائمة مشتريات قبل الذهاب إلى المتجر.'
              : 'Write a shopping list before visiting the store.',
      'category': 'Food',
    },
  ],
  'based_on': {
    'period_start': '2026-09-01',
    'period_end': '2026-09-23',
    'comparison_end': '2026-08-23',
    'expense_count': 1,
    'total_expense_cents': 3000,
    'comparison_expense_count': 0,
    'comparison_total_expense_cents': 0,
  },
};

Widget insightsApp(
  FinanceStore store,
  Future<http.Response> Function(http.Request) send, {
  String language = 'en',
  DateTime? month,
}) => MaterialApp(
  theme: appTheme(),
  locale: Locale(language),
  supportedLocales: const [Locale('en'), Locale('ar')],
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  home: Scaffold(
    body: SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: FinancialInsightsPanel(
          store: store,
          month: month ?? insightMonth,
          now: () => insightNow,
          serviceFactory:
              (baseUrl) => FinancialInsightsService(
                baseUrl: baseUrl,
                clientFactory: () => MockClient(send),
              ),
        ),
      ),
    ),
  ),
);

Future<FinanceStore> insightStore({bool empty = false}) async {
  final store = FinanceStore(await SharedPreferences.getInstance());
  await store.start(
    userName: 'Private name',
    selectedCurrency: 'SAR',
    useDemo: false,
  );
  if (!empty) {
    store.entries.add(
      Entry(
        id: 'expense',
        merchant: 'Local market',
        cents: 3000,
        date: DateTime(2026, 9, 10),
        category: 'Food',
        note: 'Private note',
      ),
    );
    await store.persist();
  }
  return store;
}

Future<void> pressInsights(WidgetTester tester) async {
  await tester.ensureVisible(insightButton);
  await tester.tap(insightButton);
  await tester.pump();
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en');
    await initializeDateFormatting('ar');
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final language in ['en', 'ar']) {
    testWidgets(
      '$language insights run only on click and leave expenses unchanged',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final store = await insightStore();
        final ledger = store.prefs.getString('numo_v1');
        var calls = 0;
        final pending = Completer<http.Response>();
        Future<http.Response> send(http.Request request) {
          calls++;
          expect(request.url.path, '/api/insights/expenses');
          expect(jsonDecode(request.body)['language'], language);
          expect(request.body, isNot(contains('Private name')));
          expect(request.body, isNot(contains('Private note')));
          return pending.future;
        }

        await tester.pumpWidget(insightsApp(store, send, language: language));
        await tester.pumpAndSettle();
        expect(calls, 0);
        await pressInsights(tester);
        expect(calls, 1);
        expect(
          find.byKey(const Key('financial-insights-loading')),
          findsOneWidget,
        );
        expect(tester.widget<FilledButton>(insightButton).onPressed, isNull);
        await tester.pumpWidget(insightsApp(store, send, language: language));
        await tester.pump();
        expect(calls, 1);

        pending.complete(
          http.Response(
            jsonEncode(responseFor(language)),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(responseFor(language)['summary']), findsOneWidget);
        expect(
          find.byKey(const ValueKey('financial-insight-0')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('financial-insights-loading')),
          findsNothing,
        );
        expect(store.prefs.getString('numo_v1'), ledger);
        expect(store.entries, hasLength(1));
        expect(calls, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('empty month has no model requests and a disabled button', (
    tester,
  ) async {
    final store = await insightStore(empty: true);
    var calls = 0;
    await tester.pumpWidget(
      insightsApp(store, (_) async {
        calls++;
        return http.Response(jsonEncode(responseFor('en')), 200);
      }),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Add expenses for this month to get personalized insights.'),
      findsOneWidget,
    );
    expect(tester.widget<FilledButton>(insightButton).onPressed, isNull);
    expect(calls, 0);
  });

  testWidgets('safe errors allow explicit retry without automatic requests', (
    tester,
  ) async {
    final store = await insightStore();
    var calls = 0;
    await tester.pumpWidget(
      insightsApp(store, (_) async {
        calls++;
        return calls == 1
            ? http.Response(
              jsonEncode({
                'success': false,
                'code': 'ai_rate_limited',
                'error': 'private provider diagnostic',
              }),
              429,
            )
            : http.Response(jsonEncode(responseFor('en')), 200);
      }),
    );
    await pressInsights(tester);
    await tester.pumpAndSettle();
    expect(
      find.text(
        'AI insights have reached their usage limit. Please try again later.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('private provider'), findsNothing);
    expect(calls, 1);
    await pressInsights(tester);
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.byKey(const Key('financial-insights-result')), findsOneWidget);
    expect(find.byKey(const Key('financial-insights-error')), findsNothing);
  });

  for (final change in ['expenses', 'month', 'language']) {
    testWidgets('a pending response is discarded after $change changes', (
      tester,
    ) async {
      final store = await insightStore();
      final pending = Completer<http.Response>();
      var calls = 0;
      Future<http.Response> send(http.Request _) {
        calls++;
        return pending.future;
      }

      await tester.pumpWidget(insightsApp(store, send));
      await pressInsights(tester);
      if (change == 'expenses') {
        store.entries.add(
          Entry(
            id: 'new',
            merchant: 'Another market',
            cents: 500,
            date: DateTime(2026, 9, 12),
            category: 'Food',
          ),
        );
        await store.persist();
      } else {
        await tester.pumpWidget(
          insightsApp(
            store,
            send,
            month: change == 'month' ? DateTime(2026, 8) : insightMonth,
            language: change == 'language' ? 'ar' : 'en',
          ),
        );
      }
      pending.complete(http.Response(jsonEncode(responseFor('en')), 200));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('financial-insights-result')), findsNothing);
      expect(find.byKey(const Key('financial-insights-loading')), findsNothing);
      expect(find.byKey(const Key('financial-insights-error')), findsOneWidget);
      expect(calls, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('leaving while generating does not update a disposed widget', (
    tester,
  ) async {
    final store = await insightStore();
    final pending = Completer<http.Response>();
    await tester.pumpWidget(insightsApp(store, (_) => pending.future));
    await pressInsights(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    pending.complete(http.Response(jsonEncode(responseFor('en')), 200));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
