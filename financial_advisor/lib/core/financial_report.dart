import 'finance_store.dart';
import 'invoice.dart' show invoiceCategories;

DateTime _day(DateTime date) => DateTime(date.year, date.month, date.day);
DateTime _later(DateTime a, DateTime b) => a.isAfter(b) ? a : b;
DateTime _earlier(DateTime a, DateTime b) => a.isBefore(b) ? a : b;

void _validateDate(DateTime date) {
  if (date.year < 1 || date.year > 9999) {
    throw ArgumentError.value(date, 'date', 'Unsupported reporting date');
  }
}

enum ReportPeriodKind { allTime, month, custom }

/// Calendar-date boundaries are inclusive, including the entire final day.
class ReportPeriod {
  final ReportPeriodKind kind;
  final DateTime? start;
  final DateTime? end;

  const ReportPeriod.allTime()
    : kind = ReportPeriodKind.allTime,
      start = null,
      end = null;

  ReportPeriod.month(DateTime month)
    : kind = ReportPeriodKind.month,
      start = DateTime(month.year, month.month),
      end = DateTime(month.year, month.month + 1, 0) {
    _validateDate(month);
  }

  ReportPeriod.range(DateTime first, DateTime last)
    : kind = ReportPeriodKind.custom,
      start = _day(first),
      end = _day(last) {
    _validateDate(first);
    _validateDate(last);
    if (end!.isBefore(start!)) {
      throw ArgumentError('The report end date must not precede its start');
    }
  }

  bool contains(DateTime date) {
    final value = _day(date);
    return (start == null || !value.isBefore(start!)) &&
        (end == null || !value.isAfter(end!));
  }
}

class ReportCategoryTotal {
  final String category;
  final int cents;

  const ReportCategoryTotal(this.category, this.cents);
}

class ReportTrendBucket {
  final DateTime start;
  final DateTime end;
  final int incomeCents;
  final int expenseCents;

  const ReportTrendBucket({
    required this.start,
    required this.end,
    required this.incomeCents,
    required this.expenseCents,
  });

  int get netCents => incomeCents - expenseCents;
}

/// Category totals cover only the months for which that category has a saved
/// limit. An Overall row is a separate comparison, never an extra allowance.
class ReportBudgetSummary {
  final String category;
  final int limitCents;
  final int spentCents;
  final int monthCount;
  final bool partial;
  final bool isOngoing;

  const ReportBudgetSummary({
    required this.category,
    required this.limitCents,
    required this.spentCents,
    required this.monthCount,
    required this.partial,
    required this.isOngoing,
  });

  bool get isOverall => category == 'Overall';
  int get varianceCents => spentCents - limitCents;
}

class ReportMonthlyBudget {
  final DateTime month;
  final int limitCents;
  final int spentCents;
  final int unbudgetedExpenseCents;
  final bool partial;
  final bool isOngoing;
  final bool usesOverall;

  const ReportMonthlyBudget({
    required this.month,
    required this.limitCents,
    required this.spentCents,
    required this.unbudgetedExpenseCents,
    required this.partial,
    required this.isOngoing,
    required this.usesOverall,
  });

  bool get fullyCovered => unbudgetedExpenseCents == 0;
  bool get overBudget => spentCents > limitCents;
}

/// A retrospective comparison with saved category limits. It is not a forecast
/// or a sum of every monthly overspend: underspending within the same category
/// offsets overspending when comparing that category across its covered months.
class ReportBudgetScenario {
  final List<ReportBudgetSummary> categories;
  final int reductionCents;
  final int incomeCents;
  final int expenseCents;

  ReportBudgetScenario._({
    required List<ReportBudgetSummary> categories,
    required this.reductionCents,
    required this.incomeCents,
    required this.expenseCents,
  }) : categories = List.unmodifiable(categories);

  int get netCents => incomeCents - expenseCents;
  double? get retainedSharePercent =>
      incomeCents > 0 ? netCents * 100 / incomeCents : null;
}

class ReportBudgetPerformance {
  final DateTime month;
  final String category;
  final int limitCents;
  final int spentCents;
  final DateTime coverageStart;
  final DateTime coverageEnd;
  final bool partial;
  final bool isOngoing;

  const ReportBudgetPerformance({
    required this.month,
    required this.category,
    required this.limitCents,
    required this.spentCents,
    required this.coverageStart,
    required this.coverageEnd,
    required this.partial,
    required this.isOngoing,
  });

