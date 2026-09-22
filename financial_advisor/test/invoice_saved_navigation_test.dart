import 'package:financial_advisor/core/finance_store.dart';
import 'package:financial_advisor/core/invoice.dart';
import 'package:financial_advisor/main.dart';
import 'package:financial_advisor/screens/home.dart';
import 'package:financial_advisor/screens/scan.dart';
import 'package:financial_advisor/screens/transactions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<FinanceStore> createStore(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  final store = FinanceStore(await SharedPreferences.getInstance());
  await store.start(
    userName: 'Invoice tester',
    selectedCurrency: 'SAR',
    useDemo: false,
  );
  await store.setLanguage('en');
  await tester.binding.setSurfaceSize(const Size(430, 932));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  return store;
}

Future<void> openTab(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label)),
  );
  await tester.pumpAndSettle();
}

Future<void> openScanner(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.text('Scan Invoice'),
    300,
    scrollable:
        find
            .descendant(
              of: find.byType(HomePage),
              matching: find.byType(Scrollable),
            )
            .first,
  );
  await tester.tap(find.text('Scan Invoice'));
  await tester.pumpAndSettle();
  expect(find.byType(ScanPage), findsOneWidget);
}

void main() {
  testWidgets(
    'a saved older invoice opens its month in Transactions and clears stale filters',
    (tester) async {
      final store = await createStore(tester);
      final now = DateTime.now();
      final invoiceDate = DateTime(now.year, now.month - 2, 11);
      await store.saveEntry(
        Entry(
          id: 'more-recent-in-same-month',
          merchant: 'Later merchant',
          cents: 5000,
          date: DateTime(invoiceDate.year, invoiceDate.month, 25),
          category: 'Transportation',
        ),
      );
      await tester.pumpWidget(TadbeerApp(store: store));
      await tester.pumpAndSettle();

      await openTab(tester, 'Transactions');
      final transactions = find.byType(TransactionsPage);
      await tester.enterText(
        find.descendant(of: transactions, matching: find.byType(TextField)),
        'does not match the invoice',
      );
      await tester.tap(
        find.descendant(
          of: transactions,
          matching: find.widgetWithText(ChoiceChip, 'Income'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: transactions,
          matching: find.byType(DropdownButtonFormField<String>),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Food').last);
      await tester.pumpAndSettle();

      await openTab(tester, 'Home');
      await openScanner(tester);
      final invoice = InvoiceModel(
        merchantName: 'Saved historical invoice',
        invoiceNumber: 'INV-HISTORICAL',
        date: invoiceDate,
        currency: 'SAR',
        subtotal: 100,
        tax: 15,
        discount: 0,
        total: 115,
        category: 'Shopping',
        items: const [
          InvoiceItemModel(
            name: 'Coffee',
            quantity: 2,
            unitPrice: 20,
            totalPrice: 40,
            category: 'Food',
          ),
          InvoiceItemModel(
            name: 'Notebook',
            quantity: 1,
            unitPrice: 60,
            totalPrice: 60,
            category: 'Shopping',
          ),
        ],
      );
      await store.saveInvoice(invoice, id: 'saved-historical-invoice');
      final saved = store.entries.singleWhere(
        (entry) => entry.id == 'saved-historical-invoice',
      );
      // Complete the actual scanner route with the successfully persisted entry.
      // Extraction and the review form are covered by their dedicated tests.
      Navigator.of(tester.element(find.byType(ScanPage))).pop<Entry>(saved);
      await tester.pumpAndSettle();

      expect(find.byType(ScanPage), findsNothing);
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        1,
      );
      expect(
        tester.widget<TransactionsPage>(transactions).month,
        DateTime(invoiceDate.year, invoiceDate.month),
      );
      expect(
        find.text(DateFormat.yMMMM('en').format(invoiceDate)),
        findsOneWidget,
      );
      final search = tester.widget<EditableText>(
        find.descendant(of: transactions, matching: find.byType(EditableText)),
      );
      expect(search.controller.text, isEmpty);
      expect(
        tester
            .widget<ChoiceChip>(
              find.descendant(
                of: transactions,
                matching: find.widgetWithText(ChoiceChip, 'All'),
              ),
            )
            .selected,
        isTrue,
      );
      expect(
        find.descendant(
          of: transactions,
          matching: find.text('All categories'),
        ),
        findsOneWidget,
      );
      final savedTile = find.byWidgetPredicate(
        (widget) => widget is EntryTile && widget.entry.id == saved.id,
      );
      await tester.scrollUntilVisible(
        savedTile,
        200,
        scrollable:
            find
                .descendant(of: transactions, matching: find.byType(Scrollable))
                .first,
      );
      expect(savedTile, findsOneWidget);
      expect(
        tester.widget<EntryTile>(find.byType(EntryTile).first).entry.id,
        saved.id,
      );
      expect(store.entries.length, 2);
      expect(store.expensesFor(invoiceDate), 16500);

      final restored = FinanceStore(store.prefs);
      await restored.load();
      final restoredInvoice = restored.entries.singleWhere(
        (entry) => entry.id == saved.id,
      );
      expect(restoredInvoice.date, invoiceDate);
      expect(restoredInvoice.cents, 11500);
      expect(restoredInvoice.income, isFalse);
      expect(restoredInvoice.invoice!.invoiceNumber, 'INV-HISTORICAL');
      expect(restoredInvoice.invoice!.items.length, 2);
      expect(restoredInvoice.invoice!.items.first.quantity, 2);
      expect(restoredInvoice.invoice!.items.last.totalPrice, 60);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('canceling the scanner preserves the selected month and Home', (
    tester,
  ) async {
    final store = await createStore(tester);
    await tester.pumpWidget(TadbeerApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Previous month'));
    await tester.pumpAndSettle();
    final now = DateTime.now();
    final selectedMonth = DateTime(now.year, now.month - 1);
    await openScanner(tester);
    Navigator.of(tester.element(find.byType(ScanPage))).pop<Entry>();
    await tester.pumpAndSettle();

    expect(find.byType(ScanPage), findsNothing);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      0,
    );
    expect(
      find.text(DateFormat.yMMMM('en').format(selectedMonth)),
      findsOneWidget,
    );
    expect(store.entries, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
