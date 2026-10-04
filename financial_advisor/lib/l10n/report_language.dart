import '../core/financial_report.dart';
import 'app_language.dart';

class ReportCopy {
  final String languageCode;

  const ReportCopy({required this.languageCode});

  bool get isArabic => languageCode == 'ar';

  String t(String text) =>
      isArabic ? (_arabic[text] ?? translate(text, 'ar')) : text;

  String category(String value) =>
      value == 'Overall' ? t('Overall') : translate(value, languageCode);

  String _digits(String value) {
    if (!isArabic) return value;
    const arabicDigits = '٠١٢٣٤٥٦٧٨٩';
    return value.replaceAllMapped(
      RegExp(r'[0-9]'),
      (match) => arabicDigits[int.parse(match[0]!)],
    );
  }

  String number(int value) {
    final digits = value.abs().toString();
    final grouped = digits.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => isArabic ? '٬' : ',',
    );
    return '${value < 0 ? '−' : ''}${_digits(grouped)}';
  }

  String amount(int cents, String currency) {
    final sign = cents < 0 ? '−' : '';
    final whole = number(cents.abs() ~/ 100);
    final fraction = _digits((cents.abs() % 100).toString().padLeft(2, '0'));
    return '$sign$whole${isArabic ? '٫' : '.'}$fraction $currency';
  }

  String amountNumber(int cents) {
    final whole = number(cents.abs() ~/ 100);
    final fraction = cents.abs() % 100;
    return '${cents < 0 ? '−' : ''}$whole'
        '${fraction == 0 ? '' : '${isArabic ? '٫' : '.'}${_digits(fraction.toString().padLeft(2, '0'))}'}';
  }

  String percentage(int part, int total) {
    if (total <= 0) return _digits('0') + (isArabic ? '٪' : '%');
    // Use integer arithmetic so report percentages match the recorded cents.
    final tenths = (part.abs() * 1000 + total ~/ 2) ~/ total;
    final fraction = tenths % 10;
    return '${part < 0 && tenths != 0 ? '−' : ''}${number(tenths ~/ 10)}'
        '${fraction == 0 ? '' : '${isArabic ? '٫' : '.'}${_digits('$fraction')}'}'
        '${isArabic ? '٪' : '%'}';
  }

  String date(DateTime value) =>
      '${number(value.day)} ${_months[value.month - 1]} ${_digits('${value.year}')}';

  String month(DateTime value) =>
      '${_months[value.month - 1]} ${_digits('${value.year}')}';

  String period(ReportPeriod value) {
    if (value.kind == ReportPeriodKind.allTime) return t('All Time');
    if (value.kind == ReportPeriodKind.month) return month(value.start!);
    return '${date(value.start!)} - ${date(value.end!)}';
  }

  String trendLabel(ReportTrendBucket value) {
    if (value.start.year == value.end.year &&
        value.start.month == value.end.month &&
        value.start.day == 1 &&
        value.end.day == DateTime(value.end.year, value.end.month + 1, 0).day) {
      return month(value.start);
    }
    if (value.start.year == value.end.year &&
        value.start.month == value.end.month &&
        value.start.day == value.end.day) {
      return date(value.start);
    }
    return '${date(value.start)} - ${date(value.end)}';
  }

  String chartTrendLabel(ReportTrendBucket value) {
    if (value.start.year == value.end.year &&
        value.start.month == value.end.month) {
      if (value.start.day == 1 &&
          value.end.day ==
              DateTime(value.end.year, value.end.month + 1, 0).day) {
        return month(value.start);
      }
      final days =
          value.start.day == value.end.day
              ? number(value.start.day)
              : '${number(value.start.day)} - ${number(value.end.day)}';
      return '$days\n${month(value.start)}';
    }
    return '${date(value.start)}\n${date(value.end)}';
  }

  String page(int current, int total) =>
      isArabic
          ? 'صفحة ${number(current)} من ${number(total)}'
          : 'Page ${number(current)} of ${number(total)}';

  String retainedShare(FinancialReport report) =>
      report.incomeCents > 0
          ? percentage(report.netCents, report.incomeCents)
          : t('Not available');

  String periodDetail(FinancialReport report) {
    final label = period(report.period);
    if (report.period.kind != ReportPeriodKind.allTime ||
        report.recordedStart == null ||
        report.recordedEnd == null) {
      return label;
    }
    final range =
        '${date(report.recordedStart!)} - ${date(report.recordedEnd!)}';
    return isArabic
        ? '$label | تواريخ المعاملات المسجلة: $range'
        : '$label | Recorded dates: $range';
  }

  String transactionBreakdown(FinancialReport report) =>
      isArabic
          ? '${number(report.transactionCount)} معاملة مسجلة | ${number(report.expenseTransactionCount)} مصروفات | ${number(report.incomeTransactionCount)} معاملات دخل'
          : '${number(report.transactionCount)} recorded transactions | ${number(report.expenseTransactionCount)} expenses | ${number(report.incomeTransactionCount)} income entries';

  String overviewNarrative(FinancialReport report) {
    if (report.transactionCount == 0) {
      return t('No completed transactions in this period.');
    }
    final income = amount(report.incomeCents, report.currency);
    final spent = amount(report.expenseCents, report.currency);
    final net = amount(report.netCents, report.currency);
    return isArabic
        ? 'بلغ الدخل المسجل $income والمصروفات $spent، بصافي مبلغ $net خلال الفترة المختارة.'
        : 'Recorded income of $income less expenses of $spent leaves a net amount of $net within the selected period.';
  }

  String budgetNarrative(FinancialReport report) {
    if (report.budgets.isEmpty) {
      return t('No budgets are available for this reporting period.');
    }
    if (report.categoryBudgetLimitCents == 0) {
      return t(
        'Overall budgets are shown separately. No category budgets are available for this period.',
      );
    }
    final limit = amount(report.categoryBudgetLimitCents, report.currency);
    final spent = amount(report.categoryBudgetSpentCents, report.currency);
    final variance =
        report.categoryBudgetSpentCents - report.categoryBudgetLimitCents;
    final difference = amount(variance.abs(), report.currency);
    if (isArabic) {
      final comparison =
          variance == 0
              ? 'وتساوي مجموع الحدود'
              : variance > 0
              ? 'وتتجاوز مجموع الحدود بمقدار $difference'
              : 'وتقل عن مجموع الحدود بمقدار $difference';
      return 'بلغت حدود ميزانيات الفئات المحفوظة $limit. المصروفات المقابلة لهذه الفئات وأشهرها هي $spent، $comparison.';
    }
    final comparison =
        variance == 0
            ? 'equal to the combined limits'
            : variance > 0
            ? '$difference above the combined limits'
            : '$difference below the combined limits';
    return 'Saved category limits total $limit. Spending for those categories and covered months is $spent, $comparison.';
  }

  String budgetCoverageNote(FinancialReport report) {
    final parts = <String>[
      t(
        'Each category comparison includes only months with a saved limit for that category. Overall limits are separate and are not added to category limits.',
      ),
    ];
    if (report.categoryUnbudgetedExpenseCents > 0) {
      final uncovered = amount(
        report.categoryUnbudgetedExpenseCents,
        report.currency,
      );
      parts.add(
        isArabic
            ? 'لا تشمل مقارنات الفئات مصروفات بقيمة $uncovered لعدم توفر حدود للفئات في أشهر تسجيلها.'
            : 'Category comparisons exclude $uncovered of expenses without a category limit in their recorded month.',
      );
    }
    if (report.budgets.any((row) => row.partial)) {
      parts.add(
        t(
          'Partial-month spending is compared with the full monthly limit; limits are not prorated.',
        ),
      );
    }
    if (report.budgets.any((row) => row.isOngoing)) {
      parts.add(
        t(
          'Some budget months are still open or in the future; their recorded spending is not final.',
        ),
      );
    }
    return parts.join(' ');
  }

  String monthlyAverageCaption(FinancialReport report) {
    final count = number(report.monthCount);
    return isArabic
        ? 'المتوسط عبر $count من الأشهر التقويمية التي تشملها الفترة. قد تكون الأشهر الأولى أو الأخيرة جزئية؛ هذا ليس توقعاً.'
        : 'Average across $count calendar months touched by the period. First or last months may be partial; this is not a forecast.';
  }

  String trendNarrative(FinancialReport report) {
    final highest = report.highestExpenseMonth;
    if (highest == null) return t('No expenses in this period.');
    final value = amount(highest.expenseCents, report.currency);
    final label = month(highest.start);
    final highestText =
        isArabic
            ? 'أعلى مصروفات شهرية ضمن التواريخ المختارة كانت $value خلال $label.'
            : 'The highest monthly spending within the selected dates is $value in $label.';
    if (report.comparableBudgetMonthCount == 0) return highestText;
    final over = number(report.overBudgetMonthCount);
    final comparable = number(report.comparableBudgetMonthCount);
    return isArabic
        ? '$highestText تجاوزت المصروفات الحد في $over من أصل $comparable من الأشهر المكتملة ذات تغطية الميزانية الكاملة.'
        : '$highestText Spending exceeded the limit in $over of $comparable completed months with full expense-budget coverage.';
  }

  String scenarioNarrative(FinancialReport report) {
    final scenario = report.budgetScenario;
    if (scenario == null) {
      return t('No complete budget comparisons are available for this period.');
    }
    final spent = amount(scenario.expenseCents, report.currency);
    final net = amount(scenario.netCents, report.currency);
    return isArabic
        ? 'لو التزمت الفئات المعروضة بحدودها في الأشهر المكتملة التي تتوفر لها ميزانيات، مع ثبات بقية المبالغ، لبلغ إجمالي المصروفات $spent وصافي المبلغ $net. هذه مقارنة توضيحية وليست توقعاً أو وعداً بالادخار.'
        : 'If the displayed categories met their limits in the completed months with saved budgets, with every other amount unchanged, total expenses would be $spent and the net amount $net. This is an illustration, not a forecast or promised saving.';
  }

  List<String> summary(FinancialReport report) {
    if (report.transactionCount == 0) {
      return [t('No completed transactions in this period.'), t(_insufficient)];
    }
    final income = amount(report.incomeCents, report.currency);
    final expenses = amount(report.expenseCents, report.currency);
    final net = amount(report.netCents, report.currency);
    final result = <String>[
      isArabic
          ? 'تضم الفترة ${number(report.transactionCount)} معاملة مسجلة: دخل بقيمة $income، ومصروفات بقيمة $expenses، وصافي مبلغ $net.'
          : 'The period contains ${number(report.transactionCount)} recorded transaction${report.transactionCount == 1 ? '' : 's'}: income of $income, expenses of $expenses, and a net amount of $net.',
    ];
    if (report.incomeCents == 0) {
      result.add(
        t(
          'No income is recorded for this period; these records cannot establish your full income or savings.',
        ),
      );
    }
    final largest = _largestCategory(report);
    if (largest != null && report.expenseCents > 0) {
      final name = category(largest.category);
      final spent = amount(largest.cents, report.currency);
      final share = percentage(largest.cents, report.expenseCents);
      result.add(
        isArabic
            ? 'أكبر فئة للمصروفات هي $name بقيمة $spent، وتمثل $share من المصروفات المسجلة.'
            : '$name is the largest expense category at $spent, representing $share of recorded expenses.',
      );
    }
    if (report.recurringExpenses.isNotEmpty) {
      final count = number(report.recurringExpenses.length);
      final spent = amount(report.recurringExpenseCents, report.currency);
      result.add(
        isArabic
            ? 'سُجلت $count معاملة مصروف متكرر بقيمة إجمالية $spent خلال الفترة.'
            : '$count recorded recurring expense ${report.recurringExpenses.length == 1 ? 'transaction totals' : 'transactions total'} $spent in this period.',
      );
    }
    final overBudget =
        report.budgets.where((row) => row.spentCents > row.limitCents).toList();
    if (overBudget.isNotEmpty) {
      final count = number(overBudget.length);
      result.add(
        isArabic
            ? 'تجاوزت المصروفات المسجلة الحد الشهري في $count من بنود الميزانية المعروضة.'
            : 'Recorded spending exceeds the monthly limit in $count displayed budget row${overBudget.length == 1 ? '' : 's'}.',
      );
    } else if (report.budgets.isNotEmpty) {
      result.add(
        t('Recorded spending is within the displayed monthly budget limits.'),
      );
    }
    if (report.budgets.any((row) => row.partial)) {
      result.add(
        t(
          'Partial-month spending is compared with the full monthly limit; limits are not prorated.',
        ),
      );
    }
    final activeTrends =
        report.trends.where((row) => row.expenseCents > 0).toList();
    if (activeTrends.length > 1) {
      final highest = activeTrends.reduce(
        (a, b) => a.expenseCents >= b.expenseCents ? a : b,
      );
      final label = trendLabel(highest);
      final spent = amount(highest.expenseCents, report.currency);
      result.add(
        isArabic
            ? 'أعلى إجمالي مصروفات بين الفترات المعروضة كان خلال $label بقيمة $spent. قد تختلف مدة الفترات وتغطيتها.'
            : 'The highest expense total among the displayed intervals is $spent during $label. Interval length and coverage may differ.',
      );
    } else {
      result.add(t(_insufficient));
    }
    return result;
  }

  List<String> recommendations(FinancialReport report) {
    if (report.transactionCount == 0) {
      return [
        t(
          'Add income and expenses, or choose a period with saved transactions, to build a useful report.',
        ),
      ];
    }
    final result = <String>[];
    if (report.incomeCents == 0) {
      result.add(
        t(
          'Record income for this period before using the report to assess income versus expenses.',
        ),
      );
    } else if (report.expenseCents > report.incomeCents) {
      final gap = amount(
        report.expenseCents - report.incomeCents,
        report.currency,
      );
      result.add(
        isArabic
            ? 'تزيد المصروفات المسجلة على الدخل المسجل بمقدار $gap. راجع النفقات القادمة وما يمكنك تعديله.'
            : 'Recorded expenses exceed recorded income by $gap. Review upcoming costs and what you can adjust.',
      );
    }
    final largest = _largestCategory(report);
    if (largest != null && report.expenseCents > 0) {
      final name = category(largest.category);
      result.add(
        isArabic
            ? 'راجع معاملات فئة $name، فهي أكبر جزء من مصروفاتك المسجلة، وحدد ما يناسب أولوياتك.'
            : 'Review transactions in $name, your largest recorded expense category, and check how they fit your priorities.',
      );
    }
    if (report.budgets.isEmpty && report.expenseCents > 0) {
      result.add(
        t(
          'Set category budget limits to compare future spending with your plan.',
        ),
      );
    } else if (report.budgets.any((row) => row.spentCents > row.limitCents)) {
      result.add(
        t(
          'Review budgets exceeding their monthly limits and adjust upcoming category spending where practical.',
        ),
      );
    }
    if (report.recurringExpenses.isNotEmpty) {
      result.add(
        t(
          'Review recorded recurring expenses and confirm that each repeated cost is still needed.',
        ),
      );
    }
    if (report.commitments.isNotEmpty &&
        report.commitmentStart != null &&
        report.commitmentEnd != null) {
      final start = date(report.commitmentStart!);
      final end = date(report.commitmentEnd!);
      final total = amount(report.scheduledExpenseCents, report.currency);
      result.add(
        isArabic
            ? 'خصص مساحة للمصروفات المجدولة المعروضة بقيمة $total من $start إلى $end. هذه توقعات من جداولك وليست مصروفات مسجلة.'
            : 'Plan for the displayed scheduled expenses of $total from $start to $end. These are schedule projections, not recorded expenses.',
      );
    }
    if (result.isEmpty) {
      result.add(
        t(
          'Keep recording income and expenses to make future period comparisons more useful.',
        ),
      );
    }
    return result;
  }

  ReportCategoryTotal? _largestCategory(FinancialReport report) =>
      report.categories.isEmpty
          ? null
          : report.categories.reduce((a, b) => a.cents >= b.cents ? a : b);

  List<String> get _months => isArabic ? _arabicMonths : _englishMonths;
}

