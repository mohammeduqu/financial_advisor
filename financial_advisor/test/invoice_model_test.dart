import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:financial_advisor/core/finance_store.dart';
import 'package:financial_advisor/core/invoice.dart';

InvoiceModel fixture({String currency = 'SAR', double total = 115}) =>
    InvoiceModel(
      merchantName: 'Store',
      date: DateTime(2024, 3, 25),
      currency: currency,
      invoiceNumber: '000123',
      subtotal: 100,
      tax: 15,
      discount: 0,
      total: total,
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

class FailingStore extends FinanceStore {
  FailingStore(super.prefs);
  @override
  Future<void> persist() async {
    error = 'Test write failure';
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('invoice numbers, missing fields and exact total cents round-trip', () {
    final restored = InvoiceModel.fromJson(
      jsonDecode(jsonEncode(fixture().toJson())),
    );
    expect(restored.invoiceNumber, '000123');
    expect(restored.totalCents, 11500);
    expect(restored.items.first.quantity, 2);
    expect(const InvoiceModel(total: 0.29).totalCents, 29);
    expect(const InvoiceModel(total: 1.005).totalCents, isNull);
    expect(const InvoiceModel(total: double.infinity).totalCents, isNull);
    expect(InvoiceModel.fromJson({}).date, isNull);
    expect(InvoiceModel.fromJson({'date': '2026-02-31'}).date, isNull);
    expect(parseInvoiceNumber('١٬٢٣٤٫٥٠'), 1234.5);
    expect(parseInvoiceNumber('NaN'), isNull);
    expect(parseInvoiceNumber('١٬٢٣٫٥٠'), isNull);
  });
  test('legacy entries load without invoice metadata', () {
    final entry = Entry.fromJson({
      'id': 'old',
      'merchant': 'Old',
      'cents': 2500,
      'date': '2024-03-25',
      'category': 'Food',
    });
    expect(entry.invoice, isNull);
    expect(entry.cents, 2500);
  });
  test(
    'invoice remains one expense; items and tax survive reload and edits',
    () async {
      final store = FinanceStore(await SharedPreferences.getInstance());
      await store.saveInvoice(
        fixture(),
        id: 'receipt',
        receipt: 'image',
        note: 'Keep note',
      );
      await store.saveInvoice(
        fixture(),
        id: 'receipt',
        receipt: 'image',
        note: 'Keep note',
      );
      final restored = FinanceStore(store.prefs);
      await restored.load();
      expect(restored.error, isNull);
      expect(restored.entries, hasLength(1));
      expect(restored.entries.single.note, 'Keep note');
      expect(restored.entries.single.invoice!.items, hasLength(2));
      expect(restored.entries.single.invoice!.tax, 15);
      expect(restored.expensesFor(DateTime(2024, 3)), 11500);
      expect(restored.categorySpent(DateTime(2024, 3), 'Shopping'), 11500);
      expect(restored.categorySpent(DateTime(2024, 3), 'Food'), 0);
      expect(
        restored.isDuplicate(
          Entry(
            id: 'second',
            merchant: 'Store',
            cents: 11500,
            date: DateTime(2024, 3, 25),
            category: 'Shopping',
            receipt: 'image',
          ),
        ),
        isTrue,
      );
    },
  );
  test(
    'invalid and foreign-currency totals never enter expense storage',
    () async {
      final store = FinanceStore(await SharedPreferences.getInstance());
      for (final invoice in [
        fixture(currency: 'USD'),
        fixture(total: -1),
        fixture(total: double.nan),
        fixture(total: 1.005),
      ]) {
        await expectLater(
          store.saveInvoice(invoice, id: 'bad'),
          throwsArgumentError,
        );
      }
      expect(store.entries, isEmpty);
    },
  );
  test(
    'failed persistence rolls back added invoice so retry does not duplicate it',
    () async {
      final store = FailingStore(await SharedPreferences.getInstance());
      await store.saveInvoice(fixture(), id: 'failed');
      expect(store.entries, isEmpty);
      expect(store.error, 'Test write failure');
    },
  );
}
