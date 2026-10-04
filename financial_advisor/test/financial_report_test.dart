import 'dart:convert';

import 'package:financial_advisor/core/finance_store.dart';
import 'package:financial_advisor/core/financial_report.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/report_design_fixture.dart';

Entry record(
  String id,
  DateTime date,
  int cents, {
  String category = 'Food',
  bool income = false,
  bool projected = false,
  String? recurringId,
  DateTime? scheduledDate,
}) => Entry(
  id: id,
  merchant: 'Merchant $id',
  cents: cents,
  date: date,
  category: income ? 'Income' : category,
  income: income,
  isProjected: projected,
  parentRecurringTransactionId: recurringId,
  recurringScheduleId: recurringId,
  recurringScheduledDate: scheduledDate,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FinanceStore store;
  final now = DateTime(2026, 10, 3, 12);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store =
        FinanceStore(await SharedPreferences.getInstance())
          ..name = 'Report user'
          ..currency = 'SAR';
  });

  test(
    'approved six-month design metrics are derived from the actual snapshot',
    () {
      seedApprovedReportDesign(store);
      final report = FinancialReport.fromStore(
        store,
        generatedAt: DateTime(2026, 10, 4),
      );
      expect(report.transactionCount, 218);
      expect(report.expenseTransactionCount, 210);
      expect(report.incomeTransactionCount, 8);
      expect(report.monthCount, 6);
      expect(report.averageMonthlyExpenseCents, 936667);
      expect(report.highestExpenseMonth!.start, DateTime(2026, 9));
      expect(report.highestExpenseMonth!.expenseCents, 1050000);
      expect(report.retainedSharePercent, closeTo(25.5629139, 0.000001));
      expect(report.categoryBudgetLimitCents, 5700000);
      expect(report.categoryBudgetSpentCents, 5620000);
      expect(report.categoryUnbudgetedExpenseCents, 0);
      expect(report.budgetSummaries, hasLength(8));
      expect(
        report.budgetSummaries.every((row) => row.monthCount == 6),
        isTrue,
      );
      expect(report.comparableBudgetMonthCount, 6);
      expect(report.overBudgetMonthCount, 3);
      expect(
        report.monthlyBudgets.map((row) => row.spentCents - row.limitCents),
        [-130000, -85000, 60000, -50000, 25000, 100000],
      );
      final scenario = report.budgetScenario!;
      expect(scenario.categories.map((row) => row.category), [
        'Shopping',
        'Entertainment',
      ]);
      expect(scenario.reductionCents, 146000);
      expect(scenario.expenseCents, 5474000);
      expect(scenario.netCents, 2076000);
      expect(scenario.retainedSharePercent, closeTo(27.4966887, 0.000001));
      expect(() => report.budgetSummaries.clear(), throwsUnsupportedError);
      expect(() => report.monthlyBudgets.clear(), throwsUnsupportedError);
      expect(() => scenario.categories.clear(), throwsUnsupportedError);
    },
  );

  test(
    'budget summaries compare covered months only and never add Overall to categories',
    () {
      store.entries = [
        record('salary', DateTime(2026, 4, 1), 200000, income: true),
        record('covered-food', DateTime(2026, 4, 12), 15000),
        record(
          'covered-other',
          DateTime(2026, 4, 13),
          10000,
          category: 'Other',
        ),
        record('unbudgeted-food', DateTime(2026, 5, 12), 90000),
      ];
      store.budgets = {
        '2026-04': {'Food': 10000, 'Overall': 50000},
      };
      final report = FinancialReport.fromStore(store, generatedAt: now);
      expect(
        report.budgetSummaries.map(
          (row) => (row.category, row.spentCents, row.limitCents),
        ),
        [('Food', 15000, 10000), ('Overall', 25000, 50000)],
      );
      expect(report.categoryBudgetSpentCents, 15000);
      expect(report.categoryBudgetLimitCents, 10000);
      expect(report.categoryUnbudgetedExpenseCents, 100000);
      expect(report.monthlyBudgets.single.usesOverall, isTrue);
      expect(report.monthlyBudgets.single.limitCents, 50000);
      expect(report.monthlyBudgets.single.spentCents, 25000);
      expect(report.monthlyBudgets.single.fullyCovered, isTrue);
      expect(report.budgetScenario!.reductionCents, 5000);
      expect(report.budgetScenario!.expenseCents, 110000);
      expect(report.budgetScenario!.netCents, 90000);
    },
  );

  test(
    'partial and ongoing budget coverage cannot produce a completed-period scenario',
    () {
      store.entries = [record('meal', DateTime(2026, 9, 12), 15000)];
      store.budgets = {
        '2026-09': {'Food': 10000},
      };
      final partial = FinancialReport.fromStore(
        store,
        period: ReportPeriod.range(
          DateTime(2026, 9, 10),
          DateTime(2026, 9, 20),
        ),
        generatedAt: now,
      );
      expect(partial.budgetSummaries.single.partial, isTrue);
      expect(partial.budgetSummaries.single.limitCents, 10000);
      expect(partial.budgetScenario, isNull);
      expect(partial.comparableBudgetMonthCount, 0);
      final ongoing = FinancialReport.fromStore(
        store,
        period: ReportPeriod.month(DateTime(2026, 9)),
        generatedAt: DateTime(2026, 9, 15),
      );
      expect(ongoing.budgetSummaries.single.isOngoing, isTrue);
      expect(ongoing.budgetScenario, isNull);
      expect(ongoing.comparableBudgetMonthCount, 0);
      final completed = FinancialReport.fromStore(
        store,
        period: ReportPeriod.month(DateTime(2026, 9)),
        generatedAt: now,
      );
      expect(completed.budgetScenario!.reductionCents, 5000);
    },
  );

  test(
    'incomplete category budgets cannot establish overall monthly budget status',
    () {
      store.entries = [
        record('meal', DateTime(2026, 9, 12), 15000),
        record('other', DateTime(2026, 9, 12), 40000, category: 'Other'),
      ];
      store.budgets = {
        '2026-09': {'Food': 10000},
      };
      final report = FinancialReport.fromStore(store, generatedAt: now);
      expect(report.monthlyBudgets.single.unbudgetedExpenseCents, 40000);
      expect(report.monthlyBudgets.single.fullyCovered, isFalse);
      expect(report.comparableBudgetMonthCount, 0);
      expect(report.overBudgetMonthCount, 0);
      expect(report.budgetScenario!.reductionCents, 5000);
      expect(report.budgetScenario!.expenseCents, 50000);
    },
  );

  test(
    'month statistics include zero months and do not invent a retained share without income',
    () {
      store.entries = [
        record('jan', DateTime(2026, 1, 2), 10000),
        record('march', DateTime(2026, 3, 15), 50000),
      ];
      final report = FinancialReport.fromStore(store, generatedAt: now);
      expect(report.monthCount, 3);
      expect(report.averageMonthlyExpenseCents, 20000);
      expect(report.retainedSharePercent, isNull);
      expect(report.highestExpenseMonth!.start, DateTime(2026, 3));
      expect(report.budgetScenario, isNull);
      store.entries.clear();
      final empty = FinancialReport.fromStore(store, generatedAt: now);
      expect(empty.averageMonthlyExpenseCents, isNull);
      expect(empty.highestExpenseMonth, isNull);
      expect(empty.monthCount, 0);
    },
  );

  void seedHistory() {
    store.entries = [
      record('old', DateTime(2024, 2, 29), 10000, income: true),
      record('income', DateTime(2026, 9, 1), 20000, income: true),
      record('food', DateTime(2026, 9, 10), 1234),
      record(
        'housing',
        DateTime(2026, 9, 30, 23, 59, 59, 999),
        5000,
        category: 'Housing',
      ),
      record('october', DateTime(2026, 10, 1), 2345),
      record('saved-future', DateTime(2026, 12, 15), 1000),
      record('preview', DateTime(2026, 9, 2), 999999, projected: true),
    ];
  }

  void expectConservedTrends(FinancialReport report) {
    expect(report.trends.length, lessThanOrEqualTo(24));
    expect(
      report.trends.fold(0, (sum, row) => sum + row.incomeCents),
      report.incomeCents,
    );
    expect(
      report.trends.fold(0, (sum, row) => sum + row.expenseCents),
      report.expenseCents,
    );
    for (var index = 1; index < report.trends.length; index++) {
      final previous = report.trends[index - 1].end;
      expect(
        report.trends[index].start,
        DateTime(previous.year, previous.month, previous.day + 1),
      );
    }
  }

  test(
    'default history exactly matches dashboard and preserves stored future records',
    () {
      seedHistory();
      final report = FinancialReport.fromStore(store, generatedAt: now);
      expect(report.period.kind, ReportPeriodKind.allTime);
      expect(report.name, 'Report user');
      expect(report.currency, 'SAR');
      expect(report.incomeCents, store.incomeFor(null));
      expect(report.expenseCents, store.expensesFor(null));
      expect(report.transactionCount, store.forPeriod(null).length);
      expect(report.incomeCents, 30000);
      expect(report.expenseCents, 9579);
      expect(report.netCents, 20421);
      expect(report.transactionCount, 6);
      expect(report.hasRecordedFutureEntries, isTrue);
      expect(report.categories.map((row) => (row.category, row.cents)), [
        ('Housing', 5000),
        ('Food', 4579),
      ]);
      expectConservedTrends(report);
    },
  );

  test(
    'month normalizes boundaries and all calculations match the selected month',
    () {
      seedHistory();
      final period = ReportPeriod.month(DateTime(2026, 9, 15, 22));
      final report = FinancialReport.fromStore(
        store,
        period: period,
        generatedAt: now,
      );
      expect(period.start, DateTime(2026, 9));
      expect(period.end, DateTime(2026, 9, 30));
      expect(report.incomeCents, store.incomeFor(period.start));
      expect(report.expenseCents, store.expensesFor(period.start));
      expect(report.transactionCount, 3);
      expect(report.hasRecordedFutureEntries, isFalse);
      expect(report.commitmentStart, isNull);
      expect(report.commitmentEnd, isNull);
      expect(report.trends.first.start, DateTime(2026, 9));
      expect(report.trends.last.end, DateTime(2026, 9, 30));
      expectConservedTrends(report);
    },
  );

  test(
    'custom range includes the complete last calendar day and no outside records',
    () {
      seedHistory();
      final period = ReportPeriod.range(
        DateTime(2026, 9, 10, 15),
        DateTime(2026, 9, 30, 8),
      );
      final report = FinancialReport.fromStore(
        store,
        period: period,
        generatedAt: now,
      );
      expect(report.entries.map((entry) => entry.id), ['housing', 'food']);
      expect(report.incomeCents, 0);
      expect(report.expenseCents, 6234);
      expect(period.contains(DateTime(2026, 9, 30, 23, 59)), isTrue);
      expect(period.contains(DateTime(2026, 10)), isFalse);
      expectConservedTrends(report);
    },
  );

  test('report validates impossible ranges and supported year boundaries', () {
    expect(
      () => ReportPeriod.range(DateTime(2026, 2), DateTime(2026, 1)),
      throwsArgumentError,
    );
    expect(() => ReportPeriod.month(DateTime(0, 1)), throwsArgumentError);
    expect(
      () => ReportPeriod.range(DateTime(2000), DateTime(10000)),
      throwsArgumentError,
    );
    expect(ReportPeriod.month(DateTime(2024, 2)).end, DateTime(2024, 2, 29));
    final report = FinancialReport.fromStore(
      store,
      generatedAt: DateTime(9999, 12, 30),
    );
    expect(report.commitmentEnd, DateTime(9999, 12, 31));
  });

  test(
    'sparse and extreme ranges have bounded charts, zero intervals and exact totals',
    () {
      store.entries = [
        record('early', DateTime(1, 1, 1), 1),
        record('late', DateTime(9999, 12, 31), 99999999, income: true),
      ];
      final report = FinancialReport.fromStore(store, generatedAt: now);
      expect(report.trends.length, 24);
      expect(report.trends.first.start, DateTime(1));
      expect(report.trends.last.end, DateTime(9999, 12, 31));
      expect(
        report.trends.where(
          (bucket) => bucket.incomeCents == 0 && bucket.expenseCents == 0,
        ),
        hasLength(22),
      );
      expectConservedTrends(report);
      final monthReport = FinancialReport.fromStore(
        store,
        period: ReportPeriod.range(DateTime(2025), DateTime(2026, 12, 31)),
        generatedAt: now,
      );
      expect(monthReport.trends, hasLength(24));
      expectConservedTrends(monthReport);
    },
  );

  test('empty data stays empty rather than implying financial behavior', () {
    final report = FinancialReport.fromStore(store, generatedAt: now);
    expect(report.transactionCount, 0);
    expect(report.incomeCents, 0);
    expect(report.expenseCents, 0);
    expect(report.netCents, 0);
    expect(report.categories, isEmpty);
    expect(report.trends, isEmpty);
    expect(report.budgets, isEmpty);
    expect(report.recurringExpenses, isEmpty);
    expect(report.scheduledTransactions, isEmpty);
    expect(report.budgetCoveredExpenseCents, 0);
  });

  test(
    'chart extents use stored calendar dates for mixed UTC and local records',
    () {
      store.entries = [
        record('local', DateTime(2026, 10, 1), 100),
        record('utc', DateTime.utc(2026, 9, 30, 23, 59), 200),
      ];
      final report = FinancialReport.fromStore(store, generatedAt: now);
      expect(report.trends.first.start, DateTime(2026, 9, 30));
      expect(report.trends.last.end, DateTime(2026, 10, 1));
      expect(report.trends.map((row) => row.expenseCents), [200, 100]);
      expectConservedTrends(report);
    },
  );

  test(
    'budgets use only selected expenses, preserve full limits and flag partial coverage',
    () {
      seedHistory();
      store.budgets = {
        '2026-09': {'Overall': 10000, 'Food': 2000, 'Housing': 4000},
        '2026-10': {'Food': 5000},
        '2026-13': {'Food': 5000},
        'invalid': {'Food': 1000},
      };
      final report = FinancialReport.fromStore(
        store,
        period: ReportPeriod.range(
          DateTime(2026, 9, 20),
          DateTime(2026, 10, 10),
        ),
        generatedAt: now,
      );
      expect(report.budgets, hasLength(4));
      final september =
          report.budgets.where((row) => row.month.month == 9).toList();
      expect(
        september.map((row) => (row.category, row.limitCents, row.spentCents)),
        [('Overall', 10000, 5000), ('Food', 2000, 0), ('Housing', 4000, 5000)],
      );
      expect(september.every((row) => row.partial), isTrue);
      expect(
        september.every(
          (row) =>
              row.coverageStart == DateTime(2026, 9, 20) &&
              row.coverageEnd == DateTime(2026, 9, 30),
        ),
        isTrue,
      );
      expect(september.every((row) => !row.isOngoing), isTrue);
      expect(report.budgets.last.isOngoing, isTrue);
      expect(report.budgetCoveredExpenseCents, 7345);
      expect(report.unbudgetedExpenseCents, 0);
      expect(report.budgets.first.remainingCents, 5000);
      final fullMonth = FinancialReport.fromStore(
        store,
        period: ReportPeriod.month(DateTime(2026, 9)),
        generatedAt: now,
      );
      expect(fullMonth.budgets.every((row) => !row.partial), isTrue);
      // Overall and per-category limits overlap; their coverage is never summed.
      expect(fullMonth.budgetCoveredExpenseCents, 6234);
    },
  );

  test(
    'missing budgets do not fabricate limits or claim to cover other months/categories',
    () {
      seedHistory();
      store.budgets = {
        '2026-09': {'Food': 2000, 'Other': 0},
      };
      final report = FinancialReport.fromStore(store, generatedAt: now);
      expect(report.budgets, hasLength(1));
      expect(report.budgetCoveredExpenseCents, 1234);
      expect(report.unbudgetedExpenseCents, 8345);
      expect(report.budgets.single.partial, isFalse);
    },
  );

  test(
    'upcoming recurring transactions are separate, bounded and respect saved occurrences',
    () {
      store.recurringTransactions = [
        RecurringTransaction(
          id: 'rent',
          merchant: 'Rent',
          cents: 50000,
          category: 'Housing',
          income: false,
          startDate: DateTime(2026, 9, 3),
          frequency: RepeatFrequency.monthly,
          nextOccurrence: 1,
        ),
        RecurringTransaction(
          id: 'salary',
          merchant: 'Salary',
          cents: 100000,
          category: 'Income',
          income: true,
          startDate: DateTime(2026, 10, 15),
          frequency: RepeatFrequency.monthly,
        ),
        RecurringTransaction(
          id: 'stopped',
          merchant: 'Stopped',
          cents: 999999,
          category: 'Food',
          income: false,
          startDate: DateTime(2026, 10, 5),
          frequency: RepeatFrequency.monthly,
          active: false,
        ),
      ];
      store.entries = [
        record(
          'recurring:rent:0',
          DateTime(2026, 9, 3),
          50000,
          category: 'Housing',
          recurringId: 'rent',
        ),
        record(
          'recurring:rent:1',
          DateTime(2026, 10, 3),
          51000,
          category: 'Housing',
          recurringId: 'rent',
        ),
      ];
      final report = FinancialReport.fromStore(store, generatedAt: now);
      expect(report.expenseCents, 101000);
      expect(report.recurringExpenseCents, 101000);
      expect(report.transactionCount, 2);
      expect(report.commitmentStart, DateTime(2026, 10, 3));
      expect(report.commitmentEnd, DateTime(2026, 12, 31));
      expect(report.commitments.map((entry) => entry.date), [
        DateTime(2026, 11, 3),
        DateTime(2026, 12, 3),
      ]);
      expect(report.scheduledExpenseCents, 100000);
      expect(report.scheduledIncomeCents, 300000);
      expect(
        report.scheduledTransactions.every((entry) => entry.isProjected),
        isTrue,
      );
      final october = FinancialReport.fromStore(
        store,
        period: ReportPeriod.month(DateTime(2026, 10)),
        generatedAt: now,
      );
      expect(october.commitmentEnd, DateTime(2026, 10, 31));
      expect(october.commitments, isEmpty);
      expect(october.scheduledIncomeCents, 100000);
      expect(october.expenseCents, 51000);
      final farFuture = FinancialReport.fromStore(
        store,
        period: ReportPeriod.month(DateTime(2027, 2)),
        generatedAt: now,
      );
      expect(farFuture.commitmentStart, isNull);
      expect(farFuture.commitmentEnd, isNull);
      expect(farFuture.scheduledTransactions, isEmpty);
    },
  );

  test(
    'moved saved occurrences are not presented a second time as scheduled',
    () {
      store.recurringTransactions = [
        RecurringTransaction(
          id: 'bill',
          merchant: 'Bill',
          cents: 10000,
          category: 'Utilities',
          income: false,
          startDate: DateTime(2026, 10, 5),
          frequency: RepeatFrequency.monthly,
        ),
      ];
      store.entries = [
        record(
          'legacy-custom-id',
          DateTime(2026, 9, 30),
          10000,
          category: 'Utilities',
          recurringId: 'bill',
          scheduledDate: DateTime(2026, 10, 5),
        ),
      ];
      final report = FinancialReport.fromStore(
        store,
        period: ReportPeriod.month(DateTime(2026, 10)),
        generatedAt: now,
      );
      expect(report.transactionCount, 0);
      expect(report.commitments, isEmpty);
    },
  );

  test('deleted future occurrences stay deleted in reports', () async {
    store.recurringTransactions = [
      RecurringTransaction(
        id: 'bill',
        merchant: 'Bill',
        cents: 10000,
        category: 'Utilities',
        income: false,
        startDate: DateTime(2026, 10, 5),
        frequency: RepeatFrequency.monthly,
      ),
    ];
    final occurrence =
        store
            .entriesForRange(
              DateTime(2026, 10),
              DateTime(2026, 10, 31),
              now: now,
            )
            .single;
    await store.deleteRecurringEntry(
      occurrence,
      scope: RecurringScope.onlyThis,
      now: now,
    );
    final report = FinancialReport.fromStore(
      store,
      period: ReportPeriod.month(DateTime(2026, 10)),
      generatedAt: now,
    );
    expect(report.commitments, isEmpty);
  });

  test(
    'snapshot does not mutate storage, schedules or filters and survives store changes',
    () async {
      seedHistory();
      store.budgets = {
        '2026-09': {'Food': 2000},
      };
      store.recurringTransactions = [
        RecurringTransaction(
          id: 'daily',
          merchant: 'Daily',
          cents: 1,
          category: 'Food',
          income: false,
          startDate: DateTime(2026, 10, 3),
          frequency: RepeatFrequency.daily,
        ),
      ];
      final entriesBefore = jsonEncode(
        store.entries.map((entry) => entry.toJson()).toList(),
      );
      final schedulesBefore = jsonEncode(
        store.recurringTransactions.map((rule) => rule.toJson()).toList(),
      );
      final budgetBefore = jsonEncode(store.budgets);
      final report = FinancialReport.fromStore(store, generatedAt: now);
      expect(report.commitments, hasLength(90));
      expect(
        jsonEncode(store.entries.map((entry) => entry.toJson()).toList()),
        entriesBefore,
      );
      expect(
        jsonEncode(
          store.recurringTransactions.map((rule) => rule.toJson()).toList(),
        ),
        schedulesBefore,
      );
      expect(jsonEncode(store.budgets), budgetBefore);
      expect(store.prefs.getKeys(), isEmpty);
      store.entries.clear();
      store.budgets.clear();
      store.name = 'Changed';
      expect(report.name, 'Report user');
      expect(report.transactionCount, 6);
      expect(report.expenseCents, 9579);
      expect(report.budgets.single.limitCents, 2000);
      expect(() => report.entries.clear(), throwsUnsupportedError);
      expect(() => report.trends.clear(), throwsUnsupportedError);
      expect(() => report.categories.clear(), throwsUnsupportedError);
      expect(() => report.commitments.clear(), throwsUnsupportedError);
    },
  );
}
