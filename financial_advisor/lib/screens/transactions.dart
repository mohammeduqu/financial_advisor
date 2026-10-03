import '../l10n/app_language.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/finance_store.dart';
import '../core/invoice.dart' show normalizeInvoiceDigits;
import '../widgets/design.dart';
import 'invoice_review.dart';
import 'recurring_transactions.dart';

Future<void> editEntry(
  BuildContext context,
  FinanceStore store, {
  Entry? entry,
  bool receiptReview = false,
  bool initialIncome = false,
}) async {
  RecurringScope? scope;
  if (entry != null && store.recurringForEntry(entry) != null) {
    scope = await chooseRecurringScope(context);
    if (scope == null || !context.mounted) return;
  }
  if (entry != null &&
      entry.invoice != null &&
      store.recurringForEntry(entry) == null) {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) => InvoiceReviewScreen(
              store: store,
              invoice: entry.invoice!,
              receipt: entry.receipt,
              existingEntry: entry,
              recurringScope: scope,
            ),
      ),
    );
    return;
  }
  await Navigator.push(
    context,
    MaterialPageRoute(
      builder:
          (_) => EntryEditor(
            store: store,
            entry: entry,
            receiptReview: receiptReview,
            initialIncome: initialIncome,
            recurringScope: scope,
          ),
    ),
  );
}

String recurringScopeLabel(RecurringScope scope) => switch (scope) {
  RecurringScope.onlyThis => 'Only this transaction',
  RecurringScope.thisAndFuture => 'This and future transactions',
  RecurringScope.all => 'All transactions in this series',
};

Future<RecurringScope?> chooseRecurringScope(BuildContext context) =>
    showDialog<RecurringScope>(
      context: context,
      builder:
          (dialogContext) => SimpleDialog(
            title: const AppText('Apply changes to'),
            children: [
              for (final scope in RecurringScope.values)
                SimpleDialogOption(
                  key: ValueKey('recurring-scope-${scope.name}'),
                  onPressed: () => Navigator.pop(dialogContext, scope),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: AppText(recurringScopeLabel(scope)),
                  ),
                ),
              SimpleDialogOption(
                onPressed: () => Navigator.pop(dialogContext),
                child: const AppText('Cancel'),
              ),
            ],
          ),
    );

class EntryEditor extends StatefulWidget {
  final FinanceStore store;
  final Entry? entry;
  final bool receiptReview;
  final bool initialIncome;
  final RecurringScope? recurringScope;
  final RecurringTransaction? recurringTemplate;
  final bool scheduleOnly;
  const EntryEditor({
    super.key,
    required this.store,
    this.entry,
    this.receiptReview = false,
    this.initialIncome = false,
    this.recurringScope,
    this.recurringTemplate,
    this.scheduleOnly = false,
  });
  @override
  State<EntryEditor> createState() => _EntryEditorState();
}

