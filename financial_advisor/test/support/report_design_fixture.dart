import 'package:financial_advisor/core/finance_store.dart';

/// Fictional ledger used only by tests and local visual verification.
/// The approved design contains the same 218 entries and six-month totals.
void seedApprovedReportDesign(FinanceStore store) {
  const amounts = <String, List<int>>{
    'Housing': [3500, 3500, 3500, 3500, 3500, 3500],
    'Food': [1800, 2000, 2200, 2150, 2500, 2650],
    'Shopping': [800, 900, 1800, 1300, 1500, 1700],
    'Utilities': [700, 720, 800, 780, 820, 800],
    'Transportation': [650, 650, 700, 750, 800, 800],
    'Entertainment': [450, 580, 700, 120, 160, 450],
    'Healthcare': [100, 100, 150, 100, 150, 200],
    'Subscriptions': [200, 200, 250, 300, 320, 400],
  };
  const counts = <String, int>{
    'Housing': 1,
    'Food': 12,
    'Shopping': 4,
    'Utilities': 4,
    'Transportation': 6,
    'Entertainment': 3,
    'Healthcare': 1,
    'Subscriptions': 4,
  };
  const limits = <String, int>{
    'Housing': 350000,
    'Food': 240000,
    'Shopping': 120000,
    'Utilities': 80000,
    'Transportation': 80000,
    'Entertainment': 30000,
    'Healthcare': 20000,
    'Subscriptions': 30000,
  };
  const recurringDays = <String, List<int>>{
    'Housing': [1],
    'Utilities': [5, 8, 12, 20],
    'Subscriptions': [6, 10, 15, 22],
  };
  const merchants = <String, List<String>>{
    'Housing': ['الإيجار / Rent'],
    'Utilities': ['Electricity', 'Internet', 'Mobile plan', 'Water'],
    'Subscriptions': [
      'Gym membership',
      'Streaming',
      'Cloud storage',
      'Learning service',
    ],
  };
  final entries = <Entry>[];
  for (var month = 4; month <= 9; month++) {
    for (final row in amounts.entries) {
      final count = counts[row.key]!;
      final cents = row.value[month - 4] * 100;
      for (var index = 0; index < count; index++) {
        final scheduledDays = recurringDays[row.key];
        final day =
            scheduledDays?[index] ??
            (2 + index * 26 ~/ (count > 1 ? count - 1 : 1));
        final recurringId =
            scheduledDays == null ? null : 'schedule-${row.key}-$index';
        final date = DateTime(2026, month, day);
        entries.add(
          Entry(
            id: '$month-${row.key}-$index',
            merchant: merchants[row.key]?[index] ?? '${row.key} purchase',
            cents: cents ~/ count + (index < cents % count ? 1 : 0),
            date: date,
            category: row.key,
            recurringId: recurringId,
            recurringScheduleId: recurringId,
            recurringScheduledDate: recurringId == null ? null : date,
          ),
        );
      }
    }
    entries.add(
      Entry(
        id: 'salary-$month',
        merchant: 'Salary',
        cents: 1200000,
        date: DateTime(2026, month, 27),
        category: 'Income',
        income: true,
        recurringId: 'salary',
        recurringScheduleId: 'salary',
        recurringScheduledDate: DateTime(2026, month, 27),
      ),
    );
  }
  entries.addAll([
    Entry(
      id: 'june-bonus',
      merchant: 'Bonus',
      cents: 200000,
      date: DateTime(2026, 6, 15),
      category: 'Income',
      income: true,
    ),
    Entry(
      id: 'august-freelance',
      merchant: 'Freelance work',
      cents: 150000,
      date: DateTime(2026, 8, 15),
      category: 'Income',
      income: true,
    ),
  ]);
  const nextAmounts = <String, List<int>>{
    'Housing': [350000],
    'Utilities': [31000, 25000, 18000, 6000],
    'Subscriptions': [18000, 9000, 5000, 8000],
  };
  store
    ..name = 'Design validation / تحقق التصميم'
    ..currency = 'SAR'
    ..entries = entries
    ..budgets = {
      for (var month = 4; month <= 9; month++)
        '2026-${month.toString().padLeft(2, '0')}': Map.of(limits),
    }
    ..recurringTransactions = [
      for (final row in recurringDays.entries)
        for (var index = 0; index < row.value.length; index++)
          RecurringTransaction(
            id: 'schedule-${row.key}-$index',
            merchant: merchants[row.key]![index],
            cents: nextAmounts[row.key]![index],
            category: row.key,
            income: false,
            startDate: DateTime(
              2026,
              row.key == 'Housing' ? 11 : 10,
              row.value[index],
            ),
            frequency: RepeatFrequency.monthly,
          ),
      RecurringTransaction(
        id: 'salary',
        merchant: 'Salary',
        cents: 1200000,
        category: 'Income',
        income: true,
        startDate: DateTime(2026, 10, 27),
        frequency: RepeatFrequency.monthly,
      ),
    ];
}
