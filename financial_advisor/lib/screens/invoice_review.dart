import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import '../core/finance_store.dart';
import '../core/invoice.dart';
import '../core/recommendation.dart';
import 'recommendation_review.dart';
import '../l10n/app_language.dart';
import '../widgets/design.dart';

enum InvoiceReviewAction { saved, retake, analyzeAgain }

class InvoiceReviewResult {
  final InvoiceReviewAction action;
  final Entry? entry;

  const InvoiceReviewResult(this.action, {this.entry});
}

class InvoiceReviewScreen extends StatefulWidget {
  final FinanceStore store;
  final InvoiceModel invoice;
  final String? receipt;
  final List<String> warnings;
  final Entry? existingEntry;
  const InvoiceReviewScreen({
    super.key,
    required this.store,
    required this.invoice,
    this.receipt,
    this.warnings = const [],
    this.existingEntry,
  });
  @override
  State<InvoiceReviewScreen> createState() => _InvoiceReviewScreenState();
}

class _InvoiceReviewScreenState extends State<InvoiceReviewScreen> {
  final form = GlobalKey<FormState>();
  late final String id;
  late final TextEditingController merchant, number, date;
  late final TextEditingController subtotal, tax, discount, total;
  final List<_ItemFields> items = [];
  late String category;
  String? error;
  bool busy = false;
  bool amountsReviewed = false;

  String amountText(double? value) => value?.toString() ?? '';

  @override
  void initState() {
    super.initState();
    final value = widget.invoice;
    id = widget.existingEntry?.id ?? newId();
    merchant = TextEditingController(text: value.merchantName ?? '');
    number = TextEditingController(text: value.invoiceNumber ?? '');
    date = TextEditingController(
      text: DateFormat(
        'yyyy-MM-dd',
        'en',
      ).format(widget.existingEntry?.date ?? DateTime.now()),
    );
    subtotal = TextEditingController(text: amountText(value.subtotal));
    tax = TextEditingController(text: amountText(value.tax));
    discount = TextEditingController(text: amountText(value.discount));
    total = TextEditingController(text: amountText(value.total));
    category = categories.contains(value.category) ? value.category : 'Other';
    items.addAll(value.items.map(_ItemFields.new));
  }

  @override
  void dispose() {
    for (final c in [merchant, number, date, subtotal, tax, discount, total]) {
      c.dispose();
    }
    for (final item in items) {
      item.dispose();
    }
    super.dispose();
  }

  DateTime? parsedDate() {
    try {
      var text = date.text.trim();
      const ar = '٠١٢٣٤٥٦٧٨٩';
      const fa = '۰۱۲۳۴۵۶۷۸۹';
      for (var i = 0; i < 10; i++) {
        text = text.replaceAll(ar[i], '$i').replaceAll(fa[i], '$i');
      }
      final parsed = DateFormat('yyyy-MM-dd', 'en').parseStrict(text);
      final now = DateTime.now();
      return parsed.isBefore(DateTime(2000)) ||
              parsed.isAfter(DateTime(now.year, now.month, now.day))
          ? null
          : parsed;
    } catch (_) {
      return null;
    }
  }

  double? numberValue(TextEditingController controller) =>
      controller.text.trim().isEmpty
          ? null
          : parseInvoiceNumber(controller.text);

  InvoiceModel snapshot() => InvoiceModel(
    merchantName: merchant.text.trim(),
    invoiceNumber: number.text.trim().isEmpty ? null : number.text.trim(),
    date: parsedDate(),
    currency: widget.store.currency.trim().toUpperCase(),
    subtotal: numberValue(subtotal),
    tax: numberValue(tax),
    discount: numberValue(discount),
    total: numberValue(total),
    category: category,
    items:
        items
            .map(
              (i) => InvoiceItemModel(
                name: i.name.text.trim(),
                quantity: numberValue(i.quantity),
                unitPrice: numberValue(i.unitPrice),
                totalPrice: numberValue(i.totalPrice),
                category: i.category,
                brand: i.original.brand,
                model: i.original.model,
                variant: i.original.variant,
                sizeValue: i.original.sizeValue,
                sizeUnit: i.original.sizeUnit,
                packSize: i.original.packSize,
                condition: i.original.condition,
                confidence: i.original.confidence,
                searchQuery: i.original.searchQuery,
              ),
            )
            .toList(),
  );

