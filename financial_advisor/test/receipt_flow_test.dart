import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:financial_advisor/core/finance_store.dart';
import 'package:financial_advisor/main.dart';
import 'package:financial_advisor/screens/transactions.dart';

void main() {
  testWidgets('receipt review confirms once and updates dashboard and budget', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final store = FinanceStore(await SharedPreferences.getInstance());
    await store.start(userName: 'Alex', selectedCurrency: 'SAR', useDemo: true);
    await tester.pumpWidget(TadbeerApp(store: store));
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(AppShell));
    editEntry(
      context,
      store,
      receiptReview: true,
      entry: Entry(
        id: 'new-receipt',
        merchant: 'Test receipt',
        cents: 18650,
        date: DateTime.now(),
        category: 'Food',
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Confirm & save expense'),
      200,
      scrollable:
          find
              .descendant(
                of: find.byType(EntryEditor),
                matching: find.byType(Scrollable),
              )
              .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm & save expense'));
    await tester.pumpAndSettle();
    expect(find.text('Confirm receipt'), findsOneWidget);
    expect(store.expensesFor(DateTime.now()), 775000);
    await tester.tap(find.text('Save expense'));
    await tester.pumpAndSettle();
    expect(store.expensesFor(DateTime.now()), 793650);
    expect(store.categorySpent(DateTime.now(), 'Food'), 143150);
    expect(
      store.budgetFor(DateTime.now()) - store.expensesFor(DateTime.now()),
      206350,
    );
    expect(find.text('4,063.50'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  test(
    'current month compares equivalent days when previous month is shorter',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = FinanceStore(await SharedPreferences.getInstance());
      store.entries = [
        Entry(
          id: 'a',
          merchant: 'A',
          cents: 100,
          date: DateTime(2026, 3, 28),
          category: 'Food',
        ),
        Entry(
          id: 'b',
          merchant: 'B',
          cents: 900,
          date: DateTime(2026, 3, 31),
          category: 'Food',
        ),
        Entry(
          id: 'c',
          merchant: 'C',
          cents: 200,
          date: DateTime(2026, 2, 28),
          category: 'Food',
        ),
      ];
      final comparison = store.spendingComparison(
        DateTime(2026, 3),
        now: DateTime(2026, 3, 31),
      );
      expect(comparison.days, 28);
      expect(comparison.current, 100);
      expect(comparison.previous, 200);
    },
  );
}
