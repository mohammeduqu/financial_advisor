import 'package:financial_advisor/core/finance_store.dart';
import 'package:financial_advisor/core/invoice.dart';
import 'package:financial_advisor/screens/invoice_review.dart';
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
  DateTime? month,
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
          builder: (context, _) => TransactionsPage(store: store, month: month),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  if (find.byType(ListView).evaluate().isNotEmpty) {
    final scrollable =
        find
            .descendant(
              of: find.byType(ListView).last,
              matching: find.byType(Scrollable),
            )
            .first;
    tester.state<ScrollableState>(scrollable).position.jumpTo(0);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      finder,
      180,
      scrollable: scrollable,
      maxScrolls: 30,
    );
    await tester.pumpAndSettle();
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> openEditor(WidgetTester tester) =>
    tapVisible(tester, find.byTooltip('Add transaction'));

Future<void> fillEntry(WidgetTester tester, {bool income = false}) async {
  if (income) {
    await tapVisible(
      tester,
      find.descendant(
        of: find.byType(SegmentedButton<bool>),
        matching: find.text('Income'),
      ),
    );
  }
  final fields = find.descendant(
    of: find.byType(EntryEditor),
    matching: find.byType(TextFormField),
  );
  await tester.enterText(fields.at(0), income ? 'Salary' : 'Rent');
  await tester.enterText(fields.at(1), '125.50');
}

Future<void> chooseFrequency(WidgetTester tester, RepeatFrequency value) async {
  await tapVisible(tester, find.byKey(const Key('entry-repeat')));
  await tester.tap(find.text(value.label).last);
  await tester.pumpAndSettle();
}

Future<void> selectDate(
  WidgetTester tester,
  DateTime value, {
  String key = 'entry-date',
}) async {
  await tapVisible(tester, find.byKey(Key(key)));
  tester
      .widget<CalendarDatePicker>(find.byType(CalendarDatePicker))
      .onDateChanged(value);
  await tester.pump();
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
}

Future<void> submitEntry(WidgetTester tester) =>
    tapVisible(tester, find.byKey(const Key('save-entry')));

Future<void> editOccurrence(
  WidgetTester tester,
  Entry entry,
  RecurringScope scope,
) async {
  await tapVisible(tester, find.byKey(ValueKey('entry-${entry.id}')));
  await tester.tap(find.byKey(ValueKey('recurring-scope-${scope.name}')));
  await tester.pumpAndSettle();
}

Future<void> seedMonthly(
  FinanceStore store, {
  String id = 'rent',
  DateTime? date,
}) => store.saveScheduledEntry(
  Entry(
    id: id,
    merchant: 'Rent',
    cents: 10000,
    date: date ?? DateTime.now(),
    category: 'Housing',
  ),
  RepeatFrequency.monthly,
);

