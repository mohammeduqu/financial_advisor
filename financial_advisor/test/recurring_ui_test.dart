import 'package:financial_advisor/core/finance_store.dart';
import 'package:financial_advisor/screens/recurring_transactions.dart';
import 'package:financial_advisor/screens/transactions.dart';
import 'package:financial_advisor/widgets/design.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FailFirstWriteStore extends FinanceStore {
  FailFirstWriteStore(super.prefs);
  bool failNextWrite = true;

  @override
  Future<void> persist() async {
    if (failNextWrite) {
      failNextWrite = false;
      error = 'Changes could not be saved. Keep the app open and tap Retry.';
      notifyListeners();
      return;
    }
    await super.persist();
  }
}

Future<FinanceStore> makeStore() async {
  SharedPreferences.setMockInitialValues({});
  return FinanceStore(await SharedPreferences.getInstance());
}

Future<void> pumpTransactions(
  WidgetTester tester,
  FinanceStore store, {
  Locale locale = const Locale('en'),
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: appTheme(),
      locale: locale,
      supportedLocales: const [Locale('en'), Locale('ar')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: Scaffold(
        body: AnimatedBuilder(
          animation: store,
          builder:
              (context, _) =>
                  TransactionsPage(store: store, month: DateTime.now()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> openEditor(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Add transaction'));
  await tester.pumpAndSettle();
}

Future<void> fillEntry(WidgetTester tester, {bool income = false}) async {
  if (income) {
    await tester.tap(
      find.descendant(
        of: find.byType(SegmentedButton<bool>),
        matching: find.text('Income'),
      ),
    );
    await tester.pumpAndSettle();
  }
  final fields = find.descendant(
    of: find.byType(EntryEditor),
    matching: find.byType(TextFormField),
  );
  await tester.enterText(fields.at(0), income ? 'Salary' : 'Rent');
  await tester.enterText(fields.at(1), '125.50');
}

Future<void> chooseFrequency(
  WidgetTester tester,
  RepeatFrequency frequency,
) async {
  await tester.ensureVisible(find.byKey(const Key('entry-repeat')));
  await tester.tap(find.byKey(const Key('entry-repeat')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(frequency.label).last);
  await tester.pumpAndSettle();
}

Future<void> submitEntry(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const Key('save-entry')));
  await tester.tap(find.byKey(const Key('save-entry')));
  await tester.pumpAndSettle();
}

void main() {
  for (final income in [true, false]) {
    for (final frequency in [
      RepeatFrequency.daily,
      RepeatFrequency.weekly,
      RepeatFrequency.monthly,
    ]) {
      testWidgets(
        '${income ? 'income' : 'expense'} creates a ${frequency.name} schedule and first entry',
        (tester) async {
          final store = await makeStore();
          await pumpTransactions(tester, store);
          await openEditor(tester);
          await fillEntry(tester, income: income);
          await chooseFrequency(tester, frequency);
          expect(
            find.text(repeatScheduleExplanation(frequency)),
            findsOneWidget,
          );
          await submitEntry(tester);

          expect(find.byType(EntryEditor), findsNothing);
          expect(store.recurringTransactions, hasLength(1));
          final rule = store.recurringTransactions.single;
          expect(rule.frequency, frequency);
          expect(rule.income, income);
          expect(rule.cents, 12550);
          expect(store.entries, hasLength(1));
          expect(store.entries.single.recurringId, rule.id);
          expect(store.entries.single.income, income);
          expect(store.entries.single.cents, 12550);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('one time remains the default and creates no schedule', (
    tester,
  ) async {
    final store = await makeStore();
    await pumpTransactions(tester, store);
    await openEditor(tester);
    await fillEntry(tester);
    expect(
      tester
          .widget<DropdownButtonFormField<RepeatFrequency>>(
            find.byKey(const Key('entry-repeat')),
          )
          .initialValue,
      RepeatFrequency.once,
    );
    await submitEntry(tester);
    expect(store.entries, hasLength(1));
    expect(store.entries.single.recurringId, isNull);
    expect(store.recurringTransactions, isEmpty);
  });

  testWidgets(
    'future repeat starts wait for their date and are visible in management',
    (tester) async {
      final store = await makeStore();
      await pumpTransactions(tester, store);
      await openEditor(tester);
      await fillEntry(tester, income: true);
      await chooseFrequency(tester, RepeatFrequency.monthly);
      await tester.ensureVisible(find.byKey(const Key('entry-date')));
      await tester.tap(find.byKey(const Key('entry-date')));
      await tester.pumpAndSettle();
      final now = DateTime.now();
      final future = DateTime(now.year, now.month + 1, 5);
      final calendar = tester.widget<CalendarDatePicker>(
        find.byType(CalendarDatePicker),
      );
      expect(calendar.lastDate.isAfter(future), isTrue);
      calendar.onDateChanged(future);
      await tester.pump();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await submitEntry(tester);
      expect(store.entries, isEmpty);
      expect(store.recurringTransactions.single.startDate, future);
      await tester.tap(find.byKey(const Key('manage-recurring')));
      await tester.pumpAndSettle();
      expect(find.byType(RecurringTransactionsPage), findsOneWidget);
      expect(find.text('Salary'), findsOneWidget);
      expect(find.text('Next entry'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('switching a future schedule back to one time resets its date', (
    tester,
  ) async {
    final store = await makeStore();
    await pumpTransactions(tester, store);
    await openEditor(tester);
    await fillEntry(tester);
    await chooseFrequency(tester, RepeatFrequency.weekly);
    await tester.ensureVisible(find.byKey(const Key('entry-date')));
    await tester.tap(find.byKey(const Key('entry-date')));
    await tester.pumpAndSettle();
    final today = DateUtils.dateOnly(DateTime.now());
    tester
        .widget<CalendarDatePicker>(find.byType(CalendarDatePicker))
        .onDateChanged(DateTime(today.year, today.month + 1, 15));
    await tester.pump();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await chooseFrequency(tester, RepeatFrequency.once);
    await tester.ensureVisible(find.byKey(const Key('entry-date')));
    await tester.tap(find.byKey(const Key('entry-date')));
    await tester.pumpAndSettle();
    final calendar = tester.widget<CalendarDatePicker>(
      find.byType(CalendarDatePicker),
    );
    expect(calendar.initialDate, today);
    expect(calendar.lastDate, today);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await submitEntry(tester);
    expect(DateUtils.dateOnly(store.entries.single.date), today);
    expect(store.recurringTransactions, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'editing an occurrence preserves its link and leaves the schedule unchanged',
    (tester) async {
      final store = await makeStore();
      await store.saveScheduledEntry(
        Entry(
          id: 'rent',
          merchant: 'Rent',
          cents: 10000,
          date: DateTime.now(),
          category: 'Other',
        ),
        RepeatFrequency.weekly,
      );
      await pumpTransactions(tester, store);
      await tester.ensureVisible(find.byType(EntryTile));
      await tester.tap(find.byType(EntryTile));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('entry-repeat')), findsNothing);
      expect(
        find.text(
          'This is one recorded entry. Changes here do not change its repeat schedule.',
        ),
        findsOneWidget,
      );
      final fields = find.descendant(
        of: find.byType(EntryEditor),
        matching: find.byType(TextFormField),
      );
      await tester.enterText(fields.at(1), '150');
      await submitEntry(tester);
      expect(store.entries.single.cents, 15000);
      expect(store.entries.single.recurringId, 'rent');
      expect(store.recurringTransactions.single.cents, 10000);
      expect(
        store.recurringTransactions.single.frequency,
        RepeatFrequency.weekly,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'stopping a schedule needs confirmation and preserves recorded income',
    (tester) async {
      final store = await makeStore();
      await store.saveScheduledEntry(
        Entry(
          id: 'salary',
          merchant: 'Salary',
          cents: 30000,
          date: DateTime.now(),
          category: 'Income',
          income: true,
        ),
        RepeatFrequency.monthly,
      );
      final recordedId = store.entries.single.id;
      await pumpTransactions(tester, store);
      await tester.tap(find.byKey(const Key('manage-recurring')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('stop-recurring-salary')),
        160,
        scrollable:
            find
                .descendant(
                  of: find.byType(RecurringTransactionsPage),
                  matching: find.byType(Scrollable),
                )
                .first,
      );
      await tester.tap(find.byKey(const Key('stop-recurring-salary')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(store.recurringTransactions, hasLength(1));
      await tester.tap(find.byKey(const Key('stop-recurring-salary')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Stop repeating'),
        ),
      );
      await tester.pumpAndSettle();
      expect(store.recurringTransactions, isEmpty);
      expect(store.entries.single.id, recordedId);
      expect(store.entries.single.cents, 30000);
      expect(find.text('No recurring transactions'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'failed recurring write keeps the form open and retries without duplicates',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final store = FailFirstWriteStore(await SharedPreferences.getInstance());
      await pumpTransactions(tester, store);
      await openEditor(tester);
      await fillEntry(tester, income: true);
      await chooseFrequency(tester, RepeatFrequency.weekly);
      await submitEntry(tester);
      expect(find.byType(EntryEditor), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('Recurring transaction saved'), findsNothing);
      expect(store.recurringTransactions, hasLength(1));
      expect(store.entries, hasLength(1));
      final stagedId = store.entries.single.id;
      expect(
        tester
            .widget<DropdownButtonFormField<RepeatFrequency>>(
              find.byKey(const Key('entry-repeat')),
            )
            .onChanged,
        isNull,
      );
      await submitEntry(tester);
      expect(find.byType(EntryEditor), findsNothing);
      expect(store.error, isNull);
      expect(store.entries.single.id, stagedId);
      expect(store.recurringTransactions, hasLength(1));
      final restored = FinanceStore(store.prefs);
      await restored.load();
      expect(restored.recurringTransactions, hasLength(1));
      expect(restored.entries.single.id, stagedId);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('failed stop can be retried within recurring management', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final store = FailFirstWriteStore(await SharedPreferences.getInstance())
      ..failNextWrite = false;
    await store.saveScheduledEntry(
      Entry(
        id: 'stop-retry',
        merchant: 'Rent',
        cents: 15000,
        date: DateTime.now(),
        category: 'Other',
      ),
      RepeatFrequency.monthly,
    );
    final recordedId = store.entries.single.id;
    await pumpTransactions(tester, store);
    await tester.tap(find.byKey(const Key('manage-recurring')));
    await tester.pumpAndSettle();
    store.failNextWrite = true;
    await tester.scrollUntilVisible(
      find.byKey(const Key('stop-recurring-stop-retry')),
      160,
      scrollable:
          find
              .descendant(
                of: find.byType(RecurringTransactionsPage),
                matching: find.byType(Scrollable),
              )
              .first,
    );
    await tester.tap(find.byKey(const Key('stop-recurring-stop-retry')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Stop repeating'),
      ),
    );
    await tester.pumpAndSettle();
    expect(store.error, isNotNull);
    expect(store.recurringTransactions, isEmpty);
    await tester.scrollUntilVisible(
      find.text('Retry'),
      -160,
      scrollable:
          find
              .descendant(
                of: find.byType(RecurringTransactionsPage),
                matching: find.byType(Scrollable),
              )
              .first,
    );
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.byType(RecurringTransactionsPage), findsOneWidget);
    expect(store.error, isNull);
    expect(find.text('Retry'), findsNothing);
    final restored = FinanceStore(store.prefs);
    await restored.load();
    expect(restored.recurringTransactions, isEmpty);
    expect(restored.entries.single.id, recordedId);
    expect(tester.takeException(), isNull);
  });

  testWidgets('recurring management renders Arabic in a narrow viewport', (
    tester,
  ) async {
    final store = await makeStore();
    await store.saveScheduledEntry(
      Entry(
        id: 'arabic',
        merchant: 'الراتب الشهري',
        cents: 300000,
        date: DateTime.now(),
        category: 'Income',
        income: true,
      ),
      RepeatFrequency.monthly,
    );
    await pumpTransactions(tester, store, locale: const Locale('ar'));
    await tester.tap(find.byKey(const Key('manage-recurring')));
    await tester.pumpAndSettle();
    expect(find.text('الراتب الشهري'), findsOneWidget);
    expect(
      Directionality.of(tester.element(find.byType(RecurringTransactionsPage))),
      TextDirection.rtl,
    );
    expect(find.text('Recurring transactions'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
