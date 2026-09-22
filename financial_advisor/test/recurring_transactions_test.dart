import 'dart:async';
import 'dart:convert';

import 'package:financial_advisor/core/finance_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Entry transaction(
  String id,
  DateTime date, {
  bool income = false,
  int cents = 15000,
}) => Entry(
  id: id,
  merchant: income ? 'Salary' : 'Groceries',
  cents: cents,
  date: date,
  category: income ? 'Income' : 'Food',
  income: income,
  note: 'Keep this note',
);

// A controllable persistence boundary exercises real FinanceStore write queues.
class ControlledPreferences implements SharedPreferences {
  final values = <String, Object>{};
  final snapshots = <Map<String, dynamic>>[];
  int failedWrites = 0;
  String? failedRemoveKey;
  bool throwOnRemove = false;
  Completer<void>? nextWriteGate;
  Completer<void>? writeStarted;

  @override
  String? getString(String key) => values[key] as String?;

  @override
  Future<bool> setString(String key, String value) async {
    final gate = nextWriteGate;
    nextWriteGate = null;
    final started = writeStarted;
    writeStarted = null;
    started?.complete();
    if (gate != null) await gate.future;
    if (failedWrites > 0) {
      failedWrites--;
      return false;
    }
    values[key] = value;
    if (key == 'numo_v1') {
      snapshots.add(jsonDecode(value) as Map<String, dynamic>);
    }
    return true;
  }