void main() {
  for (final income in [true, false]) {
    for (final frequency in [
      RepeatFrequency.daily,
      RepeatFrequency.weekly,
      RepeatFrequency.monthly,
      RepeatFrequency.yearly,
    ]) {
      testWidgets(
        '${income ? 'income' : 'expense'} creates ${frequency.name} recurrence',
        (tester) async {
          final store = await makeStore();
          await pumpTransactions(tester, store);
          await openEditor(tester);
          await fillEntry(tester, income: income);
          await chooseFrequency(tester, frequency);
          await submitEntry(tester);
          expect(find.byType(EntryEditor), findsNothing);
          expect(store.recurringTransactions.single.frequency, frequency);
          expect(store.recurringTransactions.single.income, income);
          expect(store.entries.single.cents, 12550);
          expect(store.entries.single.parentRecurringTransactionId, isNotNull);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('switching to one time preserves a future manual date', (
    tester,
  ) async {
    final store = await makeStore();
    await pumpTransactions(tester, store);
    await openEditor(tester);
    await fillEntry(tester);
    await chooseFrequency(tester, RepeatFrequency.weekly);
    final future = DateTime(DateTime.now().year + 1, 2, 15);
    await selectDate(tester, future);
    await chooseFrequency(tester, RepeatFrequency.once);
    await submitEntry(tester);
    expect(store.entries.single.date, future);
    expect(store.recurringTransactions, isEmpty);
    await tapVisible(
      tester,
      find.byKey(const Key('transaction-dates-Upcoming')),
    );
    expect(
      find.byKey(ValueKey('entry-${store.entries.single.id}')),
      findsOneWidget,
    );
    await tapVisible(
      tester,
      find.byKey(const Key('transaction-dates-All dates')),
    );
    expect(
      find.byKey(ValueKey('entry-${store.entries.single.id}')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('only-this edit preserves the parent and sibling amount', (
    tester,
  ) async {
    final store = await makeStore();
    await seedMonthly(store);
    final entry = store.entries.single;
    await pumpTransactions(tester, store);
    await editOccurrence(tester, entry, RecurringScope.onlyThis);
    final repeat = tester.widget<DropdownButtonFormField<RepeatFrequency>>(
      find.byKey(const Key('entry-repeat')),
    );
    expect(repeat.initialValue, RepeatFrequency.monthly);
    final fields = find.descendant(
      of: find.byType(EntryEditor),
      matching: find.byType(TextFormField),
    );
    await tester.enterText(fields.at(1), '150');
    await submitEntry(tester);
    expect(store.entries.single.cents, 15000);
    expect(
      store.entries.single.parentRecurringTransactionId,
      entry.parentRecurringTransactionId,
    );
    expect(store.recurringTransactions.single.cents, 10000);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'series edit changes frequency, interval, and inclusive end date',
    (tester) async {
      final store = await makeStore();
      await seedMonthly(store);
      await pumpTransactions(tester, store);
      await editOccurrence(
        tester,
        store.entries.single,
        RecurringScope.thisAndFuture,
      );
      await chooseFrequency(tester, RepeatFrequency.yearly);
      await tester.enterText(
        find.byKey(const Key('entry-repeat-interval')),
        '٢',
      );
      final end = DateTime(DateTime.now().year + 4, 12, 31);
      await selectDate(tester, end, key: 'entry-repeat-end');
      await submitEntry(tester);
      final rule = store.recurringTransactions.where(isRecurringActive).single;
      expect(rule.frequency, RepeatFrequency.yearly);
      expect(rule.interval, 2);
      expect(rule.endDate, end);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('only-this can become one time without stopping the parent', (
    tester,
  ) async {
    final store = await makeStore();
    await seedMonthly(store);
    final original = store.entries.single;
    await pumpTransactions(tester, store);
    await editOccurrence(tester, original, RecurringScope.onlyThis);
    await chooseFrequency(tester, RepeatFrequency.once);
    await submitEntry(tester);
    final saved = store.entries.single;
    expect(saved.id, original.id);
    expect(
      saved.parentRecurringTransactionId,
      original.parentRecurringTransactionId,
    );
    expect(saved.recurrenceDisabled, isTrue);
    expect(store.recurringTransactions.where(isRecurringActive), hasLength(1));
    final next = store.recurringTransactions.single.nextDate;
    expect(
      store.entriesForRange(next, next).single.recurrenceDisabled,
      isFalse,
    );
    expect(find.text('Repeat: Monthly'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('all scope can turn a recurring transaction into one time', (
    tester,
  ) async {
    final store = await makeStore();
    await seedMonthly(store);
    await pumpTransactions(tester, store);
    await editOccurrence(tester, store.entries.single, RecurringScope.all);
    await chooseFrequency(tester, RepeatFrequency.once);
    await submitEntry(tester);
    expect(store.recurringTransactions.where(isRecurringActive), isEmpty);
    expect(store.entries.single.parentRecurringTransactionId, isNull);
    expect(find.text('Repeat: Monthly'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('future month shows bounded previews and edits one occurrence', (
    tester,
  ) async {
    final store = await makeStore();
    final future = DateTime(DateTime.now().year, DateTime.now().month + 1, 5);
    await seedMonthly(store, date: future);
    await pumpTransactions(tester, store, month: future);
    expect(store.entries, isEmpty);
    final preview =
        store
            .entriesForRange(future, DateTime(future.year, future.month + 1, 0))
            .single;
    expect(preview.isProjected, isTrue);
    await editOccurrence(tester, preview, RecurringScope.onlyThis);
    final fields = find.descendant(
      of: find.byType(EntryEditor),
      matching: find.byType(TextFormField),
    );
    await tester.enterText(fields.at(1), '175');
    await submitEntry(tester);
    expect(store.entries.single.cents, 17500);
    expect(store.entries.single.isProjected, isFalse);
    expect(store.recurringTransactions.single.cents, 10000);
    expect(
      store.entriesForRange(future, DateTime(future.year, future.month + 1, 0)),
      hasLength(1),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'deleting an upcoming occurrence leaves its parent and siblings',
    (tester) async {
      final store = await makeStore();
      final future = DateTime(DateTime.now().year, DateTime.now().month + 1, 5);
      await seedMonthly(store, date: future);
      await pumpTransactions(tester, store, month: future);
      final preview = store.entriesForRange(future, future).single;
      await editOccurrence(tester, preview, RecurringScope.onlyThis);
      await tester.tap(find.byTooltip('Delete transaction'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(store.entriesForRange(future, future), isEmpty);
      final sibling = DateTime(future.year, future.month + 1, future.day);
      expect(store.entriesForRange(sibling, sibling), hasLength(1));
      expect(
        store.recurringTransactions.where(isRecurringActive),
        hasLength(1),
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final all in [true, false]) {
    testWidgets(
      'parent delete ${all ? 'all' : 'future'} has explicit choices and preserves the selected scope',
      (tester) async {
        final store = await makeStore();
        final today = DateUtils.dateOnly(DateTime.now());
        await seedMonthly(store, date: today.subtract(const Duration(days: 1)));
        final oldId = store.entries.first.id;
        await pumpTransactions(tester, store);
        await tapVisible(tester, find.byKey(const Key('manage-recurring')));
        expect(find.text('Stop repeating'), findsNothing);
        await tapVisible(
          tester,
          find.byKey(const Key('delete-recurring-rent')),
        );
        await tester.tap(find.byKey(const Key('delete-series-cancel')));
        await tester.pumpAndSettle();
        expect(
          store.recurringTransactions.where(isRecurringActive),
          hasLength(1),
        );
        await tapVisible(
          tester,
          find.byKey(const Key('delete-recurring-rent')),
        );
        await tester.tap(
          find.byKey(Key(all ? 'delete-series-all' : 'delete-series-future')),
        );
        await tester.pumpAndSettle();
        expect(store.recurringTransactions.where(isRecurringActive), isEmpty);
        expect(store.entries.any((entry) => entry.id == oldId), !all);
        expect(find.text('No recurring transactions'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'parent editor changes next occurrence without rewriting history',
    (tester) async {
      final store = await makeStore();
      await seedMonthly(store);
      final oldId = store.entries.single.id;
      await pumpTransactions(tester, store);
      await tapVisible(tester, find.byKey(const Key('manage-recurring')));
      await tapVisible(tester, find.byKey(const Key('edit-recurring-rent')));
      final fields = find.descendant(
        of: find.byType(EntryEditor),
        matching: find.byType(TextFormField),
      );
      await tester.enterText(fields.at(1), '200');
      await chooseFrequency(tester, RepeatFrequency.yearly);
      await submitEntry(tester);
      expect(store.entries.single.id, oldId);
      expect(store.entries.single.cents, 10000);
      expect(
        store.recurringTransactions.where(isRecurringActive).single.cents,
        20000,
      );
      expect(
        store.recurringTransactions.where(isRecurringActive).single.frequency,
        RepeatFrequency.yearly,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'future schedule changes share one parent card and keep previews editable',
    (tester) async {
      final store = await makeStore();
      await seedMonthly(store);
      final future = store.recurringTransactions.single.dateForOccurrence(2);
      final projected = store.entriesForRange(future, future).single;
      await store.updateRecurringEntry(
        projected.copyWith(cents: 25000),
        scope: RecurringScope.thisAndFuture,
        frequency: RepeatFrequency.weekly,
      );
      expect(
        store.recurringTransactions.where(isRecurringActive),
        hasLength(2),
      );
      await pumpTransactions(tester, store);
      await tapVisible(tester, find.byKey(const Key('manage-recurring')));
      expect(find.byKey(const Key('recurring-rent')), findsOneWidget);
      expect(find.byKey(const Key('edit-recurring-rent')), findsOneWidget);
      expect(find.text('Scheduled changes'), findsOneWidget);
      expect(find.text('Repeat: Weekly'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await pumpTransactions(tester, store, month: future);
      final next = store.entriesForRange(future, future).single;
      await editOccurrence(tester, next, RecurringScope.onlyThis);
      final fields = find.descendant(
        of: find.byType(EntryEditor),
        matching: find.byType(TextFormField),
      );
      await tester.enterText(fields.at(1), '300');
      await submitEntry(tester);
      expect(
        store.entries.where((entry) => entry.id == next.id).single.cents,
        30000,
      );
      expect(
        store.recurringTransactions.where(isRecurringActive),
        hasLength(2),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('failed recurring save retries without creating duplicates', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final store = FailFirstWriteStore(await SharedPreferences.getInstance());
    await pumpTransactions(tester, store);
    await openEditor(tester);
    await fillEntry(tester);
    await chooseFrequency(tester, RepeatFrequency.weekly);
    await submitEntry(tester);
    expect(find.byType(EntryEditor), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    final id = store.entries.single.id;
    expect(
      tester
          .widget<DropdownButtonFormField<RepeatFrequency>>(
            find.byKey(const Key('entry-repeat')),
          )
          .onChanged,
      isNull,
    );
    await tester.pump(const Duration(seconds: 5));
    await submitEntry(tester);
    expect(find.byType(EntryEditor), findsNothing);
    expect(store.error, isNull);
    expect(store.entries.single.id, id);
    expect(store.recurringTransactions, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'existing invoice can start recurrence without losing item metadata',
    (tester) async {
      final store = await makeStore();
      final invoice = InvoiceModel(
        merchantName: 'Invoice shop',
        currency: 'SAR',
        date: DateTime.now(),
        category: 'Food',
        total: 25,
        subtotal: 25,
        items: [
          const InvoiceItemModel(
            name: 'Rice',
            quantity: 1,
            totalPrice: 25,
            category: 'Food',
          ),
        ],
      );
      await store.saveInvoice(invoice, id: 'invoice');
      await pumpTransactions(tester, store);
      await tapVisible(tester, find.byKey(const Key('entry-invoice')));
      expect(find.byType(InvoiceReviewScreen), findsOneWidget);
      await tapVisible(
        tester,
        find.byKey(const Key('invoice-repeat-settings')),
      );
      await chooseFrequency(tester, RepeatFrequency.monthly);
      await submitEntry(tester);
      expect(
        store.recurringTransactions.where(isRecurringActive),
        hasLength(1),
      );
      expect(store.entries.single.invoice?.items.single.name, 'Rice');
      expect(store.entries.single.cents, 2500);
      expect(store.entries.single.parentRecurringTransactionId, isNotNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'recurring management renders Arabic and currency in narrow layout',
    (tester) async {
      final store = await makeStore();
      await seedMonthly(store);
      store.currency = 'USD';
      await pumpTransactions(tester, store, locale: const Locale('ar'));
      await tapVisible(tester, find.byKey(const Key('manage-recurring')));
      expect(
        Directionality.of(
          tester.element(find.byType(RecurringTransactionsPage)),
        ),
        TextDirection.rtl,
      );
      expect(find.text('Recurring transactions'), findsNothing);
      expect(find.textContaining('USD'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'invoice details do not overwrite an edited recurring ledger amount',
    (tester) async {
      final store = await makeStore();
      final invoice = InvoiceModel(
        merchantName: 'Original shop',
        currency: 'SAR',
        date: DateTime.now(),
        category: 'Food',
        total: 25,
        subtotal: 25,
        items: [
          const InvoiceItemModel(
            name: 'Rice',
            quantity: 1,
            totalPrice: 25,
            category: 'Food',
          ),
        ],
      );
      await store.saveInvoice(invoice, id: 'invoice-ledger');
      await store.saveScheduledEntry(
        store.entries.single,
        RepeatFrequency.monthly,
      );
      await pumpTransactions(tester, store);
      await editOccurrence(
        tester,
        store.entries.single,
        RecurringScope.onlyThis,
      );
      expect(find.byType(EntryEditor), findsOneWidget);
      final fields = find.descendant(
        of: find.byType(EntryEditor),
        matching: find.byType(TextFormField),
      );
      await tester.enterText(fields.at(1), '40');
      await submitEntry(tester);
      expect(store.entries.single.cents, 4000);
      expect(store.entries.single.invoice?.totalCents, 2500);
      await tester.pump(const Duration(seconds: 5));
      await editOccurrence(
        tester,
        store.entries.single,
        RecurringScope.onlyThis,
      );
      await tapVisible(tester, find.byKey(const Key('entry-invoice-details')));
      expect(find.byType(InvoiceReviewScreen), findsOneWidget);
      await tapVisible(tester, find.byKey(const Key('add-invoice-expense')));
      expect(store.entries.single.cents, 4000);
      expect(store.entries.single.invoice?.items.single.name, 'Rice');
      expect(tester.takeException(), isNull);
    },
  );
}
