import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../core/finance_store.dart';
import '../core/invoice.dart';
import '../core/recommendation.dart';
import '../l10n/app_language.dart';
import '../services/invoice_service.dart';
import '../services/recommendation_service.dart';
import '../widgets/design.dart';
import 'recommendation_results.dart';

class RecommendationReviewPage extends StatefulWidget {
  final FinanceStore store;
  final RecommendationReview review;
  final Uint8List? photo;
  final String? expenseId;
  final RecommendationService? service;
  const RecommendationReviewPage({
    super.key,
    required this.store,
    required this.review,
    this.photo,
    this.expenseId,
    this.service,
  });
  @override
  State<RecommendationReviewPage> createState() =>
      _RecommendationReviewPageState();
}

class _RecommendationReviewPageState extends State<RecommendationReviewPage> {
  late final List<_ProductFields> products;
  late final RecommendationService service;
  bool busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    products = widget.review.products.map(_ProductFields.new).toList();
    service =
        widget.service ??
        RecommendationService(
          baseUrl: configuredInvoiceApiUrl(widget.store.prefs),
        );
  }

  @override
  void dispose() {
    service.close();
    for (final product in products) {
      product.dispose();
    }
    super.dispose();
  }

  Future<void> search() async {
    if (busy) return;
    final selected = products.where((p) => p.selected).toList();
    if (selected.isEmpty) {
      setState(() => error = 'Select at least one product to compare.');
      return;
    }
    for (final product in selected) {
      final problem = product.validate();
      if (problem != null) {
        setState(() => error = problem);
        return;
      }
    }
    if (widget.review.invoice != null &&
        widget.review.invoice!.currency != 'SAR') {
      setState(
        () =>
            error =
                const RecommendationApiException(
                  'unsupported_currency',
                ).message,
      );
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await service.search(
        mode: widget.review.mode,
        products:
            selected
                .map(
                  (p) => p.snapshot(
                    productMode: widget.review.mode == 'product',
                    shoppingListMode: widget.review.mode == 'shopping-list',
                  ),
                )
                .toList(),
        invoice: widget.review.invoice,
      );
      String? historyError;
      try {
        await RecommendationHistory(
          widget.store.prefs,
        ).save(result, expenseId: widget.expenseId);
      } catch (_) {
        historyError = 'Results are available, but history could not be saved.';
      }
      if (!mounted) return;
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder:
              (_) => RecommendationResultsPage(
                result: result,
                notice: historyError,
              ),
        ),
      );
    } on RecommendationApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted) setState(() => error = 'Price search failed. Try again.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget field(
    _ProductFields product,
    String key,
    String label, {
    bool numeric = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      key: ValueKey('${product.original.id}-$key'),
      controller: product.fields[key],
      enabled: !busy,
      textDirection: numeric ? TextDirection.ltr : null,
      keyboardType:
          numeric
              ? const TextInputType.numberWithOptions(decimal: true)
              : TextInputType.text,
      decoration: InputDecoration(labelText: tr(context, label)),
    ),
  );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: Scaffold(
      appBar: AppBar(title: const AppText('Review products')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const PageHeading(
            'Smart Price Recommendation',
            'Review before searching',
          ),
          const AppText(
            'Correct names, brand, model, size and pack count. Only selected products will be searched.',
          ),
          const SizedBox(height: 12),
          const AppText(
            'Unknown details should stay blank. Original prices are in SAR; listing currencies may differ.',
            style: TextStyle(color: muted),
          ),
          if (products.where((product) => product.selected).length > 1) ...[
            const SizedBox(height: 12),
            const AppText(
              'Your selected items use one combined search. Some items may have no matching offers.',
            ),
          ],
          if (widget.review.mode == 'shopping-list') ...[
            const SizedBox(height: 12),
            const AppText(
              'These are items you want to buy. Prices are optional. Generic items show shopping options, not verified equivalents.',
            ),
          ],
          if (widget.review.mode == 'invoice') ...[
            const SizedBox(height: 12),
            const AppText(
              'Comparing prices does not save an expense. Return to Review invoice and use Add Expense.',
            ),
          ],
          if (widget.review.warnings.isNotEmpty) ...[
            const SizedBox(height: 12),
            const AppText(
              'Check the extracted items and quantities against your original list or image.',
            ),
          ],
          if (widget.photo != null) ...[
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Image.memory(
                widget.photo!,
                height: 200,
                fit: BoxFit.contain,
                errorBuilder:
                    (_, __, ___) => const AppText('Photo preview unavailable'),
              ),
            ),
          ],
          const SizedBox(height: 20),
          if (products.isEmpty)
            const EmptyState(
              icon: Icons.search_off,
              title: 'No products to compare',
              body: 'Add identifiable items in the invoice review first.',
            ),
          for (final product in products)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Surface(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const AppText('Compare this product'),
                      value: product.selected,
                      onChanged:
                          busy
                              ? null
                              : (value) =>
                                  setState(() => product.selected = value!),
                    ),
                    field(product, 'name', 'Product name'),
                    if (recommendationNumber(
                          product.original.data['confidence'],
                        )
                        case final double confidence)
                      AppText(
                        'Model confidence: ${confidence <= 1 ? (confidence * 100).round() : '?'}% (self-reported)',
                        style: const TextStyle(color: muted, fontSize: 12),
                      ),
                    const SizedBox(height: 12),
                    field(
                      product,
                      'unit_price',
                      widget.review.mode == 'product'
                          ? 'Current price (SAR, optional)'
                          : widget.review.mode == 'shopping-list'
                          ? 'Current price (SAR, optional)'
                          : 'Original unit price (SAR)',
                      numeric: true,
                    ),
                    if (widget.review.mode != 'product')
                      field(product, 'quantity', 'Quantity', numeric: true),
                    if (widget.review.mode == 'invoice') ...[
                      field(
                        product,
                        'total_price',
                        'Original line total (SAR)',
                        numeric: true,
                      ),
                    ],
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: const AppText('Identity, size and packaging'),
                      children: [
                        field(product, 'brand', 'Brand'),
                        field(product, 'model', 'Model / generation'),
                        field(product, 'variant', 'Variant / capacity / color'),
                        field(
                          product,
                          'size_value',
                          'Size / weight / volume',
                          numeric: true,
                        ),
                        DropdownButtonFormField<String>(
                          value: product.sizeUnit,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: tr(context, 'Size unit'),
                          ),
                          items:
                              ['', 'ml', 'l', 'g', 'kg', 'unit']
                                  .map(
                                    (v) => DropdownMenuItem(
                                      value: v,
                                      child: AppText(v.isEmpty ? 'Unknown' : v),
                                    ),
                                  )
                                  .toList(),
                          onChanged:
                              busy
                                  ? null
                                  : (v) =>
                                      setState(() => product.sizeUnit = v!),
                        ),
                        const SizedBox(height: 12),
                        field(
                          product,
                          'pack_size',
                          'Units per pack',
                          numeric: true,
                        ),
                        DropdownButtonFormField<String>(
                          value: product.condition,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: tr(context, 'Condition'),
                          ),
                          items:
                              ['', 'new', 'used', 'refurbished']
                                  .map(
                                    (v) => DropdownMenuItem(
                                      value: v,
                                      child: AppText(v.isEmpty ? 'Unknown' : v),
                                    ),
                                  )
                                  .toList(),
                          onChanged:
                              busy
                                  ? null
                                  : (v) =>
                                      setState(() => product.condition = v!),
                        ),
                        const SizedBox(height: 12),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          if (error != null) ...[
            Surface(
              child: AppText(
                error!,
                style: const TextStyle(color: Color(0xFFFFB4AB)),
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (busy) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: 12),
            const AppText('Searching matching offers…'),
            const SizedBox(height: 16),
          ],
          FilledButton.icon(
            key: const Key('confirm-price-search'),
            onPressed: busy || products.isEmpty ? null : search,
            icon: const Icon(Icons.manage_search),
            label: const AppText('Confirm and compare prices'),
          ),
          const SizedBox(height: 12),
          const AppText(
            'Search starts only when you confirm. Product details are sent through your server to shopping search.',
            style: TextStyle(color: muted, fontSize: 12),
          ),
        ],
      ),
    ),
  );
}