class _EntryEditorState extends State<EntryEditor> {
  final form = GlobalKey<FormState>();
  late TextEditingController merchant, amount, note, interval;
  late DateTime date;
  late String category;
  late bool income;
  bool busy = false;
  bool retryPending = false;
  RepeatFrequency frequency = RepeatFrequency.once;
  DateTime? endDate;
  late RecurringScope scope;
  late final String id;
  RecurringTransaction? get parent =>
      widget.recurringTemplate ??
      (widget.entry == null
          ? null
          : widget.store.recurringForEntry(widget.entry!));
  RecurringTransaction? get activeParent =>
      widget.recurringTemplate ??
      (widget.entry == null
          ? null
          : activeRecurringForEntry(widget.store, widget.entry!));
  bool get canSetRepeat => !widget.receiptReview;
  bool get onlyThisOccurrence =>
      widget.recurringTemplate == null &&
      parent != null &&
      scope == RecurringScope.onlyThis;
  bool get editingEnabled => !busy && !retryPending;
  int get selectedInterval =>
      frequency == RepeatFrequency.once
          ? 1
          : int.parse(normalizeInvoiceDigits(interval.text));
  DateTime? get selectedEndDate =>
      frequency == RepeatFrequency.once ? null : endDate;
  @override
  void initState() {
    super.initState();
    final rule = widget.recurringTemplate;
    final e = widget.entry;
    scope = widget.recurringScope ?? RecurringScope.onlyThis;
    id = rule?.id ?? e?.id ?? newId();
    merchant = TextEditingController(text: rule?.merchant ?? e?.merchant ?? '');
    final cents = rule?.cents ?? e?.cents;
    amount = TextEditingController(
      text: cents == null || cents == 0 ? '' : (cents / 100).toStringAsFixed(2),
    );
    note = TextEditingController(text: rule?.note ?? e?.note ?? '');
    date = rule?.nextDate ?? e?.date ?? DateTime.now();
    final savedCategory = rule?.category ?? e?.category;
    category = categories.contains(savedCategory) ? savedCategory! : 'Other';
    income = rule?.income ?? e?.income ?? widget.initialIncome;
    frequency =
        (!onlyThisOccurrence || widget.entry?.recurrenceDisabled != true) &&
                activeParent != null
            ? activeParent!.frequency
            : RepeatFrequency.once;
    interval = TextEditingController(text: '${activeParent?.interval ?? 1}');
    endDate = activeParent?.endDate;
  }

  @override
  void dispose() {
    merchant.dispose();
    amount.dispose();
    note.dispose();
    interval.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (busy) return;
    if (retryPending) {
      setState(() => busy = true);
      await widget.store.persist();
      finishSave();
      return;
    }
    if (!form.currentState!.validate()) return;
    if (canSetRepeat &&
        !onlyThisOccurrence &&
        frequency != RepeatFrequency.once &&
        endDate != null &&
        endDate!.isBefore(DateUtils.dateOnly(date))) {
      toast(context, 'End date must be on or after the start date.');
      return;
    }
    final e = Entry(
      id: id,
      merchant: merchant.text.trim(),
      cents: parseMoney(amount.text)!,
      date: date,
      category: income ? 'Income' : category,
      income: income,
      note: note.text.trim(),
      receipt: widget.entry?.receipt,
      invoice: widget.entry?.invoice,
      recurringId: widget.entry?.recurringId,
      recurringScheduleId: widget.entry?.recurringScheduleId,
      recurringScheduledDate: widget.entry?.recurringScheduledDate,
      isProjected: widget.entry?.isProjected ?? false,
      recurrenceDisabled: widget.entry?.recurrenceDisabled ?? false,
    );
    if (widget.recurringTemplate == null && widget.store.isDuplicate(e)) {
      if (!await confirm(
        context,
        'Possible duplicate',
        'An entry with this merchant, date and amount, or this receipt image, already exists. Save another?',
        action: 'Save another',
      )) {
        return;
      }
    }
    if (!mounted) return;
    if (widget.receiptReview &&
        !await confirm(
          context,
          'Confirm receipt',
          'Save ${widget.store.currency} ${money(e.cents)} at ${e.merchant}? The displayed total already includes any VAT.',
          action: 'Save expense',
        )) {
      return;
    }
    if (!mounted) return;
    setState(() => busy = true);
    try {
      if (widget.recurringTemplate != null) {
        await widget.store.updateRecurringTemplate(
          widget.recurringTemplate!.copyWith(
            merchant: e.merchant,
            cents: e.cents,
            category: e.category,
            income: e.income,
            note: e.note,
            startDate: date,
            frequency:
                frequency == RepeatFrequency.once
                    ? widget.recurringTemplate!.frequency
                    : frequency,
            interval: selectedInterval,
            endDate: selectedEndDate,
            clearEndDate: selectedEndDate == null,
          ),
          frequency: frequency,
        );
      } else if (widget.entry != null && parent != null) {
        await widget.store.updateRecurringEntry(
          e,
          scope: scope,
          frequency: canSetRepeat ? frequency : null,
          interval:
              canSetRepeat && !onlyThisOccurrence ? selectedInterval : null,
          endDate: onlyThisOccurrence ? null : selectedEndDate,
          clearEndDate:
              canSetRepeat && !onlyThisOccurrence && selectedEndDate == null,
        );
      } else if (canSetRepeat) {
        await widget.store.saveScheduledEntry(
          e,
          frequency,
          interval: selectedInterval,
          endDate: selectedEndDate,
        );
      } else {
        await widget.store.saveEntry(e);
      }
    } on ArgumentError catch (error) {
      if (!mounted) return;
      setState(() => busy = false);
      toast(
        context,
        error.message ==
                'Start date must be after earlier recorded occurrences.'
            ? 'Start date must be after earlier recorded occurrences.'
            : 'Transaction could not be saved. Try again.',
      );
      return;
    } catch (_) {
      if (!mounted) return;
      setState(() => busy = false);
      toast(
        context,
        widget.store.error ?? 'Transaction could not be saved. Try again.',
      );
      return;
    }
    finishSave();
  }