  bool get totalsDiffer {
    final t = numberValue(total), s = numberValue(subtotal);
    final vat = numberValue(tax), reduction = numberValue(discount);
    if (t != null &&
        s != null &&
        vat != null &&
        reduction != null &&
        (s + vat - reduction - t).abs() > 0.02) {
      return true;
    }
    if (items.isNotEmpty &&
        items.every((i) => numberValue(i.totalPrice) != null)) {
      final sum = items.fold<double>(
        0,
        (v, i) => v + numberValue(i.totalPrice)!,
      );
      final candidates = [
        if (s != null) s,
        if (t != null) t,
        if (t != null && vat != null && reduction != null) t - vat + reduction,
      ];
      if (candidates.isNotEmpty &&
          candidates.every((v) => (sum - v).abs() > 0.02)) {
        return true;
      }
    }
    return false;
  }

  String? validateAllFields() {
    if (merchant.text.trim().isEmpty) return 'Enter a name';
    if (parsedDate() == null) {
      return 'Enter a valid invoice date, no later than today';
    }
    if (parseMoney(total.text) == null) {
      return 'Use a positive amount with up to 2 decimals';
    }
    final amounts = [
      subtotal,
      tax,
      discount,
      for (final item in items) ...[item.unitPrice, item.totalPrice],
    ];
    if (amounts.any(
      (c) => c.text.trim().isNotEmpty && parseInvoiceNumber(c.text) == null,
    )) {
      return 'Enter a valid non-negative number';
    }
    for (final item in items) {
      if (item.name.text.trim().isEmpty) return 'Enter a name';
      if (item.quantity.text.trim().isNotEmpty &&
          (parseInvoiceNumber(item.quantity.text) ?? 0) <= 0) {
        return 'Enter a valid non-negative number';
      }
    }
    return null;
  }