  bool get isOverall => category == 'Overall';
  int get remainingCents => limitCents - spentCents;
}

/// A read-only snapshot. Exporting never posts recurring occurrences, changes
/// dashboard filters, updates budgets, or writes financial data to storage.
class FinancialReport {
  final String name;
  final String currency;
  final ReportPeriod period;
  final DateTime generatedAt;
  final List<Entry> entries;
  final int incomeCents;
  final int expenseCents;
  final List<ReportCategoryTotal> categories;
  final List<ReportTrendBucket> trends;
  final List<ReportBudgetPerformance> budgets;
  final List<Entry> recurringExpenses;
  final List<Entry> scheduledTransactions;
  final List<Entry> commitments;
  final DateTime? commitmentStart;
  final DateTime? commitmentEnd;
  final int budgetCoveredExpenseCents;
  final bool hasRecordedFutureEntries;

  FinancialReport._({
    required this.name,
    required this.currency,
    required this.period,
    required this.generatedAt,
    required List<Entry> entries,
    required this.incomeCents,
    required this.expenseCents,
    required List<ReportCategoryTotal> categories,
    required List<ReportTrendBucket> trends,
    required List<ReportBudgetPerformance> budgets,
    required List<Entry> recurringExpenses,
    required List<Entry> scheduledTransactions,
    required this.commitmentStart,
    required this.commitmentEnd,
    required this.budgetCoveredExpenseCents,
    required this.hasRecordedFutureEntries,
  }) : entries = List.unmodifiable(entries),
       categories = List.unmodifiable(categories),
       trends = List.unmodifiable(trends),
       budgets = List.unmodifiable(budgets),
       recurringExpenses = List.unmodifiable(recurringExpenses),
       scheduledTransactions = List.unmodifiable(scheduledTransactions),
       commitments = List.unmodifiable(
         scheduledTransactions.where((entry) => !entry.income),
       );

  int get netCents => incomeCents - expenseCents;
  int get transactionCount => entries.length;
  int get incomeTransactionCount =>
      entries.where((entry) => entry.income).length;
  int get expenseTransactionCount => transactionCount - incomeTransactionCount;
  double? get retainedSharePercent =>
      incomeCents > 0 ? netCents * 100 / incomeCents : null;
  int get recurringExpenseCents =>
      recurringExpenses.fold(0, (total, entry) => total + entry.cents);
  int get scheduledIncomeCents => scheduledTransactions
      .where((entry) => entry.income)
      .fold(0, (total, entry) => total + entry.cents);
  int get scheduledExpenseCents =>
      commitments.fold(0, (total, entry) => total + entry.cents);
  int get unbudgetedExpenseCents => expenseCents - budgetCoveredExpenseCents;

  DateTime? get recordedStart =>
      entries.isEmpty
          ? null
          : entries.map((entry) => _day(entry.date)).reduce(_earlier);
  DateTime? get recordedEnd =>
      entries.isEmpty
          ? null
          : entries.map((entry) => _day(entry.date)).reduce(_later);

  /// Calendar months touched by the selected dates (including empty months).
  /// An average over these months must not be labelled a monthly forecast.
  int get monthCount {
    final first = period.start ?? recordedStart;
    final last = period.end ?? recordedEnd;
    if (first == null || last == null) return 0;
    return (last.year - first.year) * 12 + last.month - first.month + 1;
  }

  int? get averageMonthlyExpenseCents =>
      monthCount == 0 ? null : (expenseCents + monthCount ~/ 2) ~/ monthCount;

  late final ReportTrendBucket? highestExpenseMonth = _highestExpenseMonth(
    entries,
  );

  late final List<ReportBudgetSummary> budgetSummaries = List.unmodifiable(
    _summarizeBudgets(budgets),
  );
  late final List<ReportMonthlyBudget> monthlyBudgets = List.unmodifiable(
    _monthlyBudgets(entries, budgets),
  );

  int get categoryBudgetLimitCents => budgetSummaries
      .where((row) => !row.isOverall)
      .fold(0, (sum, row) => sum + row.limitCents);
  int get categoryBudgetSpentCents => budgetSummaries
      .where((row) => !row.isOverall)
      .fold(0, (sum, row) => sum + row.spentCents);
  int get categoryUnbudgetedExpenseCents =>
      expenseCents - categoryBudgetSpentCents;

