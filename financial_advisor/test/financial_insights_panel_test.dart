import 'dart:async';
import 'dart:convert';

import 'package:financial_advisor/core/finance_store.dart';
import 'package:financial_advisor/l10n/app_language.dart';
import 'package:financial_advisor/services/financial_insights_service.dart';
import 'package:financial_advisor/widgets/design.dart';
import 'package:financial_advisor/widgets/financial_insights_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

final insightMonth = DateTime(2026, 9);
final insightNow = DateTime(2026, 9, 23);
final insightButton = find.byKey(const Key('generate-financial-insights'));
final clearInsightsButton = find.byKey(const Key('clear-financial-insights'));

class LazyInsightsHarness extends StatefulWidget {
  final FinanceStore store;
  final Future<http.Response> Function(http.Request) send;
  const LazyInsightsHarness({
    super.key,
    required this.store,
    required this.send,
  });

  @override
  State<LazyInsightsHarness> createState() => _LazyInsightsHarnessState();
}

class _LazyInsightsHarnessState extends State<LazyInsightsHarness> {
  int index = 0;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: IndexedStack(
      index: index,
      children: [
        ListView.builder(
          key: const Key('insights-lazy-list'),
          cacheExtent: 0,
          itemCount: 24,
          itemBuilder: (context, item) {
            if (item == 0) return const SizedBox(height: 120);
            if (item == 1) {
              return Padding(
                padding: const EdgeInsets.all(22),
                child: FinancialInsightsPanel(
                  store: widget.store,
                  month: insightMonth,
                  now: () => insightNow,
                  serviceFactory:
                      (baseUrl) => FinancialInsightsService(
                        baseUrl: baseUrl,
                        clientFactory: () => MockClient(widget.send),
                      ),
                ),
              );
            }
            return SizedBox(height: 420, child: Text('List section $item'));
          },
        ),
        const Center(child: Text('Profile screen')),
      ],
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: index,
      onDestinationSelected: (value) => setState(() => index = value),
      destinations: const [
        NavigationDestination(
          key: Key('insights-home-tab'),
          icon: Icon(Icons.home_outlined),
          label: 'Home',
        ),
        NavigationDestination(
          key: Key('insights-profile-tab'),
          icon: Icon(Icons.person_outline),
          label: 'Profile',
        ),
      ],
    ),
  );
}

Widget lazyInsightsApp(
  FinanceStore store,
  Future<http.Response> Function(http.Request) send,
  String language,
) => MaterialApp(
  theme: appTheme(),
  locale: Locale(language),
  supportedLocales: const [Locale('en'), Locale('ar')],
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  home: LazyInsightsHarness(store: store, send: send),
);