  Future<void> comparePrices() async {
    if (busy) return;
    final invoice = snapshot();
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder:
            (_) => RecommendationReviewPage(
              store: widget.store,
              review: RecommendationReview.invoice(invoice),
              photo:
                  widget.receipt == null ? null : base64Decode(widget.receipt!),
              expenseId: widget.existingEntry?.id,
            ),
      ),
    );
  }

  Future<void> save() async {
    if (busy) return;
    final validationError = validateAllFields();
    final visibleFieldsValid = form.currentState!.validate();
    if (validationError != null || !visibleFieldsValid) {
      setState(
        () =>
            error =
                validationError ??
                'Could not save this invoice. Check the fields and try again.',
      );
      return;
    }
    if (totalsDiffer && !amountsReviewed) {
      setState(
        () =>
            error =
                'Review the amounts and confirm the invoice total before saving.',
      );
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final value = snapshot();
      final candidate = Entry(
        id: id,
        merchant: value.merchantName!,
        cents: value.totalCents!,
        date: value.date!,
        category: value.category,
        receipt: widget.receipt,
      );
      if (widget.store.isDuplicate(candidate)) {
        final accepted = await confirm(
          context,
          'Possible duplicate',
          'An entry with this merchant, date and amount, or this receipt image, already exists. Save another?',
          action: 'Save another',
        );
        if (!accepted || !mounted) return;
      }
      await widget.store.saveInvoice(
        value,
        id: id,
        receipt: widget.receipt,
        note: widget.existingEntry?.note ?? '',
      );
      if (!mounted) return;
      if (widget.store.error != null) {
        setState(() => error = widget.store.error);
        return;
      }
      final savedEntry = widget.store.entries.firstWhere((e) => e.id == id);
      Navigator.pop(
        context,
        InvoiceReviewResult(InvoiceReviewAction.saved, entry: savedEntry),
      );
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              error =
                  'Could not save this invoice. Check the fields and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget field(
    String label,
    TextEditingController controller, {
    String? Function(String?)? validator,
    bool numeric = false,
    bool requiredAmount = false,
    bool positive = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextFormField(
      key: ValueKey(controller),
      controller: controller,
      enabled: !busy,
      textDirection: numeric ? TextDirection.ltr : null,
      keyboardType:
          numeric
              ? const TextInputType.numberWithOptions(decimal: true)
              : TextInputType.text,
      decoration: InputDecoration(labelText: tr(context, label)),
      onChanged:
          (_) => setState(() {
            amountsReviewed = false;
            error = null;
          }),
      validator:
          validator ??
          (numeric
              ? (text) {
                if ((text ?? '').trim().isEmpty) {
                  return requiredAmount ? tr(context, 'Enter an amount') : null;
                }
                final value = parseInvoiceNumber(text!);
                if (value == null ||
                    !value.isFinite ||
                    value < 0 ||
                    value > 999999999 ||
                    (positive && value <= 0) ||
                    (requiredAmount && parseMoney(text) == null)) {
                  return tr(
                    context,
                    requiredAmount
                        ? 'Use a positive amount with up to 2 decimals'
                        : 'Enter a valid non-negative number',
                  );
                }
                return null;
              }
              : null),
    ),
  );

  Widget categoryField(String value, ValueChanged<String> changed) =>
      DropdownButtonFormField<String>(
        value: value,
        isExpanded: true,
        decoration: InputDecoration(labelText: tr(context, 'Category')),
        items:
            categories
                .map((c) => DropdownMenuItem(value: c, child: AppText(c)))
                .toList(),
        onChanged: busy ? null : (v) => changed(v!),
      );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: Scaffold(
      backgroundColor: canvas,
      appBar: AppBar(
        title: const AppText('Review invoice'),
        actions: [
          if (widget.existingEntry != null)
            IconButton(
              tooltip: tr(context, 'Delete transaction'),
              icon: const Icon(Icons.delete_outline),
              onPressed:
                  busy
                      ? null
                      : () async {
                        if (!await confirm(
                          context,
                          'Delete transaction?',
                          'This removes it from your recorded totals.',
                          action: 'Delete',
                        )) {
                          return;
                        }
                        if (!mounted) return;
                        setState(() => busy = true);
                        await widget.store.deleteEntry(id);
                        if (!context.mounted) return;
                        Navigator.pop(context);
                      },
            ),
        ],
      ),
      body: Form(
        key: form,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const AppText(
              'Check every field against the photo. Missing information stays blank.',
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              key: const Key('compare-invoice-prices'),
              onPressed: busy || items.isEmpty ? null : comparePrices,
              icon: const Icon(Icons.manage_search),
              label: const AppText('Compare prices'),
            ),
            const SizedBox(height: 16),
            if (widget.receipt != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.memory(
                  base64Decode(widget.receipt!),
                  height: 220,
                  fit: BoxFit.contain,
                  errorBuilder:
                      (_, __, ___) =>
                          const AppText('Receipt preview unavailable'),
                ),
              ),
              const SizedBox(height: 20),
            ],
            if (widget.warnings.isNotEmpty) ...[
              const Surface(
                child: AppText(
                  'Some fields may be missing or amounts may not match. Check the whole invoice before saving.',
                ),
              ),
              const SizedBox(height: 20),
            ],
            field(
              'Merchant Name',
              merchant,
              validator:
                  (v) =>
                      v == null || v.trim().isEmpty
                          ? tr(context, 'Enter a name')
                          : null,
            ),
            field('Invoice Number', number),
            field(
              'Date (YYYY-MM-DD)',
              date,
              validator:
                  (_) =>
                      parsedDate() == null
                          ? tr(
                            context,
                            'Enter a valid invoice date, no later than today',
                          )
                          : null,
            ),
            field('Subtotal', subtotal, numeric: true),
            field('Tax', tax, numeric: true),
            field('Discount', discount, numeric: true),
            field(
              'Total',
              total,
              numeric: true,
              requiredAmount: true,
              positive: true,
            ),
            categoryField(category, (v) => setState(() => category = v)),
            const SizedBox(height: 24),
            AppText(
              'Invoice items',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            if (items.isEmpty) ...[
              const AppText('No invoice items were detected.'),
              const AppText(
                'You can add items manually or save the reviewed invoice total.',
              ),
              const SizedBox(height: 12),
            ],
            for (var index = 0; index < items.length; index++)
              Padding(
                key: ValueKey(items[index]),
                padding: const EdgeInsets.only(bottom: 16),
                child: Surface(
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: AppText(
                              'Item {0}'.replaceFirst('{0}', '${index + 1}'),
                            ),
                          ),
                          IconButton(
                            tooltip: tr(context, 'Remove item'),
                            onPressed:
                                busy
                                    ? null
                                    : () {
                                      final removed = items[index];
                                      setState(() {
                                        items.removeAt(index);
                                        amountsReviewed = false;
                                      });
                                      WidgetsBinding.instance
                                          .addPostFrameCallback(
                                            (_) => removed.dispose(),
                                          );
                                    },
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ),
                      field(
                        'Item name',
                        items[index].name,
                        validator:
                            (v) =>
                                v == null || v.trim().isEmpty
                                    ? tr(context, 'Enter a name')
                                    : null,
                      ),
                      field(
                        'Quantity',
                        items[index].quantity,
                        numeric: true,
                        positive: true,
                      ),
                      field(
                        'Unit price',
                        items[index].unitPrice,
                        numeric: true,
                      ),
                      field(
                        'Total price',
                        items[index].totalPrice,
                        numeric: true,
                      ),
                      categoryField(
                        items[index].category,
                        (v) => setState(() => items[index].category = v),
                      ),
                    ],
                  ),
                ),
              ),
            OutlinedButton.icon(
              onPressed:
                  busy
                      ? null
                      : () => setState(
                        () => items.add(_ItemFields(const InvoiceItemModel())),
                      ),
              icon: const Icon(Icons.add),
              label: const AppText('Add item'),
            ),
            const SizedBox(height: 18),
            if (totalsDiffer) ...[
              const AppText(
                'Amounts do not reconcile. Check VAT, discounts, and missing items.',
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: amountsReviewed,
                onChanged:
                    busy ? null : (v) => setState(() => amountsReviewed = v!),
                title: const AppText(
                  'I checked the amounts. Save the displayed invoice total.',
                ),
              ),
            ],
            const Surface(
              child: AppText(
                'Saved as one expense with all items attached. Only the invoice total affects your balance and budget; tax is not added twice.',
              ),
            ),
            const SizedBox(height: 20),
            if (error != null) ...[
              AppText(error!, style: const TextStyle(color: Color(0xFFFFB4AB))),
              const SizedBox(height: 14),
            ],
            FilledButton.icon(
              key: const Key('add-invoice-expense'),
              onPressed: busy ? null : save,
              icon: const Icon(Icons.check),
              label: AppText(
                busy
                    ? 'Saving…'
                    : widget.existingEntry == null
                    ? 'Add Expense'
                    : 'Save changes',
              ),
            ),
            if (widget.existingEntry == null) ...[
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed:
                    busy
                        ? null
                        : () => Navigator.pop(
                          context,
                          const InvoiceReviewResult(
                            InvoiceReviewAction.analyzeAgain,
                          ),
                        ),
                child: const AppText('Analyze Again'),
              ),
              TextButton(
                onPressed:
                    busy
                        ? null
                        : () => Navigator.pop(
                          context,
                          const InvoiceReviewResult(InvoiceReviewAction.retake),
                        ),
                child: const AppText('Retake Photo'),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

class _ItemFields {
  final InvoiceItemModel original;
  final TextEditingController name, quantity, unitPrice, totalPrice;
  String category;
  _ItemFields(InvoiceItemModel item)
    : original = item,
      name = TextEditingController(text: item.name ?? ''),
      quantity = TextEditingController(text: item.quantity?.toString() ?? ''),
      unitPrice = TextEditingController(text: item.unitPrice?.toString() ?? ''),
      totalPrice = TextEditingController(
        text: item.totalPrice?.toString() ?? '',
      ),
      category = categories.contains(item.category) ? item.category : 'Other';
  void dispose() {
    for (final c in [name, quantity, unitPrice, totalPrice]) {
      c.dispose();
    }
  }
}