  /// Only comparable, fully selected, completed months contribute. A month
  /// with uncovered expense categories cannot establish overall budget status.
  int get comparableBudgetMonthCount =>
      monthlyBudgets
          .where((row) => row.fullyCovered && !row.partial && !row.isOngoing)
          .length;
  int get overBudgetMonthCount =>
      monthlyBudgets
          .where(
            (row) =>
                row.fullyCovered &&
                !row.partial &&
                !row.isOngoing &&
                row.overBudget,
          )
          .length;

  ReportBudgetScenario? get budgetScenario {
    final eligible =
        budgetSummaries
            .where(
              (row) =>
                  !row.isOverall &&
                  !row.partial &&
                  !row.isOngoing &&
                  row.varianceCents > 0,
            )
            .toList()
          ..sort((a, b) => b.varianceCents.compareTo(a.varianceCents));
    if (eligible.isEmpty) return null;
    final reduction = eligible.fold(0, (sum, row) => sum + row.varianceCents);
    return ReportBudgetScenario._(
      categories: eligible,
      reductionCents: reduction,
      incomeCents: incomeCents,
      expenseCents: expenseCents - reduction,
    );
  }

  factory FinancialReport.fromStore(
    FinanceStore store, {
    ReportPeriod period = const ReportPeriod.allTime(),
    DateTime? generatedAt,
  }) {
    final clock = generatedAt ?? DateTime.now();
    _validateDate(clock);
    final today = _day(clock);
    // Use precisely the recorded-history scope used by dashboard calculations.
    // A saved future-dated record remains recorded, while a projection does not.
    final entries = switch (period.kind) {
      ReportPeriodKind.allTime => store.forPeriod(null),
      ReportPeriodKind.month => store.forPeriod(period.start),
      ReportPeriodKind.custom =>
        store
            .entriesForRange(
              period.start!,
              period.end!,
              includeProjected: false,
            )
            .where((entry) => !entry.isProjected)
            .toList(),
    };
    var income = 0;
    var expenses = 0;
    var budgetCovered = 0;
    final categoryTotals = <String, int>{};
    final monthExpenses = <String, Map<String, int>>{};
    for (final entry in entries) {
      _validateDate(entry.date);
      if (entry.income) {
        income += entry.cents;
      } else {
        expenses += entry.cents;
        categoryTotals.update(
          entry.category,
          (amount) => amount + entry.cents,
          ifAbsent: () => entry.cents,
        );
        final totals = monthExpenses.putIfAbsent(
          monthKey(entry.date),
          () => {},
        );
        totals.update(
          entry.category,
          (amount) => amount + entry.cents,
          ifAbsent: () => entry.cents,
        );
        // Overall and category budgets can overlap. Each expense contributes
        // once to coverage; budget limits themselves are never added together.
        if (store.budgetFor(entry.date) > 0 ||
            (invoiceCategories.contains(entry.category) &&
                store.budgetFor(entry.date, entry.category) > 0)) {
          budgetCovered += entry.cents;
        }
      }
    }
    final categoryRows =
        categoryTotals.entries
            .map((row) => ReportCategoryTotal(row.key, row.value))
            .toList()
          ..sort((a, b) {
            final amount = b.cents.compareTo(a.cents);
            return amount == 0 ? a.category.compareTo(b.category) : amount;
          });

    final budgetRows = <ReportBudgetPerformance>[];
    // Iterate saved budget months, rather than allocating every month in a
    // potentially centuries-long custom range.
    for (final key in store.budgets.keys) {
      final match = RegExp(r'^(\d{1,4})-(\d{2})$').firstMatch(key);
      if (match == null) continue;
      final year = int.parse(match.group(1)!);
      final monthNumber = int.parse(match.group(2)!);
      if (year < 1 || monthNumber < 1 || monthNumber > 12) continue;
      final month = DateTime(year, monthNumber);
      final end = DateTime(year, monthNumber + 1, 0);
      final coverageStart = _later(period.start ?? month, month);
      final coverageEnd = _earlier(period.end ?? end, end);
      if (coverageEnd.isBefore(coverageStart)) continue;
      for (final category in ['Overall', ...invoiceCategories]) {
        final limit = store.budgetFor(month, category);
        if (limit <= 0) continue;
        final selectedExpenses = monthExpenses[key] ?? const <String, int>{};
        final spent =
            category == 'Overall'
                ? selectedExpenses.values.fold(0, (a, b) => a + b)
                : selectedExpenses[category] ?? 0;
        budgetRows.add(
          ReportBudgetPerformance(
            month: month,
            category: category,
            limitCents: limit,
            spentCents: spent,
            coverageStart: coverageStart,
            coverageEnd: coverageEnd,
            partial: coverageStart != month || coverageEnd != end,
            isOngoing: !end.isBefore(today),
          ),
        );
      }
    }
    budgetRows.sort((a, b) {
      final month = a.month.compareTo(b.month);
      if (month != 0) return month;
      if (a.isOverall != b.isOverall) return a.isOverall ? -1 : 1;
      return a.category.compareTo(b.category);
    });

    final horizonEnd = _earlier(
      DateTime(today.year, today.month, today.day + 89),
      DateTime(9999, 12, 31),
    );
    final from = _later(period.start ?? today, today);
    final until = _earlier(period.end ?? horizonEnd, horizonEnd);
    final hasHorizon = !until.isBefore(from);
    final scheduled = <Entry>[];
    if (hasHorizon) {
      // Reuse the store's cursors, disabled schedules and deleted-occurrence
      // handling. The short, explicit horizon also bounds projection work.
      final recordedOccurrenceKeys =
          store.entries
              .where((entry) => !entry.isProjected)
              .map((entry) => _occurrenceKey(store, entry))
              .whereType<String>()
              .toSet();
      final seenIds = <String>{};
      final seenOccurrences = <String>{};
      for (final entry in store.entriesForRange(from, until, now: clock)) {
        if (!entry.isProjected) continue;
        final key = _occurrenceKey(store, entry);
        if (key != null &&
            (recordedOccurrenceKeys.contains(key) ||
                !seenOccurrences.add(key))) {
          continue;
        }
        if (seenIds.add(entry.id)) scheduled.add(entry);
      }
      scheduled.sort((a, b) {
        final date = a.date.compareTo(b.date);
        return date == 0 ? a.id.compareTo(b.id) : date;
      });
    }
    return FinancialReport._(
      name: store.name,
      currency: store.currency,
      period: period,
      generatedAt: clock,
      entries: entries,
      incomeCents: income,
      expenseCents: expenses,
      categories: categoryRows,
      trends: _trends(entries, period),
      budgets: budgetRows,
      recurringExpenses:
          entries
              .where((entry) => !entry.income && entry.recurringId != null)
              .toList(),
      scheduledTransactions: scheduled,
      commitmentStart: hasHorizon ? from : null,
      commitmentEnd: hasHorizon ? until : null,
      budgetCoveredExpenseCents: budgetCovered,
      hasRecordedFutureEntries: entries.any(
        (entry) => _day(entry.date).isAfter(today),
      ),
    );
  }
}