Map<String, Object?> savedPreferences(FinanceStore store) => {
  for (final key in store.prefs.getKeys()) key: store.prefs.get(key),
};

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
    acceptedLegal: true,
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
        expect(find.byKey(const ValueKey('financial-insight-0')), findsNothing);
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

    testWidgets(
      '$language completed insights survive lazy scrolling and tab switches',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final store = await insightStore();
        final saved = savedPreferences(store);
        var calls = 0;
        await tester.pumpWidget(
          lazyInsightsApp(store, (_) async {
            calls++;
            return http.Response(
              jsonEncode(responseFor(language)),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }, language),
        );
        await pressInsights(tester);
        await tester.pumpAndSettle();
        final originalPanel = tester.state(find.byType(FinancialInsightsPanel));
        expect(find.text(responseFor(language)['summary']), findsOneWidget);

        final scrollable = tester.state<ScrollableState>(
          find.descendant(
            of: find.byKey(const Key('insights-lazy-list')),
            matching: find.byType(Scrollable),
          ),
        );
        scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
        await tester.pumpAndSettle();
        expect(scrollable.position.pixels, greaterThan(5000));
        scrollable.position.jumpTo(0);
        await tester.pumpAndSettle();
        expect(
          tester.state(find.byType(FinancialInsightsPanel)),
          same(originalPanel),
        );
        expect(find.text(responseFor(language)['summary']), findsOneWidget);

        await tester.tap(find.byKey(const Key('insights-profile-tab')));
        await tester.pumpAndSettle();
        expect(find.text('Profile screen'), findsOneWidget);
        expect(
          find.byKey(const Key('financial-insights-result')),
          findsNothing,
        );
        await tester.tap(find.byKey(const Key('insights-home-tab')));
        await tester.pumpAndSettle();
        expect(find.text(responseFor(language)['summary']), findsOneWidget);
        expect(
          tester.state(find.byType(FinancialInsightsPanel)),
          same(originalPanel),
        );
        expect(calls, 1);
        expect(savedPreferences(store), saved);
        expect(store.entries, hasLength(1));
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'Clear removes completed insights without requests or ledger writes',
    (tester) async {
      final store = await insightStore();
      final saved = savedPreferences(store);
      var calls = 0;
      await tester.pumpWidget(
        insightsApp(store, (_) async {
          calls++;
          return http.Response(jsonEncode(responseFor('en')), 200);
        }),
      );
      await pressInsights(tester);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('financial-insights-result')),
        findsOneWidget,
      );
      await tester.ensureVisible(clearInsightsButton);
      await tester.tap(clearInsightsButton);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('financial-insights-result')), findsNothing);
      expect(find.byKey(const ValueKey('financial-insight-0')), findsNothing);
      expect(clearInsightsButton, findsNothing);
      expect(find.text('Generate AI insights'), findsOneWidget);
      expect(calls, 1);
      expect(savedPreferences(store), saved);
      expect(store.entries, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('clearing during refresh discards the late result', (
    tester,
  ) async {
    final store = await insightStore();
    final saved = savedPreferences(store);
    final pending = Completer<http.Response>();
    var calls = 0;
    await tester.pumpWidget(
      insightsApp(store, (_) {
        calls++;
        return calls == 1
            ? Future.value(http.Response(jsonEncode(responseFor('en')), 200))
            : pending.future;
      }),
    );
    await pressInsights(tester);
    await tester.pumpAndSettle();
    await pressInsights(tester);
    expect(find.byKey(const Key('financial-insights-loading')), findsOneWidget);
    expect(find.byKey(const Key('financial-insights-result')), findsOneWidget);
    await tester.ensureVisible(clearInsightsButton);
    await tester.tap(clearInsightsButton);
    await tester.pump();
    pending.complete(http.Response(jsonEncode(responseFor('en')), 200));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('financial-insights-result')), findsNothing);
    expect(find.byKey(const Key('financial-insights-loading')), findsNothing);
    expect(find.byKey(const Key('financial-insights-error')), findsNothing);
    expect(clearInsightsButton, findsNothing);
    expect(calls, 2);
    expect(savedPreferences(store), saved);
    expect(tester.takeException(), isNull);
  });

  testWidgets('full unmount and reopen starts empty without saving insights', (
    tester,
  ) async {
    final store = await insightStore();
    final saved = savedPreferences(store);
    var calls = 0;
    Future<http.Response> send(http.Request _) async {
      calls++;
      return http.Response(jsonEncode(responseFor('en')), 200);
    }

    await tester.pumpWidget(insightsApp(store, send));
    await pressInsights(tester);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('financial-insights-result')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(insightsApp(store, send));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('financial-insights-result')), findsNothing);
    expect(clearInsightsButton, findsNothing);
    expect(calls, 1);
    expect(savedPreferences(store), saved);
    expect(tester.takeException(), isNull);
  });

  for (final change in ['expenses', 'month', 'language']) {
    testWidgets(
      'completed insights remain with their period after $change changes',
      (tester) async {
        final store = await insightStore();
        var calls = 0;
        Future<http.Response> send(http.Request _) async {
          calls++;
          return http.Response(jsonEncode(responseFor('en')), 200);
        }

        await tester.pumpWidget(insightsApp(store, send));
        await pressInsights(tester);
        await tester.pumpAndSettle();
        if (change == 'expenses') {
          store.entries.add(
            Entry(
              id: 'after-analysis',
              merchant: 'Later market',
              cents: 2000,
              date: DateTime(2026, 9, 20),
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
        await tester.pumpAndSettle();
        final language = change == 'language' ? 'ar' : 'en';
        expect(find.text(responseFor('en')['summary']), findsOneWidget);
        expect(
          find.text(
            translate(
              'Insights for ${DateFormat.yMMMM(language).format(insightMonth)}',
              language,
            ),
          ),
          findsOneWidget,
        );
        expect(
          find.text(
            translate(
              'Your financial data or language changed. These insights reflect the earlier analysis.',
              language,
            ),
          ),
          findsOneWidget,
        );
        expect(clearInsightsButton, findsOneWidget);
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
