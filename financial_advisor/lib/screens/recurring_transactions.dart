import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/finance_store.dart';
import '../l10n/app_language.dart';
import '../widgets/design.dart';
import 'transactions.dart';

String repeatIntervalUnit(RepeatFrequency frequency) => switch (frequency) {
  RepeatFrequency.once => '',
  RepeatFrequency.daily => 'days',
  RepeatFrequency.weekly => 'weeks',
  RepeatFrequency.monthly => 'months',
  RepeatFrequency.yearly => 'years',
};

bool isRecurringActive(RecurringTransaction rule) =>
    rule.active &&
    (rule.endDate == null || !rule.nextDate.isAfter(rule.endDate!));

String recurringScheduleLabel(RecurringTransaction rule) =>
    rule.interval == 1
        ? 'Repeat: ${rule.frequency.label}'
        : 'Repeat every ${rule.interval} ${repeatIntervalUnit(rule.frequency)}';

RecurringTransaction? activeRecurringForEntry(FinanceStore store, Entry entry) {
  final root =
      store.recurringForEntry(entry)?.rootId ??
      entry.parentRecurringTransactionId;
  if (root == null) return null;
  return store.recurringTransactions
      .where((rule) => rule.rootId == root && isRecurringActive(rule))
      .lastOrNull;
}

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
  RepeatFrequency.yearly =>
    'Adds an entry on the same date each year, or the last day of February in a non-leap year. Missed entries are added when you next open the app.',
};

class RecurringTransactionsPage extends StatefulWidget {
  final FinanceStore store;
  const RecurringTransactionsPage({super.key, required this.store});

  @override
  State<RecurringTransactionsPage> createState() =>
      _RecurringTransactionsPageState();
}

class _RecurringTransactionsPageState extends State<RecurringTransactionsPage> {
  final Set<String> deleting = {};
  bool retrying = false;

  Future<void> retry() async {
    if (retrying) return;
    setState(() => retrying = true);
    await widget.store.persist();
    if (mounted) setState(() => retrying = false);
  }

  Future<void> delete(RecurringTransaction rule) async {
    if (deleting.contains(rule.id)) return;
    final scope = await showDialog<RecurringScope>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const AppText('Delete recurring transaction?'),
            content: const AppText(
              'Choose whether to remove the whole series or keep past transactions.',
            ),
            actions: [
              TextButton(
                key: const Key('delete-series-cancel'),
                onPressed: () => Navigator.pop(dialogContext),
                child: const AppText('Cancel'),
              ),
              TextButton(
                key: const Key('delete-series-future'),
                onPressed:
                    () => Navigator.pop(
                      dialogContext,
                      RecurringScope.thisAndFuture,
                    ),
                child: const AppText('Stop and delete future transactions'),
              ),
              FilledButton(
                key: const Key('delete-series-all'),
                onPressed:
                    () => Navigator.pop(dialogContext, RecurringScope.all),
                child: const AppText('Delete all transactions in this series'),
              ),
            ],
          ),
    );
    if (scope == null || !mounted) return;
    setState(() => deleting.add(rule.id));
    await widget.store.deleteRecurringTemplate(rule.id, scope: scope);
    if (!mounted) return;
    setState(() => deleting.remove(rule.id));
    toast(context, widget.store.error ?? 'Recurring transaction deleted');
  }

  @override
  Widget build(BuildContext context) => AuroraBackground(
    child: Scaffold(
      appBar: AppBar(title: const AppText('Recurring transactions')),
      body: AnimatedBuilder(
        animation: widget.store,
        builder: (context, _) {
          final activeRules =
              widget.store.recurringTransactions
                  .where(isRecurringActive)
                  .toList()
                ..sort((a, b) => a.nextDate.compareTo(b.nextDate));
          final groups = <String, List<RecurringTransaction>>{};
          for (final rule in activeRules) {
            groups.putIfAbsent(rule.rootId, () => []).add(rule);
          }
          final rules =
              groups.values.map((versions) => versions.first).toList();
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
                  key: ValueKey('recurring-${rule.rootId}'),
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
                                    rule.income ? 'Income' : 'Expense',
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
                        if (groups[rule.rootId]!.length > 1) ...[
                          const SizedBox(height: 16),
                          const AppText(
                            'Scheduled changes',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          for (final change in groups[rule.rootId]!.skip(1))
                            Padding(
                              key: ValueKey('recurring-change-${change.id}'),
                              padding: const EdgeInsets.only(top: 12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  AppText(
                                    'From ${DateFormat.yMMMd(languageOf(context)).format(change.startDate)}',
                                    style: const TextStyle(
                                      color: muted,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  AppText(recurringScheduleLabel(change)),
                                  Text(
                                    '${change.merchant} · ${change.income ? '+' : '−'}${widget.store.currency} ${money(change.cents)}',
                                  ),
                                ],
                              ),
                            ),
                        ],
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
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            AppText(recurringScheduleLabel(rule)),
                            AppText(
                              rule.endDate == null
                                  ? 'No end date'
                                  : 'Ends: ${DateFormat.yMMMd(languageOf(context)).format(rule.endDate!)}',
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              key: ValueKey('edit-recurring-${rule.rootId}'),
                              onPressed:
                                  deleting.contains(rule.id)
                                      ? null
                                      : () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder:
                                              (_) => EntryEditor(
                                                store: widget.store,
                                                recurringTemplate: rule,
                                              ),
                                        ),
                                      ),
                              icon: const Icon(Icons.edit_outlined, size: 18),
                              label: const AppText('Edit'),
                            ),
                            OutlinedButton.icon(
                              key: ValueKey('delete-recurring-${rule.rootId}'),
                              onPressed:
                                  deleting.contains(rule.id)
                                      ? null
                                      : () => delete(rule),
                              icon: const Icon(Icons.delete_outline, size: 18),
                              label: const AppText('Delete'),
                            ),
                          ],
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
