import 'package:financial_advisor/core/finance_store.dart';
import 'package:financial_advisor/screens/plan.dart';
import 'package:financial_advisor/widgets/design.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late FinanceStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = FinanceStore(await SharedPreferences.getInstance());
    store.entries = [
      Entry(
        id: 'old-food',
        merchant: 'Earlier groceries',
        cents: 1200,
        date: DateTime(2025, 12, 31),
        category: 'Food',
      ),
      Entry(
        id: 'new-food',
        merchant: 'Recent groceries',
        cents: 2300,
        date: DateTime(2026, 1, 5),
        category: 'Food',
      ),
      Entry(
        id: 'income',
        merchant: 'Salary',
        cents: 100000,
        date: DateTime(2026, 1, 1),
        category: 'Income',
        income: true,
      ),
    ];
    await store.setBudget(DateTime(2026, 1), 'Overall', 5000);
    await store.setBudget(DateTime(2026, 1), 'Food', 4000);
  });

  Future<void> pumpPlan(
    WidgetTester tester, {
    DateTime? month,
    VoidCallback? chooseMonth,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Scaffold(
          body: PlanPage(store: store, month: month, chooseMonth: chooseMonth),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> expandFood(WidgetTester tester, String period) async {
    final tile = find.byKey(PageStorageKey('category-budget-$period-Food'));
    await tester.scrollUntilVisible(tile, 180);
    final title = find.descendant(of: tile, matching: find.text('Food'));
    await tester.ensureVisible(title);
    await tester.pumpAndSettle();
    await tester.tap(title);
    await tester.pumpAndSettle();
  }

  testWidgets('all-time analysis includes history without monthly limits', (
    tester,
  ) async {
    await pumpPlan(tester);
    expect(find.text('Total expenses'), findsOneWidget);
    expect(find.text('SAR 35.00'), findsWidgets);
    expect(find.text('Edit monthly budget →'), findsNothing);
    expect(find.text('Use previous month’s category budgets'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    await expandFood(tester, 'all');
    expect(find.text('Recent groceries'), findsOneWidget);
    expect(find.text('Earlier groceries'), findsOneWidget);
    expect(find.text('Salary'), findsNothing);
    expect(
      tester.getTopLeft(find.text('Recent groceries')).dy,
      lessThan(tester.getTopLeft(find.text('Earlier groceries')).dy),
    );
    expect(find.text('SAR 35.00 / SAR 40.00'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('selecting a month restores only its spending and budgets', (
    tester,
  ) async {
    await pumpPlan(tester);
    await pumpPlan(tester, month: DateTime(2026, 1));
    expect(find.text('JANUARY BUDGET'), findsOneWidget);
    expect(find.text('SAR 23.00'), findsOneWidget);
    expect(find.text('Edit monthly budget →'), findsNothing);
    expect(find.text('Use previous month’s category budgets'), findsOneWidget);
    expect(store.budgetFor(DateTime(2026, 1)), 5000);
    expect(find.byType(TextFormField), findsNothing);
    await expandFood(tester, '2026-01');
    expect(find.text('SAR 23.00 / SAR 40.00'), findsOneWidget);
    expect(find.text('Recent groceries'), findsOneWidget);
    expect(find.text('Earlier groceries'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('all-time planning offers month selection and keeps goals', (
    tester,
  ) async {
    var requestedMonth = false;
    await pumpPlan(tester, chooseMonth: () => requestedMonth = true);
    final choose = find.byKey(const Key('planning-choose-month'));
    await tester.ensureVisible(choose);
    await tester.tap(choose);
    expect(requestedMonth, isTrue);
    await tester.ensureVisible(find.text('Goals'));
    await tester.tap(find.text('Goals'));
    await tester.pumpAndSettle();
    expect(find.text('Create a goal'), findsOneWidget);
    expect(find.text('Total expenses'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