class _ProductFields {
  final ReviewProduct original;
  late final Map<String, TextEditingController> fields;
  String sizeUnit, condition;
  bool selected = true;
  _ProductFields(this.original)
    : sizeUnit =
          [
                '',
                'ml',
                'l',
                'g',
                'kg',
                'unit',
              ].contains(original.data['size_unit'])
              ? original.data['size_unit'] as String
              : '',
      condition =
          [
                '',
                'new',
                'used',
                'refurbished',
              ].contains(original.data['condition'])
              ? original.data['condition'] as String
              : '' {
    fields = {
      for (final key in [
        'name',
        'brand',
        'model',
        'variant',
        'size_value',
        'pack_size',
        'quantity',
        'unit_price',
        'total_price',
      ])
        key: TextEditingController(text: original.data[key]?.toString() ?? ''),
    };
  }
  String? validate() {
    if (fields['name']!.text.trim().isEmpty) return 'Enter a product name.';
    for (final key in [
      'size_value',
      'pack_size',
      'quantity',
      'unit_price',
      'total_price',
    ]) {
      final text = fields[key]!.text.trim();
      if (text.isEmpty) continue;
      final number = parseInvoiceNumber(text);
      if (number == null || number <= 0) {
        return 'Enter positive quantities, sizes and prices, or leave unknown values blank.';
      }
      if (key == 'pack_size' && number != number.roundToDouble()) {
        return 'Units per pack must be a whole number.';
      }
      if (['unit_price', 'total_price'].contains(key) &&
          parseMoney(text) == null) {
        return 'Use a positive amount with up to 2 decimals';
      }
    }
    if ((fields['size_value']!.text.trim().isEmpty) != sizeUnit.isEmpty) {
      return 'Enter both a size and its unit, or leave both blank.';
    }
    return null;
  }

  ReviewProduct snapshot({
    required bool productMode,
    bool shoppingListMode = false,
  }) {
    final json = original.toJson();
    for (final key in fields.keys) {
      final text = fields[key]!.text.trim();
      json[key] =
          text.isEmpty
              ? null
              : ['name', 'brand', 'model', 'variant'].contains(key)
              ? text
              : parseInvoiceNumber(text);
    }
    json['size_unit'] = sizeUnit.isEmpty ? null : sizeUnit;
    json['condition'] = condition.isEmpty ? null : condition;
    json['search_query'] = null;
    if (productMode) {
      json['quantity'] = 1;
      json['total_price'] = json['unit_price'];
    } else if (shoppingListMode) {
      final unit = recommendationNumber(json['unit_price']);
      final quantity = recommendationNumber(json['quantity']);
      json['total_price'] =
          unit == null || quantity == null
              ? null
              : double.parse((unit * quantity).toStringAsFixed(2));
    }
    return ReviewProduct(json);
  }

  void dispose() {
    for (final c in fields.values) {
      c.dispose();
    }
  }
}
