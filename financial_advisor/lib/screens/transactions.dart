import '../l10n/app_language.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/finance_store.dart';
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
  if (entry?.invoice != null) {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) => InvoiceReviewScreen(
              store: store,
              invoice: entry!.invoice!,
              receipt: entry.receipt,
              existingEntry: entry,
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
          ),
    ),
  );
}

class EntryEditor extends StatefulWidget {
  final FinanceStore store;
  final Entry? entry;
  final bool receiptReview;
  final bool initialIncome;
  const EntryEditor({
    super.key,
    required this.store,
    this.entry,
    this.receiptReview = false,
    this.initialIncome = false,
  });
  @override
  State<EntryEditor> createState() => _EntryEditorState();
}

class _EntryEditorState extends State<EntryEditor> {
  final form = GlobalKey<FormState>();
  late TextEditingController merchant, amount, note;
  late DateTime date;
  late String category;
  late bool income;
  bool busy = false;
  bool retryPending = false;
  RepeatFrequency frequency = RepeatFrequency.once;
  late final String id;
  bool get canSetRepeat => widget.entry == null && !widget.receiptReview;
  bool get editingEnabled => !busy && !retryPending;
  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    id = e?.id ?? newId();
    merchant = TextEditingController(text: e?.merchant ?? '');
    amount = TextEditingController(
      text: e == null || e.cents == 0 ? '' : (e.cents / 100).toStringAsFixed(2),
    );
    note = TextEditingController(text: e?.note ?? '');
    date = e?.date ?? DateTime.now();
    category = e?.category ?? 'Other';
    income = e?.income ?? widget.initialIncome;
  }

  @override
  void dispose() {
    merchant.dispose();
    amount.dispose();
    note.dispose();
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
    );
    if (widget.store.isDuplicate(e)) {
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
      if (canSetRepeat) {
        await widget.store.saveScheduledEntry(e, frequency);
      } else {
        await widget.store.saveEntry(e);
      }
    } on StateError {
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
    Navigator.pop(context);
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
            : widget.entry == null
            ? 'New transaction'
            : 'Edit transaction',
      ),
      actions: [
        if (widget.entry != null && !widget.receiptReview)
          IconButton(
            tooltip: tr(context, 'Delete transaction'),
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              if (await confirm(
                context,
                'Delete transaction?',
                'This removes it from your recorded totals.',
                action: 'Delete',
              )) {
                await widget.store.deleteEntry(id);
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
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
          if (canSetRepeat) ...[
            DropdownButtonFormField<RepeatFrequency>(
              key: const Key('entry-repeat'),
              value: frequency,
              decoration: InputDecoration(
                labelText: tr(context, 'Repeat'),
                prefixIcon: const Icon(Icons.repeat),
              ),
              items:
                  RepeatFrequency.values
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
                        if (frequency == RepeatFrequency.once &&
                            date.isAfter(DateTime.now())) {
                          date = DateTime.now();
                        }
                      }),
            ),
            if (frequency != RepeatFrequency.once) ...[
              const SizedBox(height: 10),
              AppText(
                repeatScheduleExplanation(frequency),
                style: const TextStyle(color: muted, fontSize: 12, height: 1.5),
              ),
            ],
            const SizedBox(height: 16),
          ],
          if (widget.entry?.recurringId != null) ...[
            const AppText(
              'This is one recorded entry. Changes here do not change its repeat schedule.',
              style: TextStyle(color: muted, fontSize: 12, height: 1.5),
            ),
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
                        lastDate:
                            frequency == RepeatFrequency.once
                                ? DateTime.now()
                                : DateTime(DateTime.now().year + 20, 12, 31),
                      );
                      if (picked != null) setState(() => date = picked);
                    },
          ),
          const SizedBox(height: 16),
          if (!income) ...[
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
  final DateTime month;
  final String? highlightedEntryId;
  const TransactionsPage({
    super.key,
    required this.store,
    required this.month,
    this.highlightedEntryId,
  });
  @override
  State<TransactionsPage> createState() => _TransactionsPageState();
}

class _TransactionsPageState extends State<TransactionsPage> {
  String query = '', filter = 'All', category = 'All categories';
  @override
  Widget build(BuildContext context) {
    final entries =
        widget.store
            .forMonth(widget.month)
            .where(
              (e) =>
                  (filter == 'All' || e.income == (filter == 'Income')) &&
                  (category == 'All categories' || category == e.category) &&
                  ('${e.merchant} ${e.note}').toLowerCase().contains(
                    query.toLowerCase(),
                  ),
            )
            .toList();
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
          '${entries.length} entries',
          action: AppText(
            DateFormat.MMM(languageOf(context)).format(widget.month),
            style: const TextStyle(color: muted),
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
                      '${entry.category} · ${DateFormat.MMMd(languageOf(context)).format(entry.date)}',
                      style: const TextStyle(fontSize: 11, color: muted),
                    ),
                    if (entry.recurringId != null) ...[
                      const SizedBox(height: 4),
                      const AppText(
                        'Recurring',
                        style: TextStyle(fontSize: 11, color: blue),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              AppText(
                '${entry.income ? '+' : '−'}${money(entry.cents)}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: entry.income ? const Color(0xFF73CBB0) : ink,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
