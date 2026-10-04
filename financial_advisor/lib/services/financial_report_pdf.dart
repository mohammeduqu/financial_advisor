import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../core/financial_report.dart';
import '../l10n/report_language.dart';

/// Builds one local, self-contained report from a read-only financial snapshot.
Future<Uint8List> buildFinancialReportPdf(
  FinancialReport report, {
  required String language,
}) async {
  // Test asset bundles can return synchronous futures: await each explicitly.
  final fonts = <ByteData>[
    await rootBundle.load('assets/fonts/Lato-Regular.ttf'),
    await rootBundle.load('assets/fonts/Lato-Bold.ttf'),
    await rootBundle.load('assets/fonts/IBMPlexSansArabic-Regular.ttf'),
    await rootBundle.load('assets/fonts/IBMPlexSansArabic-SemiBold.ttf'),
  ];
  return _ReportPdf(
    report,
    ReportCopy(languageCode: language == 'ar' ? 'ar' : 'en'),
    latin: pw.Font.ttf(fonts[0]),
    latinBold: pw.Font.ttf(fonts[1]),
    arabic: pw.Font.ttf(fonts[2]),
    arabicBold: pw.Font.ttf(fonts[3]),
  ).build();
}

class _ReportPdf {
  _ReportPdf(
    this.report,
    this.copy, {
    required this.latin,
    required this.latinBold,
    required this.arabic,
    required this.arabicBold,
  });
  final FinancialReport report;
  final ReportCopy copy;
  final pw.Font latin, latinBold, arabic, arabicBold;
  static const navy = PdfColor.fromInt(0xff172d47);
  static const muted = PdfColor.fromInt(0xff63768c);
  static const blue = PdfColor.fromInt(0xff247cb6);
  static const orange = PdfColor.fromInt(0xfff28a32);
  static const pale = PdfColor.fromInt(0xfff1f6fa);
  static const line = PdfColor.fromInt(0xffdce6ee);
  static final arabicText = RegExp(
    r'[\u0600-\u06ff\u0750-\u077f\u08a0-\u08ff]',
  );
  static final unicodeLetter = RegExp(r'\p{L}', unicode: true);
  bool get rtl => copy.isArabic;
  pw.TextDirection get direction =>
      rtl ? pw.TextDirection.rtl : pw.TextDirection.ltr;
  pw.TextAlign get startAlign => rtl ? pw.TextAlign.right : pw.TextAlign.left;
  pw.TextAlign get endAlign => rtl ? pw.TextAlign.left : pw.TextAlign.right;
  String amount(int cents) => copy.amount(cents, report.currency);
  String numberAmount(int cents) => copy.amountNumber(cents);

  pw.Widget text(
    String value, {
    double size = 9.3,
    bool bold = false,
    PdfColor color = navy,
    pw.TextAlign? align,
  }) {
    final hasArabic = arabicText.hasMatch(value);
    // Arabic digits need the Arabic font, but numeric expressions retain their
    // left-to-right order (amount | percentage, negative values, and ratios).
    final hasArabicLetters = arabicText
        .allMatches(value)
        .any((match) => unicodeLetter.hasMatch(match[0]!));
    return pw.Text(
      value,
      textDirection:
          hasArabicLetters ? pw.TextDirection.rtl : pw.TextDirection.ltr,
      textAlign: align ?? startAlign,
      style: pw.TextStyle(
        font:
            hasArabic
                ? (bold ? arabicBold : arabic)
                : (bold ? latinBold : latin),
        fontFallback: [arabic, latin],
        fontSize: size,
        color: color,
        lineSpacing: hasArabic ? 2.2 : 1.6,
      ),
    );
  }

  Future<Uint8List> build() async {
    final document = pw.Document(
      title: copy.t('Financial behavior report'),
      author: 'Tadbeer',
      creator: 'Tadbeer',
      subject: copy.periodDetail(report),
      theme: pw.ThemeData.withFont(
        base: rtl ? arabic : latin,
        bold: rtl ? arabicBold : latinBold,
        fontFallback: [arabic, latin],
      ),
    );
    addSection(
      document,
      1,
      'Overview',
      'Your money, in focus.',
      '${report.name}\n${copy.periodDetail(report)} | ${copy.t('Generated on')}: ${copy.date(report.generatedAt)}',
      overview(),
    );
    addSection(
      document,
      2,
      'Spending & budget',
      'Where your money goes',
      '${copy.periodDetail(report)} | ${copy.t('Amounts in')} ${report.currency}',
      spending(),
    );
    addSection(
      document,
      3,
      'Spending trends',
      'The pattern behind the totals',
      copy.periodDetail(report),
      trends(),
    );
    addSection(
      document,
      4,
      'Recurring & upcoming',
      'What is already committed',
      copy.t(
        'Only recorded transactions are included in totals. Scheduled projections are shown separately.',
      ),
      commitments(),
    );
    addSection(
      document,
      5,
      'Insights & next steps',
      'Small changes, visible impact',
      copy.t('Budget comparison'),
      insights(),
    );
    return document.save();
  }

