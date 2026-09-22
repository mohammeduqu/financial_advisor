import '../l10n/app_language.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/finance_store.dart';
import '../widgets/design.dart';
import 'transactions.dart';

class PlanPage extends StatefulWidget {
  final FinanceStore store;
  final DateTime month;
  const PlanPage({super.key, required this.store, required this.month});
  @override
  State<PlanPage> createState() => _PlanPageState();
}

class _PlanPageState extends State<PlanPage> {
  bool goals = false;
  FinanceStore get store => widget.store;
  Future<void> budget(String category) async {
    final value = await amountDialog(
      context,
      '$category budget',
      store.currency,
      initial: store.budgetFor(widget.month, category),
      allowRemove: store.budgetFor(widget.month, category) > 0,
    );
    if (value != null) await store.setBudget(widget.month, category, value);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: store,
    builder: (context, _) => _buildContent(context),
  );

  Widget _buildContent(BuildContext context) {
    final spent = store.expensesFor(widget.month),
        limit = store.budgetFor(widget.month);
    final expensesByCategory = <String, List<Entry>>{};
    for (final entry in store.forMonth(widget.month)) {
      if (!entry.income) {
        expensesByCategory.putIfAbsent(entry.category, () => []).add(entry);
      }
    }
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const PageHeading('Small steps. Real progress.', 'Analysis & planning'),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(
              value: false,
              label: AppText('Budgets'),
              icon: Icon(Icons.pie_chart_outline),
            ),
            ButtonSegment(
              value: true,
              label: AppText('Goals'),
              icon: Icon(Icons.flag_outlined),
            ),
          ],
          selected: {goals},
          onSelectionChanged: (s) => setState(() => goals = s.first),
        ),
        const SizedBox(height: 24),
        if (!goals) ...[
          Surface(
            color: ink,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppText(
                  '${DateFormat.MMMM(languageOf(context)).format(widget.month).toUpperCase()} BUDGET',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 10,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 14),
                AppText(
                  '${store.currency} ${money(spent)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                AppText(
                  limit == 0
                      ? 'No overall budget set'
                      : 'of ${money(limit)} · ${money(limit - spent)} remaining',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 20),
                LinearProgressIndicator(
                  value: limit > 0 ? (spent / limit).clamp(0.0, 1.0) : 0,
                  backgroundColor: Colors.white12,
                  color: const Color(0xFF91B7FF),
                  minHeight: 7,
                  borderRadius: BorderRadius.circular(5),
                ),
                const SizedBox(height: 14),
                TextButton(
                  onPressed: () => budget('Overall'),
                  style: TextButton.styleFrom(foregroundColor: Colors.white),
                  child: const AppText('Edit monthly budget →'),
                ),
              ],
            ),
          ),
          if (limit > 0 && spent >= limit * .8) ...[
            const SizedBox(height: 16),
            Surface(
              color: const Color(0xFF30291E),
              child: AppText(
                spent >= limit
                    ? 'You have reached your monthly budget.'
                    : 'You have used ${(spent / limit * 100).round()}% of your monthly budget.',
                style: const TextStyle(color: Color(0xFFE1BD7D), fontSize: 13),
              ),
            ),
          ],
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.content_copy_outlined, size: 18),
            label: const AppText('Use previous month’s budgets'),
            onPressed: () async {
              final count = await store.copyPreviousBudgets(widget.month);
              if (!context.mounted) return;
              toast(
                context,
                store.error ??
                    (count == 0
                        ? 'No missing budgets to copy from the previous month.'
                        : 'Copied $count budgets. Existing limits kept.'),
              );
            },
          ),
          const SectionHeading('Category budgets'),
          const AppText(
            'Tap a category to view its expenses. Tap an expense to edit it.',
            style: TextStyle(fontSize: 12, color: muted, height: 1.5),
          ),
          const SizedBox(height: 16),
          ...categories.map((c) {
            final expenses = expensesByCategory[c] ?? const <Entry>[];
            final used = expenses.fold(
              0,
              (total, entry) => total + entry.cents,
            );
            final cap = store.budgetFor(widget.month, c);
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Surface(
                padding: EdgeInsets.zero,
                child: ExpansionTile(
                  key: PageStorageKey(
                    'category-budget-${monthKey(widget.month)}-$c',
                  ),
                  tilePadding: const EdgeInsets.all(16),
                  childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                  shape: const RoundedRectangleBorder(),
                  collapsedShape: const RoundedRectangleBorder(),
                  iconColor: blue,
                  collapsedIconColor: muted,
                  leading: CategoryBadge(c),
                  title: AppText(
                    c,
                    style: const TextStyle(
                      color: ink,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      AppText(
                        '${money(used)} / ${cap > 0 ? money(cap) : 'not set'}',
                        style: const TextStyle(fontSize: 11, color: muted),
                      ),
                      const SizedBox(height: 4),
                      AppText(
                        expenses.length == 1
                            ? '1 expense'
                            : '${expenses.length} expenses',
                        style: const TextStyle(fontSize: 11, color: muted),
                      ),
                      if (cap > 0) ...[
                        const SizedBox(height: 12),
                        LinearProgressIndicator(
                          value: (used / cap).clamp(0.0, 1.0),
                          minHeight: 5,
                          color:
                              used >= cap * .8 ? const Color(0xFFDB6B32) : blue,
                          backgroundColor: line,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ],
                    ],
                  ),
                  children: [
                    const Divider(height: 1, color: line),
                    const SizedBox(height: 12),
                    if (expenses.isEmpty)
                      const Padding(
                        padding: EdgeInsets.fromLTRB(4, 0, 4, 16),
                        child: AppText(
                          'No expenses in this category this month.',
                          style: TextStyle(fontSize: 12, color: muted),
                        ),
                      ),
                    for (final expense in expenses)
                      EntryTile(
                        key: ValueKey('category-expense-${expense.id}'),
                        entry: expense,
                        store: store,
                      ),
                  ],
                ),
              ),
            );
          }),
          const AppText(
            'Category limits sit within the overall budget; they are not added to it.',
            style: TextStyle(fontSize: 11, color: muted),
          ),
        ] else ...[
          if (store.goals.isEmpty)
            const EmptyState(
              icon: Icons.flag_outlined,
              title: 'Make room for your next chapter',
              body: 'Create a goal and record contributions as you save.',
            ),
          ...store.goals.map(
            (g) => Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap:
                    () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => GoalDetail(store: store, goal: g),
                      ),
                    ),
                child: Surface(
                  color: g == store.goals.first ? ink : const Color(0xFFEAF1FF),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.flag_outlined,
                            color: g == store.goals.first ? Colors.white : blue,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              g.name,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color:
                                    g == store.goals.first ? Colors.white : ink,
                              ),
                            ),
                          ),
                          Icon(
                            Icons.chevron_right,
                            color:
                                g == store.goals.first ? Colors.white70 : muted,
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      AppText(
                        '${store.currency} ${money(g.saved)}',
                        style: TextStyle(
                          fontSize: 27,
                          fontWeight: FontWeight.w600,
                          color: g == store.goals.first ? Colors.white : ink,
                        ),
                      ),
                      const SizedBox(height: 6),
                      AppText(
                        'of ${money(g.target)} · ${(g.saved / g.target * 100).round()}%',
                        style: TextStyle(
                          fontSize: 12,
                          color:
                              g == store.goals.first ? Colors.white70 : muted,
                        ),
                      ),
                      const SizedBox(height: 18),
                      LinearProgressIndicator(
                        value: (g.saved / g.target).clamp(0.0, 1.0),
                        backgroundColor:
                            g == store.goals.first ? Colors.white12 : line,
                        color:
                            g == store.goals.first
                                ? const Color(0xFF91B7FF)
                                : blue,
                        minHeight: 6,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          OutlinedButton.icon(
            onPressed: () => newGoal(context, store),
            icon: const Icon(Icons.add),
            label: const AppText('Create a goal'),
          ),
          const SizedBox(height: 18),
          const AppText(
            'Contributions are records of your savings. This app does not move money.',
            style: TextStyle(fontSize: 11, color: muted),
          ),
        ],
      ],
    );
  }
}

