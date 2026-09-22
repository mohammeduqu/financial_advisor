import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:financial_advisor/core/finance_store.dart';
import 'package:financial_advisor/core/receipt.dart';

void main() {
  late FinanceStore store;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = FinanceStore(await SharedPreferences.getInstance());
  });
  test('money parsing is exact and rejects invalid inputs', () {
    expect(parseMoney('0.10'), 10);
    expect(parseMoney('1,234.56'), 123456);
    expect(parseMoney('12.345'), isNull);
    expect(parseMoney('-5'), isNull);
    expect(parseMoney('NaN'), isNull);
    expect(parseMoney('0'), isNull);
  });
  test(
    'receipt parser uses total, not VAT or subtotal and rejects invalid date',
    () {
      final draft = ReceiptDraft.parse(
        'Palm Market\n2026-02-30\nSubtotal 162.17\nVAT 24.33\nTOTAL SAR 186.50',
      );
      expect(draft.cents, 18650);
      expect(draft.date, isNull);
      expect(draft.category, 'Food');
    },
  );
  test('month boundaries, edits and deletion reconcile every total', () async {
    final sep = DateTime(2026, 9);
    await store.saveEntry(
      Entry(
        id: 'a',
        merchant: 'Store',
        cents: 100,
        date: DateTime(2026, 9, 30),
        category: 'Food',
      ),
    );
    await store.saveEntry(
      Entry(
        id: 'b',
        merchant: 'Store',
        cents: 200,
        date: DateTime(2026, 10, 1),
        category: 'Food',
      ),
    );
    expect(store.expensesFor(sep), 100);
    await store.saveEntry(
      Entry(
        id: 'a',
        merchant: 'Store',
        cents: 550,
        date: DateTime(2026, 9, 30),
        category: 'Food',
      ),
    );
    expect(store.categorySpent(sep, 'Food'), 550);
    expect(store.expensesFor(sep), 550);
    await store.deleteEntry('a');
    expect(store.expensesFor(sep), 0);
    expect(store.expensesFor(DateTime(2026, 10)), 200);
  });
  test('idempotent save and duplicate warning protect receipts', () async {
    final e = Entry(
      id: 'receipt',
      merchant: 'Palm',
      cents: 18650,
      date: DateTime(2026, 9, 6),
      category: 'Food',
      receipt: 'same image',
    );
    await store.saveEntry(e);
    await store.saveEntry(e);
    expect(store.entries.length, 1);
    expect(
      store.isDuplicate(
        Entry(
          id: 'other',
          merchant: 'Palm',
          cents: 18650,
          date: DateTime(2026, 9, 6),
          category: 'Food',
        ),
      ),
      isTrue,
    );
  });
  test(
    'sample budgets reconcile and goal contributions never affect expenses',
    () async {
      store.seed();
      final month = DateTime.now();
      expect(store.expensesFor(month), 775000);
      expect(store.incomeFor(month), 1200000);
      expect(store.budgetFor(month), 1000000);
      await store.contribute(store.goals.first, 12000);
      expect(store.goals.first.saved, 912000);
      expect(store.expensesFor(month), 775000);
    },
  );
  test(
    'persistence reloads entries, goals, budgets and account settings',
    () async {
      await store.start(
        userName: 'Test',
        selectedCurrency: 'SAR',
        useDemo: true,
      );
      await store.setLanguage('ar');
      await store.setBudget(DateTime.now(), 'Overall', 1100000);
      final restored = FinanceStore(store.prefs);
      await restored.load();
      expect(restored.entries.length, 7);
      expect(restored.goals.length, 2);
      expect(restored.name, 'Test');
      expect(restored.currency, 'SAR');
      expect(restored.languageCode, 'ar');
      expect(restored.onboarded, isTrue);
      expect(restored.demo, isTrue);
      expect(restored.budgetFor(DateTime.now()), 1100000);
      final saved = jsonDecode(store.prefs.getString('numo_v1')!) as Map;
      expect(saved.containsKey('saved'), isFalse);
    },
  );
  for (final obsoleteSaved in [
    ['global', 'sukuk'],
    {'retiredFormat': true},
  ]) {
    test(
      'legacy investment field ${obsoleteSaved.runtimeType} is ignored without losing financial records',
      () async {
        final month = DateTime(2026, 9);
        final legacy = {
          'version': 1,
          'language': 'ar',
          'entries': [
            Entry(
              id: 'income',
              merchant: 'Salary',
              cents: 900000,
              date: month,
              category: 'Income',
              income: true,
              note: 'Monthly pay',
            ).toJson(),
            Entry(
              id: 'expense',
              merchant: 'Grocer',
              cents: 18650,
              date: DateTime(2026, 9, 2),
              category: 'Food',
              note: 'Weekly groceries',
              receipt: 'existing receipt',
            ).toJson(),
          ],
          'goals': [
            Goal(
              id: 'emergency',
              name: 'Emergency fund',
              target: 300000,
              contributions: [Contribution('deposit', 25000, month)],
            ).toJson(),
          ],
          'budgets': {
            '2026-09': {'Overall': 500000, 'Food': 75000},
          },
          'saved': obsoleteSaved,
          'name': 'Amina',
          'currency': 'SAR',
          'onboarded': true,
          'demo': false,
        };
        final raw = jsonEncode(legacy);
        await store.prefs.setString('numo_v1', raw);
        await store.load();

        expect(store.error, isNull);
        expect(store.prefs.getString('numo_v1'), raw);
        expect(store.incomeFor(month), 900000);
        expect(store.expensesFor(month), 18650);
        expect(store.goals.single.saved, 25000);
        expect(store.budgetFor(month, 'Food'), 75000);
        expect(store.entries.last.receipt, 'existing receipt');
        expect(store.entries.last.note, 'Weekly groceries');
        expect(store.languageCode, 'ar');

        await store.persist();
        final migrated = jsonDecode(store.prefs.getString('numo_v1')!) as Map;
        final expected = Map<String, dynamic>.from(legacy)..remove('saved');
        expect(migrated, expected);

        final restored = FinanceStore(store.prefs);
        await restored.load();
        expect(restored.error, isNull);
        expect(restored.incomeFor(month), 900000);
        expect(restored.expensesFor(month), 18650);
        expect(restored.goals.single.saved, 25000);
        expect(restored.budgetFor(month), 500000);
        expect(restored.name, 'Amina');
        expect(restored.onboarded, isTrue);
        expect(restored.demo, isFalse);
      },
    );
  }
  test(
    'corrupt local data is preserved rather than silently replaced',
    () async {
      await store.prefs.setString('numo_v1', '{broken');
      await store.load();
      expect(store.error, isNotNull);
      await store.persist();
      expect(store.prefs.getString('numo_v1'), '{broken');
    },
  );
}
