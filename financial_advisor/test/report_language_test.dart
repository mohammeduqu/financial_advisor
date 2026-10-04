import 'package:financial_advisor/core/finance_store.dart';
import 'package:financial_advisor/core/financial_report.dart';
import 'package:financial_advisor/l10n/app_language.dart';
import 'package:financial_advisor/l10n/report_language.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/report_design_fixture.dart';

Entry record(
  String id,
  int cents,
  DateTime date, {
  String category = 'Food',
  bool income = false,
  String? recurringId,
}) => Entry(
  id: id,
  merchant: id,
  cents: cents,
  date: date,
  category: category,
  income: income,
  recurringId: recurringId,
);

void main() {
  const english = ReportCopy(languageCode: 'en');
  const arabicCopy = ReportCopy(languageCode: 'ar');
  late FinanceStore store;
  final generation = DateTime(2026, 10, 3);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = FinanceStore(await SharedPreferences.getInstance());
  });

  test('compact chart dates retain both boundaries and localize digits', () {
    final bucket = ReportTrendBucket(
      start: DateTime(2026, 9, 1),
      end: DateTime(2026, 9, 2),
      incomeCents: 0,
      expenseCents: 0,
    );
    expect(english.chartTrendLabel(bucket), '1 - 2\nSeptember 2026');
    expect(arabicCopy.chartTrendLabel(bucket), '١ - ٢\nسبتمبر ٢٠٢٦');
    expect(english.trendLabel(bucket), '1 September 2026 - 2 September 2026');
    final crossing = ReportTrendBucket(
      start: DateTime(2026, 12, 30),
      end: DateTime(2027, 1, 2),
      incomeCents: 0,
      expenseCents: 0,
    );
    expect(
      english.chartTrendLabel(crossing),
      '30 December 2026\n2 January 2027',
    );
  });

  test(
    'retained-share labels preserve negative values and hide undefined ratios',
    () {
      expect(english.percentage(-25599, 100000), '−25.6%');
      expect(arabicCopy.percentage(-1, 3), '−٣٣٫٣٪');
      expect(english.amountNumber(7550000), '75,500');
      expect(english.amountNumber(-25599), '−255.99');
      expect(arabicCopy.amountNumber(936667), '٩٬٣٦٦٫٦٧');
      final empty = FinancialReport.fromStore(store, generatedAt: generation);
      expect(english.retainedShare(empty), 'Not available');
      expect(arabicCopy.retainedShare(empty), 'غير متاح');
    },
  );

  test(
    'approved report narratives use only the snapshot totals and supported scenario',
    () {
      seedApprovedReportDesign(store);
      final report = FinancialReport.fromStore(
        store,
        generatedAt: DateTime(2026, 10, 4),
      );
      expect(english.overviewNarrative(report), contains('75,500.00 SAR'));
      expect(english.overviewNarrative(report), contains('19,300.00 SAR'));
      expect(
        english.transactionBreakdown(report),
        contains('218 recorded transactions'),
      );
      expect(english.retainedShare(report), '25.6%');
      expect(english.budgetNarrative(report), contains('800.00 SAR below'));
      expect(english.budgetNarrative(report), contains('covered months'));
      expect(
        english.trendNarrative(report),
        contains('3 of 6 completed months'),
      );
      expect(english.scenarioNarrative(report), contains('54,740.00 SAR'));
      expect(english.scenarioNarrative(report), contains('20,760.00 SAR'));
      expect(
        english.scenarioNarrative(report),
        contains('not a forecast or promised saving'),
      );
      expect(arabicCopy.scenarioNarrative(report), contains('٥٤٬٧٤٠٫٠٠ SAR'));
      expect(arabicCopy.scenarioNarrative(report), contains('وليست توقعاً'));
      expect(arabicCopy.budgetNarrative(report), contains('أشهرها'));
      expect(
        english.monthlyAverageCaption(report),
        contains('6 calendar months'),
      );
      expect(
        english.periodDetail(report),
        contains('All Time | Recorded dates:'),
      );
    },
  );

  test(
    'budget coverage copy discloses missing, partial and open budget months',
    () {
      store.entries = [
        record('food', 15000, DateTime(2026, 9, 12)),
        record('other', 90000, DateTime(2026, 9, 12), category: 'Other'),
      ];
      store.budgets = {
        '2026-09': {'Food': 10000, 'Overall': 100000},
      };
      final report = FinancialReport.fromStore(
        store,
        period: ReportPeriod.range(
          DateTime(2026, 9, 10),
          DateTime(2026, 9, 20),
        ),
        generatedAt: DateTime(2026, 9, 15),
      );
      final en = english.budgetCoverageNote(report);
      expect(en, contains('900.00 SAR'));
      expect(en, contains('not added to category limits'));
      expect(en, contains('limits are not prorated'));
      expect(en, contains('spending is not final'));
      expect(arabicCopy.budgetCoverageNote(report), contains('٩٠٠٫٠٠ SAR'));
      expect(report.budgetScenario, isNull);
    },
  );

  test('approved design section labels and data notes are fully localized', () {
    for (final label in [
      'Overview',
      'Spending & budget',
      'Spending trends',
      'Recurring & upcoming',
      'Insights & next steps',
      'Your money, in focus.',
      'Where your money goes',
      'The pattern behind the totals',
      'What is already committed',
      'Small changes, visible impact',
      'Recorded surplus',
      'Retained share',
      'Average monthly spend',
      'Highest spending month',
      'Months over budget',
      'Recorded recurring costs',
      'Combined budget gap',
      'Illustrative surplus',
      'Illustrative share',
      'Overall budgets',
      'Category budgets',
      'Positive variance means over budget; negative means under budget.',
      'No complete budget comparisons are available for this period.',
      'No expense categories exceed their complete budget-period limits.',
    ]) {
      expect(arabicCopy.t(label), isNot(label), reason: label);
      expect(arabicCopy.t(label), matches(RegExp(r'[\u0600-\u06ff]')));
    }
  });

  test('report numbers preserve cents, signs and account currency', () {
    expect(english.amount(123456, 'SAR'), '1,234.56 SAR');
    expect(english.amount(-1, 'USD'), '−0.01 USD');
    expect(english.amount(0, 'AED'), '0.00 AED');
    expect(arabicCopy.amount(123456, 'SAR'), '١٬٢٣٤٫٥٦ SAR');
    expect(arabicCopy.amount(-1, 'USD'), '−٠٫٠١ USD');
    expect(english.percentage(1, 3), '33.3%');
    expect(arabicCopy.percentage(1, 3), '٣٣٫٣٪');
    expect(english.percentage(0, 0), '0%');
    expect(arabicCopy.number(12000), '١٢٬٠٠٠');
  });

  test('report dates and selected periods need no locale initialization', () {
    expect(english.date(DateTime(2026, 10, 3)), '3 October 2026');
    expect(arabicCopy.date(DateTime(2026, 10, 3)), '٣ أكتوبر ٢٠٢٦');
    expect(english.period(const ReportPeriod.allTime()), 'All Time');
    expect(arabicCopy.period(const ReportPeriod.allTime()), 'جميع الفترات');
    expect(
      english.period(ReportPeriod.month(DateTime(2025, 12))),
      'December 2025',
    );
    expect(
      english.period(
        ReportPeriod.range(DateTime(2025, 12, 31), DateTime(2026, 1, 1)),
      ),
      '31 December 2025 - 1 January 2026',
    );
    expect(arabicCopy.page(2, 5), 'صفحة ٢ من ٥');
  });

  test('report scope and budget notes are localized without English fallback', () {
    for (final label in [
      'Open month',
      'Overall budgets and category budgets may overlap; do not add their limits together.',
      'Expenses without a budget',
      'No budgets are available for this reporting period.',
      'Only recorded transactions are included in totals. Scheduled projections are shown separately.',
      'Saved future-dated transactions are included in recorded totals, matching the dashboard. Scheduled projections are excluded.',
      'Review budgets exceeding their monthly limits and adjust upcoming category spending where practical.',
    ]) {
      expect(arabicCopy.t(label), isNot(label), reason: label);
      expect(arabicCopy.t(label), matches(RegExp(r'[\u0600-\u06ff]')));
      expect(english.t(label), label);
    }
  });

  test(
    'English report override is independent from Arabic app language',
    () async {
      await store.setLanguage('ar');
      expect(
        english.t('Financial behavior report'),
        'Financial behavior report',
      );
      expect(english.category('Food'), 'Food');
      expect(arabicCopy.category('Food'), translate('Food', 'ar'));
      expect(arabicCopy.t('Financial behavior report'), 'تقرير السلوك المالي');
      expect(english.amount(1599, 'SAR'), '15.99 SAR');
      expect(store.languageCode, 'ar');
    },
  );

  test(
    'empty records explicitly state insufficient data without conclusions',
    () {
      final report = FinancialReport.fromStore(store, generatedAt: generation);
      expect(
        english.summary(report).join(' '),
        contains('not enough recorded spending'),
      );
      expect(english.summary(report).join(' '), isNot(contains('largest')));
      expect(
        english.recommendations(report).single,
        contains('Add income and expenses'),
      );
      expect(
        arabicCopy.summary(report).join(' '),
        isNot(contains('No completed')),
      );
    },
  );

  test('narrative totals and largest category use only selected records', () {
    store.entries = [
      record('income', 10000, DateTime(2026, 9, 1), income: true),
      record('food', 7500, DateTime(2026, 9, 2)),
      record('travel', 2500, DateTime(2026, 9, 3), category: 'Travel'),
      record('other month', 900000, DateTime(2026, 8, 1), category: 'Shopping'),
    ];
    final report = FinancialReport.fromStore(
      store,
      period: ReportPeriod.month(DateTime(2026, 9)),
      generatedAt: generation,
    );
    final text = english.summary(report).join(' ');
    expect(text, contains('3 recorded transactions'));
    expect(text, contains('income of 100.00 SAR'));
    expect(text, contains('expenses of 100.00 SAR'));
    expect(text, contains('net amount of 0.00 SAR'));
    expect(text, contains('Food is the largest expense category at 75.00 SAR'));
    expect(text, contains('75%'));
    expect(text, isNot(contains('Shopping')));
    expect(text, isNot(contains('savings rate')));
    expect(
      english.recommendations(report).join(' '),
      contains('category budget limits'),
    );
  });

  test(
    'missing income never becomes an inferred saving or deficit assessment',
    () {
      store.entries = [record('meal', 1500, DateTime(2026, 9, 1))];
      final report = FinancialReport.fromStore(store, generatedAt: generation);
      expect(
        english.summary(report).join(' '),
        contains('No income is recorded'),
      );
      expect(
        english.recommendations(report).join(' '),
        contains('Record income'),
      );
      expect(
        english.recommendations(report).join(' '),
        isNot(contains('exceed recorded income')),
      );
      expect(arabicCopy.summary(report).join(' '), contains('١٥٫٠٠ SAR'));
      expect(arabicCopy.summary(report).join(' '), contains('الطعام'));
    },
  );

  test(
    'recorded income deficit is the exact difference without a forecast',
    () {
      store.entries = [
        record('income', 10000, DateTime(2026, 9, 1), income: true),
        record('expense', 12599, DateTime(2026, 9, 2)),
      ];
      final report = FinancialReport.fromStore(store, generatedAt: generation);
      expect(english.recommendations(report).first, contains('by 25.99 SAR'));
      expect(
        english.summary(report).first,
        contains('net amount of −25.99 SAR'),
      );
    },
  );

  test(
    'partial budgets disclose full limits and do not sum overlapping limits',
    () {
      store.entries = [record('meal', 15000, DateTime(2026, 9, 12))];
      store.budgets = {
        '2026-09': {'Overall': 12000, 'Food': 10000},
      };
      final report = FinancialReport.fromStore(
        store,
        period: ReportPeriod.range(
          DateTime(2026, 9, 10),
          DateTime(2026, 9, 15),
        ),
        generatedAt: generation,
      );
      final text = english.summary(report).join(' ');
      expect(text, contains('2 displayed budget rows'));
      expect(text, contains('full monthly limit; limits are not prorated'));
      expect(text, isNot(contains('220.00')));
      expect(
        english.recommendations(report).join(' '),
        isNot(contains('overall budget')),
      );
    },
  );

  test(
    'recurring summary counts recorded expenses once and labels projections',
    () {
      store.entries = [
        record(
          'subscription',
          2500,
          DateTime(2026, 9, 1),
          recurringId: 'repeat',
        ),
        record(
          'salary',
          100000,
          DateTime(2026, 9, 1),
          income: true,
          recurringId: 'salary',
        ),
      ];
      store.recurringTransactions = [
        RecurringTransaction(
          id: 'repeat',
          merchant: 'subscription',
          cents: 2500,
          category: 'Subscriptions',
          income: false,
          startDate: DateTime(2026, 11, 1),
          frequency: RepeatFrequency.monthly,
        ),
      ];
      final report = FinancialReport.fromStore(store, generatedAt: generation);
      final summary = english.summary(report).join(' ');
      expect(
        summary,
        contains('1 recorded recurring expense transaction totals 25.00 SAR'),
      );
      expect(summary, contains('expenses of 25.00 SAR'));
      final actions = english.recommendations(report).join(' ');
      expect(actions, contains('schedule projections, not recorded expenses'));
      expect(actions, contains('scheduled expenses of 50.00 SAR'));
    },
  );

  test(
    'trend statement identifies an actual interval without fabricated growth',
    () {
      store.entries = [
        record('first', 2000, DateTime(2026, 6, 2)),
        record('second', 4000, DateTime(2026, 9, 2)),
      ];
      final report = FinancialReport.fromStore(store, generatedAt: generation);
      final text = english.summary(report).join(' ');
      expect(text, contains('highest expense total'));
      expect(text, contains('40.00 SAR'));
      expect(text, contains('Interval length and coverage may differ'));
      expect(text, isNot(contains('increased')));
      expect(text, isNot(contains('forecast')));
    },
  );

  test(
    'export UI copy has Arabic labels and keeps raw identifiers untouched',
    () {
      for (final label in [
        'Export PDF Report',
        'Reporting period',
        'All Time',
        'Month and year',
        'Custom date range',
        'Report language',
        'App language',
        'English',
        'Start date',
        'End date',
        'Preview report',
        'Preparing your report…',
        'Could not create the report. Please try again.',
        'Retry',
        'Save PDF',
        'Share PDF',
        'Save or print',
      ]) {
        expect(translate(label, 'ar'), isNot(label), reason: label);
      }
      expect(
        english.category('User entered category'),
        'User entered category',
      );
    },
  );
}