Future<int?> amountDialog(
  BuildContext context,
  String title,
  String currency, {
  int initial = 0,
  bool allowRemove = false,
}) async {
  final controller = TextEditingController(
    text: initial > 0 ? (initial / 100).toStringAsFixed(2) : '',
  );
  final form = GlobalKey<FormState>();
  final result = await showDialog<int>(
    context: context,
    builder:
        (c) => AlertDialog(
          title: AppText(title),
          content: Form(
            key: form,
            child: TextFormField(
              autofocus: true,
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: tr(context, 'Amount ($currency)'),
              ),
              validator:
                  (v) =>
                      parseMoney(v ?? '') == null
                          ? tr(
                            context,
                            'Enter a positive amount (up to 2 decimals)',
                          )
                          : null,
            ),
          ),
          actions: [
            if (allowRemove)
              TextButton(
                onPressed: () => Navigator.pop(c, 0),
                child: const AppText('Remove budget'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const AppText('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (form.currentState!.validate()) {
                  Navigator.pop(c, parseMoney(controller.text));
                }
              },
              child: const AppText('Save'),
            ),
          ],
        ),
  );
  controller.dispose();
  return result;
}

Future<void> newGoal(BuildContext context, FinanceStore store, {Goal? goal}) =>
    Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => GoalEditor(store: store, goal: goal)),
    );

