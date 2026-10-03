import 'package:financial_advisor/core/finance_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Entry transaction(
  String id,
  DateTime date,
  int cents, {
  bool income = false,
  String category = 'Food',
}) => Entry(
  id: id,
  merchant: id,
  cents: cents,
  date: date,
  category: category,
  income: income,
);

Future<void> saveHistory(FinanceStore store) async {
  for (final entry in [
    transaction('2024 food', DateTime(2024, 1, 31, 23, 59), 3750),
    transaction('2023 income', DateTime(2023, 12, 1), 100000, income: true),
    transaction('2025 food', DateTime(2025, 1, 1), 2500),
    transaction('2024 income', DateTime(2024, 1, 1), 200000, income: true),
    transaction('2023 food', DateTime(2023, 12, 31), 1250),
    transaction('Travel', DateTime(2024, 2, 1), 5000, category: 'Travel'),
  ]) {
    await store.saveEntry(entry);
  }
}

void main() {
  late FinanceStore store;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = FinanceStore(await SharedPreferences.getInstance());
  });

  test(
    'all dates totals and newest records cross month and year boundaries',
    () async {
      await saveHistory(store);
      final originalOrder = store.entries.map((entry) => entry.id).toList();

      expect(store.forPeriod(null).map((entry) => entry.id), [
        '2025 food',
        'Travel',
        '2024 food',
        '2024 income',
        '2023 food',
        '2023 income',
      ]);
      expect(store.incomeFor(null), 300000);
      expect(store.expensesFor(null), 12500);
      expect(store.incomeFor(null) - store.expensesFor(null), 287500);
      expect(store.categorySpent(null, 'Food'), 7500);
      expect(store.categorySpent(null, 'Travel'), 5000);
      expect(store.entries.map((entry) => entry.id), originalOrder);

      final january = DateTime(2024, 1, 17);
      expect(store.forPeriod(january).map((entry) => entry.id), [
        '2024 food',
        '2024 income',
      ]);
      expect(store.incomeFor(january), 200000);
      expect(store.expensesFor(january), 3750);
      expect(store.categorySpent(january, 'Food'), 3750);
      expect(store.forMonth(january), store.forPeriod(january));
      expect(store.expensesFor(DateTime(2023, 12)), 1250);
      expect(store.expensesFor(DateTime(2025, 1)), 2500);
    },
  );

  test('empty history and an empty selected month have zero totals', () async {
    expect(store.forPeriod(null), isEmpty);
    expect(store.incomeFor(null), 0);
    expect(store.expensesFor(null), 0);
    expect(store.categorySpent(null, 'Food'), 0);

    await saveHistory(store);
    final emptyMonth = DateTime(2025, 2);
    expect(store.forPeriod(emptyMonth), isEmpty);
    expect(store.incomeFor(emptyMonth), 0);
    expect(store.expensesFor(emptyMonth), 0);
    expect(store.categorySpent(emptyMonth, 'Food'), 0);
    expect(store.forPeriod(null), hasLength(6));
  });

  test(
    'reloading in a later year retains complete financial history',
    () async {
      await saveHistory(store);
      final restored = FinanceStore(store.prefs);
      await restored.load(now: DateTime(2026, 2, 1));

      expect(restored.error, isNull);
      expect(
        restored.forPeriod(null).map((entry) => entry.id),
        store.forPeriod(null).map((entry) => entry.id),
      );
      expect(restored.incomeFor(null), 300000);
      expect(restored.expensesFor(null), 12500);
      expect(restored.categorySpent(null, 'Food'), 7500);
      expect(restored.forPeriod(DateTime(2026, 2)), isEmpty);
      expect(restored.expensesFor(DateTime(2024, 1)), 3750);
    },
  );

  test(
    'new calendar month adds due records without resetting prior totals',
    () async {
      final december = DateTime(2024, 12, 31);
      for (final entry in [
        transaction('Salary', december, 100000, income: true),
        transaction('Food subscription', december, 1000),
      ]) {
        await store.saveScheduledEntry(
          entry,
          RepeatFrequency.monthly,
          now: december,
        );
      }
      await store.saveEntry(transaction('December snack', december, 250));
      final decemberIds =
          store.forPeriod(december).map((entry) => entry.id).toSet();
      expect(store.incomeFor(null), 100000);
      expect(store.expensesFor(null), 1250);

      final january = DateTime(2025, 1, 31);
      expect(await store.processRecurringEntries(now: january), 2);
      expect(store.forPeriod(null), hasLength(5));
      expect(store.incomeFor(null), 200000);
      expect(store.expensesFor(null), 2250);
      expect(store.categorySpent(null, 'Food'), 2250);
      expect(store.incomeFor(january), 100000);
      expect(store.expensesFor(january), 1000);
      expect(store.incomeFor(december), 100000);
      expect(store.expensesFor(december), 1250);
      expect(
        store.forPeriod(december).map((entry) => entry.id).toSet(),
        decemberIds,
      );
      expect(await store.processRecurringEntries(now: january), 0);
      expect(store.forPeriod(null), hasLength(5));
    },
  );

  test(
    'period totals include saved future records and exclude projections',
    () async {
      final december = DateTime(2024, 12, 31);
      for (final entry in [
        transaction('Salary', december, 100000, income: true),
        transaction('Food subscription', december, 1000),
      ]) {
        await store.saveScheduledEntry(
          entry,
          RepeatFrequency.monthly,
          now: december,
        );
      }
      final january = DateTime(2025, 1);
      await store.saveEntry(
        transaction('Saved future expense', DateTime(2025, 1, 15), 2500),
      );
      final preview = store.entriesForRange(
        january,
        DateTime(2025, 1, 31),
        now: january,
      );
      expect(preview.where((entry) => entry.isProjected), hasLength(2));
      expect(store.forPeriod(null), hasLength(3));
      expect(store.forPeriod(null).any((entry) => entry.isProjected), isFalse);
      expect(store.incomeFor(null), 100000);
      expect(store.expensesFor(null), 3500);
      expect(store.categorySpent(null, 'Food'), 3500);
      expect(store.forPeriod(january).single.id, 'Saved future expense');
      expect(store.incomeFor(january), 0);
      expect(store.expensesFor(january), 2500);

      final restored = FinanceStore(store.prefs);
      await restored.load(now: january);
      expect(restored.forPeriod(null), hasLength(3));
      expect(restored.incomeFor(null), 100000);
      expect(restored.expensesFor(null), 3500);
      expect(
        await restored.processRecurringEntries(now: DateTime(2025, 1, 31)),
        2,
      );
      expect(restored.incomeFor(null), 200000);
      expect(restored.expensesFor(null), 4500);
      expect(restored.incomeFor(january), 100000);
      expect(restored.expensesFor(january), 3500);
    },
  );
}