  @override
  Future<bool> remove(String key) async {
    if (key == failedRemoveKey) {
      if (throwOnRemove) throw StateError('Storage unavailable');
      return false;
    }
    values.remove(key);
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late ControlledPreferences prefs;
  late FinanceStore store;
  setUp(() {
    prefs = ControlledPreferences();
    store = FinanceStore(prefs);
  });

  test(
    'one-time income and expense are recorded once without schedules',
    () async {
      final now = DateTime(2026, 9, 18);
      for (final income in [true, false]) {
        final entry = transaction('once-$income', now, income: income);
        await store.saveScheduledEntry(entry, RepeatFrequency.once, now: now);
        await store.saveScheduledEntry(entry, RepeatFrequency.once, now: now);
      }
      expect(store.entries, hasLength(2));
      expect(store.recurringTransactions, isEmpty);
      expect(store.incomeFor(now), 15000);
      expect(store.expensesFor(now), 15000);
      expect(await store.processRecurringEntries(now: DateTime(2027)), 0);
    },
  );

  for (final income in [true, false]) {
    for (final frequency in [RepeatFrequency.daily, RepeatFrequency.weekly]) {
      test(
        '${frequency.name} ${income ? 'income' : 'expense'} follows calendar dates',
        () async {
          final start = DateTime(2026, 9, 18, 23, 59);
          await store.saveScheduledEntry(
            transaction('routine', start, income: income),
            frequency,
            now: start,
          );
          expect(store.entries.single.date, DateTime(2026, 9, 18));
          expect(store.entries.single.note, 'Keep this note');
          expect(store.entries.single.recurringId, 'routine');
          final day = frequency == RepeatFrequency.daily ? 19 : 25;
          expect(
            store.recurringTransactions.single.nextDate,
            DateTime(2026, 9, day),
          );
          expect(
            await store.processRecurringEntries(
              now: DateTime(2026, 9, day - 1, 23, 59),
            ),
            0,
          );
          expect(
            await store.processRecurringEntries(now: DateTime(2026, 9, day)),
            1,
          );
          expect(store.entries.last.date, DateTime(2026, 9, day));
          expect(
            store.entries.every((entry) => entry.income == income),
            isTrue,
          );
          expect(
            income ? store.incomeFor(start) : store.expensesFor(start),
            30000,
          );
          expect(
            await store.processRecurringEntries(now: DateTime(2026, 9, day)),
            0,
          );
          expect(store.entries, hasLength(2));
        },
      );
    }
  }

  for (final year in [2024, 2025]) {
    test(
      'monthly January 31 handles February $year then returns to March 31',
      () async {
        await store.saveScheduledEntry(
          transaction('monthly', DateTime(year, 1, 31), income: true),
          RepeatFrequency.monthly,
          now: DateTime(year, 3, 31),
        );
        expect(store.entries.map((entry) => entry.date), [
          DateTime(year, 1, 31),
          DateTime(year, 2, year == 2024 ? 29 : 28),
          DateTime(year, 3, 31),
        ]);
        expect(
          store.recurringTransactions.single.nextDate,
          DateTime(year, 4, 30),
        );
        expect(
          await store.processRecurringEntries(now: DateTime(year, 5, 31)),
          2,
        );
        expect(store.entries.last.date, DateTime(year, 5, 31));
        expect(store.incomeFor(DateTime(year, 2)), 15000);
      },
    );
  }

  test('monthly expenses cross years and retain the anchor day', () async {
    await store.saveScheduledEntry(
      transaction('rent', DateTime(2025, 12, 30)),
      RepeatFrequency.monthly,
      now: DateTime(2026, 3, 30),
    );
    expect(store.entries.map((entry) => entry.date), [
      DateTime(2025, 12, 30),
      DateTime(2026, 1, 30),
      DateTime(2026, 2, 28),
      DateTime(2026, 3, 30),
    ]);
    expect(store.expensesFor(DateTime(2026, 2)), 15000);
  });

  test(
    'future start creates only a rule; due date posts the first entry',
    () async {
      await store.saveScheduledEntry(
        transaction('future', DateTime(2026, 10, 1)),
        RepeatFrequency.weekly,
        now: DateTime(2026, 9, 18),
      );
      expect(store.entries, isEmpty);
      expect(store.recurringTransactions.single.nextOccurrence, 0);
      final restored = FinanceStore(prefs);
      await restored.load(now: DateTime(2026, 9, 30));
      expect(restored.entries, isEmpty);
      expect(
        restored.recurringTransactions.single.nextDate,
        DateTime(2026, 10, 1),
      );
      expect(
        await restored.processRecurringEntries(now: DateTime(2026, 10, 1)),
        1,
      );
      expect(restored.entries.single.date, DateTime(2026, 10, 1));
    },
  );

  test(
    'startup catches up missed weeks with original dates exactly once',
    () async {
      await store.saveScheduledEntry(
        transaction('pay', DateTime(2026, 8, 28), income: true),
        RepeatFrequency.weekly,
        now: DateTime(2026, 8, 28),
      );
      final restored = FinanceStore(prefs);
      await restored.load(now: DateTime(2026, 9, 18));
      expect(restored.entries.map((entry) => entry.date), [
        DateTime(2026, 8, 28),
        DateTime(2026, 9, 4),
        DateTime(2026, 9, 11),
        DateTime(2026, 9, 18),
      ]);
      expect(restored.incomeFor(DateTime(2026, 8)), 15000);
      expect(restored.incomeFor(DateTime(2026, 9)), 45000);
      expect(restored.recurringTransactions.single.nextOccurrence, 4);
      final again = FinanceStore(prefs);
      await again.load(now: DateTime(2026, 9, 18));
      expect(again.entries, hasLength(4));
      expect(again.entries.map((entry) => entry.id).toSet(), hasLength(4));
      expect(
        await again.processRecurringEntries(now: DateTime(2026, 9, 18)),
        0,
      );
    },
  );

  test(
    'editing or deleting an occurrence never re-creates it after reload',
    () async {
      final now = DateTime(2026, 9, 18);
      await store.saveScheduledEntry(
        transaction('daily', DateTime(2026, 9, 16)),
        RepeatFrequency.daily,
        now: now,
      );
      final first = store.entries.first;
      final deletedId = store.entries[1].id;
      await store.saveEntry(
        Entry(
          id: first.id,
          merchant: 'Corrected amount',
          cents: 123,
          date: first.date,
          category: first.category,
          recurringId: first.recurringId,
        ),
      );
      await store.deleteEntry(deletedId);
      final restored = FinanceStore(prefs);
      await restored.load(now: now);
      expect(restored.entries, hasLength(2));
      expect(restored.entries.any((entry) => entry.id == deletedId), isFalse);
      expect(
        restored.entries.singleWhere((entry) => entry.id == first.id).cents,
        123,
      );
      expect(
        await restored.processRecurringEntries(now: DateTime(2026, 9, 19)),
        1,
      );
      expect(restored.entries.last.cents, 15000);
      expect(restored.entries.last.merchant, 'Groceries');
    },
  );

  test('stopping a rule leaves its history and survives a restart', () async {
    final now = DateTime(2026, 9, 18);
    await store.saveScheduledEntry(
      transaction('weekly', now),
      RepeatFrequency.weekly,
      now: now,
    );
    await store.stopRecurringTransaction('weekly');
    expect(store.entries, hasLength(1));
    expect(store.recurringTransactions, isEmpty);
    final restored = FinanceStore(prefs);
    await restored.load(now: DateTime(2027));
    expect(restored.entries, hasLength(1));
    expect(restored.recurringTransactions, isEmpty);
    expect(await restored.processRecurringEntries(now: DateTime(2028)), 0);
  });

  test(
    'repeated submission and overlapping catch-up calls are idempotent',
    () async {
      final now = DateTime(2026, 9, 18);
      final entry = transaction('weekly', now);
      await Future.wait([
        store.saveScheduledEntry(entry, RepeatFrequency.weekly, now: now),
        store.saveScheduledEntry(entry, RepeatFrequency.weekly, now: now),
      ]);
      expect(store.entries, hasLength(1));
      expect(store.recurringTransactions, hasLength(1));
      final counts = await Future.wait([
        store.processRecurringEntries(now: DateTime(2026, 10, 2)),
        store.processRecurringEntries(now: DateTime(2026, 10, 2)),
        store.processRecurringEntries(now: DateTime(2026, 10, 2)),
      ]);
      expect(counts.fold(0, (sum, count) => sum + count), 2);
      expect(store.entries, hasLength(3));
      expect(store.recurringTransactions.single.nextOccurrence, 3);
    },
  );

  test(
    'failed write retries both entries and cursor without duplicates',
    () async {
      await store.saveScheduledEntry(
        transaction('weekly', DateTime(2026, 9, 18)),
        RepeatFrequency.weekly,
        now: DateTime(2026, 9, 18),
      );
      prefs.failedWrites = 1;
      expect(
        await store.processRecurringEntries(now: DateTime(2026, 9, 25)),
        1,
      );
      expect(store.error, contains('Changes could not be saved'));
      expect(store.entries, hasLength(2));
      expect(prefs.snapshots.last['entries'], hasLength(1));
      expect(
        prefs.snapshots.last['recurringTransactions'][0]['nextOccurrence'],
        1,
      );
      expect(
        await store.processRecurringEntries(now: DateTime(2026, 9, 25)),
        0,
      );
      expect(store.error, isNull);
      expect(prefs.snapshots.last['entries'], hasLength(2));
      expect(
        prefs.snapshots.last['recurringTransactions'][0]['nextOccurrence'],
        2,
      );
      final restored = FinanceStore(prefs);
      await restored.load(now: DateTime(2026, 9, 25));
      expect(restored.entries, hasLength(2));
    },
  );

  test(
    'restart after a failed catch-up replays the same deterministic IDs',
    () async {
      await store.saveScheduledEntry(
        transaction('weekly', DateTime(2026, 9, 18)),
        RepeatFrequency.weekly,
        now: DateTime(2026, 9, 18),
      );
      prefs.failedWrites = 1;
      await store.processRecurringEntries(now: DateTime(2026, 10, 2));
      final expectedIds = store.entries.map((entry) => entry.id).toList();
      final restored = FinanceStore(prefs);
      await restored.load(now: DateTime(2026, 10, 2));
      expect(restored.entries.map((entry) => entry.id), expectedIds);
      expect(restored.error, isNull);
    },
  );

  test(
    'a pending recurrence write cannot overwrite a later edited entry',
    () async {
      await store.saveScheduledEntry(
        transaction('daily', DateTime(2026, 9, 18)),
        RepeatFrequency.daily,
        now: DateTime(2026, 9, 18),
      );
      final gate = Completer<void>();
      final started = Completer<void>();
      prefs.nextWriteGate = gate;
      prefs.writeStarted = started;
      final processing = store.processRecurringEntries(
        now: DateTime(2026, 9, 19),
      );
      await started.future;
      final occurrence = store.entries.last;
      final editing = store.saveEntry(
        Entry(
          id: occurrence.id,
          merchant: 'Edited during save',
          cents: 555,
          date: occurrence.date,
          category: occurrence.category,
          recurringId: occurrence.recurringId,
        ),
      );
      gate.complete();
      await Future.wait([processing, editing]);
      final restored = FinanceStore(prefs);
      await restored.load(now: DateTime(2026, 9, 19));
      expect(restored.entries.last.cents, 555);
      expect(restored.entries.last.merchant, 'Edited during save');
      expect(restored.recurringTransactions.single.nextOccurrence, 2);
    },
  );

  test(
    'clear during a pending write blocks subsequent recurring processors',
    () async {
      await store.saveScheduledEntry(
        transaction('daily', DateTime(2026, 9, 18)),
        RepeatFrequency.daily,
        now: DateTime(2026, 9, 18),
      );
      final gate = Completer<void>();
      final started = Completer<void>();
      prefs.nextWriteGate = gate;
      prefs.writeStarted = started;
      final processing = store.processRecurringEntries(
        now: DateTime(2026, 9, 19),
      );
      await started.future;
      final clearing = store.clear();
      expect(
        await store.processRecurringEntries(now: DateTime(2026, 9, 20)),
        0,
      );
      gate.complete();
      await Future.wait([processing, clearing]);
      expect(prefs.getString('numo_v1'), isNull);
      expect(store.entries, isEmpty);
      expect(store.recurringTransactions, isEmpty);
      expect(
        await store.processRecurringEntries(now: DateTime(2026, 9, 21)),
        0,
      );
      expect(prefs.getString('numo_v1'), isNull);
    },
  );

  for (final throws in [false, true]) {
    test(
      'failed clear (throws: $throws) retains rules and history for retry',
      () async {
        await store.saveScheduledEntry(
          transaction('daily', DateTime(2026, 9, 18)),
          RepeatFrequency.daily,
          now: DateTime(2026, 9, 18),
        );
        final raw = prefs.getString('numo_v1');
        prefs.failedRemoveKey = 'numo_v1';
        prefs.throwOnRemove = throws;
        await store.clear();
        expect(
          store.error,
          'Saved data could not be cleared. Try clearing it again.',
        );
        expect(store.entries, hasLength(1));
        expect(store.recurringTransactions, hasLength(1));
        expect(prefs.getString('numo_v1'), raw);
        expect(
          await store.processRecurringEntries(now: DateTime(2026, 9, 19)),
          0,
        );
        expect(prefs.getString('numo_v1'), raw);
        prefs.failedRemoveKey = null;
        await store.clear();
        expect(store.entries, isEmpty);
        expect(store.recurringTransactions, isEmpty);
        expect(prefs.getString('numo_v1'), isNull);
        expect(store.error, isNull);
      },
    );
  }

  test('failed clear cannot unlock overwriting corrupt saved data', () async {
    prefs.values['numo_v1'] = '{broken';
    await store.load();
    expect(store.error, startsWith('Saved data'));
    prefs.failedRemoveKey = 'numo_v1';
    await store.clear();
    expect(store.error, startsWith('Saved data'));
    await store.persist();
    expect(await store.processRecurringEntries(now: DateTime(2026, 9, 19)), 0);
    expect(prefs.getString('numo_v1'), '{broken');
  });

  test(
    'invalid schedule data does not overwrite valid financial records',
    () async {
      await store.saveEntry(transaction('existing', DateTime(2026, 9, 18)));
      final json =
          jsonDecode(prefs.getString('numo_v1')!) as Map<String, dynamic>;
      json['recurringTransactions'] = [
        {
          'id': 'invalid',
          'merchant': 'Bad rule',
          'cents': 500,
          'category': 'Food',
          'income': false,
          'startDate': '2026-09-18',
          'frequency': 'daily',
          'nextOccurrence': -1,
        },
      ];
      final raw = jsonEncode(json);
      prefs.values['numo_v1'] = raw;
      final restored = FinanceStore(prefs);
      await restored.load(now: DateTime(2026, 9, 20));
      expect(restored.error, startsWith('Saved data'));
      expect(
        await restored.processRecurringEntries(now: DateTime(2026, 9, 21)),
        0,
      );
      await restored.persist();
      expect(prefs.getString('numo_v1'), raw);
    },
  );
}