class GoalEditor extends StatefulWidget {
  final FinanceStore store;
  final Goal? goal;
  const GoalEditor({super.key, required this.store, this.goal});
  @override
  State<GoalEditor> createState() => _GoalEditorState();
}

class _GoalEditorState extends State<GoalEditor> {
  final form = GlobalKey<FormState>();
  late final TextEditingController name, amount;
  DateTime? deadline;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    name = TextEditingController(text: widget.goal?.name ?? '');
    amount = TextEditingController(
      text:
          widget.goal == null
              ? ''
              : (widget.goal!.target / 100).toStringAsFixed(2),
    );
    deadline = widget.goal?.deadline;
  }

  @override
  void dispose() {
    name.dispose();
    amount.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    setState(() => busy = true);
    final existing =
        widget.store.goals.where((g) => g.id == widget.goal?.id).firstOrNull;
    await widget.store.saveGoal(
      Goal(
        id: widget.goal?.id ?? newId(),
        name: name.text.trim(),
        target: parseMoney(amount.text)!,
        deadline: deadline,
        contributions: List.of(existing?.contributions ?? []),
      ),
    );
    if (!mounted) return;
    if (widget.store.error != null) {
      setState(() => busy = false);
      toast(context, widget.store.error!);
      return;
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: AppText(widget.goal == null ? 'Create a goal' : 'Edit goal'),
    ),
    body: Form(
      key: form,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          PageHeading(
            'Give your savings a purpose',
            widget.goal == null
                ? 'What are you saving for?'
                : 'Keep your plan up to date',
          ),
          TextFormField(
            key: const Key('goal-name'),
            controller: name,
            decoration: InputDecoration(labelText: tr(context, 'Goal name')),
            maxLength: 60,
            validator:
                (v) =>
                    v == null || v.trim().isEmpty
                        ? tr(context, 'Name your goal')
                        : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            key: const Key('goal-target'),
            controller: amount,
            decoration: InputDecoration(
              labelText: tr(context, 'Target (${widget.store.currency})'),
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            validator:
                (v) =>
                    parseMoney(v ?? '') == null
                        ? tr(
                          context,
                          'Enter a positive target with up to 2 decimals',
                        )
                        : null,
          ),
          const SizedBox(height: 24),
          Surface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const AppText(
                  'Your deadline',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                AppText(
                  deadline == null
                      ? 'Save at your own pace. Add a date for a monthly target.'
                      : DateFormat.yMMMd(languageOf(context)).format(deadline!),
                  style: const TextStyle(color: muted, fontSize: 13),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton.icon(
                      icon: const Icon(Icons.calendar_today_outlined, size: 18),
                      label: AppText(
                        deadline == null ? 'Set a date' : 'Change date',
                      ),
                      onPressed: () async {
                        final today = DateUtils.dateOnly(DateTime.now());
                        final picked = await showDatePicker(
                          context: context,
                          initialDate:
                              deadline != null && !deadline!.isBefore(today)
                                  ? deadline!
                                  : today.add(const Duration(days: 365)),
                          firstDate: today,
                          lastDate: DateTime(today.year + 30),
                        );
                        if (picked != null && mounted) {
                          setState(() => deadline = picked);
                        }
                      },
                    ),
                    if (deadline != null)
                      TextButton(
                        onPressed: () => setState(() => deadline = null),
                        child: const AppText('Remove deadline'),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          if (widget.goal != null)
            const Padding(
              padding: EdgeInsets.only(bottom: 20),
              child: AppText(
                'Your recorded contributions stay with this goal when you change its name, target or deadline.',
                style: TextStyle(fontSize: 12, color: muted, height: 1.6),
              ),
            ),
          FilledButton(
            onPressed: busy ? null : save,
            child: AppText(
              busy
                  ? 'Saving…'
                  : widget.goal == null
                  ? 'Create goal'
                  : 'Save goal',
            ),
          ),
        ],
      ),
    ),
  );
}

class ContributionEditor extends StatefulWidget {
  final FinanceStore store;
  final String goalId;
  final Contribution? contribution;
  const ContributionEditor({
    super.key,
    required this.store,
    required this.goalId,
    this.contribution,
  });
  @override
  State<ContributionEditor> createState() => _ContributionEditorState();
}

class _ContributionEditorState extends State<ContributionEditor> {
  final form = GlobalKey<FormState>();
  late final TextEditingController amount;
  late DateTime date;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    amount = TextEditingController(
      text:
          widget.contribution == null
              ? ''
              : (widget.contribution!.cents / 100).toStringAsFixed(2),
    );
    date = widget.contribution?.date ?? DateTime.now();
  }

  @override
  void dispose() {
    amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: AppText(
        widget.contribution == null
            ? 'Record contribution'
            : 'Edit contribution',
      ),
    ),
    body: Form(
      key: form,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const PageHeading('Every step counts', 'Record your progress'),
          TextFormField(
            key: const Key('contribution-amount'),
            controller: amount,
            decoration: InputDecoration(
              labelText: tr(context, 'Amount (${widget.store.currency})'),
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            validator:
                (v) =>
                    parseMoney(v ?? '') == null
                        ? tr(
                          context,
                          'Enter a positive amount with up to 2 decimals',
                        )
                        : null,
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            icon: const Icon(Icons.calendar_today_outlined, size: 18),
            label: AppText(DateFormat.yMMMd(languageOf(context)).format(date)),
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: date,
                firstDate: DateTime(2000),
                lastDate: DateTime.now(),
              );
              if (picked != null && mounted) setState(() => date = picked);
            },
          ),
          const SizedBox(height: 24),
          const Surface(
            child: AppText(
              'This records money you have already set aside. It does not transfer money or change your expense totals.',
              style: TextStyle(fontSize: 13, color: muted, height: 1.6),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed:
                busy
                    ? null
                    : () async {
                      if (!form.currentState!.validate()) return;
                      setState(() => busy = true);
                      await widget.store.saveContribution(
                        widget.goalId,
                        Contribution(
                          widget.contribution?.id ?? newId(),
                          parseMoney(amount.text)!,
                          date,
                        ),
                      );
                      if (!context.mounted) return;
                      if (widget.store.error != null) {
                        setState(() => busy = false);
                        toast(context, widget.store.error!);
                        return;
                      }
                      Navigator.pop(context);
                    },
            child: AppText(busy ? 'Saving…' : 'Save contribution'),
          ),
        ],
      ),
    ),
  );
}