const _insufficient =
    'There is not enough recorded spending across multiple intervals to assess a spending trend.';

const _englishMonths = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];
const _arabicMonths = [
  'يناير',
  'فبراير',
  'مارس',
  'أبريل',
  'مايو',
  'يونيو',
  'يوليو',
  'أغسطس',
  'سبتمبر',
  'أكتوبر',
  'نوفمبر',
  'ديسمبر',
];

const _arabic = <String, String>{
  'Overview': 'نظرة عامة',
  'Comparable months': 'الأشهر القابلة للمقارنة',
  'Scheduled item': 'البند المجدول',
  'Illustrative net amount': 'صافي مبلغ توضيحي',
  'Saved monthly budget': 'الميزانية الشهرية المحفوظة',
  'Expenses by period': 'المصروفات حسب الفترة',
  'Recorded results': 'النتائج المسجلة',
  'Spending focus': 'المصروفات الأبرز',
  'Your financial behavior': 'سلوكك المالي',
  'Recorded recurring details': 'تفاصيل المصروفات المتكررة المسجلة',
  'Budget details': 'تفاصيل الميزانية',
  'Covered months': 'الأشهر المشمولة',
  'Category budget total': 'إجمالي ميزانيات الفئات',
  'Overall budget comparison': 'مقارنة الميزانية الإجمالية',
  'No category budget is set for some recorded expenses.':
      'لا توجد ميزانية للفئة لبعض المصروفات المسجلة.',
  'Positive variance means over budget; negative means under budget.':
      'يعني الفرق الموجب تجاوز الميزانية، ويعني الفرق السالب إنفاقاً أقل من الحد.',
  'Projected difference': 'الفرق المتوقع',
  'Not a savings forecast': 'ليس توقعاً للادخار',
  'No recorded transactions in this period.':
      'لا توجد معاملات مسجلة خلال هذه الفترة.',
  'No recorded expense history is available for this comparison.':
      'لا تتوفر مصروفات مسجلة لهذه المقارنة.',
  'No scheduled transactions fall within this report window.':
      'لا توجد معاملات مجدولة ضمن النطاق الزمني المعروض.',
  'Budget comparison': 'مقارنة الميزانية',
  'Spending & budget': 'المصروفات والميزانية',
  'Spending trends': 'اتجاهات الإنفاق',
  'Recurring & upcoming': 'المتكرر والقادم',
  'Insights & next steps': 'الملاحظات والخطوات القادمة',
  'Your money, in focus.': 'صورة أوضح لأموالك.',
  'Where your money goes': 'أين تذهب أموالك؟',
  'The pattern behind the totals': 'ما وراء الأرقام الإجمالية',
  'What is already committed': 'ما التزمت به وما هو قادم',
  'Small changes, visible impact': 'خطوات صغيرة، أثر واضح',
  'Recorded surplus': 'الفائض المسجل',
  'Retained share': 'نسبة الفائض',
  'Recorded income': 'الدخل المسجل',
  'Recorded expenses': 'المصروفات المسجلة',
  'Income less expenses': 'الدخل ناقص المصروفات',
  'Surplus as a share of income': 'الفائض كنسبة من الدخل',
  'Not available': 'غير متاح',
  'Recorded net amount': 'صافي المبلغ المسجل',
  'Largest expense category': 'أكبر فئة للمصروفات',
  'How to read this report': 'كيف تقرأ هذا التقرير',
  'The net amount is recorded income less recorded expenses. It is not a verified bank balance or confirmed savings. Scheduled projections are shown separately.':
      'صافي المبلغ هو الدخل المسجل ناقص المصروفات المسجلة. ولا يمثل رصيداً بنكياً مؤكداً أو ادخاراً فعلياً. وتعرض التوقعات المجدولة بشكل منفصل.',
  'Budget performance across the selected period':
      'أداء الميزانية خلال الفترة المختارة',
  'Actual': 'الفعلي',
  'Over / under': 'التجاوز / المتبقي',
  'Total': 'الإجمالي',
  'Average monthly spend': 'متوسط الإنفاق الشهري',
  'Highest spending month': 'أعلى شهر إنفاقاً',
  'Months over budget': 'أشهر تجاوزت الميزانية',
  'Recorded recurring costs': 'مصروفات متكررة مسجلة',
  'Recorded occurrences': 'المعاملات المتكررة',
  'Share of all expenses': 'حصتها من المصروفات',
  'Already included in expenses': 'ضمن إجمالي المصروفات',
  'Each occurrence is counted once': 'تحسب كل معاملة مرة واحدة',
  'Before variable costs': 'قبل المصروفات المتغيرة',
  'Not confirmed savings': 'ليس ادخاراً مؤكداً',
  'A schedule is not a completed payment': 'الجدول لا يعني إتمام الدفع',
  'Scheduled income and expenses are projections, excluded from recorded totals. Variable costs are not included in the difference.':
      'الدخل والمصروفات المجدولة توقعات لا تدخل ضمن الإجماليات المسجلة. ولا يشمل الفرق المصروفات المتغيرة.',
  'Categories above their saved limits': 'فئات تجاوزت حدودها المحفوظة',
  'Recorded spending': 'الإنفاق المسجل',
  'Saved budget': 'حد الميزانية',
  'Combined budget gap': 'التجاوز في الفئات',
  'Illustrative surplus': 'فائض توضيحي',
  'Illustrative share': 'نسبة الفائض التوضيحي',
  'If these limits were met': 'لو تم الالتزام بالحدود',
  'With every other amount unchanged': 'مع ثبات جميع المبالغ الأخرى',
  'No complete budget comparisons are available for this period.':
      'لا تتوفر مقارنات ميزانية لأشهر مكتملة خلال هذه الفترة.',
  'No expense categories exceed their complete budget-period limits.':
      'لا تتجاوز فئات المصروفات حدودها الإجمالية في فترات الميزانية المكتملة.',
  'Your recorded history': 'سجل معاملاتك المحفوظة',
  'Period details': 'تفاصيل الفترة',
  'Net amount by period': 'صافي المبلغ حسب الفترة',
  'Interval': 'الفترة الزمنية',
  'Amounts in': 'المبالغ بعملة',
  'Partial coverage': 'تغطية جزئية',
  'Budget coverage': 'تغطية الميزانية',
  'Saved budget months': 'أشهر الميزانية المحفوظة',
  'No income is recorded for this period.': 'لم يُسجل دخل خلال هذه الفترة.',
  'Complete history': 'السجل الكامل',
  'Monthly average across recorded history': 'المتوسط الشهري عبر السجل المحفوظ',
  'Incomplete budget coverage': 'تغطية الميزانية غير مكتملة',
  'Limits may cover only some months or categories.':
      'قد تغطي الحدود بعض الأشهر أو الفئات فقط.',
  'Category budgets': 'ميزانيات الفئات',
  'Overall budgets': 'الميزانيات الإجمالية',
  'Overall budgets are shown separately. No category budgets are available for this period.':
      'تعرض الميزانيات الإجمالية بشكل منفصل. لا توجد ميزانيات للفئات خلال هذه الفترة.',
  'Each category comparison includes only months with a saved limit for that category. Overall limits are separate and are not added to category limits.':
      'تشمل مقارنة كل فئة الأشهر التي يتوفر لها حد محفوظ فقط. وتعرض الحدود الإجمالية بشكل منفصل ولا تجمع مع حدود الفئات.',
  'Some budget months are still open or in the future; their recorded spending is not final.':
      'بعض أشهر الميزانية لم تنتهِ بعد أو تقع في المستقبل؛ ومصروفاتها المسجلة ليست نهائية.',
  'Financial behavior report': 'تقرير السلوك المالي',
  'Generated on': 'تاريخ إنشاء التقرير',
  'Reporting period': 'فترة التقرير',
  'Account holder': 'صاحب الحساب',
  'Completed transactions': 'المعاملات المسجلة',
  'Net amount': 'صافي المبلغ',
  'Financial overview': 'نظرة عامة على الوضع المالي',
  'Income versus expenses': 'الدخل مقابل المصروفات',
  'Expense distribution by category': 'توزيع المصروفات حسب الفئة',
  'Spending over time': 'المصروفات عبر الزمن',
  'Spending by category': 'المصروفات حسب الفئة',
  'Amount': 'المبلغ',
  'Share': 'النسبة',
  'Budget performance': 'أداء الميزانية',
  'Month': 'الشهر',
  'Budget': 'الميزانية',
  'Spent': 'المصروف',
  'Remaining': 'المتبقي',
  'Coverage': 'التغطية',
  'Partial month': 'جزء من الشهر',
  'Full month': 'الشهر كاملًا',
  'Month / Category': 'الشهر / الفئة',
  'Month in progress': 'الشهر لم ينتهِ بعد',
  'Open month': 'شهر لم ينتهِ بعد',
  'Overall budgets and category budgets may overlap; do not add their limits together.':
      'قد تتداخل الميزانيات الإجمالية مع ميزانيات الفئات؛ لذلك لا تجمع حدودها معًا.',
  'Expenses without a budget': 'مصروفات دون ميزانية',
  'No budgets are available for this reporting period.':
      'لا توجد ميزانيات خلال فترة التقرير.',
  'Recorded recurring expenses': 'المصروفات المتكررة المسجلة',
  'Upcoming commitments': 'الالتزامات القادمة',
  'Scheduled transactions': 'المعاملات المجدولة',
  'Date': 'التاريخ',
  'Description': 'الوصف',
  'Type': 'النوع',
  'Overall': 'الإجمالي',
  'All Time': 'جميع الفترات',
  'No completed transactions in this period.':
      'لا توجد معاملات مسجلة خلال هذه الفترة.',
  'No expenses in this period.': 'لا توجد مصروفات خلال هذه الفترة.',
  'No budgets set for this period.': 'لم تُحدد ميزانيات لهذه الفترة.',
  'No recorded recurring expenses in this period.':
      'لا توجد مصروفات متكررة مسجلة خلال هذه الفترة.',
  'No scheduled transactions in this period.':
      'لا توجد معاملات مجدولة خلال هذه الفترة.',
  'Financial behavior summary': 'ملخص السلوك المالي',
  'Suggested next steps': 'خطوات مقترحة',
  'Only recorded transactions are included in completed totals. Scheduled amounts are shown separately.':
      'تشمل الإجماليات المعاملات المسجلة فقط. وتُعرض المبالغ المجدولة بشكل منفصل.',
  'Only recorded transactions are included in totals. Scheduled projections are shown separately.':
      'تشمل الإجماليات المعاملات المسجلة فقط. وتُعرض توقعات المعاملات المجدولة بشكل منفصل.',
  'Saved future-dated transactions are included in recorded totals, matching the dashboard. Scheduled projections are excluded.':
      'تشمل الإجماليات المسجلة المعاملات المحفوظة ذات التواريخ المستقبلية، كما في لوحة المعلومات. ولا تشمل توقعات المعاملات المجدولة.',
  'All amounts use the account currency; no exchange-rate conversion is applied.':
      'جميع المبالغ بعملة الحساب دون تطبيق تحويل بسعر الصرف.',
  'Budgets are monthly limits. Partial periods compare only the selected dates with the full monthly limit; limits are not prorated.':
      'الميزانيات حدود شهرية. تُقارن مصروفات التواريخ المختارة بالحد الشهري الكامل دون تقسيم الحد على أيام الفترة.',
  'Expenses without a category budget': 'مصروفات دون ميزانية للفئة',
  'Recorded recurring expenses are already included in total expenses. Each recorded occurrence is counted once.':
      'المصروفات المتكررة المسجلة مدرجة ضمن إجمالي المصروفات. تُحتسب كل معاملة مسجلة مرة واحدة.',
  'Occurrences': 'عدد المعاملات',
  'First / last recorded': 'أول وآخر تسجيل',
  'Scheduled income': 'الدخل المجدول',
  'Scheduled expenses': 'المصروفات المجدولة',
  'Upcoming amounts are projections, not completed payments. The schedule covers only the dates shown.':
      'المبالغ القادمة توقعات وليست دفعات منفذة. يغطي الجدول التواريخ المعروضة فقط.',
  'No upcoming commitments in this reporting period.':
      'لا توجد التزامات قادمة خلال فترة التقرير.',
  'No recurring expenses were recorded in this reporting period.':
      'لم تُسجل مصروفات متكررة خلال فترة التقرير.',
  'No category budgets are available for this reporting period.':
      'لا توجد ميزانيات للفئات خلال فترة التقرير.',
  'Expense trend details': 'تفاصيل اتجاه المصروفات',
  'This report reflects data recorded in Tadbeer at generation time.':
      'يعكس هذا التقرير البيانات المسجلة في تدبير عند إنشاء التقرير.',
  'Period': 'الفترة',
  'Count': 'العدد',
  _insufficient:
      'لا توجد مصروفات مسجلة كافية عبر فترات متعددة لتقييم اتجاه الإنفاق.',
  'No income is recorded for this period; these records cannot establish your full income or savings.':
      'لم يُسجل دخل خلال هذه الفترة؛ لا تكفي هذه السجلات لتحديد دخلك الكامل أو مدخراتك.',
  'Recorded spending is within the displayed monthly budget limits.':
      'المصروفات المسجلة ضمن حدود الميزانية الشهرية المعروضة.',
  'Partial-month spending is compared with the full monthly limit; limits are not prorated.':
      'تُقارن مصروفات جزء الشهر بالحد الشهري الكامل دون تقسيم الحد على أيام الفترة.',
  'Add income and expenses, or choose a period with saved transactions, to build a useful report.':
      'أضف الدخل والمصروفات، أو اختر فترة تحتوي على معاملات محفوظة لإعداد تقرير مفيد.',
  'Record income for this period before using the report to assess income versus expenses.':
      'سجل الدخل لهذه الفترة قبل استخدام التقرير لتقييم الدخل مقابل المصروفات.',
  'Set category budget limits to compare future spending with your plan.':
      'حدد ميزانيات للفئات لمقارنة المصروفات القادمة بخطتك.',
  'Review budgets exceeding their monthly limits and adjust upcoming category spending where practical.':
      'راجع بنود الميزانية التي تجاوزت حدودها الشهرية وعدّل المصروفات القادمة للفئات حيثما أمكن.',
  'Review recorded recurring expenses and confirm that each repeated cost is still needed.':
      'راجع المصروفات المتكررة المسجلة وتأكد من استمرار حاجتك إلى كل منها.',
  'Keep recording income and expenses to make future period comparisons more useful.':
      'واصل تسجيل الدخل والمصروفات لتكون المقارنة بين الفترات أكثر فائدة.',
};
