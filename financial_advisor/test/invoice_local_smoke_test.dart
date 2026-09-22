import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:financial_advisor/core/finance_store.dart';
import 'package:financial_advisor/services/invoice_service.dart';

void main() {
  const enabled = bool.fromEnvironment('RUN_LOCAL_INVOICE_TEST');
  test(
    'real Flutter client → Flask → Qwen → existing expense store',
    () async {
      const path = String.fromEnvironment('INVOICE_TEST_IMAGE');
      expect(
        path,
        isNotEmpty,
        reason: 'Set INVOICE_TEST_IMAGE to the synthetic test receipt.',
      );
      final image = await File(path).readAsBytes();
      final service = InvoiceService(baseUrl: 'http://127.0.0.1:5000');
      final result = await service.analyze(image, 'invoice.png');
      expect(result.invoice.merchantName, 'NUMO TEST STORE');
      expect(result.invoice.totalCents, 11500);
      expect(result.invoice.tax, 15);
      expect(result.invoice.items.length, 2);
      expect(
        result.invoice.items.map((i) => i.name),
        containsAll(['Coffee', 'Notebook']),
      );
      SharedPreferences.setMockInitialValues({});
      final store = FinanceStore(await SharedPreferences.getInstance());
      await store.saveInvoice(result.invoice, id: 'real-invoice-test');
      final restored = FinanceStore(store.prefs);
      await restored.load();
      expect(restored.entries.single.cents, 11500);
      expect(restored.entries.single.invoice!.items.length, 2);
      expect(restored.expensesFor(result.invoice.date!), 11500);
    },
    skip: !enabled,
    timeout: const Timeout(Duration(minutes: 6)),
  );
}