class GoalDetail extends StatelessWidget {
  final FinanceStore store;
  final Goal goal;
  const GoalDetail({super.key, required this.store, required this.goal});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: store,
    builder: (context, _) {
      final current = store.goals.where((g) => g.id == goal.id).firstOrNull;
      if (current == null) {
        return Scaffold(
          appBar: AppBar(),
          body: const Center(child: AppText('Goal removed')),
        );
      }
      final remaining = (current.target - current.saved).clamp(
        0,
        current.target,
      );
      final today = DateUtils.dateOnly(DateTime.now());
      final days = current.deadline?.difference(today).inDays;
      final months = days == null || days < 0 ? 0 : ((days + 1) / 30).ceil();
      final history = List<Contribution>.of(current.contributions)
        ..sort((a, b) => b.date.compareTo(a.date));
      return Scaffold(
        appBar: AppBar(
          title: Text(current.name),
          actions: [
            IconButton(
              tooltip: tr(context, 'Edit goal'),
              onPressed: () => newGoal(context, store, goal: current),
              icon: const Icon(Icons.edit_outlined),
            ),
            IconButton(
              tooltip: tr(context, 'Delete goal'),
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                if (await confirm(
                  context,
                  'Delete goal?',
                  'Remove this goal and its recorded contributions?',
                  action: 'Delete',
                )) {
                  await store.deleteGoal(current.id);
                  if (context.mounted) Navigator.pop(context);
                }
              },
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Surface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const AppText(
                    'SAVED SO FAR',
                    style: TextStyle(
                      fontSize: 10,
                      color: muted,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  AppText(
                    '${store.currency} ${money(current.saved)}',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  AppText(
                    'Target ${money(current.target)}',
                    style: const TextStyle(color: muted),
                  ),
                  const SizedBox(height: 18),
                  LinearProgressIndicator(
                    value: (current.saved / current.target).clamp(0.0, 1.0),
                    minHeight: 7,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  const SizedBox(height: 20),
                  AppText(
                    remaining == 0
                        ? 'You reached your goal.'
                        : months > 0
                        ? 'Illustrative monthly contribution: ${store.currency} ${money((remaining / months).ceil())} to reach your deadline.'
                        : days != null
                        ? 'The deadline has passed. Edit your goal to set a new date.'
                        : '${store.currency} ${money(remaining)} left to reach your goal.',
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      color: muted,
                    ),
                  ),
                  if (current.deadline != null) ...[
                    const SizedBox(height: 12),
                    AppText(
                      'Target date: ${DateFormat.yMMMd(languageOf(context)).format(current.deadline!)}',
                      style: const TextStyle(fontSize: 12, color: muted),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed:
                  () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder:
                          (_) => ContributionEditor(
                            store: store,
                            goalId: current.id,
                          ),
                    ),
                  ),
              icon: const Icon(Icons.add),
              label: const AppText('Record contribution'),
            ),
            const SectionHeading('Contribution history'),
            if (history.isEmpty)
              const EmptyState(
                icon: Icons.savings_outlined,
                title: 'Your first step is waiting',
                body: 'Record a contribution when you set money aside.',
              ),
            ...history.map(
              (c) => ListTile(
                contentPadding: EdgeInsets.zero,
                title: AppText('${store.currency} ${money(c.cents)}'),
                subtitle: AppText(
                  DateFormat.yMMMd(languageOf(context)).format(c.date),
                ),
                onTap:
                    () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder:
                            (_) => ContributionEditor(
                              store: store,
                              goalId: current.id,
                              contribution: c,
                            ),
                      ),
                    ),
                trailing: PopupMenuButton<String>(
                  tooltip: tr(context, 'Contribution actions'),
                  onSelected: (action) async {
                    if (action == 'edit') {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder:
                              (_) => ContributionEditor(
                                store: store,
                                goalId: current.id,
                                contribution: c,
                              ),
                        ),
                      );
                    } else if (await confirm(
                      context,
                      'Remove contribution?',
                      'This corrects your recorded goal progress.',
                    )) {
                      await store.removeContribution(current.id, c.id);
                    }
                  },
                  itemBuilder:
                      (_) => const [
                        PopupMenuItem(
                          value: 'edit',
                          child: AppText('Edit contribution'),
                        ),
                        PopupMenuItem(
                          value: 'remove',
                          child: AppText('Remove contribution'),
                        ),
                      ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            const AppText(
              'Goal contributions never create expenses or change cash flow.',
              style: TextStyle(fontSize: 12, color: muted),
            ),
          ],
        ),
      );
    },
  );
}
