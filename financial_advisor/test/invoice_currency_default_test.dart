import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:financial_advisor/core/finance_store.dart';
import 'package:financial_advisor/core/invoice.dart';
import 'package:financial_advisor/main.dart';
import 'package:financial_advisor/screens/invoice_review.dart';
import 'package:financial_advisor/screens/recommendation_review.dart';

Finder _reviewScrollable() =>
    find
        .descendant(
          of: find.byType(InvoiceReviewScreen),
          matching: find.byType(Scrollable),
        )
        .first;

Future<FinanceStore> _openInvoice(
  WidgetTester tester, {
  required String accountCurrency,
  String? detectedCurrency,
  String language = 'en',
  List<InvoiceItemModel> items = const [],
}) async {
  await tester.binding.setSurfaceSize(const Size(800, 1800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  SharedPreferences.setMockInitialValues({});
  final store = FinanceStore(await SharedPreferences.getInstance());
  await store.start(
    userName: 'Alex',
    selectedCurrency: accountCurrency,
    useDemo: false,
  );
  await store.setLanguage(language);
  await tester.pumpWidget(TadbeerApp(store: store));
  await tester.pumpAndSettle();
  Navigator.push(
    tester.element(find.byType(AppShell)),
    MaterialPageRoute(
      builder:
          (_) => InvoiceReviewScreen(
            store: store,
            invoice: InvoiceModel(
              merchantName: 'Receipt Store',
              currency: detectedCurrency,
              total: 25.50,
              category: 'Shopping',
              items: items,
            ),
          ),
    ),
  );
  await tester.pumpAndSettle();
  return store;
}

void _expectNoCurrencyInput() {
  expect(
    find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          {'Currency', 'العملة'}.contains(widget.decoration?.labelText),
    ),
    findsNothing,
  );
  for (final phrase in [
    'Leave blank to use your account currency',
    'اترك الحقل فارغاً لاستخدام عملة حسابك',
    'Invoice currency must match your account',
    'يجب أن تطابق عملة الفاتورة عملة حسابك',
    'No currency conversion is performed',
    'لا يُجرى تحويل للعملة',
  ]) {
    expect(find.textContaining(phrase), findsNothing);
  }
}

Future<void> _saveInvoice(WidgetTester tester) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump();
  final button = find.byKey(const Key('add-invoice-expense'));
  await tester.scrollUntilVisible(button, 400, scrollable: _reviewScrollable());
  await tester.tap(button);
  await tester.pumpAndSettle();
}

Future<void> _expectSavedCurrency(
  FinanceStore store,
  String expectedCurrency,
) async {
  expect(store.entries, hasLength(1));
  expect(store.entries.single.cents, 2550);
  expect(store.entries.single.invoice!.currency, expectedCurrency);
  expect(store.entries.single.invoice!.total, 25.50);
  final restored = FinanceStore(store.prefs);
  await restored.load();
  expect(restored.currency, expectedCurrency);
  expect(restored.entries.single.cents, 2550);
  expect(restored.entries.single.invoice!.currency, expectedCurrency);
  expect(restored.entries.single.invoice!.total, 25.50);
}

void main() {
  for (final testCase in [
    (account: 'SAR', detected: null),
    (account: 'USD', detected: ''),
    (account: 'EUR', detected: '   '),
    (account: 'EUR', detected: ' eur '),
    (account: 'SAR', detected: 'USD'),
    (account: 'USD', detected: 'SAR'),
  ]) {
    testWidgets(
      'scan currency ${testCase.detected} saves using account ${testCase.account} without an input',
      (tester) async {
        final store = await _openInvoice(
          tester,
          accountCurrency: testCase.account,
          detectedCurrency: testCase.detected,
        );
        _expectNoCurrencyInput();
        await _saveInvoice(tester);
        expect(find.byType(InvoiceReviewScreen), findsNothing);
        await _expectSavedCurrency(store, testCase.account);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'Arabic review saves with account currency without a currency input',
    (tester) async {
      final store = await _openInvoice(
        tester,
        accountCurrency: 'SAR',
        detectedCurrency: 'USD',
        language: 'ar',
      );
      _expectNoCurrencyInput();
      expect(find.text('اسم التاجر'), findsOneWidget);
      await _saveInvoice(tester);
      expect(find.byType(InvoiceReviewScreen), findsNothing);
      await _expectSavedCurrency(store, 'SAR');
      expect(tester.takeException(), isNull);
    },
  );

  for (final accountCurrency in ['SAR', 'USD']) {
    testWidgets(
      'price comparison carries account currency $accountCurrency instead of scan currency',
      (tester) async {
        final store = await _openInvoice(
          tester,
          accountCurrency: accountCurrency,
          detectedCurrency: 'EUR',
          items: const [
            InvoiceItemModel(
              name: 'Notebook',
              quantity: 1,
              unitPrice: 25.50,
              totalPrice: 25.50,
              category: 'Shopping',
            ),
          ],
        );
        _expectNoCurrencyInput();
        final button = find.byKey(const Key('compare-invoice-prices'));
        await tester.scrollUntilVisible(
          button,
          -300,
          scrollable: _reviewScrollable(),
        );
        await tester.tap(button);
        await tester.pumpAndSettle();
        final review = tester.widget<RecommendationReviewPage>(
          find.byType(RecommendationReviewPage),
        );
        expect(review.review.invoice!.currency, accountCurrency);
        expect(review.review.invoice!.total, 25.50);
        expect(store.entries, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