ReportTrendBucket? _highestExpenseMonth(List<Entry> entries) {
  final totals = <DateTime, List<int>>{};
  for (final entry in entries) {
    final month = DateTime(entry.date.year, entry.date.month);
    final amounts = totals.putIfAbsent(month, () => [0, 0]);
    amounts[entry.income ? 0 : 1] += entry.cents;
  }
  final candidates =
      totals.entries.where((row) => row.value[1] > 0).toList()..sort((a, b) {
        final amount = b.value[1].compareTo(a.value[1]);
        return amount == 0 ? a.key.compareTo(b.key) : amount;
      });
  if (candidates.isEmpty) return null;
  final highest = candidates.first;
  return ReportTrendBucket(
    start: highest.key,
    end: DateTime(highest.key.year, highest.key.month + 1, 0),
    incomeCents: highest.value[0],
    expenseCents: highest.value[1],
  );
}

List<ReportBudgetSummary> _summarizeBudgets(
  List<ReportBudgetPerformance> rows,
) {
  final groups = <String, List<ReportBudgetPerformance>>{};
  for (final row in rows) {
    groups.putIfAbsent(row.category, () => []).add(row);
  }
  final result =
      groups.entries
          .map(
            (group) => ReportBudgetSummary(
              category: group.key,
              limitCents: group.value.fold(
                0,
                (sum, row) => sum + row.limitCents,
              ),
              spentCents: group.value.fold(
                0,
                (sum, row) => sum + row.spentCents,
              ),
              monthCount: group.value.map((row) => row.month).toSet().length,
              partial: group.value.any((row) => row.partial),
              isOngoing: group.value.any((row) => row.isOngoing),
            ),
          )
          .toList();
  result.sort((a, b) {
    if (a.isOverall != b.isOverall) return a.isOverall ? 1 : -1;
    final amount = b.spentCents.compareTo(a.spentCents);
    return amount == 0 ? a.category.compareTo(b.category) : amount;
  });
  return result;
}