  void finishSave() {
    if (!mounted) return;
    if (widget.store.error != null) {
      setState(() {
        busy = false;
        retryPending = true;
      });
      toast(context, widget.store.error!);
      return;
    }
    Navigator.pop(context, true);
    toast(
      context,
      frequency == RepeatFrequency.once
          ? 'Transaction saved'
          : 'Recurring transaction saved',
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: AppText(
        widget.receiptReview
            ? 'Review receipt'
            : widget.scheduleOnly
            ? 'Repeat settings'
            : widget.recurringTemplate != null
            ? 'Edit recurring transaction'
            : widget.entry == null
            ? 'New transaction'
            : 'Edit transaction',
      ),
      actions: [
        if (widget.entry != null &&
            !widget.receiptReview &&
            !widget.scheduleOnly &&
            widget.recurringTemplate == null)
          IconButton(
            tooltip: tr(context, 'Delete transaction'),
            icon: const Icon(Icons.delete_outline),
            onPressed:
                !editingEnabled
                    ? null
                    : () async {
                      if (await confirm(
                        context,
                        'Delete transaction?',
                        parent == null
                            ? 'This removes it from your recorded totals.'
                            : 'Only this transaction will be removed. Other transactions in this series stay unchanged.',
                        action: 'Delete',
                      )) {
                        if (parent != null) {
                          await widget.store.deleteRecurringEntry(
                            widget.entry!,
                            scope: RecurringScope.onlyThis,
                          );
                        } else {
                          await widget.store.deleteEntry(id);
                        }
                        if (context.mounted) Navigator.pop(context);
                      }
                    },
          ),
      ],
    ),
    body: Form(
      key: form,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          if (widget.receiptReview) ...[
            Surface(
              color: const Color(0xFF30291E),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.fact_check_outlined,
                    color: Color(0xFFE1BD7D),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AppText(
                      'Review every field before saving. OCR can misread totals and dates. Currency: ${widget.store.currency}.',
                      style: const TextStyle(fontSize: 13, height: 1.5),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],
          if (widget.entry?.receipt != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.memory(
                base64Decode(widget.entry!.receipt!),
                height: 190,
                fit: BoxFit.contain,
                errorBuilder:
                    (_, __, ___) =>
                        const AppText('Receipt preview unavailable'),
              ),
            ),
            const SizedBox(height: 20),
          ],
          if (widget.entry?.invoice != null && !widget.scheduleOnly) ...[
            if (widget.entry!.invoice!.totalCents != widget.entry!.cents)
              const AppText(
                'The original invoice amount differs from this edited transaction. Repeat settings keep the original invoice unchanged.',
                style: TextStyle(color: muted, fontSize: 12),
              ),
            OutlinedButton.icon(
              key: const Key('entry-invoice-details'),
              onPressed:
                  !editingEnabled
                      ? null
                      : () async {
                        final result =
                            await Navigator.push<InvoiceReviewResult>(
                              context,
                              MaterialPageRoute(
                                builder:
                                    (_) => InvoiceReviewScreen(
                                      store: widget.store,
                                      invoice: widget.entry!.invoice!,
                                      existingEntry: widget.entry,
                                      receipt: widget.entry!.receipt,
                                      recurringScope: scope,
                                    ),
                              ),
                            );
                        if (result?.action == InvoiceReviewAction.saved &&
                            context.mounted) {
                          Navigator.pop(context, true);
                        }
                      },
              icon: const Icon(Icons.receipt_long_outlined),
              label: const AppText('Invoice details'),
            ),
            const SizedBox(height: 16),
          ],
          if (widget.scheduleOnly) ...[
            Text(merchant.text, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text('${widget.store.currency} ${amount.text}'),
            const SizedBox(height: 20),
          ],
          if (parent != null && widget.recurringTemplate == null) ...[
            Surface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppText(recurringScopeLabel(scope)),
                  if (scope == RecurringScope.onlyThis)
                    const AppText(
                      'The repeat schedule stays unchanged for other transactions.',
                      style: TextStyle(color: muted, fontSize: 12),
                    ),
                  TextButton(
                    key: const Key('change-recurring-scope'),
                    onPressed:
                        !editingEnabled
                            ? null
                            : () async {
                              final selected = await chooseRecurringScope(
                                context,
                              );
                              if (selected != null && mounted) {
                                setState(() {
                                  scope = selected;
                                  frequency =
                                      onlyThisOccurrence &&
                                              widget
                                                      .entry
                                                      ?.recurrenceDisabled ==
                                                  true
                                          ? RepeatFrequency.once
                                          : activeParent?.frequency ??
                                              RepeatFrequency.once;
                                  interval.text =
                                      '${activeParent?.interval ?? 1}';
                                  endDate = activeParent?.endDate;
                                });
                              }
                            },
                    child: const AppText('Change scope'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],
          if (!widget.scheduleOnly) ...[
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: false,
                  label: AppText('Expense'),
                  icon: Icon(Icons.arrow_upward),
                ),
                ButtonSegment(
                  value: true,
                  label: AppText('Income'),
                  icon: Icon(Icons.arrow_downward),
                ),
              ],
              selected: {income},
              onSelectionChanged:
                  widget.receiptReview || !editingEnabled
                      ? null
                      : (v) => setState(() => income = v.first),
            ),
            const SizedBox(height: 24),
            TextFormField(
              controller: merchant,
              readOnly: !editingEnabled,
              decoration: InputDecoration(
                labelText: tr(context, income ? 'Source' : 'Merchant'),
                prefixIcon: const Icon(Icons.storefront_outlined),
              ),
              textCapitalization: TextCapitalization.words,
              validator:
                  (v) =>
                      v == null || v.trim().isEmpty
                          ? tr(context, 'Enter a name')
                          : null,
              onChanged: (v) {
                if (widget.entry == null && !income) {
                  setState(() => category = suggestCategoryLocal(v));
                }
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: amount,
              readOnly: !editingEnabled,
              decoration: InputDecoration(
                labelText: tr(context, 'Amount (${widget.store.currency})'),
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              validator:
                  (v) =>
                      parseMoney(v ?? '') == null
                          ? tr(
                            context,
                            'Use a positive amount with up to 2 decimals',
                          )
                          : null,
            ),
            const SizedBox(height: 16),
          ],
          if (canSetRepeat) ...[
            DropdownButtonFormField<RepeatFrequency>(
              key: const Key('entry-repeat'),
              value: frequency,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: tr(context, 'Repeat'),
                prefixIcon: const Icon(Icons.repeat),
              ),
              items:
                  (onlyThisOccurrence
                          ? [
                            RepeatFrequency.once,
                            if (activeParent != null) activeParent!.frequency,
                          ]
                          : RepeatFrequency.values)
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: AppText(value.label),
                        ),
                      )
                      .toList(),
              onChanged:
                  !editingEnabled
                      ? null
                      : (value) => setState(() {
                        frequency = value!;
                      }),
            ),
            if (frequency != RepeatFrequency.once && !onlyThisOccurrence) ...[
              const SizedBox(height: 10),
              AppText(
                interval.text == '1'
                    ? repeatScheduleExplanation(frequency)
                    : 'Repeat every ${interval.text} ${repeatIntervalUnit(frequency)}',
                style: const TextStyle(color: muted, fontSize: 12, height: 1.5),
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const Key('entry-repeat-interval'),
                controller: interval,
                enabled: editingEnabled,
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: tr(context, 'Repeat every'),
                  suffixText: tr(context, repeatIntervalUnit(frequency)),
                ),
                validator: (value) {
                  final parsed = int.tryParse(
                    normalizeInvoiceDigits(value ?? ''),
                  );
                  return parsed == null || parsed < 1 || parsed > 365
                      ? tr(context, 'Enter a whole number from 1 to 365')
                      : null;
                },
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const Key('entry-repeat-end'),
                icon: const Icon(Icons.event_available_outlined),
                label: AppText(
                  endDate == null
                      ? 'No end date'
                      : 'Ends: ${DateFormat.yMMMd(languageOf(context)).format(endDate!)}',
                ),
                onPressed:
                    !editingEnabled
                        ? null
                        : () async {
                          final first = DateUtils.dateOnly(date);
                          final picked = await showDatePicker(
                            context: context,
                            initialDate:
                                endDate == null || endDate!.isBefore(first)
                                    ? first
                                    : endDate!,
                            firstDate: first,
                            lastDate: DateTime(
                              DateTime.now().year + 50,
                              12,
                              31,
                            ),
                          );
                          if (picked != null && mounted) {
                            setState(() => endDate = picked);
                          }
                        },
              ),
              if (endDate != null)
                TextButton(
                  key: const Key('clear-repeat-end'),
                  onPressed:
                      !editingEnabled
                          ? null
                          : () => setState(() => endDate = null),
                  child: const AppText('Remove end date'),
                ),
            ],
            const SizedBox(height: 16),
          ],
          if (frequency != RepeatFrequency.once) ...[
            const AppText('Start date', style: TextStyle(color: muted)),
            const SizedBox(height: 8),
          ],
          OutlinedButton.icon(
            key: const Key('entry-date'),
            icon: const Icon(Icons.calendar_today_outlined, size: 18),
            label: AppText(DateFormat.yMMMd(languageOf(context)).format(date)),
            onPressed:
                !editingEnabled
                    ? null
                    : () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: date,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(DateTime.now().year + 50, 12, 31),
                      );
                      if (picked != null) setState(() => date = picked);
                    },
          ),
          const SizedBox(height: 16),
          if (!income && !widget.scheduleOnly) ...[
            DropdownButtonFormField<String>(
              value: categories.contains(category) ? category : 'Other',
              decoration: InputDecoration(labelText: tr(context, 'Category')),
              items:
                  categories
                      .map((c) => DropdownMenuItem(value: c, child: AppText(c)))
                      .toList(),
              onChanged:
                  !editingEnabled ? null : (v) => setState(() => category = v!),
            ),
            const SizedBox(height: 16),
          ],
          if (!widget.scheduleOnly)
            TextFormField(
              controller: note,
              readOnly: !editingEnabled,
              decoration: InputDecoration(
                labelText: tr(context, 'Note (optional)'),
              ),
              maxLines: 2,
            ),
          const SizedBox(height: 28),
          FilledButton.icon(
            key: const Key('save-entry'),
            onPressed: busy ? null : save,
            icon: const Icon(Icons.check),
            label: AppText(
              busy
                  ? 'Saving…'
                  : retryPending
                  ? 'Retry'
                  : widget.receiptReview
                  ? 'Confirm & save expense'
                  : 'Save transaction',
            ),
          ),
        ],
      ),
    ),
  );
}

