import 'dart:convert';
import 'dart:io';

import 'package:financial_advisor/core/finance_store.dart';
import 'package:financial_advisor/core/financial_report.dart';
import 'package:financial_advisor/services/financial_report_pdf.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/report_design_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FinanceStore store;
  final generatedAt = DateTime(2026, 10, 3, 14, 30);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store =
        FinanceStore(await SharedPreferences.getInstance())
          ..name = 'سارة أحمد / Sara Ahmed'
          ..currency = 'SAR';
  });

  void seed() {
    store.entries = [
      for (var month = 7; month <= 10; month++) ...[
        Entry(
          id: 'salary-$month',
          merchant: 'Salary',
          cents: 1200000,
          date: DateTime(2026, month),
          category: 'Income',
          income: true,
        ),
        Entry(
          id: 'rent-$month',
          merchant: 'إيجار المنزل',
          cents: 350000,
          date: DateTime(2026, month, 2),
          category: 'Housing',
          recurringId: 'rent',
        ),
        Entry(
          id: 'groceries-$month',
          merchant: 'Weekly groceries',
          cents: month * 8500,
          date: DateTime(2026, month, 3),
          category: 'Food',
        ),
      ],
      Entry(
        id: 'transport',
        merchant: 'Metro pass',
        cents: 15000,
        date: DateTime(2026, 8, 3),
        category: 'Transportation',
      ),
      Entry(
        id: 'health',
        merchant: 'Pharmacy',
        cents: 47500,
        date: DateTime(2026, 9, 20),
        category: 'Healthcare',
      ),
      Entry(
        id: 'shopping',
        merchant: 'Home supplies',
        cents: 85300,
        date: DateTime(2026, 9, 27),
        category: 'Shopping',
      ),
    ];
    store.budgets = {
      for (var month = 7; month <= 10; month++)
        '2026-${month.toString().padLeft(2, '0')}': {
          'Food': 70000,
          'Housing': 350000,
          'Transportation': 20000,
        },
    };
    store.recurringTransactions = [
      RecurringTransaction(
        id: 'rent',
        merchant: 'إيجار المنزل',
        cents: 350000,
        category: 'Housing',
        income: false,
        startDate: DateTime(2026, 11, 2),
        frequency: RepeatFrequency.monthly,
      ),
      RecurringTransaction(
        id: 'salary',
        merchant: 'Salary',
        cents: 1200000,
        category: 'Income',
        income: true,
        startDate: DateTime(2026, 11),
        frequency: RepeatFrequency.monthly,
      ),
    ];
  }

  for (final language in ['en', 'ar']) {
    test(
      'builds $language PDF with bundled fonts, all charts and paginated tables',
      () async {
        seed();
        final report = FinancialReport.fromStore(
          store,
          generatedAt: generatedAt,
        );
        final bytes = await buildFinancialReportPdf(report, language: language);
        final serialized = latin1.decode(bytes);
        expect(serialized, startsWith('%PDF-1.5'));
        expect(serialized, contains('%%EOF'));
        expect(serialized, contains('/ToUnicode'));
        expect(serialized, contains('/FontFile2'));
        expect(
          RegExp(r'/Type\s*/Page\b').allMatches(serialized).length,
          greaterThanOrEqualTo(5),
        );
        expect(bytes.length, greaterThan(15000));
        expect(report.incomeCents, 4800000);
        expect(report.transactionCount, 15);
        if (const bool.fromEnvironment('WRITE_REPORT_FIXTURES')) {
          final directory = Directory('.dart_tool/report-qa')
            ..createSync(recursive: true);
          File(
            '${directory.path}/report-$language.pdf',
          ).writeAsBytesSync(bytes);
        }
      },
    );
  }

  for (final language in ['en', 'ar']) {
    test('approved $language design uses the full recorded fixture', () async {
      seedApprovedReportDesign(store);
      final report = FinancialReport.fromStore(
        store,
        generatedAt: DateTime(2026, 10, 4, 12),
      );
      final bytes = await buildFinancialReportPdf(report, language: language);
      expect(report.transactionCount, 218);
      expect(report.incomeCents, 7550000);
      expect(report.expenseCents, 5620000);
      expect(report.netCents, 1930000);
      expect(report.recurringExpenses, hasLength(54));
      final serialized = latin1.decode(bytes);
      expect(serialized, contains('/FontFile2'));
      expect(serialized, contains('/IBMPlexSansArabic-Regular'));
      // Five core sections plus the complete 90-day schedule continuation.
      // In particular, the two trend charts and their note fit on one page.
      expect(RegExp(r'/Type\s*/Page\b').allMatches(serialized), hasLength(6));
      if (const bool.fromEnvironment('WRITE_REPORT_FIXTURES')) {
        final directory = Directory('.dart_tool/report-qa')
          ..createSync(recursive: true);
        File(
          '${directory.path}/integrated-design-$language.pdf',
        ).writeAsBytesSync(bytes);
      }
    });
  }

  test(
    'empty custom period exports no-data states rather than failing on zero charts',
    () async {
      final report = FinancialReport.fromStore(
        store,
        period: ReportPeriod.range(DateTime(2026, 1, 5), DateTime(2026, 1, 7)),
        generatedAt: generatedAt,
      );
      final bytes = await buildFinancialReportPdf(report, language: 'ar');
      expect(latin1.decode(bytes), startsWith('%PDF-1.5'));
      expect(report.transactionCount, 0);
      expect(
        report.trends.every(
          (bucket) => bucket.expenseCents == 0 && bucket.incomeCents == 0,
        ),
        isTrue,
      );
    },
  );

  test(
    'Arabic monthly charts keep their filtered totals and full interval details',
    () async {
      seedApprovedReportDesign(store);
      final report = FinancialReport.fromStore(
        store,
        period: ReportPeriod.month(DateTime(2026, 9)),
        generatedAt: DateTime(2026, 10, 4, 12),
      );
      final bytes = await buildFinancialReportPdf(report, language: 'ar');
      expect(report.incomeCents, 1200000);
      expect(report.expenseCents, 1050000);
      expect(report.transactionCount, 36);
      expect(report.scheduledTransactions, isEmpty);
      expect(
        RegExp(r'/Type\s*/Page\b').allMatches(latin1.decode(bytes)),
        hasLength(6),
      );
      if (const bool.fromEnvironment('WRITE_REPORT_FIXTURES')) {
        File(
          '.dart_tool/report-qa/monthly-design-ar.pdf',
        ).writeAsBytesSync(bytes);
      }
    },
  );

  test(
    'long recurring history is summarized without losing amounts or occurrences',
    () async {
      store.entries = [
        for (var i = 0; i < 500; i++)
          Entry(
            id: '$i',
            merchant: 'Recurring expense $i with a descriptive merchant name',
            cents: 123456,
            date: DateTime(2026, 9, 1 + i % 28),
            category: 'Other',
            recurringId: 'series-$i',
          ),
      ];
      final report = FinancialReport.fromStore(store, generatedAt: generatedAt);
      final bytes = await buildFinancialReportPdf(report, language: 'en');
      final serialized = latin1.decode(bytes);
      expect(
        RegExp(r'/Type\s*/Page\b').allMatches(serialized).length,
        greaterThanOrEqualTo(5),
      );
      expect(report.recurringExpenses, hasLength(500));
      expect(report.recurringExpenseCents, 500 * 123456);
    },
  );

  test(
    '500 upcoming rows paginate beyond twenty pages without truncating the schedule',
    () async {
      store.recurringTransactions = [
        for (var i = 0; i < 500; i++)
          RecurringTransaction(
            id: 'future-$i',
            merchant: 'Upcoming commitment $i with a descriptive merchant name',
            cents: 12345,
            category: 'Other',
            income: false,
            startDate: DateTime(2026, 10, 5),
            endDate: DateTime(2026, 10, 5),
            frequency: RepeatFrequency.monthly,
          ),
      ];
      final report = FinancialReport.fromStore(store, generatedAt: generatedAt);
      final bytes = await buildFinancialReportPdf(report, language: 'en');
      expect(report.scheduledTransactions, hasLength(500));
      expect(report.scheduledExpenseCents, 500 * 12345);
      expect(
        RegExp(r'/Type\s*/Page\b').allMatches(latin1.decode(bytes)).length,
        greaterThan(20),
      );
    },
  );

  test(
    'a partial period with negative net amounts renders safely in Arabic',
    () async {
      store.entries = [
        Entry(
          id: 'expense',
          merchant: 'مصاريف مسجلة',
          cents: 32199,
          date: DateTime(2026, 9, 15),
          category: 'Other',
        ),
        Entry(
          id: 'income',
          merchant: 'دخل',
          cents: 10000,
          date: DateTime(2026, 9, 29),
          category: 'Income',
          income: true,
        ),
      ];
      final report = FinancialReport.fromStore(
        store,
        period: ReportPeriod.range(
          DateTime(2026, 9, 14),
          DateTime(2026, 10, 2),
        ),
        generatedAt: generatedAt,
      );
      final bytes = await buildFinancialReportPdf(report, language: 'ar');
      expect(report.netCents, -22199);
      expect(latin1.decode(bytes), contains('%%EOF'));
      if (const bool.fromEnvironment('WRITE_REPORT_FIXTURES')) {
        File(
          '.dart_tool/report-qa/negative-custom-ar.pdf',
        ).writeAsBytesSync(bytes);
      }
    },
  );
}
