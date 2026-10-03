import 'package:financial_advisor/core/finance_store.dart';
import 'package:financial_advisor/widgets/design.dart';
import 'package:financial_advisor/widgets/finance_charts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

Entry record(
  String id,
  DateTime date,
  int cents, {
  String category = 'Food',
  bool income = false,
}) => Entry(
  id: id,
  merchant: id,
  cents: cents,
  date: date,
  category: category,
  income: income,
);

Widget charts(FinanceStore store, DateTime? month) => MaterialApp(
  theme: appTheme(),
  home: Scaffold(
    body: SingleChildScrollView(
      child: Column(
        children: [
          SpendingTrend(store: store, month: month),
          BudgetDistribution(store: store, month: month),
        ],
      ),
    ),
  ),
);

void main() {
  setUpAll(() => initializeDateFormatting('en'));
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('charts switch between complete history and a selected month', (
    tester,
  ) async {
    final store = FinanceStore(await SharedPreferences.getInstance());
    store.entries = [
      record('Older food', DateTime(2023, 1, 10), 1000),
      record('January food', DateTime(2024, 1, 20), 2000),
      record('March travel', DateTime(2024, 3, 31), 3000, category: 'Travel'),
      record('Salary', DateTime(2024, 3, 1), 90000, income: true),
    ];

    await tester.pumpWidget(charts(store, null));
    expect(find.text('All time'), findsOneWidget);
    expect(find.text('Jan 2023'), findsOneWidget);
    expect(find.text('Mar 2024'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Cumulative spending across all dates: SAR 60.00'),
      findsOneWidget,
    );
    expect(find.text('Share of all expenses'), findsOneWidget);
    expect(find.text('SAR 60.00 spent across categories'), findsOneWidget);
    expect(find.text('50%'), findsNWidgets(2));
    expect(find.byKey(const ValueKey('expense-share-Income')), findsNothing);

    await tester.pumpWidget(charts(store, DateTime(2024, 1)));
    expect(find.text('Selected month'), findsOneWidget);
    expect(find.text('Day 1'), findsOneWidget);
    expect(find.text('Day 31'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Cumulative spending over 31 days: SAR 20.00'),
      findsOneWidget,
    );
    expect(find.text('Share of selected month’s expenses'), findsOneWidget);
    expect(find.text('SAR 20.00 spent across categories'), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
    expect(find.byKey(const ValueKey('expense-share-Travel')), findsNothing);

    await tester.pumpWidget(charts(store, null));
    expect(find.text('SAR 60.00 spent across categories'), findsOneWidget);
    expect(find.byKey(const ValueKey('expense-share-Travel')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('selected current month includes saved end-of-month expenses', (
    tester,
  ) async {
    final store = FinanceStore(await SharedPreferences.getInstance());
    final now = DateTime.now();
    final lastDay = DateTime(now.year, now.month + 1, 0);
    store.entries = [record('Month end', lastDay, 4200)];

    await tester.pumpWidget(charts(store, now));
    expect(find.text('Day ${lastDay.day}'), findsOneWidget);
    expect(
      find.bySemanticsLabel(
        'Cumulative spending over ${lastDay.day} days: SAR 42.00',
      ),
      findsOneWidget,
    );
    expect(find.text('SAR 42.00 spent across categories'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty all-time and empty month charts show zero expenses', (
    tester,
  ) async {
    final store = FinanceStore(await SharedPreferences.getInstance());
    for (final month in <DateTime?>[null, DateTime(2024, 2)]) {
      await tester.pumpWidget(charts(store, month));
      expect(
        find.text('Add expenses to see your spending trend.'),
        findsOneWidget,
      );
      expect(
        find.text('Add an expense to see your distribution.'),
        findsOneWidget,
      );
      expect(find.text('0.00'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    }
    expect(find.text('Day 29'), findsOneWidget);
  });
}
