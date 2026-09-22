import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:financial_advisor/core/finance_store.dart';
import 'package:financial_advisor/core/invoice.dart';
import 'package:financial_advisor/main.dart';
import 'package:financial_advisor/screens/invoice_review.dart';
import 'package:financial_advisor/screens/transactions.dart';

void main() {
  testWidgets(
    'review edits and persists all items; reopening preserves totals',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final store = FinanceStore(await SharedPreferences.getInstance());
      await store.start(
        userName: 'Alex',
        selectedCurrency: 'SAR',
        useDemo: false,
      );
      await store.setLanguage('en');
      await tester.pumpWidget(TadbeerApp(store: store));
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(AppShell));
      final reviewResult = Navigator.push<InvoiceReviewResult>(
        context,
        MaterialPageRoute(
          builder:
              (_) => InvoiceReviewScreen(
                store: store,
                invoice: InvoiceModel(
                  merchantName: 'Review Store',
                  date: DateTime.now(),
                  currency: 'SAR',
                  subtotal: 100,
                  tax: 15,
                  discount: 0,
                  total: 115,
                  category: 'Shopping',
                  items: const [
                    InvoiceItemModel(
                      name: 'Coffee',
                      brand: 'Acme',
                      model: 'Dark',
                      variant: 'Beans',
                      sizeValue: 250,
                      sizeUnit: 'g',
                      packSize: 1,
                      condition: 'new',
                      confidence: .91,
                      searchQuery: 'Acme Dark Beans 250g',
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
                ),
              ),
        ),
      );
      await tester.pumpAndSettle();
      final merchant = find.byWidgetPredicate(
        (w) => w is TextFormField && w.controller?.text == 'Review Store',
      );
      await tester.enterText(merchant, 'Corrected Store');
      final dateField = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Date (YYYY-MM-DD)',
      );
      final scrollable =
          find
              .descendant(
                of: find.byType(InvoiceReviewScreen),
                matching: find.byType(Scrollable),
              )
              .first;
      await tester.scrollUntilVisible(dateField, 200, scrollable: scrollable);
      await tester.enterText(dateField, '2024-03-25');
      await tester.scrollUntilVisible(
        find.byKey(const Key('add-invoice-expense')),
        500,
        scrollable:
            find
                .descendant(
                  of: find.byType(InvoiceReviewScreen),
                  matching: find.byType(Scrollable),
                )
                .first,
      );
      await tester.tap(find.byKey(const Key('add-invoice-expense')));
      await tester.pumpAndSettle();
      final result = await reviewResult;
      expect(result?.action, InvoiceReviewAction.saved);
      expect(result?.entry, same(store.entries.single));
      expect(store.entries.length, 1);
      expect(store.entries.single.merchant, 'Corrected Store');
      expect(store.entries.single.cents, 11500);
      expect(store.entries.single.invoice!.items.length, 2);
      expect(result?.entry?.date, DateTime(2024, 3, 25));
      expect(store.expensesFor(DateTime(2024, 3)), 11500);
      final reloaded = FinanceStore(store.prefs);
      await reloaded.load();
      expect(reloaded.entries.single.invoice!.items.first.quantity, 2);
      expect(reloaded.entries.single.invoice!.items.first.brand, 'Acme');
      expect(reloaded.entries.single.invoice!.items.first.sizeValue, 250);
      expect(reloaded.entries.single.invoice!.items.first.packSize, 1);
      expect(
        reloaded.entries.single.invoice!.items.first.searchQuery,
        'Acme Dark Beans 250g',
      );
      editEntry(
        tester.element(find.byType(AppShell)),
        store,
        entry: store.entries.single,
      );
      await tester.pumpAndSettle();
      expect(find.byType(InvoiceReviewScreen), findsOneWidget);
      expect(find.text('Review invoice'), findsOneWidget);
      await tester.scrollUntilVisible(dateField, 200, scrollable: scrollable);
      expect(
        tester.widget<TextField>(dateField).controller!.text,
        '2024-03-25',
      );
      expect(tester.takeException(), isNull);
    },
  );
}
