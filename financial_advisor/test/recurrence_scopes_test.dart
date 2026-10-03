import 'dart:convert';

import 'package:financial_advisor/core/finance_store.dart';
import 'package:financial_advisor/core/invoice.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Entry expense(
  String id,
  DateTime date, {
  int cents = 10000,
  InvoiceModel? invoice,
}) => Entry(
  id: id,
  merchant: 'Groceries',
  cents: cents,
  date: date,
  category: 'Food',
  invoice: invoice,
);

void main() {
  late FinanceStore store;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = FinanceStore(await SharedPreferences.getInstance());
  });

  test(
    'yearly leap dates and interval months keep their original anchor',
    () async {
      await store.saveScheduledEntry(
        expense('leap', DateTime(2024, 2, 29)),
        RepeatFrequency.yearly,
        now: DateTime(2028, 2, 29),
        endDate: DateTime(2028, 2, 29),
      );
      expect(store.entries.map((entry) => entry.date), [
        DateTime(2024, 2, 29),
        DateTime(2025, 2, 28),
        DateTime(2026, 2, 28),
        DateTime(2027, 2, 28),
        DateTime(2028, 2, 29),
      ]);
      expect(await store.processRecurringEntries(now: DateTime(2030)), 0);
      final rule = RecurringTransaction(
        id: 'months',
        merchant: 'Bill',
        cents: 1,
        category: 'Food',
        income: false,
        startDate: DateTime(2024, 12, 31),
        frequency: RepeatFrequency.monthly,
        interval: 2,
      );
      expect(rule.dateForOccurrence(1), DateTime(2025, 2, 28));
      expect(rule.dateForOccurrence(2), DateTime(2025, 4, 30));
      expect(rule.dateForOccurrence(3), DateTime(2025, 6, 30));
      expect(rule.dateForOccurrence(4), DateTime(2025, 8, 31));
    },
  );

  test(
    'bounded previews include future one-time records without posting plans',
    () async {
      final now = DateTime(2024, 1, 1);
      await store.saveScheduledEntry(
        expense('weekly', now),
        RepeatFrequency.weekly,
        interval: 2,
        endDate: DateTime(2024, 3, 31),
        now: now,
      );
      await store.saveEntry(
        expense('future one-time', DateTime(2024, 3, 20), cents: 900),
      );
      final before = store.prefs.getString('numo_v1');
      final range = store.entriesForRange(
        DateTime(2024, 3, 1),
        DateTime(2024, 3, 31),
        now: now,
      );
      expect(range.map((entry) => entry.date), [
        DateTime(2024, 3, 25),
        DateTime(2024, 3, 20),
        DateTime(2024, 3, 11),
      ]);
      expect(range.where((entry) => entry.isProjected), hasLength(2));
      expect(store.entries, hasLength(2));
      expect(store.expensesFor(DateTime(2024, 3)), 900);
      expect(store.prefs.getString('numo_v1'), before);
      expect(
        store.entriesForRange(DateTime(2025), DateTime(2025, 12, 31), now: now),
        isEmpty,
      );
    },
  );

  test(
    'future occurrence override survives posting and leaves parent unchanged',
    () async {
      final now = DateTime(2024, 1, 1);
      await store.saveScheduledEntry(
        expense('monthly', now),
        RepeatFrequency.monthly,
        now: now,
      );
      final february =
          store
              .entriesForRange(
                DateTime(2024, 2),
                DateTime(2024, 2, 29),
                now: now,
              )
              .single;
      await store.updateRecurringEntry(
        february.copyWith(cents: 7500, date: DateTime(2024, 2, 5)),
        scope: RecurringScope.onlyThis,
        now: now,
      );
      expect(store.recurringTransactions.single.cents, 10000);
      final restored = FinanceStore(store.prefs);
      await restored.load(now: DateTime(2024, 3, 2));
      expect(restored.entries, hasLength(3));
      expect(
        restored.entries.singleWhere((entry) => entry.id == february.id).date,
        DateTime(2024, 2, 5),
      );
      expect(
        restored.entries.singleWhere((entry) => entry.id == february.id).cents,
        7500,
      );
      expect(
        restored.entries.where((entry) => entry.date == DateTime(2024, 2, 1)),
        isEmpty,
      );
      expect(restored.entries.last.cents, 10000);
    },
  );

  test(
    'deleting a projected occurrence never recreates it after reload or series edit',
    () async {
      final now = DateTime(2024, 1, 1);
      await store.saveScheduledEntry(
        expense('monthly', now),
        RepeatFrequency.monthly,
        now: now,
      );
      final february =
          store
              .entriesForRange(
                DateTime(2024, 2),
                DateTime(2024, 2, 29),
                now: now,
              )
              .single;
      await store.deleteRecurringEntry(
        february,
        scope: RecurringScope.onlyThis,
        now: now,
      );
      final january = store.entries.single;
      await store.updateRecurringEntry(
        january.copyWith(cents: 20000),
        scope: RecurringScope.all,
        now: now,
      );
      expect(
        store.entriesForRange(
          DateTime(2024, 2),
          DateTime(2024, 2, 29),
          now: now,
        ),
        isEmpty,
      );
      final restored = FinanceStore(store.prefs);
      await restored.load(now: DateTime(2024, 3, 2));
      expect(restored.forMonth(DateTime(2024, 2)), isEmpty);
      expect(restored.forMonth(DateTime(2024, 3)).single.cents, 20000);
    },
  );

  test(
    'this and future edit splits schedule while preserving earlier history and root',
    () async {
      final now = DateTime(2024, 1, 10);
      await store.saveScheduledEntry(
        expense('weekly', DateTime(2024, 1, 1)),
        RepeatFrequency.weekly,
        now: now,
      );
      final selected =
          store
              .entriesForRange(
                DateTime(2024, 1, 15),
                DateTime(2024, 1, 15),
                now: now,
              )
              .single;
      await store.updateRecurringEntry(
        selected.copyWith(cents: 20000, category: 'Housing'),
        scope: RecurringScope.thisAndFuture,
        frequency: RepeatFrequency.monthly,
        endDate: DateTime(2024, 3, 15),
        now: now,
      );
      expect(store.entries.map((entry) => entry.cents), [10000, 10000]);
      final plans = store.entriesForRange(
        DateTime(2024, 1, 11),
        DateTime(2024, 5),
        now: now,
      );
      expect(plans.map((entry) => entry.date), [
        DateTime(2024, 3, 15),
        DateTime(2024, 2, 15),
        DateTime(2024, 1, 15),
      ]);
      expect(
        plans.every(
          (entry) => entry.cents == 20000 && entry.category == 'Housing',
        ),
        isTrue,
      );
      expect(
        plans.every((entry) => entry.parentRecurringTransactionId == 'weekly'),
        isTrue,
      );
      final restored = FinanceStore(store.prefs);
      await restored.load(now: DateTime(2024, 4));
      expect(restored.entries, hasLength(5));
      expect(await restored.processRecurringEntries(now: DateTime(2024, 4)), 0);
      expect(
        restored.entries.every(
          (entry) => entry.parentRecurringTransactionId == 'weekly',
        ),
        isTrue,
      );
    },
  );

  test(
    'all edit changes recorded amounts and future template without duplicating history',
    () async {
      final now = DateTime(2024, 1, 16);
      await store.saveScheduledEntry(
        expense('weekly', DateTime(2024, 1, 1)),
        RepeatFrequency.weekly,
        now: now,
      );
      final originalIds = store.entries.map((entry) => entry.id).toSet();
      await store.updateRecurringEntry(
        store.entries[1].copyWith(cents: 25000, merchant: 'Updated'),
        scope: RecurringScope.all,
        now: now,
      );
      expect(store.entries.map((entry) => entry.id).toSet(), originalIds);
      expect(
        store.entries.every(
          (entry) => entry.cents == 25000 && entry.merchant == 'Updated',
        ),
        isTrue,
      );
      expect(
        store
            .entriesForRange(
              DateTime(2024, 1, 22),
              DateTime(2024, 1, 22),
              now: now,
            )
            .single
            .cents,
        25000,
      );
      final restored = FinanceStore(store.prefs);
      await restored.load(now: DateTime(2024, 1, 22));
      expect(restored.entries, hasLength(4));
    },
  );

  test(
    'stop and delete future preserves past and removes future overrides and previews',
    () async {
      final now = DateTime(2024, 1, 10);
      await store.saveScheduledEntry(
        expense('weekly', DateTime(2024, 1, 1)),
        RepeatFrequency.weekly,
        now: now,
      );
      final future =
          store
              .entriesForRange(
                DateTime(2024, 1, 15),
                DateTime(2024, 1, 15),
                now: now,
              )
              .single;
      await store.updateRecurringEntry(
        future.copyWith(cents: 19000),
        scope: RecurringScope.onlyThis,
        now: now,
      );
      await store.saveEntry(expense('unrelated future', DateTime(2024, 2, 1)));
      await store.deleteRecurringTemplate(
        'weekly',
        scope: RecurringScope.thisAndFuture,
        now: now,
      );
      expect(
        store.entries.where(
          (entry) => entry.parentRecurringTransactionId != null,
        ),
        hasLength(2),
      );
      expect(store.recurringTransactions.single.active, isFalse);
      final futureEntries = store.entriesForRange(
        DateTime(2024, 1, 11),
        DateTime(2025),
        now: now,
      );
      expect(futureEntries.single.id, 'unrelated future');
      final restored = FinanceStore(store.prefs);
      await restored.load(now: DateTime(2025));
      expect(restored.entries, hasLength(3));
      await restored.deleteRecurringTemplate(
        'weekly',
        scope: RecurringScope.all,
        now: now,
      );
      expect(restored.entries.single.id, 'unrelated future');
      expect(restored.recurringTransactions, isEmpty);
    },
  );

  test(
    'this and future deletion starts at selected occurrence instead of today',
    () async {
      final now = DateTime(2024, 1, 1);
      await store.saveScheduledEntry(
        expense('daily', now),
        RepeatFrequency.daily,
        now: now,
      );
      final third =
          store
              .entriesForRange(
                DateTime(2024, 1, 3),
                DateTime(2024, 1, 3),
                now: now,
              )
              .single;
      await store.deleteRecurringEntry(
        third,
        scope: RecurringScope.thisAndFuture,
        now: now,
      );
      expect(
        store
            .entriesForRange(
              DateTime(2024, 1, 2),
              DateTime(2024, 12, 31),
              now: now,
            )
            .single
            .date,
        DateTime(2024, 1, 2),
      );
      await store.processRecurringEntries(now: DateTime(2024, 12, 31));
      expect(store.entries, hasLength(2));
    },
  );

  test(
    'template edits preserve posted history and support converting next repeat to one time',
    () async {
      final now = DateTime(2024, 1, 10);
      await store.saveScheduledEntry(
        expense('weekly', DateTime(2024, 1, 1)),
        RepeatFrequency.weekly,
        now: now,
      );
      final template = store.recurringTransactions.single;
      await store.updateRecurringTemplate(
        template.copyWith(startDate: DateTime(2024, 2, 5), cents: 20000),
        frequency: RepeatFrequency.once,
        now: now,
      );
      expect(
        store.entries
            .where((entry) => entry.date.isBefore(now))
            .map((entry) => entry.cents),
        [10000, 10000],
      );
      final upcoming = store.entriesForRange(
        DateTime(2024, 1, 11),
        DateTime(2025),
        now: now,
      );
      expect(upcoming, hasLength(1));
      expect(upcoming.single.parentRecurringTransactionId, isNull);
      expect(upcoming.single.date, DateTime(2024, 2, 5));
    },
  );

  test(
    'existing invoice can become recurring while its original receipt remains attached',
    () async {
      final now = DateTime(2024, 1, 1);
      final invoice = InvoiceModel(
        merchantName: 'Groceries',
        date: now,
        currency: 'SAR',
        total: 100,
        category: 'Food',
        items: const [
          InvoiceItemModel(name: 'Food', totalPrice: 100, category: 'Food'),
        ],
      );
      final original = expense('invoice', now, invoice: invoice);
      await store.saveEntry(original);
      await store.saveScheduledEntry(
        original,
        RepeatFrequency.monthly,
        now: now,
      );
      expect(store.entries, hasLength(1));
      expect(store.entries.single.parentRecurringTransactionId, 'invoice');
      expect(store.entries.single.invoice?.items.single.name, 'Food');
      await store.processRecurringEntries(now: DateTime(2024, 2, 1));
      expect(store.entries, hasLength(2));
      expect(
        store.entries.where((entry) => entry.invoice != null),
        hasLength(1),
      );
      final selected = store.entries.first;
      await store.updateRecurringEntry(
        selected.copyWith(cents: 12000),
        scope: RecurringScope.all,
        now: DateTime(2024, 2, 2),
      );
      expect(store.entries.first.invoice?.total, 100);
      expect(store.entries.first.cents, 12000);
      expect(
        store.entries.where((entry) => entry.invoice != null),
        hasLength(1),
      );
    },
  );

  test(
    'legacy recurring links migrate without resetting the cursor or resurrecting records',
    () async {
      final now = DateTime(2024, 1, 1);
      await store.saveScheduledEntry(
        expense('legacy', now),
        RepeatFrequency.weekly,
        now: DateTime(2024, 1, 8),
      );
      final raw =
          jsonDecode(store.prefs.getString('numo_v1')!) as Map<String, dynamic>;
      for (final entry in raw['entries'] as List) {
        entry['recurringId'] = entry.remove('parent_recurring_transaction_id');
        entry.remove('recurring_schedule_id');
        entry.remove('recurring_scheduled_date');
      }
      for (final template in raw['recurringTransactions'] as List) {
        for (final key in ['rootId', 'interval', 'endDate', 'active']) {
          template.remove(key);
        }
      }
      (raw['entries'] as List).removeAt(0);
      await store.prefs.setString('numo_v1', jsonEncode(raw));
      final restored = FinanceStore(store.prefs);
      await restored.load(now: DateTime(2024, 1, 15));
      expect(restored.entries, hasLength(2));
      expect(
        restored.entries.every(
          (entry) => entry.parentRecurringTransactionId == 'legacy',
        ),
        isTrue,
      );
      expect(restored.recurringTransactions.single.interval, 1);
      expect(restored.recurringTransactions.single.nextOccurrence, 3);
      await restored.persist();
      final migrated = jsonDecode(store.prefs.getString('numo_v1')!) as Map;
      expect(
        (migrated['entries'] as List).every(
          (entry) =>
              entry.containsKey('parent_recurring_transaction_id') &&
              !entry.containsKey('recurringId'),
        ),
        isTrue,
      );
    },
  );

  test(
    'month-end occurrence and template edits retain their nominal day',
    () async {
      final now = DateTime(2025, 2, 1);
      await store.saveScheduledEntry(
        expense('monthly', DateTime(2025, 1, 31)),
        RepeatFrequency.monthly,
        now: now,
      );
      final february =
          store
              .entriesForRange(
                DateTime(2025, 2),
                DateTime(2025, 2, 28),
                now: now,
              )
              .single;
      await store.updateRecurringEntry(
        february.copyWith(cents: 20000),
        scope: RecurringScope.thisAndFuture,
        now: now,
      );
      expect(
        store
            .entriesForRange(DateTime(2025, 3), DateTime(2025, 3, 31), now: now)
            .single
            .date,
        DateTime(2025, 3, 31),
      );
      final current = store.recurringTransactions.last;
      await store.updateRecurringTemplate(
        current.copyWith(
          startDate: current.nextDate,
          cents: 22000,
          interval: 2,
        ),
        now: now,
      );
      final restored = FinanceStore(store.prefs);
      await restored.load(now: now);
      expect(
        restored
            .entriesForRange(DateTime(2025, 4), DateTime(2025, 4, 30), now: now)
            .single
            .date,
        DateTime(2025, 4, 30),
      );
      expect(
        restored
            .entriesForRange(DateTime(2025, 8), DateTime(2025, 8, 31), now: now)
            .single
            .date,
        DateTime(2025, 8, 31),
      );
    },
  );

  test('yearly leap anchor survives editing its non-leap occurrence', () async {
    final now = DateTime(2025, 1, 1);
    await store.saveScheduledEntry(
      expense('yearly', DateTime(2024, 2, 29)),
      RepeatFrequency.yearly,
      now: now,
    );
    final next =
        store
            .entriesForRange(DateTime(2025, 2), DateTime(2025, 2, 28), now: now)
            .single;
    await store.updateRecurringEntry(
      next.copyWith(cents: 22000),
      scope: RecurringScope.thisAndFuture,
      now: now,
    );
    final restored = FinanceStore(store.prefs);
    await restored.load(now: now);
    expect(
      restored
          .entriesForRange(DateTime(2028, 2), DateTime(2028, 2, 29), now: now)
          .single
          .date,
      DateTime(2028, 2, 29),
    );
  });

  test(
    'backdating next repeat across recorded history fails without changing data',
    () async {
      final now = DateTime(2024, 9, 3);
      await store.saveScheduledEntry(
        expense('daily', DateTime(2024, 9, 1)),
        RepeatFrequency.daily,
        now: now,
      );
      final before = store.prefs.getString('numo_v1');
      final template = store.recurringTransactions.single;
      await expectLater(
        store.updateRecurringTemplate(
          template.copyWith(startDate: DateTime(2024, 9, 2)),
          now: now,
        ),
        throwsArgumentError,
      );
      expect(store.entries, hasLength(3));
      expect(store.recurringTransactions, hasLength(1));
      expect(store.prefs.getString('numo_v1'), before);
    },
  );

  test(
    'profile stores country and currency without changing financial amounts',
    () async {
      final invoice = InvoiceModel(
        merchantName: 'Groceries',
        currency: 'SAR',
        total: 100,
        date: DateTime(2024, 1, 1),
      );
      await store.saveEntry(
        expense('receipt', DateTime(2024, 1, 1), invoice: invoice),
      );
      await store.updateProfile(
        userName: '  Noor  ',
        selectedCurrency: 'usd',
        selectedCountry: 'ae',
      );
      expect(store.name, 'Noor');
      expect(store.currency, 'USD');
      expect(store.countryCode, 'AE');
      expect(store.entries.single.cents, 10000);
      expect(store.entries.single.invoice?.currency, 'USD');
      expect(store.entries.single.invoice?.total, 100);
      final restored = FinanceStore(store.prefs);
      await restored.load();
      expect(restored.countryCode, 'AE');
      expect(restored.currency, 'USD');
      expect(() => restored.setCountry('bad-code'), throwsArgumentError);
      expect(restored.countryCode, 'AE');
    },
  );

  test(
    'future backshift respects retained projected dates and allows gaps',
    () async {
      final now = DateTime(2024, 9, 1);
      await store.saveScheduledEntry(
        expense('weekly', now),
        RepeatFrequency.weekly,
        now: now,
      );
      final selected =
          store
              .entriesForRange(
                DateTime(2024, 9, 29),
                DateTime(2024, 9, 29),
                now: now,
              )
              .single;
      await expectLater(
        store.updateRecurringEntry(
          selected.copyWith(date: DateTime(2024, 9, 15)),
          scope: RecurringScope.thisAndFuture,
          now: now,
        ),
        throwsArgumentError,
      );
      expect(store.recurringTransactions, hasLength(1));
      await store.updateRecurringEntry(
        selected.copyWith(date: DateTime(2024, 9, 25)),
        scope: RecurringScope.thisAndFuture,
        now: now,
      );
      final dates =
          store
              .entriesForRange(
                DateTime(2024, 9, 2),
                DateTime(2024, 10, 2),
                now: now,
              )
              .map((entry) => entry.date)
              .toList();
      expect(dates, [
        DateTime(2024, 10, 2),
        DateTime(2024, 9, 25),
        DateTime(2024, 9, 22),
        DateTime(2024, 9, 15),
        DateTime(2024, 9, 8),
      ]);
      expect(dates.toSet(), hasLength(dates.length));
    },
  );

  for (final future in [false, true]) {
    test(
      'all to one-time does not duplicate a ${future ? 'future' : 'past'} selected occurrence',
      () async {
        final now = DateTime(2024, 1, 10);
        await store.saveScheduledEntry(
          expense('weekly', DateTime(2024, 1, 1)),
          RepeatFrequency.weekly,
          now: now,
        );
        final selected =
            future
                ? store
                    .entriesForRange(
                      DateTime(2024, 1, 15),
                      DateTime(2024, 1, 15),
                      now: now,
                    )
                    .single
                : store.entries.first;
        await store.updateRecurringEntry(
          selected.copyWith(cents: 15000),
          scope: RecurringScope.all,
          frequency: RepeatFrequency.once,
          now: now,
        );
        expect(store.entries, hasLength(future ? 3 : 2));
        expect(
          store.entries.where((entry) => entry.id == selected.id),
          hasLength(1),
        );
        expect(
          store.entries
              .singleWhere((entry) => entry.id == selected.id)
              .parentRecurringTransactionId,
          isNull,
        );
        final after = store.entriesForRange(
          DateTime(2024, 1, 11),
          DateTime(2025),
          now: now,
        );
        expect(after, hasLength(future ? 1 : 0));
        await store.processRecurringEntries(now: DateTime(2025));
        expect(store.entries, hasLength(future ? 3 : 2));
      },
    );
  }

  test('stop and delete future keeps already posted entries today', () async {
    final today = DateTime(2024, 1, 8);
    await store.saveScheduledEntry(
      expense('weekly', DateTime(2024, 1, 1)),
      RepeatFrequency.weekly,
      now: today,
    );
    final future =
        store
            .entriesForRange(
              DateTime(2024, 1, 15),
              DateTime(2024, 1, 15),
              now: today,
            )
            .single;
    await store.updateRecurringEntry(
      future.copyWith(cents: 9000),
      scope: RecurringScope.onlyThis,
      now: today,
    );
    await store.deleteRecurringTemplate(
      'weekly',
      scope: RecurringScope.thisAndFuture,
      now: today,
    );
    expect(store.entries.map((entry) => entry.date), [
      DateTime(2024, 1, 1),
      today,
    ]);
    expect(store.recurringTransactions.single.active, isFalse);
    await store.processRecurringEntries(now: DateTime(2025));
    expect(store.entries, hasLength(2));
  });

  for (final frequency in [RepeatFrequency.monthly, RepeatFrequency.once]) {
    test(
      'all edit to ${frequency.name} preserves already posted occurrences today',
      () async {
        final today = DateTime(2024, 1, 8);
        await store.saveScheduledEntry(
          expense('weekly', DateTime(2024, 1, 1)),
          RepeatFrequency.weekly,
          now: today,
        );
        final originalIds = store.entries.map((entry) => entry.id).toSet();
        final current = store.entries.singleWhere(
          (entry) => entry.date == today,
        );
        await store.updateRecurringEntry(
          current.copyWith(cents: 15000),
          scope: RecurringScope.all,
          frequency: frequency,
          now: today,
        );
        expect(store.entries.map((entry) => entry.id).toSet(), originalIds);
        expect(store.entries.map((entry) => entry.date), [
          DateTime(2024, 1, 1),
          today,
        ]);
        expect(store.expensesFor(today), 30000);
        expect(await store.processRecurringEntries(now: today), 0);
        final restored = FinanceStore(store.prefs);
        await restored.load(now: today);
        expect(restored.entries, hasLength(2));
        expect(
          await restored.processRecurringEntries(now: DateTime(2024, 2, 1)),
          frequency == RepeatFrequency.monthly ? 1 : 0,
        );
        expect(
          restored.entries,
          hasLength(frequency == RepeatFrequency.monthly ? 3 : 2),
        );
        expect(
          await restored.processRecurringEntries(now: DateTime(2024, 2, 1)),
          0,
        );
        expect(
          restored.entries.where((entry) => entry.date == today),
          hasLength(1),
        );
      },
    );
  }

  for (final future in [false, true]) {
    test(
      'only this one-time override persists for ${future ? 'future' : 'past'} and keeps other repeats',
      () async {
        final now = DateTime(2024, 1, 8);
        await store.saveScheduledEntry(
          expense('weekly', DateTime(2024, 1, 1)),
          RepeatFrequency.weekly,
          now: now,
        );
        final selected =
            future
                ? store
                    .entriesForRange(
                      DateTime(2024, 1, 15),
                      DateTime(2024, 1, 15),
                      now: now,
                    )
                    .single
                : store.entries.first;
        await store.updateRecurringEntry(
          selected,
          scope: RecurringScope.onlyThis,
          frequency: RepeatFrequency.once,
          now: now,
        );
        final restored = FinanceStore(store.prefs);
        await restored.load(now: DateTime(2024, 1, 22));
        final override = restored.entries.singleWhere(
          (entry) => entry.id == selected.id,
        );
        expect(override.recurrenceDisabled, isTrue);
        expect(override.parentRecurringTransactionId, 'weekly');
        expect(restored.recurringTransactions.single.active, isTrue);
        expect(
          restored.recurringTransactions.single.frequency,
          RepeatFrequency.weekly,
        );
        expect(restored.entries, hasLength(4));
        expect(
          restored.entries.where((entry) => entry.recurrenceDisabled),
          hasLength(1),
        );
        await restored.deleteRecurringEntry(
          override,
          scope: RecurringScope.all,
        );
        expect(restored.entries, isEmpty);
        expect(restored.recurringTransactions, isEmpty);
      },
    );
  }

  test(
    'profile name limit counts grapheme clusters and migrates legacy long names',
    () async {
      final hundred = List.filled(100, '👨‍👩‍👧‍👦').join();
      await store.updateProfile(userName: hundred);
      expect(store.name, hundred);
      expect(
        () => store.updateProfile(userName: '${hundred}x'),
        throwsArgumentError,
      );
      expect(() => store.updateProfile(userName: '   '), throwsArgumentError);
      final raw =
          jsonDecode(store.prefs.getString('numo_v1')!) as Map<String, dynamic>;
      raw['name'] = '${hundred}x';
      raw.remove('countryCode');
      await store.prefs.setString('numo_v1', jsonEncode(raw));
      final restored = FinanceStore(store.prefs);
      await restored.load();
      expect(restored.name, hundred);
      expect(restored.countryCode, 'SA');
      expect(restored.error, isNull);
      await expectLater(
        store.start(
          userName: '${hundred}x',
          selectedCurrency: 'USD',
          acceptedLegal: true,
          useDemo: false,
        ),
        throwsArgumentError,
      );
    },
  );
}
