import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:financial_advisor/core/finance_store.dart';
import 'package:financial_advisor/core/invoice.dart';
import 'package:financial_advisor/main.dart';
import 'package:financial_advisor/screens/invoice_review.dart';

Finder reviewScrollable() =>
    find
        .descendant(
          of: find.byType(InvoiceReviewScreen),
          matching: find.byType(Scrollable),
        )
        .first;

Finder invoiceField(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

Future<FinanceStore> openInvoice(
  WidgetTester tester,
  InvoiceModel invoice,
) async {
  SharedPreferences.setMockInitialValues({});
  final store = FinanceStore(await SharedPreferences.getInstance());
  await store.start(userName: 'Alex', selectedCurrency: 'SAR', useDemo: false);
  await store.setLanguage('en');
  await tester.pumpWidget(TadbeerApp(store: store));
  await tester.pumpAndSettle();
  Navigator.push(
    tester.element(find.byType(AppShell)),
    MaterialPageRoute(
      builder: (_) => InvoiceReviewScreen(store: store, invoice: invoice),
    ),
  );
  await tester.pumpAndSettle();
  return store;
}

Future<void> pressAddExpense(WidgetTester tester) async {
  final button = find.byKey(const Key('add-invoice-expense'));
  await tester.scrollUntilVisible(button, 400, scrollable: reviewScrollable());
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  for (final extractedDate in [null, DateTime(2024, 3, 25)]) {
    testWidgets(
      'new invoice defaults to today with extracted date $extractedDate',
      (tester) async {
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final store = await openInvoice(
          tester,
          InvoiceModel(
            merchantName: 'Today Receipt',
            date: extractedDate,
            currency: 'SAR',
            total: 25,
            category: 'Shopping',
          ),
        );
        final date = invoiceField('Date (YYYY-MM-DD)');
        await tester.scrollUntilVisible(
          date,
          200,
          scrollable: reviewScrollable(),
        );
        expect(
          tester.widget<TextField>(date).controller!.text,
          DateFormat('yyyy-MM-dd', 'en').format(today),
        );
        await pressAddExpense(tester);
        expect(store.entries.single.date, today);
        expect(store.entries.single.invoice!.date, today);
        expect(store.expensesFor(today), 2500);
        final restored = FinanceStore(store.prefs);
        await restored.load();
        expect(restored.entries.single.date, today);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('detected currency saves using the selected account currency', (
    tester,
  ) async {
    final store = await openInvoice(
      tester,
      InvoiceModel(
        merchantName: 'Dollar Store',
        date: DateTime(2024, 3, 25),
        currency: 'USD',
        total: 25,
        category: 'Shopping',
      ),
    );
    await pressAddExpense(tester);
    expect(store.entries, hasLength(1));
    expect(store.entries.single.invoice!.currency, 'SAR');
    expect(store.entries.single.invoice!.total, 25);
    expect(store.entries.single.cents, 2500);
    expect(find.byType(InvoiceReviewScreen), findsNothing);
    expect(store.expensesFor(DateTime.now()), 2500);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'clearing the default date prevents saving an incomplete expense',
    (tester) async {
      final store = await openInvoice(
        tester,
        const InvoiceModel(
          merchantName: 'Incomplete Receipt',
          currency: 'SAR',
          total: 25,
          category: 'Shopping',
        ),
      );
      await tester.scrollUntilVisible(
        invoiceField('Date (YYYY-MM-DD)'),
        200,
        scrollable: reviewScrollable(),
      );
      expect(
        tester
            .widget<TextField>(invoiceField('Date (YYYY-MM-DD)'))
            .controller!
            .text,
        DateFormat('yyyy-MM-dd', 'en').format(DateTime.now()),
      );
      await tester.enterText(invoiceField('Date (YYYY-MM-DD)'), '');
      await pressAddExpense(tester);
      expect(store.entries, isEmpty);
      expect(find.byType(InvoiceReviewScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'missing subtotal still requires acknowledgement for mismatched items',
    (tester) async {
      final store = await openInvoice(
        tester,
        InvoiceModel(
          merchantName: 'Mismatched Receipt',
          date: DateTime(2024, 3, 25),
          currency: 'SAR',
          total: 115,
          category: 'Shopping',
          items: const [
            InvoiceItemModel(
              name: 'Notebook',
              quantity: 1,
              unitPrice: 90,
              totalPrice: 90,
              category: 'Shopping',
            ),
          ],
        ),
      );
      await pressAddExpense(tester);
      expect(store.entries, isEmpty);
      expect(
        find.text(
          'Review the amounts and confirm the invoice total before saving.',
        ),
        findsOneWidget,
      );
      final acknowledge = find.descendant(
        of: find.byType(InvoiceReviewScreen),
        matching: find.byType(CheckboxListTile),
      );
      await tester.ensureVisible(acknowledge);
      await tester.tap(acknowledge);
      await tester.pumpAndSettle();
      await pressAddExpense(tester);
      expect(store.entries, hasLength(1));
      expect(store.entries.single.cents, 11500);
      expect(store.entries.single.invoice!.subtotal, isNull);
      expect(store.entries.single.invoice!.items.single.totalPrice, 90);
      expect(store.expensesFor(DateTime.now()), 11500);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'invalid optional tax cannot be lost after scrolling off-screen',
    (tester) async {
      final store = await openInvoice(
        tester,
        InvoiceModel(
          merchantName: 'Long Receipt',
          date: DateTime(2024, 3, 25),
          currency: 'SAR',
          subtotal: 25,
          discount: 0,
          total: 25,
          category: 'Shopping',
          items: List.generate(
            5,
            (index) => InvoiceItemModel(
              name: 'Item ${index + 1}',
              quantity: 1,
              unitPrice: 5,
              totalPrice: 5,
              category: 'Shopping',
            ),
          ),
        ),
      );
      final tax = invoiceField('Tax');
      await tester.scrollUntilVisible(tax, 250, scrollable: reviewScrollable());
      await tester.enterText(tax, 'not a number');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      await pressAddExpense(tester);
      expect(store.entries, isEmpty);
      expect(find.byType(InvoiceReviewScreen), findsOneWidget);
      expect(store.expensesFor(DateTime(2024, 3)), 0);
      expect(tester.takeException(), isNull);
    },
  );
  for (final input in ['٢٠٢٤-٠٣-٢٥', '۲۰۲۴-۰۳-۲۵']) {
    testWidgets('manual date normalizes keyboard digits: $input', (
      tester,
    ) async {
      final store = await openInvoice(
        tester,
        const InvoiceModel(
          merchantName: 'Arabic Receipt',
          currency: 'SAR',
          total: 25,
          category: 'Food',
        ),
      );
      final date = invoiceField('Date (YYYY-MM-DD)');
      await tester.scrollUntilVisible(
        date,
        200,
        scrollable: reviewScrollable(),
      );
      await tester.enterText(date, input);
      await pressAddExpense(tester);
      expect(store.entries, hasLength(1));
      expect(store.entries.single.date, DateTime(2024, 3, 25));
      expect(store.entries.single.invoice!.date, DateTime(2024, 3, 25));
      expect(store.entries.single.invoice!.items, isEmpty);
      expect(store.entries.single.cents, 2500);
      expect(tester.takeException(), isNull);
    });
  }
}
