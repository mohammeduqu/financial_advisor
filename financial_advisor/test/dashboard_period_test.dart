import 'package:financial_advisor/core/finance_store.dart';
import 'package:financial_advisor/l10n/app_language.dart';
import 'package:financial_advisor/main.dart';
import 'package:financial_advisor/screens/home.dart';
import 'package:financial_advisor/screens/plan.dart';
import 'package:financial_advisor/screens/transactions.dart';
import 'package:financial_advisor/widgets/finance_charts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late FinanceStore store;
  final year = DateTime.now().year;

  Future<void> seedStore() async {
    SharedPreferences.setMockInitialValues({});
    store = FinanceStore(await SharedPreferences.getInstance());
    await store.start(
      userName: 'Alex',
      selectedCurrency: 'SAR',
      acceptedLegal: true,
      useDemo: false,
    );
    store.entries = [
      Entry(
        id: 'prior-income',
        merchant: 'Previous year income',
        cents: 10000,
        date: DateTime(year - 1, 12, 31),
        category: 'Income',
        income: true,
      ),
      Entry(
        id: 'income',
        merchant: 'January income',
        cents: 20000,
        date: DateTime(year, 1, 1),
        category: 'Income',
        income: true,
      ),
      for (final (id, amount, month, day) in [
        ('First expense', 1000, 1, 2),
        ('Second expense', 2000, 1, 20),
        ('Latest expense', 3000, 2, 2),
      ])
        Entry(
          id: id,
          merchant: id,
          cents: amount,
          date: DateTime(year, month, day),
          category: 'Food',
        ),
    ];
    await store.persist();
  }

  Future<void> launch(
    WidgetTester tester, {
    double width = 390,
    String language = 'en',
  }) async {
    await seedStore();
    await store.setLanguage(language);
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(TadbeerApp(store: store));
    await tester.pumpAndSettle();
  }

  void expectScope(WidgetTester tester, DateTime? month) {
    expect(
      tester.widget<HomePage>(find.byType(HomePage, skipOffstage: false)).month,
      month,
    );
    expect(
      tester
          .widget<TransactionsPage>(
            find.byType(TransactionsPage, skipOffstage: false),
          )
          .month,
      month,
    );
    expect(
      tester.widget<PlanPage>(find.byType(PlanPage, skipOffstage: false)).month,
      month,
    );
  }

  Future<void> navigate(
    WidgetTester tester,
    String label, {
    String language = 'en',
  }) async {
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text(translate(label, language)),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder scrollFor(Type page) =>
      find
          .descendant(of: find.byType(page), matching: find.byType(Scrollable))
          .first;

  Future<void> homeTop(WidgetTester tester) async {
    await navigate(tester, 'Home');
    tester.state<ScrollableState>(scrollFor(HomePage)).position.jumpTo(0);
    await tester.pumpAndSettle();
  }

  Future<void> reveal(WidgetTester tester, Finder finder, Type page) async {
    await tester.scrollUntilVisible(finder, 250, scrollable: scrollFor(page));
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
  }

  Future<void> choose(WidgetTester tester, DateTime month) async {
    var pickerYear =
        (tester
                    .widget<HomePage>(
                      find.byType(HomePage, skipOffstage: false),
                    )
                    .month ??
                DateTime.now())
            .year;
    await tester.tap(find.byKey(const Key('choose-month')));
    await tester.pumpAndSettle();
    while (pickerYear != month.year) {
      final previous = pickerYear > month.year;
      await tester.tap(
        find.byTooltip(previous ? 'Previous year' : 'Next year'),
      );
      await tester.pumpAndSettle();
      pickerYear += previous ? -1 : 1;
    }
    await tester.tap(find.byKey(ValueKey('choose-month-${month.month}')));
    await tester.pumpAndSettle();
  }

  void expectTotals(
    WidgetTester tester, {
    required String income,
    required String expenses,
    required String net,
    required int count,
  }) {
    final home = find.byType(HomePage);
    for (final amount in [income, expenses, net]) {
      expect(
        find.descendant(of: home, matching: find.text(amount)),
        findsWidgets,
      );
    }
    expect(
      tester.widget<Text>(find.byKey(const Key('home-transaction-count'))).data,
      '$count',
    );
  }

  testWidgets('default dashboard totals and latest records span all dates', (
    tester,
  ) async {
    await launch(tester);
    expectScope(tester, null);
    expectTotals(
      tester,
      income: '300.00',
      expenses: '60.00',
      net: '240.00',
      count: 5,
    );
    expect(
      tester
          .widget<IconButton>(
            find.ancestor(
              of: find.byTooltip('Next month'),
              matching: find.byType(IconButton),
            ),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<IconButton>(
            find.ancestor(
              of: find.byTooltip('Previous month'),
              matching: find.byType(IconButton),
            ),
          )
          .onPressed,
      isNull,
    );
    await reveal(tester, find.byType(SpendingTrend), HomePage);
    expect(
      tester.widget<SpendingTrend>(find.byType(SpendingTrend)).month,
      isNull,
    );
    await reveal(tester, find.byType(BudgetDistribution), HomePage);
    expect(
      tester.widget<BudgetDistribution>(find.byType(BudgetDistribution)).month,
      isNull,
    );
    await reveal(tester, find.text('Recent transactions'), HomePage);
    final recent = tester.widgetList<EntryTile>(
      find.descendant(
        of: find.byType(HomePage),
        matching: find.byType(EntryTile),
      ),
    );
    expect(recent.map((tile) => tile.entry.id), [
      'Latest expense',
      'Second expense',
      'First expense',
    ]);
    await navigate(tester, 'Transactions');
    expectScope(tester, null);
    await reveal(
      tester,
      find.byKey(const ValueKey('entry-prior-income')),
      TransactionsPage,
    );
    expect(find.text('Previous year income'), findsOneWidget);
    await navigate(tester, 'Analysis');
    expectScope(tester, null);
    expect(find.text('Total expenses'), findsOneWidget);
    expect(find.text('SAR 60.00'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'month picker filters all views, cancels, and clears to history',
    (tester) async {
      await launch(tester);
      await choose(tester, DateTime(year, 1));
      expectScope(tester, DateTime(year, 1));
      expectTotals(
        tester,
        income: '200.00',
        expenses: '30.00',
        net: '170.00',
        count: 3,
      );
      await reveal(tester, find.byType(SpendingTrend), HomePage);
      expect(
        tester.widget<SpendingTrend>(find.byType(SpendingTrend)).month,
        DateTime(year, 1),
      );
      await reveal(tester, find.byType(BudgetDistribution), HomePage);
      expect(
        tester
            .widget<BudgetDistribution>(find.byType(BudgetDistribution))
            .month,
        DateTime(year, 1),
      );
      expect(find.text('SAR 30.00 spent across categories'), findsOneWidget);
      await navigate(tester, 'Transactions');
      await reveal(
        tester,
        find.byKey(const ValueKey('entry-income')),
        TransactionsPage,
      );
      expect(find.byKey(const ValueKey('entry-prior-income')), findsNothing);
      expect(find.byKey(const ValueKey('entry-Latest expense')), findsNothing);
      await navigate(tester, 'Analysis');
      expect(find.text('SAR 30.00'), findsWidgets);
      expect(find.text('Edit monthly budget →'), findsNothing);
      await tester.tap(find.byKey(const Key('choose-month')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expectScope(tester, DateTime(year, 1));
      await homeTop(tester);
      await choose(tester, DateTime(year, 3));
      expectScope(tester, DateTime(year, 3));
      expectTotals(
        tester,
        income: '0.00',
        expenses: '0.00',
        net: '0.00',
        count: 0,
      );
      await tester.tap(find.byKey(const Key('clear-month-filter')));
      await tester.pumpAndSettle();
      expectScope(tester, null);
      expectTotals(
        tester,
        income: '300.00',
        expenses: '60.00',
        net: '240.00',
        count: 5,
      );
      await choose(tester, DateTime(year - 1, 12));
      expectTotals(
        tester,
        income: '100.00',
        expenses: '0.00',
        net: '100.00',
        count: 1,
      );
      await tester.tap(find.byKey(const Key('choose-month')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('choose-all-dates')));
      await tester.pumpAndSettle();
      expectScope(tester, null);
      expectTotals(
        tester,
        income: '300.00',
        expenses: '60.00',
        net: '240.00',
        count: 5,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('new-month records and lifecycle refresh keep the chosen scope', (
    tester,
  ) async {
    await launch(tester);
    await choose(tester, DateTime(year, 1));
    await store.saveEntry(
      Entry(
        id: 'next-year',
        merchant: 'Next year expense',
        cents: 4000,
        date: DateTime(year + 1, 1, 1),
        category: 'Food',
      ),
    );
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pumpAndSettle();
    expectScope(tester, DateTime(year, 1));
    expectTotals(
      tester,
      income: '200.00',
      expenses: '30.00',
      net: '170.00',
      count: 3,
    );
    await navigate(tester, 'Transactions');
    await tester.tap(find.byKey(const Key('transaction-dates-All dates')));
    await tester.pumpAndSettle();
    expectScope(tester, null);
    await homeTop(tester);
    expectTotals(
      tester,
      income: '300.00',
      expenses: '100.00',
      net: '200.00',
      count: 6,
    );
    await choose(tester, DateTime(year, 1));
    await tester.pumpWidget(const SizedBox());
    store = FinanceStore(store.prefs);
    await store.load();
    await tester.pumpWidget(TadbeerApp(store: store));
    await tester.pumpAndSettle();
    expectScope(tester, null);
    expectTotals(
      tester,
      income: '300.00',
      expenses: '100.00',
      net: '200.00',
      count: 6,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Arabic month controls remain usable on a narrow phone', (
    tester,
  ) async {
    await launch(tester, width: 320, language: 'ar');
    expectScope(tester, null);
    final picker = find.byKey(const Key('choose-month'));
    expect(picker.hitTestable(), findsOneWidget);
    await tester.tap(picker);
    await tester.pumpAndSettle();
    final january = find.byKey(const Key('choose-month-1'));
    expect(january.hitTestable(), findsOneWidget);
    await tester.tap(january);
    await tester.pumpAndSettle();
    expectScope(tester, DateTime(year, 1));
    final clear = find.byKey(const Key('clear-month-filter'));
    expect(clear.hitTestable(), findsOneWidget);
    expect(tester.getRect(clear).right, lessThanOrEqualTo(320));
    expect(tester.getRect(picker).left, greaterThanOrEqualTo(0));
    await tester.tap(clear);
    await tester.pumpAndSettle();
    await navigate(tester, 'Transactions', language: 'ar');
    expectScope(tester, null);
    await navigate(tester, 'Analysis', language: 'ar');
    expect(find.text(translate('Total expenses', 'ar')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
