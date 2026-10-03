import 'package:financial_advisor/core/finance_store.dart';
import 'package:financial_advisor/core/recommendation.dart';
import 'package:financial_advisor/main.dart';
import 'package:financial_advisor/screens/plan.dart';
import 'package:financial_advisor/widgets/design.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<FinanceStore> _makeStore() async {
  SharedPreferences.setMockInitialValues({});
  final store = FinanceStore(await SharedPreferences.getInstance());
  await store.start(
    userName: 'Samira',
    selectedCurrency: 'USD',
    selectedCountry: 'KW',
    acceptedLegal: true,
    useDemo: true,
  );
  await store.setLanguage('en');
  return store;
}

Future<void> _openGoal(WidgetTester tester, FinanceStore store) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: appTheme(),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('en'), Locale('ar')],
      home: Builder(
        builder:
            (context) => Scaffold(
              body: TextButton(
                onPressed:
                    () => Navigator.push<void>(
                      context,
                      MaterialPageRoute(
                        builder:
                            (_) => GoalDetail(
                              store: store,
                              goal: store.goals.first,
                            ),
                      ),
                    ),
                child: const Text('Open goal'),
              ),
            ),
      ),
    ),
  );
  await tester.tap(find.text('Open goal'));
  await tester.pumpAndSettle();
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      180,
      scrollable: find.byType(Scrollable).last,
    );
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _confirmAction(WidgetTester tester, String text) async {
  await tester.tap(
    find.descendant(of: find.byType(AlertDialog), matching: find.text(text)),
  );
  await tester.pumpAndSettle();
}

Future<FinanceStore> _reload(FinanceStore store) async {
  await store.prefs.reload();
  final restored = FinanceStore(store.prefs);
  await restored.load();
  expect(restored.error, isNull);
  return restored;
}

