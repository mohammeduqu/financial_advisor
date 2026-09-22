import 'package:flutter_localizations/flutter_localizations.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:financial_advisor/core/finance_store.dart';
import 'package:financial_advisor/screens/plan.dart';

void main() {
  late FinanceStore store;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = FinanceStore(await SharedPreferences.getInstance());
  });

  test('amounts require valid comma grouping', () {
    for (final input in ['1,23.45', ',123', '12,345,', '1,,234', '1.234,56']) {
      expect(parseMoney(input), isNull, reason: input);
    }
    expect(parseMoney(' 1,234,567.89 '), 123456789);
    expect(parseMoney('1234567.89'), 123456789);
  });

  test(
    'copy budgets preserves current overrides and isolates months',
    () async {
      final dec = DateTime(2025, 12);
      final jan = DateTime(2026, 1);
      await store.setBudget(dec, 'Overall', 100000);
      await store.setBudget(dec, 'Food', 20000);
      await store.setBudget(jan, 'Food', 30000);
      expect(await store.copyPreviousBudgets(jan), 1);
      expect(store.budgetFor(jan), 100000);
      expect(store.budgetFor(jan, 'Food'), 30000);
      expect(await store.copyPreviousBudgets(jan), 0);
      await store.setBudget(jan, 'Overall', 0);
      expect(store.budgetFor(jan), 0);
      expect(store.budgetFor(dec), 100000);
      final restored = FinanceStore(store.prefs);
      await restored.load();
      expect(restored.budgetFor(jan, 'Food'), 30000);
      expect(restored.budgetFor(jan), 0);
    },
  );

  test(
    'goal and contribution corrections persist without changing expenses',
    () async {
      store.seed();
      final original = store.goals.first;
      final revised = Goal(
        id: original.id,
        name: 'Safety fund',
        target: 4000000,
        contributions: original.contributions,
      );
      await store.saveGoal(revised);
      final contribution = revised.contributions.first;
      await store.saveContribution(
        revised.id,
        Contribution(contribution.id, 25000, DateTime(2026, 1, 2)),
      );
      expect(store.goals.first.id, original.id);
      expect(store.goals.first.saved, 25000);
      expect(store.goals.first.contributions, hasLength(1));
      final restored = FinanceStore(store.prefs);
      await restored.load();
      expect(restored.goals.first.name, 'Safety fund');
      expect(restored.goals.first.target, 4000000);
      expect(restored.goals.first.saved, 25000);
      expect(restored.expensesFor(DateTime.now()), 775000);
      await restored.removeContribution(original.id, contribution.id);
      expect(restored.goals.first.saved, 0);
    },
  );

  test(
    'invalid saved amounts cannot partially load or overwrite data',
    () async {
      await store.start(
        userName: 'Test',
        selectedCurrency: 'SAR',
        useDemo: true,
      );
      final data =
          jsonDecode(store.prefs.getString('numo_v1')!) as Map<String, dynamic>;
      data['goals'][0]['target'] = -100;
      final invalid = jsonEncode(data);
      await store.prefs.setString('numo_v1', invalid);
      final restored = FinanceStore(store.prefs);
      await restored.load();
      expect(restored.error, isNotNull);
      expect(restored.entries, isEmpty);
      await restored.persist();
      expect(store.prefs.getString('numo_v1'), invalid);
    },
  );

  testWidgets(
    'goal editing refreshes the open detail and retains contributions',
    (tester) async {
      store.seed();
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          supportedLocales: const [Locale('en'), Locale('ar')],
          home: GoalDetail(store: store, goal: store.goals.first),
        ),
      );
      await tester.tap(find.byTooltip('Edit goal'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('goal-name')), 'Safety fund');
      await tester.enterText(find.byKey(const Key('goal-target')), '40000');
      await tester.ensureVisible(find.text('Save goal'));
      await tester.tap(find.text('Save goal'));
      await tester.pumpAndSettle();
      expect(find.text('Safety fund'), findsOneWidget);
      expect(store.goals.first.target, 4000000);
      expect(store.goals.first.saved, 900000);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('contribution editor corrects an existing record', (
    tester,
  ) async {
    store.seed();
    final goal = store.goals.first;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('en'), Locale('ar')],
        home: ContributionEditor(
          store: store,
          goalId: goal.id,
          contribution: goal.contributions.first,
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const Key('contribution-amount')),
      '125.50',
    );
    await tester.ensureVisible(find.text('Save contribution'));
    await tester.tap(find.text('Save contribution'));
    await tester.pumpAndSettle();
    expect(goal.saved, 12550);
    expect(goal.contributions, hasLength(1));
    expect(tester.takeException(), isNull);
  });
}
