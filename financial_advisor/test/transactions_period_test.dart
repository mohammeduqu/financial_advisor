import 'package:financial_advisor/core/finance_store.dart';
import 'package:financial_advisor/screens/transactions.dart';
import 'package:financial_advisor/widgets/design.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<FinanceStore> transactionStore() async {
  SharedPreferences.setMockInitialValues({});
  final store = FinanceStore(await SharedPreferences.getInstance());
  store.entries.addAll([
    Entry(
      id: 'older',
      merchant: 'Previous year income',
      cents: 100000,
      date: DateTime(2023, 12, 31),
      category: 'Income',
      income: true,
    ),
    Entry(
      id: 'january',
      merchant: 'January expense',
      cents: 10000,
      date: DateTime(2024, 1, 5),
      category: 'Food',
    ),
    Entry(
      id: 'february',
      merchant: 'February expense',
      cents: 20000,
      date: DateTime(2024, 2, 5),
      category: 'Food',
    ),
  ]);
  return store;
}

void useLargeView(WidgetTester tester) {
  tester.view.physicalSize = const Size(1000, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('default transaction view includes every recorded date only', (
    tester,
  ) async {
    useLargeView(tester);
    final store = await transactionStore();
    final now = DateTime.now();
    store.entries.add(
      Entry(
        id: 'future-recorded',
        merchant: 'Recorded future expense',
        cents: 30000,
        date: DateTime(now.year + 1, now.month, 15),
        category: 'Other',
      ),
    );
    store.recurringTransactions.add(
      RecurringTransaction(
        id: 'scheduled',
        merchant: 'Unrecorded subscription',
        cents: 500,
        category: 'Other',
        income: false,
        startDate: DateTime(now.year, now.month + 1, 1),
        frequency: RepeatFrequency.monthly,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Scaffold(body: TransactionsPage(store: store)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('4 entries'), findsOneWidget);
    for (final entry in store.entries) {
      expect(find.byKey(ValueKey('entry-${entry.id}')), findsOneWidget);
    }
    expect(find.text('Unrecorded subscription'), findsNothing);
    expect(find.textContaining('Scheduled previews:'), findsNothing);
    expect(
      find.byKey(const ValueKey('transaction-dates-Selected month')),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('transaction-dates-Upcoming')));
    await tester.pumpAndSettle();
    expect(find.text('Recorded future expense'), findsOneWidget);
    expect(find.text('Unrecorded subscription'), findsOneWidget);
    expect(find.text('Scheduled preview'), findsOneWidget);
    expect(find.text('January expense'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('transaction-dates-All dates')));
    await tester.pumpAndSettle();
    expect(find.text('4 entries'), findsOneWidget);
    expect(find.text('Unrecorded subscription'), findsNothing);
    expect(find.textContaining('Scheduled previews:'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reselecting All dates exits Upcoming without changing month', (
    tester,
  ) async {
    useLargeView(tester);
    final store = await transactionStore();
    var periodRevision = 0;
    late StateSetter changeScope;
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: StatefulBuilder(
          builder: (context, setState) {
            changeScope = setState;
            return Scaffold(
              body: TransactionsPage(
                store: store,
                periodRevision: periodRevision,
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('transaction-dates-Upcoming')));
    await tester.pumpAndSettle();
    expect(find.text('No transactions found'), findsOneWidget);

    changeScope(() => periodRevision++);
    await tester.pumpAndSettle();
    expect(find.text('3 entries'), findsOneWidget);
    expect(find.text('Food · Jan 5, 2024'), findsOneWidget);
    expect(
      tester
          .widget<ChoiceChip>(
            find.byKey(const ValueKey('transaction-dates-All dates')),
          )
          .selected,
      isTrue,
    );
    expect(find.textContaining('Scheduled previews:'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('month changes and clearing the filter sync transaction state', (
    tester,
  ) async {
    useLargeView(tester);
    final store = await transactionStore();
    DateTime? month;
    late StateSetter changeScope;
    final callbackValues = <DateTime?>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: StatefulBuilder(
          builder: (context, setState) {
            changeScope = setState;
            return Scaffold(
              body: TransactionsPage(
                store: store,
                month: month,
                onMonthChanged: (value) {
                  callbackValues.add(value);
                  setState(() => month = value);
                },
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('3 entries'), findsOneWidget);

    changeScope(() => month = DateTime(2024, 1));
    await tester.pumpAndSettle();
    expect(find.text('1 entries'), findsOneWidget);
    expect(find.text('January expense'), findsOneWidget);
    expect(find.text('February expense'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('transaction-dates-Upcoming')));
    await tester.pumpAndSettle();
    expect(find.text('No transactions found'), findsOneWidget);

    changeScope(() => month = DateTime(2024, 2));
    await tester.pumpAndSettle();
    expect(find.text('February expense'), findsOneWidget);
    expect(find.text('January expense'), findsNothing);
    expect(
      tester
          .widget<ChoiceChip>(
            find.byKey(const ValueKey('transaction-dates-Selected month')),
          )
          .selected,
      isTrue,
    );

    await tester.tap(find.byKey(const ValueKey('transaction-dates-All dates')));
    await tester.pumpAndSettle();
    expect(callbackValues, [null]);
    expect(month, isNull);
    expect(find.text('3 entries'), findsOneWidget);
    expect(find.textContaining('Scheduled previews:'), findsNothing);

    changeScope(() => month = DateTime(2024, 1));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('transaction-dates-Upcoming')));
    await tester.pumpAndSettle();
    changeScope(() => month = null);
    await tester.pumpAndSettle();
    expect(find.text('3 entries'), findsOneWidget);
    expect(
      tester
          .widget<ChoiceChip>(
            find.byKey(const ValueKey('transaction-dates-All dates')),
          )
          .selected,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });
}