void main() {
  testWidgets(
    'goal deletion requires confirmation and preserves other finances',
    (tester) async {
      final store = await _makeStore();
      final initialRaw = store.prefs.getString('numo_v1');
      final originalExpenses = store.expensesFor(null);
      final retainedGoal = store.goals.last.toJson();
      final originalEntries =
          store.entries.map((entry) => entry.toJson()).toList();
      await _openGoal(tester, store);

      await tester.tap(find.byTooltip('Delete goal'));
      await tester.pumpAndSettle();
      expect(find.text('Delete goal?'), findsOneWidget);
      await _confirmAction(tester, 'Cancel');
      expect(find.byType(GoalDetail), findsOneWidget);
      expect(store.goals, hasLength(2));
      expect(store.prefs.getString('numo_v1'), initialRaw);

      await tester.tap(find.byTooltip('Delete goal'));
      await tester.pumpAndSettle();
      await _confirmAction(tester, 'Delete');
      expect(find.byType(GoalDetail), findsNothing);
      expect(find.text('Open goal'), findsOneWidget);
      expect(store.goals.single.toJson(), retainedGoal);
      expect(store.expensesFor(null), originalExpenses);
      expect(
        store.entries.map((entry) => entry.toJson()).toList(),
        originalEntries,
      );
      final restored = await _reload(store);
      expect(restored.goals.single.toJson(), retainedGoal);
      expect(
        restored.entries.map((entry) => entry.toJson()).toList(),
        originalEntries,
      );
      expect(restored.expensesFor(null), originalExpenses);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'contribution removal confirms only the selected record and persists',
    (tester) async {
      final store = await _makeStore();
      final goal = store.goals.first;
      await store.saveContribution(
        goal.id,
        Contribution('additional', 20000, DateTime.now()),
      );
      final initialRaw = store.prefs.getString('numo_v1');
      final initialSaved = goal.saved;
      final originalExpenses = store.expensesFor(null);
      final otherGoal = store.goals.last.toJson();
      await _openGoal(tester, store);

      Future<void> requestRemoval() async {
        final row = find.ancestor(
          of: find.text('USD 200.00'),
          matching: find.byType(ListTile),
        );
        await _tapVisible(
          tester,
          find.descendant(
            of: row,
            matching: find.byType(PopupMenuButton<String>),
          ),
        );
        await tester.tap(find.text('Remove contribution'));
        await tester.pumpAndSettle();
        expect(find.text('Remove contribution?'), findsOneWidget);
      }

      await requestRemoval();
      await _confirmAction(tester, 'Cancel');
      expect(goal.saved, initialSaved);
      expect(goal.contributions, hasLength(2));
      expect(store.prefs.getString('numo_v1'), initialRaw);

      await requestRemoval();
      await _confirmAction(tester, 'Confirm');
      expect(find.byType(GoalDetail), findsOneWidget);
      expect(find.text('USD 200.00'), findsNothing);
      expect(goal.contributions.single.id, 'opening');
      expect(goal.saved, initialSaved - 20000);
      expect(store.goals.last.toJson(), otherGoal);
      expect(store.expensesFor(null), originalExpenses);
      final restored = await _reload(store);
      expect(restored.goals.first.contributions.single.id, 'opening');
      expect(restored.goals.first.saved, initialSaved - 20000);
      expect(restored.goals.last.toJson(), otherGoal);
      expect(restored.expensesFor(null), originalExpenses);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Profile clear-data cancel preserves history and confirmation resets setup',
    (tester) async {
      final store = await _makeStore();
      final now = DateTime.now();
      await store.saveScheduledEntry(
        Entry(
          id: 'future-rule',
          merchant: 'Future subscription',
          cents: 2500,
          date: DateTime(now.year + 1, 1, 1),
          category: 'Subscriptions',
        ),
        RepeatFrequency.monthly,
      );
      await store.saveEntry(
        Entry(
          id: 'receipt-entry',
          merchant: 'Saved receipt',
          cents: 1250,
          date: now,
          category: 'Food',
          receipt: 'c2F2ZWQgcmVjZWlwdA==',
        ),
      );
      await RecommendationHistory(store.prefs).save(
        RecommendationResult.fromJson({
          'success': true,
          'stage': 'results',
          'mode': 'product',
          'direct_search': true,
          'query': 'Tea',
          'shopping_results': [],
          'summary': {'total_results': 0},
          'recommendations': [],
        }),
      );
      final initialRaw = store.prefs.getString('numo_v1');
      final historyRaw = store.prefs.getString(
        RecommendationHistory.preferenceKey,
      );
      await tester.pumpWidget(TadbeerApp(store: store));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Profile'),
        ),
      );
      await tester.pumpAndSettle();

      await _tapVisible(tester, find.text('Clear saved data'));
      expect(find.text('Clear saved data?'), findsOneWidget);
      await _confirmAction(tester, 'Cancel');
      expect(find.byType(SettingsPage), findsOneWidget);
      expect(store.prefs.getString('numo_v1'), initialRaw);
      expect(
        store.prefs.getString(RecommendationHistory.preferenceKey),
        historyRaw,
      );
      final canceled = await _reload(store);
      expect(canceled.entries, hasLength(8));
      expect(canceled.recurringTransactions, hasLength(1));
      expect(canceled.goals, hasLength(2));
      expect(canceled.hasAcceptedCurrentLegal, isTrue);

      await _tapVisible(tester, find.text('Clear saved data'));
      await _confirmAction(tester, 'Clear data');
      expect(find.byType(WelcomePage), findsOneWidget);
      expect(store.entries, isEmpty);
      expect(store.recurringTransactions, isEmpty);
      expect(store.goals, isEmpty);
      expect(store.budgets, isEmpty);
      expect(store.onboarded, isFalse);
      expect(store.legalAcceptance, isNull);
      expect(store.prefs.getString('numo_v1'), isNull);
      expect(
        store.prefs.getString(RecommendationHistory.preferenceKey),
        isNull,
      );
      final restored = await _reload(store);
      expect(restored.entries, isEmpty);
      expect(restored.recurringTransactions, isEmpty);
      expect(restored.goals, isEmpty);
      expect(restored.budgets, isEmpty);
      expect(restored.onboarded, isFalse);
      expect(restored.hasAcceptedCurrentLegal, isFalse);
      expect(RecommendationHistory(store.prefs).read(), isEmpty);
      await tester.pumpWidget(TadbeerApp(store: restored));
      await tester.pumpAndSettle();
      expect(find.byType(WelcomePage), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