String suggestCategoryLocal(String s) {
  final v = s.toLowerCase();
  if (RegExp('market|cafe|restaurant|coffee').hasMatch(v)) return 'Food';
  if (RegExp('uber|careem|fuel').hasMatch(v)) return 'Transportation';
  return 'Other';
}

class TransactionsPage extends StatefulWidget {
  final FinanceStore store;
  final DateTime? month;
  final int periodRevision;
  final ValueChanged<DateTime?>? onMonthChanged;
  final String? highlightedEntryId;
  const TransactionsPage({
    super.key,
    required this.store,
    this.month,
    this.periodRevision = 0,
    this.onMonthChanged,
    this.highlightedEntryId,
  });
  @override
  State<TransactionsPage> createState() => _TransactionsPageState();
}

class _TransactionsPageState extends State<TransactionsPage> {
  String query = '', filter = 'All', category = 'All categories';
  late String dateView;

  @override
  void initState() {
    super.initState();
    dateView = widget.month == null ? 'All dates' : 'Selected month';
  }

  @override
  void didUpdateWidget(covariant TransactionsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.periodRevision != widget.periodRevision ||
        oldWidget.month?.year != widget.month?.year ||
        oldWidget.month?.month != widget.month?.month) {
      dateView = widget.month == null ? 'All dates' : 'Selected month';
    }
  }

  @override
  Widget build(BuildContext context) {
    final today = DateUtils.dateOnly(DateTime.now());
    final month = widget.month;
    final rangeStart =
        month == null ? today : DateTime(month.year, month.month);
    final rangeEnd =
        month == null
            ? DateTime(today.year, today.month + 2, 0)
            : DateTime(month.year, month.month + 1, 0);
    final showPreviews = dateView != 'All dates';
    final previewEntries =
        showPreviews
            ? widget.store.entriesForRange(rangeStart, rangeEnd)
            : <Entry>[];
    final visible =
        dateView == 'All dates'
            ? widget.store.forPeriod(null)
            : month != null
            ? previewEntries
            : [
              ...widget.store.forPeriod(null),
              ...previewEntries.where((entry) => entry.isProjected),
            ];
    final entries =
        visible
            .where(
              (e) =>
                  (dateView != 'Upcoming' ||
                      DateUtils.dateOnly(e.date).isAfter(today)) &&
                  (filter == 'All' || e.income == (filter == 'Income')) &&
                  (category == 'All categories' || category == e.category) &&
                  ('${e.merchant} ${e.note}').toLowerCase().contains(
                    query.toLowerCase(),
                  ),
            )
            .toList()
          ..sort(
            (a, b) =>
                dateView == 'Upcoming'
                    ? a.date.compareTo(b.date)
                    : b.date.compareTo(a.date),
          );
    final recordedCount = entries.where((entry) => !entry.isProjected).length;
    final projectedCount = entries.length - recordedCount;
    final savedIndex = entries.indexWhere(
      (entry) => entry.id == widget.highlightedEntryId,
    );
    if (savedIndex > 0) {
      entries.insert(0, entries.removeAt(savedIndex));
    }
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        PageHeading(
          'Income and expenses',
          'Transactions',
          action: IconButton.filled(
            onPressed: () => editEntry(context, widget.store),
            tooltip: tr(context, 'Add transaction'),
            icon: const Icon(Icons.add),
          ),
        ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: OutlinedButton.icon(
            key: const Key('manage-recurring'),
            icon: const Icon(Icons.repeat, size: 18),
            label: const AppText('Recurring'),
            onPressed:
                () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder:
                        (_) => RecurringTransactionsPage(store: widget.store),
                  ),
                ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            for (final view in [
              if (month != null) 'Selected month',
              'All dates',
              'Upcoming',
            ])
              ChoiceChip(
                key: ValueKey('transaction-dates-$view'),
                label: AppText(view),
                selected: dateView == view,
                onSelected: (_) {
                  setState(() => dateView = view);
                  if (view == 'All dates') widget.onMonthChanged?.call(null);
                },
              ),
          ],
        ),
        if (showPreviews) ...[
          const SizedBox(height: 8),
          AppText(
            'Scheduled previews: ${DateFormat.yMMMd(languageOf(context)).format(rangeStart)} – ${DateFormat.yMMMd(languageOf(context)).format(rangeEnd)}',
            style: const TextStyle(color: muted, fontSize: 12),
          ),
        ],
        const SizedBox(height: 16),
        TextField(
          decoration: InputDecoration(
            hintText: tr(context, 'Search merchant or note'),
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (v) => setState(() => query = v),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          children:
              ['All', 'Expenses', 'Income']
                  .map(
                    (v) => ChoiceChip(
                      label: AppText(v),
                      selected: filter == v,
                      onSelected: (_) => setState(() => filter = v),
                    ),
                  )
                  .toList(),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: category,
          decoration: InputDecoration(labelText: tr(context, 'Category')),
          items:
              ['All categories', ...categories, 'Income']
                  .map((c) => DropdownMenuItem(value: c, child: AppText(c)))
                  .toList(),
          onChanged: (v) => setState(() => category = v!),
        ),
        SectionHeading(
          '$recordedCount entries',
          action: AppText(
            dateView == 'All dates' || month == null
                ? dateView
                : DateFormat.yMMM(languageOf(context)).format(month),
            style: const TextStyle(color: muted),
          ),
        ),
        if (projectedCount > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: AppText(
              '$projectedCount scheduled previews',
              style: const TextStyle(color: muted, fontSize: 12),
            ),
          ),
        if (entries.isEmpty)
          const EmptyState(
            icon: Icons.receipt_long_outlined,
            title: 'No transactions found',
            body: 'Add an entry or change your filters.',
          ),
        ...entries.map(
          (e) => EntryTile(
            key: ValueKey('entry-${e.id}'),
            entry: e,
            store: widget.store,
          ),
        ),
      ],
    );
  }
}

