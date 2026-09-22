import 'package:financial_advisor/core/finance_store.dart';
import 'package:financial_advisor/core/invoice.dart';
import 'package:financial_advisor/l10n/app_language.dart';
import 'package:financial_advisor/screens/invoice_review.dart';
import 'package:financial_advisor/screens/plan.dart';
import 'package:financial_advisor/screens/transactions.dart';
import 'package:financial_advisor/widgets/design.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

final month = DateTime(2024, 3);

Entry expense(
  String id, {
  String category = 'Food',
  int cents = 1575,
  int day = 15,
  bool income = false,
  DateTime? date,
  InvoiceModel? invoice,
}) => Entry(
  id: id,
  merchant: id,
  cents: cents,
  category: category,
  income: income,
  date: date ?? DateTime(2024, 3, day),
  invoice: invoice,
);

Future<FinanceStore> makeStore(List<Entry> entries) async {
  SharedPreferences.setMockInitialValues({});
  final store = FinanceStore(await SharedPreferences.getInstance());
  store.entries = entries;
  await store.persist();
  return store;
}

Future<void> pumpAnalysis(
  WidgetTester tester,
  FinanceStore store, {
  Locale locale = const Locale('en'),
  double width = 390,
}) async {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: appTheme(),
      locale: locale,
      supportedLocales: const [Locale('en'), Locale('ar')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: Scaffold(body: PlanPage(store: store, month: month)),
    ),
  );
  await tester.pumpAndSettle();
}

Finder categoryTile(String category) =>
    find.byKey(PageStorageKey('category-budget-${monthKey(month)}-$category'));

Finder expenseTile(String id) => find.byKey(ValueKey('category-expense-$id'));

Finder pageScroll(Type page) =>
    find
        .descendant(of: find.byType(page), matching: find.byType(Scrollable))
        .first;

Future<void> expandCategory(
  WidgetTester tester,
  String category, {
  String language = 'en',
}) async {
  final tile = categoryTile(category);
  await tester.scrollUntilVisible(tile, 200, scrollable: pageScroll(PlanPage));
  final title = find.descendant(
    of: tile,
    matching: find.text(translate(category, language)),
  );
  await tester.ensureVisible(title.first);
  await tester.tap(title.first);
  await tester.pumpAndSettle();
}

Future<void> openExpense(WidgetTester tester, String id) async {
  await tester.scrollUntilVisible(
    expenseTile(id),
    150,
    scrollable: pageScroll(PlanPage),
  );
  await tester.tap(expenseTile(id));
  await tester.pumpAndSettle();
}

