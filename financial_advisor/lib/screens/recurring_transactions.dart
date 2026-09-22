import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/finance_store.dart';
import '../l10n/app_language.dart';
import '../widgets/design.dart';

String repeatScheduleExplanation(
  RepeatFrequency frequency,
) => switch (frequency) {
  RepeatFrequency.once => '',
  RepeatFrequency.daily =>
    'Adds an entry every day. Missed entries are added when you next open the app.',
  RepeatFrequency.weekly =>
    'Adds an entry every 7 days. Missed entries are added when you next open the app.',
  RepeatFrequency.monthly =>
    'Adds an entry on the same date each month, or the last day of a shorter month. Missed entries are added when you next open the app.',
};

class RecurringTransactionsPage extends StatefulWidget {
  final FinanceStore store;
  const RecurringTransactionsPage({super.key, required this.store});

  @override
  State<RecurringTransactionsPage> createState() =>
      _RecurringTransactionsPageState();
}

class _RecurringTransactionsPageState extends State<RecurringTransactionsPage> {
  final Set<String> stopping = {};
  bool retrying = false;

  Future<void> retry() async {
    if (retrying) return;
    setState(() => retrying = true);
    await widget.store.persist();
    if (mounted) setState(() => retrying = false);
  }

  Future<void> stop(RecurringTransaction rule) async {
    if (stopping.contains(rule.id)) return;
    if (!await confirm(
      context,
      'Stop repeating?',
      'Future entries will stop. Recorded transactions will stay in your history.',
      action: 'Stop repeating',
    )) {
      return;
    }
    if (!mounted) return;
    setState(() => stopping.add(rule.id));
    await widget.store.stopRecurringTransaction(rule.id);
    if (!mounted) return;
    setState(() => stopping.remove(rule.id));
    toast(context, widget.store.error ?? 'Repeating stopped');
  }

  @override
  Widget build(BuildContext context) => AuroraBackground(
    child: Scaffold(
      appBar: AppBar(title: const AppText('Recurring transactions')),
      body: AnimatedBuilder(
        animation: widget.store,
        builder: (context, _) {
          final rules =
              widget.store.recurringTransactions.toList()
                ..sort((a, b) => a.nextDate.compareTo(b.nextDate));
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              if (widget.store.error != null) ...[
                Surface(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppText(widget.store.error!),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: retrying ? null : retry,
                        icon: const Icon(Icons.refresh),
                        label: AppText(retrying ? 'Saving…' : 'Retry'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],
              const AppText(
                'Manage automatic income and expenses.',
                style: TextStyle(color: muted, height: 1.5),
              ),
              const SizedBox(height: 20),
              if (rules.isEmpty)
                const EmptyState(
                  icon: Icons.repeat,
                  title: 'No recurring transactions',
                  body:
                      'Choose a repeat schedule when adding income or an expense.',
                ),
              for (final rule in rules)
                Padding(
                  key: ValueKey('recurring-${rule.id}'),
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Surface(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CategoryBadge(
                              rule.income ? 'Income' : rule.category,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    rule.merchant,
                                    style:
                                        Theme.of(context).textTheme.titleMedium,
                                  ),
                                  const SizedBox(height: 6),
                                  AppText(
                                    '${rule.income ? 'Income' : 'Expense'} · ${rule.frequency.label}',
                                    style: const TextStyle(
                                      color: muted,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '${rule.income ? '+' : '−'}${widget.store.currency} ${money(rule.cents)}',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                            color: rule.income ? blue : ink,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            const AppText(
                              'Next entry',
                              style: TextStyle(color: muted),
                            ),
                            Text(
                              DateFormat.yMMMd(
                                languageOf(context),
                              ).format(rule.nextDate),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        AppText(
                          repeatScheduleExplanation(rule.frequency),
                          style: const TextStyle(
                            color: muted,
                            fontSize: 12,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          key: ValueKey('stop-recurring-${rule.id}'),
                          onPressed:
                              stopping.contains(rule.id)
                                  ? null
                                  : () => stop(rule),
                          icon: const Icon(
                            Icons.stop_circle_outlined,
                            size: 18,
                          ),
                          label: const AppText('Stop repeating'),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    ),
  );
}
