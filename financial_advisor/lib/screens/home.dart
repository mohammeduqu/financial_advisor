import '../l10n/app_language.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/finance_store.dart';
import '../widgets/design.dart';
import '../widgets/tadbeer_logo.dart';
import '../widgets/finance_charts.dart';
import '../widgets/financial_insights_panel.dart';
import 'transactions.dart';

class HomePage extends StatelessWidget {
  final FinanceStore store;
  final DateTime month;
  final ValueChanged<int> navigate;
  final VoidCallback settings;
  const HomePage({
    super.key,
    required this.store,
    required this.month,
    required this.navigate,
    required this.settings,
  });
  @override
  Widget build(BuildContext context) {
    final income = store.incomeFor(month),
        spent = store.expensesFor(month),
        net = income - spent;
    final expenses = store.forMonth(month).where((e) => !e.income).toList();
    final highest = expenses.fold<int>(0, (a, b) => a > b.cents ? a : b.cents);
    final now = DateTime.now();
    final days =
        monthKey(month) == monthKey(now)
            ? now.day
            : DateTime(month.year, month.month + 1, 0).day;
    final top =
        categories.where((c) => store.categorySpent(month, c) > 0).toList()
          ..sort(
            (a, b) => store
                .categorySpent(month, b)
                .compareTo(store.categorySpent(month, a)),
          );
    final budget = store.budgetFor(month);
    final previous = DateTime(month.year, month.month - 1);
    final previousNet = store.incomeFor(previous) - store.expensesFor(previous);
    final hasPrevious = store.forMonth(previous).isNotEmpty && previousNet != 0;
    final change =
        hasPrevious ? (net - previousNet) / previousNet.abs() * 100 : null;
    final alert =
        budget > 0 && spent >= budget * .8
            ? 'You have used ${(spent / budget * 100).round()}% of your monthly budget. Review your remaining limits in Analysis.'
            : 'No budget alerts. Your recorded expenses are within the limits you have set.';
    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 28),
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      TadbeerLogo(size: 24),
                      SizedBox(width: 8),
                      Flexible(
                        child: AppText(
                          'TADBEER  /  MONEY MANAGEMENT',
                          style: TextStyle(
                            fontSize: 9,
                            letterSpacing: 2,
                            color: Color(0xFFC5B185),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 9),
                  AppText(
                    'Hello, ${store.name.split(' ').first}',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 5),
                  const AppText(
                    'Make every income and expense count.',
                    style: TextStyle(fontSize: 12, color: muted),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: tr(context, 'Notifications'),
              onPressed:
                  () => showModalBottomSheet(
                    context: context,
                    showDragHandle: true,
                    builder:
                        (_) => SafeArea(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const AppText(
                                  'Financial alerts',
                                  style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                AppText(
                                  budget == 0
                                      ? 'Set a budget in Analysis to receive spending alerts.'
                                      : alert,
                                ),
                                const SizedBox(height: 20),
                              ],
                            ),
                          ),
                        ),
                  ),
              icon: const Icon(Icons.notifications_none_rounded, size: 23),
            ),
            IconButton(
              tooltip: tr(context, 'Profile'),
              onPressed: settings,
              icon: CircleAvatar(
                radius: 19,
                backgroundColor: const Color(0xFF2F3D3D),
                child: AppText(
                  store.name.trim().isEmpty
                      ? 'N'
                      : store.name.trim()[0].toUpperCase(),
                  style: const TextStyle(
                    color: Color(0xFFD7C79F),
                    fontSize: 15,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 26),
        Surface(
          color: ink,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: AppText(
                      'MONTHLY CASH FLOW',
                      style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 1.7,
                        color: muted,
                      ),
                    ),
                  ),
                  AppText(
                    store.currency,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFFCDBB93),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 17),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: AppText(
                  money(net),
                  style: const TextStyle(
                    fontSize: 43,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -1.5,
                    color: ink,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              AppText(
                change == null
                    ? 'Monthly change — · no prior comparison'
                    : '${change >= 0 ? '+' : ''}${change.toStringAsFixed(1)}% net cash flow vs. previous month',
                style: const TextStyle(fontSize: 11, color: blue),
              ),
              const SizedBox(height: 8),
              const AppText(
                'Income minus expenses · not a connected bank balance',
                style: TextStyle(fontSize: 10, color: muted),
              ),
              const Divider(height: 32),
              Row(
                children: [
                  Expanded(
                    child: _stat(
                      'Monthly income',
                      money(income),
                      Icons.south_west_rounded,
                      blue,
                    ),
                  ),
                  Expanded(
                    child: _stat(
                      'Monthly expenses',
                      money(spent),
                      Icons.north_east_rounded,
                      const Color(0xFFCDBB93),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        LayoutBuilder(
          builder: (context, constraints) {
            final actionWidth =
                constraints.maxWidth < 320
                    ? constraints.maxWidth
                    : (constraints.maxWidth - 12) / 2;
            return Wrap(
              spacing: 12,
              runSpacing: 10,
              children: [
                SizedBox(
                  width: actionWidth,
                  child: FilledButton.icon(
                    key: const Key('home-add-income'),
                    onPressed:
                        () => editEntry(context, store, initialIncome: true),
                    icon: const Icon(Icons.south_west_rounded, size: 18),
                    label: const AppText('Add income'),
                  ),
                ),
                SizedBox(
                  width: actionWidth,
                  child: OutlinedButton.icon(
                    key: const Key('home-add-expense'),
                    onPressed: () => editEntry(context, store),
                    icon: const Icon(Icons.north_east_rounded, size: 18),
                    label: const AppText('Add expense'),
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => navigate(2),
          icon: const Icon(Icons.document_scanner_outlined, size: 20),
          label: const AppText('Scan Invoice'),
        ),
        const SizedBox(height: 8),
        const AppText(
          'Capture a receipt, review the details, then save.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 10, color: muted),
        ),
        const SizedBox(height: 20),
        Surface(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.auto_awesome_outlined, color: blue, size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: AppText(
                      'Smart Price Recommendation',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              const AppText(
                'Compare the same products. Discover potential savings.',
                style: TextStyle(color: muted, fontSize: 12),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  key: const Key('open-smart-prices'),
                  onPressed: () => navigate(5),
                  icon: const Icon(Icons.manage_search),
                  label: const AppText('Find better prices'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 26),
        SpendingTrend(store: store, month: month),
        const SectionHeading('Your month at a glance'),
        Row(
          children: [
            Expanded(
              child: _summary(
                'Total spending',
                money(spent),
                Icons.payments_outlined,
                store.currency,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _summary(
                'Highest expense',
                money(highest),
                Icons.north_east_rounded,
                store.currency,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _summary(
                'Daily average',
                money((spent / days).round()),
                Icons.calendar_today_outlined,
                'Across $days calendar days',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _summary(
                'Net savings',
                money(net),
                Icons.savings_outlined,
                income > 0
                    ? '${(net / income * 100).toStringAsFixed(1)}% of income'
                    : 'No income recorded',
              ),
            ),
          ],
        ),
        const SectionHeading('Spending by category'),
        Surface(
          child:
              top.isEmpty
                  ? const AppText(
                    'Add an expense to see your breakdown.',
                    style: TextStyle(color: muted),
                  )
                  : Column(
                    children: [
                      for (var i = 0; i < top.length; i++)
                        Padding(
                          padding: EdgeInsets.only(
                            bottom: i == top.length - 1 ? 0 : 20,
                          ),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    categoryIcon(top[i]),
                                    size: 16,
                                    color: chartColors[i % chartColors.length],
                                  ),
                                  const SizedBox(width: 9),
                                  Expanded(
                                    child: AppText(
                                      top[i],
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                                  AppText(
                                    money(store.categorySpent(month, top[i])),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 9),
                              LinearProgressIndicator(
                                value:
                                    store.categorySpent(month, top[i]) / spent,
                                minHeight: 6,
                                borderRadius: BorderRadius.circular(5),
                                backgroundColor: line.withValues(alpha: .5),
                                color: chartColors[i % chartColors.length],
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
        ),
        const SizedBox(height: 20),
        BudgetDistribution(store: store, month: month),
        FinancialInsightsPanel(store: store, month: month),
        SectionHeading(
          'Recent transactions',
          action: TextButton(
            onPressed: () => navigate(1),
            child: const AppText('View all'),
          ),
        ),
        if (store.forMonth(month).isEmpty)
          const AppText(
            'No transactions this month.',
            style: TextStyle(color: muted),
          ),
        ...store
            .forMonth(month)
            .take(3)
            .map((e) => EntryTile(entry: e, store: store)),
        const SectionHeading('Your monthly budget'),
        Surface(
          key: const Key('home-budget-summary'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppText(
                DateFormat.yMMMM(languageOf(context)).format(month),
                style: const TextStyle(color: muted, fontSize: 12),
              ),
              const SizedBox(height: 12),
              if (budget > 0) ...[
                const AppText(
                  'Monthly budget',
                  style: TextStyle(color: muted, fontSize: 11),
                ),
                const SizedBox(height: 6),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: AppText(
                    '${store.currency} ${money(budget)}',
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: (spent / budget).clamp(0.0, 1.0),
                    minHeight: 6,
                    backgroundColor: line,
                    color: spent > budget ? const Color(0xFFE0BD81) : blue,
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _stat(
                        'Total spending',
                        '${store.currency} ${money(spent)}',
                        Icons.north_east_rounded,
                        muted,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _stat(
                        spent > budget ? 'Over budget' : 'Remaining budget',
                        '${store.currency} ${money((budget - spent).abs())}',
                        spent > budget
                            ? Icons.warning_amber_rounded
                            : Icons.savings_outlined,
                        spent > budget ? const Color(0xFFE0BD81) : blue,
                      ),
                    ),
                  ],
                ),
              ] else ...[
                const AppText(
                  'No budget set for this month.',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                const AppText(
                  'Set a monthly budget in Analysis to track your spending limits.',
                  style: TextStyle(fontSize: 12, color: muted, height: 1.6),
                ),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  key: const Key('home-manage-budget'),
                  onPressed: () => navigate(3),
                  icon: const Icon(Icons.tune_rounded, size: 18),
                  label: const AppText('Manage budget'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        AppText(
          '${store.demo ? 'SAMPLE' : 'TADBEER'} · ${DateFormat.yMMMM(languageOf(context)).format(month).toUpperCase()}',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 9, color: muted, letterSpacing: 1),
        ),
      ],
    );
  }

  Widget _stat(String label, String value, IconData icon, Color color) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: AppText(
                  label,
                  style: const TextStyle(fontSize: 10, color: muted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FittedBox(
            child: AppText(
              value,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      );
  Widget _summary(String label, String value, IconData icon, String detail) =>
      Surface(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: const Color(0xFFCDBB93), size: 19),
            const SizedBox(height: 16),
            AppText(label, style: const TextStyle(fontSize: 11, color: muted)),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: AppText(
                value,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 7),
            AppText(detail, style: const TextStyle(fontSize: 9, color: muted)),
          ],
        ),
      );
}
