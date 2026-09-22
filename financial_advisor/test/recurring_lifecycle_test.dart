import 'package:financial_advisor/core/finance_store.dart';
import 'package:financial_advisor/widgets/recurring_entry_scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ClockStore extends FinanceStore {
  DateTime clock;
  _ClockStore(super.prefs, this.clock);

  @override
  Future<int> processRecurringEntries({DateTime? now}) =>
      super.processRecurringEntries(now: now ?? clock);
}

void main() {
  testWidgets(
    'scheduled income catches up on launch, active timer and resume',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final store = _ClockStore(
        await SharedPreferences.getInstance(),
        DateTime(2026, 9, 1),
      );
      await store.saveScheduledEntry(
        Entry(
          id: 'weekly-pay',
          merchant: 'Weekly pay',
          cents: 10000,
          date: store.clock,
          category: 'Income',
          income: true,
        ),
        RepeatFrequency.weekly,
        now: store.clock,
      );
      store.clock = DateTime(2026, 9, 8);
      await tester.pumpWidget(
        RecurringEntryScheduler(store: store, child: const SizedBox()),
      );
      await tester.pump();
      expect(store.entries.length, 2);

      store.clock = DateTime(2026, 9, 15);
      await tester.pump(const Duration(minutes: 1));
      expect(store.entries.length, 3);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      store.clock = DateTime(2026, 9, 29);
      await tester.pump(const Duration(minutes: 2));
      expect(store.entries.length, 3);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(store.entries.map((entry) => entry.date.day), [1, 8, 15, 22, 29]);
      expect(store.incomeFor(store.clock), 50000);
      await tester.pump(const Duration(minutes: 1));
      expect(store.entries.length, 5);

      await tester.pumpWidget(const SizedBox());
      store.clock = DateTime(2026, 10, 6);
      await tester.pump(const Duration(minutes: 2));
      expect(store.entries.length, 5, reason: 'scheduler is disposed');
      expect(tester.takeException(), isNull);
    },
  );
}
