import 'package:financial_advisor/core/finance_store.dart';
import 'package:financial_advisor/screens/plan.dart';
import 'package:financial_advisor/screens/transactions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FailFirstWriteStore extends FinanceStore {
  _FailFirstWriteStore(super.prefs);

  bool failNextWrite = true;

  @override
  Future<void> persist() async {
    if (failNextWrite) {
      failNextWrite = false;
      error = 'Changes could not be saved. Keep the app open and tap Retry.';
      notifyListeners();
      return;
    }
    await super.persist();
  }
}

Future<void> _openEditor(WidgetTester tester, Widget editor) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('en'), Locale('ar')],
      home: Builder(
        builder:
            (context) => Scaffold(
              body: TextButton(
                onPressed:
                    () => Navigator.push<void>(
                      context,
                      MaterialPageRoute(builder: (_) => editor),
                    ),
                child: const Text('Open editor'),
              ),
            ),
      ),
    ),
  );
  await tester.tap(find.text('Open editor'));
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

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('retrying a new goal after a failed save keeps one goal', (
    tester,
  ) async {
    final store = _FailFirstWriteStore(await SharedPreferences.getInstance());
    await _openEditor(tester, GoalEditor(store: store));
    await tester.enterText(find.byKey(const Key('goal-name')), 'Emergency');
    await tester.enterText(find.byKey(const Key('goal-target')), '1000');
    final save = find.widgetWithText(FilledButton, 'Create goal');
    await _tapVisible(tester, save);
    expect(store.error, isNotNull);
    expect(store.goals, hasLength(1));
    final id = store.goals.single.id;
    await tester.pump(const Duration(seconds: 5));
    await _tapVisible(tester, save);
    expect(store.error, isNull);
    expect(store.goals, hasLength(1));
    expect(store.goals.single.id, id);
    final restored = FinanceStore(store.prefs);
    await restored.load();
    expect(restored.goals, hasLength(1));
    expect(restored.goals.single.target, 100000);
    expect(tester.takeException(), isNull);
  });

  testWidgets('retrying a new contribution does not double saved money', (
    tester,
  ) async {
    final store = _FailFirstWriteStore(await SharedPreferences.getInstance());
    final goal = Goal(id: 'goal', name: 'Emergency', target: 100000);
    store.goals.add(goal);
    await _openEditor(
      tester,
      ContributionEditor(store: store, goalId: goal.id),
    );
    await tester.enterText(find.byKey(const Key('contribution-amount')), '125');
    final save = find.widgetWithText(FilledButton, 'Save contribution');
    await _tapVisible(tester, save);
    expect(store.error, isNotNull);
    expect(goal.saved, 12500);
    final id = goal.contributions.single.id;
    await tester.pump(const Duration(seconds: 5));
    await _tapVisible(tester, save);
    expect(store.error, isNull);
    expect(goal.contributions, hasLength(1));
    expect(goal.contributions.single.id, id);
    expect(goal.saved, 12500);
    final restored = FinanceStore(store.prefs);
    await restored.load();
    expect(restored.goals.single.saved, 12500);
    expect(restored.goals.single.contributions, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('changing income into an expense saves its displayed category', (
    tester,
  ) async {
    final store = FinanceStore(await SharedPreferences.getInstance());
    final entry = Entry(
      id: 'income',
      merchant: 'Refund correction',
      cents: 12500,
      date: DateTime(2026, 1, 2),
      category: 'Income',
      income: true,
    );
    await store.saveEntry(entry);
    await _openEditor(tester, EntryEditor(store: store, entry: entry));
    await tester.tap(find.text('Expense'));
    await tester.pumpAndSettle();
    await _tapVisible(tester, find.byKey(const Key('save-entry')));
    expect(store.entries, hasLength(1));
    expect(store.entries.single.income, isFalse);
    expect(store.entries.single.category, 'Other');
    expect(store.incomeFor(null), 0);
    expect(store.categorySpent(null, 'Other'), 12500);
    final restored = FinanceStore(store.prefs);
    await restored.load();
    expect(restored.entries.single.category, 'Other');
    expect(tester.takeException(), isNull);
  });
}