  void addSection(
    pw.Document document,
    int index,
    String label,
    String title,
    String subtitle,
    List<pw.Widget> content,
  ) {
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(42, 23, 42, 25),
        textDirection: direction,
        // Real schedules and budget details can legitimately exceed 20 pages.
        maxPages: math.max(
          30,
          (report.scheduledTransactions.length + report.budgets.length) ~/ 5 +
              20,
        ),
        header: (_) => header(),
        footer: (context) => footer(context, label),
        build:
            (_) => [
              pw.SizedBox(height: 13),
              text(
                '${copy.number(index).padLeft(rtl ? 1 : 2, '0')} / ${copy.t(label)}',
                size: 8.5,
                bold: true,
                color: blue,
              ),
              pw.SizedBox(height: 10),
              text(copy.t(title), size: rtl ? 25 : 27, bold: true),
              pw.SizedBox(height: 9),
              text(subtitle, size: 9, color: muted),
              pw.SizedBox(height: 18),
              ...content,
            ],
      ),
    );
  }

  pw.Widget header() => pw.SizedBox(
    height: 43,
    width: double.infinity,
    child: pw.Stack(
      children: [
        pw.Positioned(
          left: 0,
          right: 0,
          top: 0,
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              text(rtl ? 'تدبير.' : 'tadbeer.', size: 22, bold: true),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  text(
                    copy.t('Financial behavior report'),
                    size: 8,
                    bold: true,
                    color: blue,
                    align: endAlign,
                  ),
                  pw.SizedBox(height: 4),
                  text(
                    '${copy.t('Amounts in')} ${report.currency}',
                    size: 7.5,
                    color: muted,
                    align: endAlign,
                  ),
                ],
              ),
            ],
          ),
        ),
        pw.Positioned(
          bottom: 4,
          left: 0,
          right: 0,
          child: pw.Container(height: .65, color: line),
        ),
      ],
    ),
  );

  pw.Widget footer(pw.Context context, String section) => pw.Padding(
    padding: const pw.EdgeInsets.only(top: 12),
    child: pw.Column(
      children: [
        pw.Container(height: .6, color: line),
        pw.SizedBox(height: 7),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Expanded(
              child: text(copy.period(report.period), size: 7, color: muted),
            ),
            pw.SizedBox(width: 12),
            text(
              '${copy.t(section)} | ${copy.page(context.pageNumber, context.pagesCount)}',
              size: 7,
              color: muted,
            ),
          ],
        ),
      ],
    ),
  );

  List<pw.Widget> overview() => [
    cards([
      _Metric(
        'Total income',
        numberAmount(report.incomeCents),
        '${report.currency} | ${copy.t('Recorded income')}',
      ),
      _Metric(
        'Total expenses',
        numberAmount(report.expenseCents),
        '${report.currency} | ${copy.t('Recorded expenses')}',
      ),
      _Metric(
        'Net amount',
        numberAmount(report.netCents),
        '${report.currency} | ${copy.t('Income less expenses')}',
      ),
      _Metric(
        'Retained share',
        copy.retainedShare(report),
        copy.t('Surplus as a share of income'),
      ),
    ]),
    pw.SizedBox(height: 11),
    text(copy.transactionBreakdown(report), size: 9, bold: true, color: muted),
    if (report.hasRecordedFutureEntries) ...[
      pw.SizedBox(height: 7),
      note(
        'Saved future-dated transactions are included in recorded totals, matching the dashboard. Scheduled projections are excluded.',
      ),
    ],
    ...section('Income versus expenses', space: 17),
    if (report.entries.isEmpty)
      empty('No recorded transactions in this period.')
    else
      chart(
        labels: trendLabels(),
        series: [
          report.trends.map((e) => e.incomeCents).toList(),
          report.trends.map((e) => e.expenseCents).toList(),
        ],
        names: ['Income', 'Expenses'],
        kind: _ChartKind.grouped,
        height: 165,
      ),
    pw.SizedBox(height: 7),
    text(copy.overviewNarrative(report), size: 8.7, color: muted),
    pw.SizedBox(height: 16),
    pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: insightCard('Recorded results', copy.summary(report).first),
        ),
        pw.SizedBox(width: 10),
        pw.Expanded(
          child: insightCard(
            'Spending focus',
            copy.summary(report).skip(1).firstOrNull ??
                copy.overviewNarrative(report),
          ),
        ),
      ],
    ),
    pw.SizedBox(height: 13),
    notice(
      'How to read this report',
      copy.t(
        'The net amount is recorded income less recorded expenses. It is not a verified bank balance or confirmed savings. Scheduled projections are shown separately.',
      ),
    ),
  ];

  List<pw.Widget> spending() {
    final categoryBudgets =
        report.budgetSummaries.where((row) => !row.isOverall).toList();
    final overall =
        report.budgetSummaries.where((row) => row.isOverall).toList();
    return [
      ...section('Spending by category', space: 5),
      if (report.categories.isEmpty)
        empty('No expenses in this period.')
      else
        ...categoryBars(),
      pw.SizedBox(height: 7),
      if (report.categories.isNotEmpty)
        text(
          '${copy.t('Total expenses')}: ${amount(report.expenseCents)}',
          size: 8.7,
          color: muted,
        ),
      ...section(
        'Budget performance across the selected period',
        space: 18,
        minSpace: 150,
      ),
      if (report.budgetSummaries.isEmpty)
        empty('No budgets are available for this reporting period.')
      else ...[
        text(copy.budgetNarrative(report), size: 8.7, color: muted),
        pw.SizedBox(height: 10),
        if (categoryBudgets.isNotEmpty)
          table(
            ['Category', 'Budget', 'Actual', 'Over / under'],
            [
              for (final row in categoryBudgets)
                [
                  copy.category(row.category),
                  numberAmount(row.limitCents),
                  numberAmount(row.spentCents),
                  signedAmount(row.varianceCents),
                ],
              [
                copy.t('Total'),
                numberAmount(report.categoryBudgetLimitCents),
                numberAmount(report.categoryBudgetSpentCents),
                signedAmount(
                  report.categoryBudgetSpentCents -
                      report.categoryBudgetLimitCents,
                ),
              ],
            ],
            widths: [1.6, 1, 1, 1],
            totalLast: true,
          ),
        if (overall.isNotEmpty) ...[
          ...section('Overall budget comparison', space: 14, minSpace: 100),
          table(
            ['Budget', 'Actual', 'Over / under'],
            [
              for (final row in overall)
                [
                  numberAmount(row.limitCents),
                  numberAmount(row.spentCents),
                  signedAmount(row.varianceCents),
                ],
            ],
            widths: [1, 1, 1],
            textColumns: const {},
          ),
        ],
        pw.SizedBox(height: 8),
        note(
          'Positive variance means over budget; negative means under budget.',
        ),
        pw.SizedBox(height: 5),
        text(copy.budgetCoverageNote(report), size: 8, color: muted),
        if (report.budgetSummaries.any((row) => row.partial || row.isOngoing) ||
            report.budgetSummaries.map((row) => row.monthCount).toSet().length >
                1) ...[
          ...section('Budget coverage', space: 14, minSpace: 110),
          table(
            ['Category', 'Covered months', 'Coverage'],
            [
              for (final row in report.budgetSummaries)
                [
                  copy.category(row.category),
                  copy.number(row.monthCount),
                  [
                    if (row.partial) copy.t('Partial coverage'),
                    if (row.isOngoing) copy.t('Open month'),
                    if (!row.partial && !row.isOngoing) copy.t('Full month'),
                  ].join(' / '),
                ],
            ],
            widths: [1.5, .9, 1.7],
            textColumns: const {0, 2},
          ),
        ],
      ],
    ];
  }

  List<pw.Widget> trends() {
    final monthlyBudget = matchingTrendBudgets();
    return [
      cards([
        _Metric(
          'Average monthly spend',
          report.averageMonthlyExpenseCents == null
              ? copy.t('Not available')
              : numberAmount(report.averageMonthlyExpenseCents!),
          report.currency,
        ),
        _Metric(
          'Highest spending month',
          report.highestExpenseMonth == null
              ? copy.t('Not available')
              : numberAmount(report.highestExpenseMonth!.expenseCents),
          report.highestExpenseMonth == null
              ? copy.t('No expenses in this period.')
              : copy.month(report.highestExpenseMonth!.start),
        ),
        _Metric(
          'Months over budget',
          report.comparableBudgetMonthCount == 0
              ? copy.t('Not available')
              : '${copy.number(report.overBudgetMonthCount)} / ${copy.number(report.comparableBudgetMonthCount)}',
          copy.t('Comparable months'),
        ),
      ]),
      pw.SizedBox(height: 9),
      text(copy.monthlyAverageCaption(report), size: 8, color: muted),
      ...section('Expenses by period', space: 14),
      if (report.entries.isEmpty)
        empty('No recorded transactions in this period.')
      else
        chart(
          labels: trendLabels(),
          series: [
            report.trends.map((e) => e.expenseCents).toList(),
            if (monthlyBudget != null) monthlyBudget,
          ],
          names: [
            'Expenses',
            if (monthlyBudget != null) 'Saved monthly budget',
          ],
          kind: _ChartKind.line,
          height: 100,
        ),
      pw.SizedBox(height: 5),
      text(copy.trendNarrative(report), size: 8.5, color: muted),
      ...section('Net amount by period', space: 14, minSpace: 190),
      if (report.entries.isEmpty)
        empty('No recorded transactions in this period.')
      else
        chart(
          labels: trendLabels(),
          series: [
            report.trends.map((e) => e.incomeCents - e.expenseCents).toList(),
          ],
          names: const [],
          kind: _ChartKind.bars,
          height: 104,
        ),
      pw.SizedBox(height: 6),
      note(
        'The net amount is recorded income less recorded expenses. It is not a verified bank balance or confirmed savings. Scheduled projections are shown separately.',
      ),
      if (report.trends.length > 8) ...[
        ...section('Expense trend details', space: 17, minSpace: 110),
        table(
          ['Interval', 'Income', 'Expenses', 'Net amount'],
          [
            for (final bucket in report.trends)
              [
                copy.trendLabel(bucket),
                numberAmount(bucket.incomeCents),
                numberAmount(bucket.expenseCents),
                numberAmount(bucket.incomeCents - bucket.expenseCents),
              ],
          ],
          widths: [2.1, 1, 1, 1],
        ),
      ],
    ];
  }

  List<pw.Widget> commitments() {
    final recurringCategories = <String, int>{};
    for (final entry in report.recurringExpenses) {
      recurringCategories.update(
        entry.category,
        (value) => value + entry.cents,
        ifAbsent: () => entry.cents,
      );
    }
    final recurring =
        recurringCategories.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
    return [
      cards([
        _Metric(
          'Recorded recurring costs',
          numberAmount(report.recurringExpenseCents),
          '${report.currency} | ${copy.t('Already included in expenses')}',
        ),
        _Metric(
          'Recorded occurrences',
          copy.number(report.recurringExpenses.length),
          copy.t('Each occurrence is counted once'),
        ),
        _Metric(
          'Share of all expenses',
          report.expenseCents == 0
              ? copy.t('Not available')
              : copy.percentage(
                report.recurringExpenseCents,
                report.expenseCents,
              ),
          copy.t('Recorded expenses'),
        ),
      ]),
      pw.SizedBox(height: 10),
      if (recurring.isEmpty)
        empty('No recurring expenses were recorded in this reporting period.')
      else
        text(
          recurring
              .map(
                (item) => '${copy.category(item.key)}: ${amount(item.value)}',
              )
              .join(' | '),
          size: 8.5,
          color: muted,
        ),
      ...section('Upcoming commitments', space: 20, minSpace: 195),
      if (report.commitmentStart != null && report.commitmentEnd != null) ...[
        text(
          '${copy.date(report.commitmentStart!)} - ${copy.date(report.commitmentEnd!)}',
          size: 9,
          color: muted,
        ),
        pw.SizedBox(height: 10),
      ],
      if (report.scheduledTransactions.isEmpty)
        empty('No scheduled transactions fall within this report window.')
      else ...[
        cards([
          _Metric(
            'Scheduled income',
            numberAmount(report.scheduledIncomeCents),
            report.currency,
          ),
          _Metric(
            'Scheduled expenses',
            numberAmount(report.scheduledExpenseCents),
            report.currency,
          ),
          _Metric(
            'Before variable costs',
            numberAmount(
              report.scheduledIncomeCents - report.scheduledExpenseCents,
            ),
            copy.t('Not confirmed savings'),
          ),
        ]),
        pw.SizedBox(height: 12),
        table(
          ['Date', 'Scheduled item', 'Type', 'Amount'],
          [
            for (final entry in report.scheduledTransactions)
              [
                copy.date(entry.date),
                entry.merchant,
                copy.t(entry.income ? 'Income' : 'Expense'),
                signedAmount(entry.income ? entry.cents : -entry.cents),
              ],
          ],
          widths: [1.2, 2.1, .85, 1.1],
          textColumns: const {0, 1, 2},
        ),
      ],
      pw.SizedBox(height: 14),
      notice(
        'A schedule is not a completed payment',
        copy.t(
          'Scheduled income and expenses are projections, excluded from recorded totals. Variable costs are not included in the difference.',
        ),
      ),
    ];
  }

  List<pw.Widget> insights() {
    final scenario = report.budgetScenario;
    return [
      if (scenario != null) ...[
        ...section('Categories above their saved limits', space: 4),
        chart(
          labels:
              scenario.categories
                  .map((row) => copy.category(row.category))
                  .toList(),
          series: [
            scenario.categories.map((row) => row.spentCents).toList(),
            scenario.categories.map((row) => row.limitCents).toList(),
          ],
          names: ['Recorded spending', 'Saved budget'],
          kind: _ChartKind.grouped,
          height: 128,
        ),
        pw.SizedBox(height: 15),
        cards([
          _Metric(
            'Combined budget gap',
            numberAmount(scenario.reductionCents),
            report.currency,
          ),
          _Metric(
            'Illustrative net amount',
            numberAmount(scenario.netCents),
            copy.t('If these limits were met'),
          ),
          _Metric(
            'Illustrative share',
            scenario.incomeCents <= 0
                ? copy.t('Not available')
                : copy.percentage(scenario.netCents, scenario.incomeCents),
            copy.t('With every other amount unchanged'),
          ),
        ]),
        pw.SizedBox(height: 10),
        text(copy.scenarioNarrative(report), size: 8.5, color: muted),
        if (scenario.categories.length > 8) ...[
          pw.SizedBox(height: 10),
          table(
            ['Category', 'Saved budget', 'Recorded spending', 'Over / under'],
            [
              for (final row in scenario.categories)
                [
                  copy.category(row.category),
                  numberAmount(row.limitCents),
                  numberAmount(row.spentCents),
                  signedAmount(row.varianceCents),
                ],
            ],
            widths: [1.7, 1, 1, 1],
          ),
        ],
      ] else ...[
        ...section('Financial behavior summary', space: 4),
        for (final item in copy.summary(report)) bullet(item),
      ],
      ...section('Suggested next steps', space: 20, minSpace: 100),
      for (final (index, item) in copy.recommendations(report).indexed)
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 9),
          child: text('${copy.number(index + 1)}. $item', size: 9),
        ),
      pw.SizedBox(height: 15),
      pw.Container(height: .6, color: line),
      pw.SizedBox(height: 8),
      note('This report reflects data recorded in Tadbeer at generation time.'),
      pw.SizedBox(height: 4),
      note(
        'All amounts use the account currency; no exchange-rate conversion is applied.',
      ),
    ];
  }

  List<String> trendLabels() =>
      report.trends.map(copy.chartTrendLabel).toList();

  List<int>? matchingTrendBudgets() {
    if (report.trends.length < 2) return null;
    final months = <(int, int)>{};
    final limits = <int>[];
    for (final bucket in report.trends) {
      // A last recorded date can precede month-end in All Time. Compare its
      // monthly bucket only when budget coverage independently covers the full
      // closed month. Distinct month keys prevent comparing daily buckets with
      // monthly limits; multi-month buckets are also excluded.
      if (bucket.start.year != bucket.end.year ||
          bucket.start.month != bucket.end.month ||
          !months.add((bucket.start.year, bucket.start.month))) {
        return null;
      }
      final row =
          report.monthlyBudgets
              .where(
                (row) =>
                    row.month.year == bucket.start.year &&
                    row.month.month == bucket.start.month &&
                    !row.partial &&
                    !row.isOngoing &&
                    row.fullyCovered,
              )
              .firstOrNull;
      if (row == null) return null;
      limits.add(row.limitCents);
    }
    return limits;
  }

  String signedAmount(int cents) =>
      '${cents > 0 ? '+' : ''}${numberAmount(cents)}';

  pw.Widget cards(List<_Metric> items) => pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      for (var i = 0; i < items.length; i++) ...[
        if (i != 0) pw.SizedBox(width: 9),
        pw.Expanded(
          child: pw.Container(
            height: 81,
            padding: const pw.EdgeInsets.all(10),
            color: pale,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                text(
                  rtl
                      ? copy.t(items[i].label)
                      : copy.t(items[i].label).toUpperCase(),
                  size: 7.2,
                  bold: true,
                  color: muted,
                ),
                pw.SizedBox(height: 8),
                pw.SizedBox(
                  height: 26,
                  width: double.infinity,
                  child: pw.FittedBox(
                    fit: pw.BoxFit.scaleDown,
                    alignment:
                        rtl
                            ? pw.Alignment.centerRight
                            : pw.Alignment.centerLeft,
                    child: text(
                      items[i].value,
                      size: items.length == 4 ? 22 : 24,
                      bold: true,
                    ),
                  ),
                ),
                pw.SizedBox(height: 5),
                text(items[i].note, size: 7.2, color: muted),
              ],
            ),
          ),
        ),
      ],
    ],
  );

  List<pw.Widget> section(
    String title, {
    double space = 14,
    double minSpace = 70,
  }) => [
    pw.NewPage(freeSpace: minSpace),
    pw.SizedBox(height: space),
    text(copy.t(title), size: 13.4, bold: true),
    pw.SizedBox(height: 10),
  ];
  pw.Widget note(String key) => text(copy.t(key), size: 8, color: muted);
  pw.Widget empty(String key) => pw.Container(
    width: double.infinity,
    padding: const pw.EdgeInsets.all(13),
    color: pale,
    child: text(copy.t(key), size: 9, color: muted),
  );
  pw.Widget insightCard(String title, String content) => pw.Container(
    padding: const pw.EdgeInsets.all(12),
    color: pale,
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        text(copy.t(title), size: 10, bold: true),
        pw.SizedBox(height: 6),
        text(content, size: 8.6),
      ],
    ),
  );
  pw.Widget notice(String title, String body) => pw.Container(
    padding: const pw.EdgeInsets.all(12),
    decoration: pw.BoxDecoration(
      color: pale,
      border:
          rtl
              ? const pw.Border(right: pw.BorderSide(color: blue, width: 2.4))
              : const pw.Border(left: pw.BorderSide(color: blue, width: 2.4)),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        text(copy.t(title), size: 10, bold: true),
        pw.SizedBox(height: 6),
        text(body, size: 8.6),
      ],
    ),
  );
  pw.Widget bullet(String value) => pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 8),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 4),
          child: pw.Container(width: 3, height: 3, color: blue),
        ),
        pw.SizedBox(width: 7),
        pw.Expanded(child: text(value, size: 9)),
      ],
    ),
  );

  pw.Widget table(
    List<String> headings,
    List<List<String>> rows, {
    required List<double> widths,
    Set<int> textColumns = const {0},
    bool totalLast = false,
  }) {
    final order = List.generate(
      headings.length,
      (i) => rtl ? headings.length - i - 1 : i,
    );
    pw.Widget cell(
      String value,
      int column, {
      bool header = false,
      bool total = false,
    }) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6.5),
      child: text(
        header ? copy.t(value) : value,
        size: 8.2,
        bold: header || total,
        color: header ? PdfColors.white : navy,
        align: textColumns.contains(column) ? startAlign : endAlign,
      ),
    );
    return pw.Table(
      columnWidths: {
        for (var i = 0; i < order.length; i++)
          i: pw.FlexColumnWidth(widths[order[i]]),
      },
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
      border: const pw.TableBorder(
        horizontalInside: pw.BorderSide(color: line, width: .45),
      ),
      children: [
        pw.TableRow(
          repeat: true,
          decoration: const pw.BoxDecoration(color: navy),
          children: [for (final i in order) cell(headings[i], i, header: true)],
        ),
        for (var row = 0; row < rows.length; row++)
          pw.TableRow(
            decoration: pw.BoxDecoration(
              color:
                  row.isEven || (totalLast && row == rows.length - 1)
                      ? pale
                      : PdfColors.white,
            ),
            children: [
              for (final i in order)
                cell(
                  rows[row][i],
                  i,
                  total: totalLast && row == rows.length - 1,
                ),
            ],
          ),
      ],
    );
  }

  List<pw.Widget> categoryBars() {
    final maximum = report.categories.fold<int>(
      0,
      (value, item) => math.max(value, item.cents),
    );
    return [
      for (final item in report.categories) ...[
        pw.NewPage(freeSpace: 30),
        pw.Row(
          children: [
            pw.SizedBox(
              width: 104,
              child: text(copy.category(item.category), size: 8.4),
            ),
            pw.SizedBox(width: 9),
            pw.Expanded(
              child: pw.LayoutBuilder(
                builder:
                    (_, constraints) => pw.CustomPaint(
                      size: PdfPoint(constraints!.maxWidth, 11),
                      painter: (canvas, size) {
                        final width =
                            maximum > 0 ? size.x * item.cents / maximum : 0.0;
                        canvas
                          ..setFillColor(blue)
                          ..drawRect(rtl ? size.x - width : 0, 0, width, size.y)
                          ..fillPath();
                      },
                    ),
              ),
            ),
            pw.SizedBox(width: 7),
            pw.SizedBox(
              width: 105,
              child: text(
                '${numberAmount(item.cents)} | ${copy.percentage(item.cents, report.expenseCents)}',
                size: 7.7,
                align: endAlign,
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 9),
      ],
    ];
  }

  pw.Widget chart({
    required List<String> labels,
    required List<List<int>> series,
    required List<String> names,
    required _ChartKind kind,
    double height = 145,
  }) {
    if (labels.isEmpty || series.isEmpty) {
      return empty('No recorded transactions in this period.');
    }
    final amounts = series.expand((values) => values);
    final low = math.min(0, amounts.reduce(math.min));
    final high = math.max(0, amounts.reduce(math.max));
    final step = niceStep(high - low);
    final minimum = (low / step).floor() * step;
    final maximum = math.max(step, (high / step).ceil() * step);
    final range = maximum - minimum;
    final ticks = [
      for (var value = minimum; value <= maximum; value += step) value,
    ];
    final colors = [blue, orange];
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        if (names.isNotEmpty) ...[
          pw.Wrap(
            spacing: 14,
            runSpacing: 5,
            children: [
              for (var i = 0; i < names.length; i++)
                pw.Row(
                  mainAxisSize: pw.MainAxisSize.min,
                  children: [
                    pw.Container(
                      width: 12,
                      height: 5,
                      color: colors[i % colors.length],
                    ),
                    pw.SizedBox(width: 5),
                    text(copy.t(names[i]), size: 7.4),
                  ],
                ),
            ],
          ),
          pw.SizedBox(height: 11),
        ],
        pw.LayoutBuilder(
          builder: (_, constraints) {
            final width = constraints!.maxWidth;
            final plotX = rtl ? 4.0 : 43.0;
            final plotWidth = width - 48;
            const plotTop = 13.0;
            final slot = plotWidth / labels.length;
            double x(int index) =>
                plotX + ((rtl ? labels.length - index - 1 : index) + .5) * slot;
            double y(int value) => (value - minimum) / range * height;
            final shownLabels =
                labels.length <= 6
                    ? List.generate(labels.length, (i) => i)
                    : List.generate(
                      6,
                      (i) => (i * (labels.length - 1) / 5).round(),
                    );
            final minimumLabelGap =
                shownLabels.length < 2
                    ? 1
                    : List.generate(
                      shownLabels.length - 1,
                      (i) => shownLabels[i + 1] - shownLabels[i],
                    ).reduce(math.min);
            final labelWidth = math.min(88.0, slot * minimumLabelGap - 6);
            return pw.SizedBox(
              height: height + 57,
              child: pw.Stack(
                children: [
                  pw.Positioned(
                    left: plotX,
                    top: plotTop,
                    child: pw.CustomPaint(
                      size: PdfPoint(plotWidth, height),
                      painter: (canvas, size) {
                        for (final tick in ticks) {
                          canvas
                            ..setStrokeColor(line)
                            ..setLineWidth(.45)
                            ..drawLine(0, y(tick), size.x, y(tick))
                            ..strokePath();
                        }
                        canvas
                          ..setStrokeColor(muted)
                          ..setLineWidth(.6)
                          ..drawLine(0, y(0), size.x, y(0))
                          ..strokePath();
                        for (var s = 0; s < series.length; s++) {
                          final color = colors[s % colors.length];
                          if (kind == _ChartKind.line) {
                            canvas
                              ..setStrokeColor(color)
                              ..setLineWidth(s == 0 ? 1.8 : 1.0)
                              ..setLineDashPattern(s == 0 ? [] : [4, 3]);
                            for (var i = 1; i < labels.length; i++) {
                              canvas
                                ..drawLine(
                                  x(i - 1) - plotX,
                                  y(series[s][i - 1]),
                                  x(i) - plotX,
                                  y(series[s][i]),
                                )
                                ..strokePath();
                            }
                            canvas.setLineDashPattern();
                            if (s == 0) {
                              for (var i = 0; i < labels.length; i++) {
                                canvas
                                  ..setFillColor(color)
                                  ..drawEllipse(
                                    x(i) - plotX,
                                    y(series[s][i]),
                                    2.2,
                                    2.2,
                                  )
                                  ..fillPath();
                              }
                            }
                          } else {
                            final barWidth = math.min(
                              kind == _ChartKind.grouped ? 21.0 : 29.0,
                              slot * .70 / series.length,
                            );
                            for (var i = 0; i < labels.length; i++) {
                              final value = series[s][i];
                              final visualSeries =
                                  rtl ? series.length - s - 1 : s;
                              final left =
                                  x(i) -
                                  plotX -
                                  barWidth * series.length / 2 +
                                  barWidth * visualSeries;
                              canvas
                                ..setFillColor(value < 0 ? orange : color)
                                ..drawRect(
                                  left,
                                  math.min(y(0), y(value)),
                                  barWidth,
                                  (y(value) - y(0)).abs(),
                                )
                                ..fillPath();
                            }
                          }
                        }
                      },
                    ),
                  ),
                  for (final tick in ticks)
                    pw.Positioned(
                      left: rtl ? plotX + plotWidth + 4 : 0,
                      top: plotTop + height - y(tick) - 4,
                      child: pw.SizedBox(
                        width: 38,
                        child: text(
                          numberAmount(tick),
                          size: 6.8,
                          color: muted,
                          align: rtl ? pw.TextAlign.left : pw.TextAlign.right,
                        ),
                      ),
                    ),
                  if (labels.length <= 8)
                    for (
                      var s = 0;
                      s < (kind == _ChartKind.line ? 1 : series.length);
                      s++
                    )
                      for (var i = 0; i < labels.length; i++)
                        pw.Positioned(
                          left:
                              x(i) -
                              29 +
                              (kind == _ChartKind.grouped
                                  ? ((rtl ? series.length - s - 1 : s) -
                                          (series.length - 1) / 2) *
                                      math.min(21.0, slot * .7 / series.length)
                                  : 0),
                          top: plotTop + height - y(series[s][i]) - 11,
                          child: pw.SizedBox(
                            width: 58,
                            child: text(
                              numberAmount(series[s][i]),
                              size: kind == _ChartKind.grouped ? 6.2 : 7,
                              bold: kind != _ChartKind.grouped,
                              align: pw.TextAlign.center,
                            ),
                          ),
                        ),
                  for (final i in shownLabels)
                    pw.Positioned(
                      left:
                          (x(i) - labelWidth / 2)
                              .clamp(0, width - labelWidth)
                              .toDouble(),
                      top: plotTop + height + 9,
                      child: pw.SizedBox(
                        width: labelWidth,
                        child: text(
                          labels[i],
                          size: 6.7,
                          align: pw.TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  int niceStep(int span) {
    if (span <= 0) return 100;
    final target = span / 3;
    final power =
        math.pow(10, (math.log(target) / math.ln10).floor()).toDouble();
    final scale = target / power;
    final multiple =
        scale <= 1
            ? 1
            : scale <= 2
            ? 2
            : scale <= 5
            ? 5
            : 10;
    return math.max(1, (power * multiple).ceil());
  }
}

class _Metric {
  const _Metric(this.label, this.value, this.note);
  final String label, value, note;
}

enum _ChartKind { grouped, line, bars }