class EntryTile extends StatelessWidget {
  final Entry entry;
  final FinanceStore store;
  const EntryTile({super.key, required this.entry, required this.store});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Material(
      color: const Color(0xFF141D29),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => editEntry(context, store, entry: entry),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CategoryBadge(entry.category),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.merchant,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 5),
                    AppText(
                      '${entry.category} · ${DateFormat.yMMMd(languageOf(context)).format(entry.date)}',
                      style: const TextStyle(fontSize: 11, color: muted),
                    ),
                    if (!entry.recurrenceDisabled &&
                        activeRecurringForEntry(store, entry) != null) ...[
                      const SizedBox(height: 4),
                      AppText(
                        recurringScheduleLabel(
                          activeRecurringForEntry(store, entry)!,
                        ),
                        style: const TextStyle(fontSize: 11, color: blue),
                      ),
                    ],
                    if (entry.isProjected) ...[
                      const SizedBox(height: 4),
                      const AppText(
                        'Scheduled preview',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFFE1BD7D),
                        ),
                      ),
                    ] else if (DateUtils.dateOnly(
                      entry.date,
                    ).isAfter(DateUtils.dateOnly(DateTime.now()))) ...[
                      const SizedBox(height: 4),
                      const AppText(
                        'Upcoming',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFFE1BD7D),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: AppText(
                  '${entry.income ? '+' : '−'}${store.currency} ${money(entry.cents)}',
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: entry.income ? const Color(0xFF73CBB0) : ink,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