List<ReportMonthlyBudget> _monthlyBudgets(
  List<Entry> entries,
  List<ReportBudgetPerformance> budgets,
) {
  final actual = <DateTime, int>{};
  for (final entry in entries.where((entry) => !entry.income)) {
    final month = DateTime(entry.date.year, entry.date.month);
    actual.update(
      month,
      (sum) => sum + entry.cents,
      ifAbsent: () => entry.cents,
    );
  }
  final groups = <DateTime, List<ReportBudgetPerformance>>{};
  for (final row in budgets) {
    groups.putIfAbsent(row.month, () => []).add(row);
  }
  final result = <ReportMonthlyBudget>[];
  for (final group in groups.entries) {
    final overall = group.value.where((row) => row.isOverall).firstOrNull;
    final rows = overall == null ? group.value : [overall];
    final spent = rows.fold(0, (sum, row) => sum + row.spentCents);
    result.add(
      ReportMonthlyBudget(
        month: group.key,
        limitCents: rows.fold(0, (sum, row) => sum + row.limitCents),
        spentCents: spent,
        unbudgetedExpenseCents: (actual[group.key] ?? 0) - spent,
        partial: rows.any((row) => row.partial),
        isOngoing: rows.any((row) => row.isOngoing),
        usesOverall: overall != null,
      ),
    );
  }
  result.sort((a, b) => a.month.compareTo(b.month));
  return result;
}

String? _occurrenceKey(FinanceStore store, Entry entry) {
  if (entry.recurringId == null) return null;
  final root = store.recurringForEntry(entry)?.rootId ?? entry.recurringId;
  final date = _day(entry.recurringScheduledDate ?? entry.date);
  return '$root:${date.year}-${date.month}-${date.day}';
}

List<ReportTrendBucket> _trends(List<Entry> entries, ReportPeriod period) {
  if (entries.isEmpty && period.start == null) return [];
  // The dashboard groups stored calendar components. Mixed UTC/local entries
  // can sort by instant in a different order from their calendar dates.
  final dates = entries.map((entry) => _day(entry.date));
  final start = period.start ?? dates.reduce(_earlier);
  final end = period.end ?? dates.reduce(_later);
  final dayCount =
      DateTime.utc(
        end.year,
        end.month,
        end.day,
      ).difference(DateTime.utc(start.year, start.month, start.day)).inDays +
      1;
  final monthCount = (end.year - start.year) * 12 + end.month - start.month + 1;
  final bounds = <({DateTime start, DateTime end})>[];
  if (dayCount <= 62) {
    final daysPerBucket = (dayCount / 24).ceil();
    var cursor = start;
    while (!cursor.isAfter(end)) {
      final next = DateTime(
        cursor.year,
        cursor.month,
        cursor.day + daysPerBucket,
      );
      bounds.add((
        start: cursor,
        end: _earlier(DateTime(next.year, next.month, next.day - 1), end),
      ));
      cursor = next;
    }
  } else if (monthCount <= 24) {
    for (var index = 0; index < monthCount; index++) {
      final month = DateTime(start.year, start.month + index);
      bounds.add((
        start: _later(start, month),
        end: _earlier(end, DateTime(month.year, month.month + 1, 0)),
      ));
    }
  } else {
    final yearsPerBucket = ((end.year - start.year + 1) / 24).ceil();
    for (var year = start.year; year <= end.year; year += yearsPerBucket) {
      bounds.add((
        start: _later(start, DateTime(year)),
        end: _earlier(end, DateTime(year + yearsPerBucket, 1, 0)),
      ));
    }
  }
  final income = List<int>.filled(bounds.length, 0);
  final expense = List<int>.filled(bounds.length, 0);
  for (final entry in entries) {
    final date = _day(entry.date);
    final index = bounds.indexWhere(
      (bound) => !date.isBefore(bound.start) && !date.isAfter(bound.end),
    );
    if (entry.income) {
      income[index] += entry.cents;
    } else {
      expense[index] += entry.cents;
    }
  }
  return List.generate(
    bounds.length,
    (index) => ReportTrendBucket(
      start: bounds[index].start,
      end: bounds[index].end,
      incomeCents: income[index],
      expenseCents: expense[index],
    ),
  );
}