Future<void> saveEntry(WidgetTester tester) async {
  final save = find.byKey(const Key('save-entry'));
  await tester.scrollUntilVisible(
    save,
    200,
    scrollable: pageScroll(EntryEditor),
  );
  await tester.tap(save);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('category expansion filters expenses and orders newest first', (
    tester,
  ) async {
    final store = await makeStore([
      expense('Earlier meal', cents: 1225, day: 2),
      expense('Newest meal', day: 20),
      expense('Taxi', category: 'Transportation'),
      expense('Food refund income', income: true),
      expense('Previous month meal', date: DateTime(2024, 2, 28)),
      expense('Next month meal', date: DateTime(2024, 4, 1)),
    ]);
    await pumpAnalysis(tester, store);
    expect(find.byType(EntryTile), findsNothing);
    await expandCategory(tester, 'Food');

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byTooltip('Edit Food budget'), findsNothing);
    expect(expenseTile('Earlier meal'), findsOneWidget);
    expect(expenseTile('Newest meal'), findsOneWidget);
    expect(expenseTile('Taxi'), findsNothing);
    expect(expenseTile('Food refund income'), findsNothing);
    expect(expenseTile('Previous month meal'), findsNothing);
    expect(expenseTile('Next month meal'), findsNothing);
    expect(
      tester.getTopLeft(expenseTile('Newest meal')).dy,
      lessThan(tester.getTopLeft(expenseTile('Earlier meal')).dy),
    );
    expect(
      find.descendant(
        of: categoryTile('Food'),
        matching: find.text('28.00 / not set'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('editing expense amount and category refreshes and persists', (
    tester,
  ) async {
    final store = await makeStore([expense('Lunch')]);
    await pumpAnalysis(tester, store);
    await expandCategory(tester, 'Food');
    await openExpense(tester, 'Lunch');
    expect(find.byType(EntryEditor), findsOneWidget);
    final amount = find.byWidgetPredicate(
      (widget) => widget is TextFormField && widget.controller?.text == '15.75',
    );
    await tester.enterText(amount, '25.50');
    final category = find.byType(DropdownButtonFormField<String>);
    await tester.scrollUntilVisible(
      category,
      150,
      scrollable: pageScroll(EntryEditor),
    );
    await tester.tap(category);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Transportation').last);
    await tester.pumpAndSettle();
    await saveEntry(tester);

    expect(find.byType(EntryEditor), findsNothing);
    expect(store.categorySpent(month, 'Food'), 0);
    expect(store.categorySpent(month, 'Transportation'), 2550);
    expect(
      find.descendant(of: categoryTile('Food'), matching: expenseTile('Lunch')),
      findsNothing,
    );
    expect(
      find.text('No expenses in this category this month.'),
      findsOneWidget,
    );
    await expandCategory(tester, 'Transportation');
    expect(expenseTile('Lunch'), findsOneWidget);
    expect(find.text('−25.50'), findsOneWidget);
    final restored = FinanceStore(store.prefs);
    await restored.load();
    expect(restored.entries.single.id, 'Lunch');
    expect(restored.entries.single.category, 'Transportation');
    expect(restored.entries.single.cents, 2550);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'deleting an expanded expense updates totals and keeps its budget',
    (tester) async {
      final store = await makeStore([expense('Coffee')]);
      await store.setBudget(month, 'Food', 5000);
      await pumpAnalysis(tester, store);
      await expandCategory(tester, 'Food');
      await openExpense(tester, 'Coffee');
      await tester.tap(find.byTooltip('Delete transaction'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(find.byType(EntryEditor), findsNothing);
      expect(expenseTile('Coffee'), findsNothing);
      expect(
        find.text('No expenses in this category this month.'),
        findsOneWidget,
      );
      expect(find.text('0.00 / 50.00'), findsOneWidget);
      expect(store.budgetFor(month, 'Food'), 5000);
      final restored = FinanceStore(store.prefs);
      await restored.load();
      expect(restored.entries, isEmpty);
      expect(restored.budgetFor(month, 'Food'), 5000);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'empty Arabic category expands without overflow on a narrow phone',
    (tester) async {
      final store = await makeStore([]);
      await pumpAnalysis(tester, store, locale: const Locale('ar'), width: 320);
      await expandCategory(tester, 'Food', language: 'ar');
      expect(
        Directionality.of(tester.element(categoryTile('Food'))),
        TextDirection.rtl,
      );
      expect(
        find.text(translate('No expenses in this category this month.', 'ar')),
        findsOneWidget,
      );
      expect(find.byType(EntryTile), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('invoice expense opens its existing review and saves in place', (
    tester,
  ) async {
    const invoice = InvoiceModel(
      merchantName: 'Invoice market',
      currency: 'SAR',
      total: 15.75,
      category: 'Food',
    );
    final store = await makeStore([
      expense('Invoice market', invoice: invoice),
    ]);
    await pumpAnalysis(tester, store);
    await expandCategory(tester, 'Food');
    await openExpense(tester, 'Invoice market');
    expect(find.byType(InvoiceReviewScreen), findsOneWidget);
    expect(find.byType(EntryEditor), findsNothing);
    final merchant = find.byWidgetPredicate(
      (widget) =>
          widget is TextFormField &&
          widget.controller?.text == 'Invoice market',
    );
    await tester.enterText(merchant, 'Corrected market');
    final save = find.byKey(const Key('add-invoice-expense'));
    await tester.scrollUntilVisible(
      save,
      400,
      scrollable: pageScroll(InvoiceReviewScreen),
    );
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(find.byType(InvoiceReviewScreen), findsNothing);
    expect(find.text('Corrected market'), findsOneWidget);
    expect(store.entries, hasLength(1));
    expect(store.entries.single.id, 'Invoice market');
    expect(store.entries.single.invoice?.merchantName, 'Corrected market');
    expect(store.entries.single.date, DateTime(2024, 3, 15));
    expect(tester.takeException(), isNull);
  });
}
