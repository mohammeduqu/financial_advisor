/// Invoice metadata attached to the existing expense entry.
const invoiceCategories = [
  'Food',
  'Transportation',
  'Housing',
  'Utilities',
  'Shopping',
  'Healthcare',
  'Entertainment',
  'Education',
  'Subscriptions',
  'Travel',
  'Other',
];

String normalizeInvoiceDigits(String value) {
  var result = value.trim().replaceAll('٫', '.').replaceAll('٬', ',');
  const ar = '٠١٢٣٤٥٦٧٨٩', fa = '۰۱۲۳۴۵۶۷۸۹';
  for (var i = 0; i < 10; i++) {
    result = result.replaceAll(ar[i], '$i').replaceAll(fa[i], '$i');
  }
  return result;
}

double? parseInvoiceNumber(String text) {
  final value = normalizeInvoiceDigits(text);
  if (!RegExp(r'^(?:\d+|\d{1,3}(?:,\d{3})+)(?:\.\d{1,6})?$').hasMatch(value)) {
    return null;
  }
  final result = double.tryParse(value.replaceAll(',', ''));
  return result != null && result.isFinite && result >= 0 && result < 1000000000
      ? result
      : null;
}

double? _number(dynamic value) {
  if (value == null) return null;
  if (value is num) {
    final result = value.toDouble();
    if (!result.isFinite || result < 0 || result >= 1000000000) return null;
    return result;
  }
  return value is String ? parseInvoiceNumber(value) : null;
}

String? _text(dynamic value) =>
    value is String && value.trim().isNotEmpty ? value.trim() : null;
String _category(dynamic value) =>
    invoiceCategories
        .where((c) => c.toLowerCase() == value?.toString().toLowerCase())
        .firstOrNull ??
    'Other';

DateTime? _date(dynamic value) {
  if (value is! String) return null;
  final text = normalizeInvoiceDigits(value);
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text)) return null;
  final date = DateTime.tryParse(text);
  return date != null && date.toIso8601String().startsWith(text) ? date : null;
}

class InvoiceItemModel {
  final String? name;
  final double? quantity, unitPrice, totalPrice;
  final String category;
  final String? brand, model, variant, sizeUnit, condition, searchQuery;
  final double? sizeValue, packSize, confidence;
  const InvoiceItemModel({
    this.name,
    this.quantity,
    this.unitPrice,
    this.totalPrice,
    this.category = 'Other',
    this.brand,
    this.model,
    this.variant,
    this.sizeUnit,
    this.condition,
    this.searchQuery,
    this.sizeValue,
    this.packSize,
    this.confidence,
  });
  factory InvoiceItemModel.fromJson(Map<String, dynamic> json) =>
      InvoiceItemModel(
        name: _text(json['name']),
        quantity: _number(json['quantity']),
        unitPrice: _number(json['unit_price']),
        totalPrice: _number(json['total_price']),
        category: _category(json['category']),
        brand: _text(json['brand']),
        model: _text(json['model']),
        variant: _text(json['variant']),
        sizeUnit: _text(json['size_unit']),
        condition: _text(json['condition']),
        searchQuery: _text(json['search_query']),
        sizeValue: _number(json['size_value']),
        packSize: _number(json['pack_size']),
        confidence: _number(json['confidence']),
      );
  Map<String, dynamic> toJson() => {
    'name': name,
    'quantity': quantity,
    'unit_price': unitPrice,
    'total_price': totalPrice,
    'category': category,
    'brand': brand,
    'model': model,
    'variant': variant,
    'size_unit': sizeUnit,
    'condition': condition,
    'search_query': searchQuery,
    'size_value': sizeValue,
    'pack_size': packSize,
    'confidence': confidence,
  };
}

class InvoiceModel {
  final String? merchantName, invoiceNumber, currency;
  final DateTime? date;
  final double? subtotal, tax, discount, total;
  final String category;
  final List<InvoiceItemModel> items;
  const InvoiceModel({
    this.merchantName,
    this.invoiceNumber,
    this.date,
    this.currency,
    this.subtotal,
    this.tax,
    this.discount,
    this.total,
    this.category = 'Other',
    this.items = const [],
  });
  int? get totalCents {
    final value = total;
    if (value == null || !value.isFinite || value <= 0 || value >= 1000000000) {
      return null;
    }
    final scaled = value * 100;
    final cents = scaled.round();
    return (scaled - cents).abs() < 0.00001 ? cents : null;
  }

  factory InvoiceModel.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    if (rawItems != null && rawItems is! List) {
      throw const FormatException('Invalid invoice items');
    }
    if (rawItems is List &&
        (rawItems.length > 200 ||
            rawItems.any((item) => item is! Map<String, dynamic>))) {
      throw const FormatException('Invalid invoice items');
    }
    return InvoiceModel(
      merchantName: _text(json['merchant_name']),
      invoiceNumber: _text(json['invoice_number']),
      date: _date(json['date']),
      currency: _text(json['currency'])?.toUpperCase(),
      subtotal: _number(json['subtotal']),
      tax: _number(json['tax']),
      discount: _number(json['discount']),
      total: _number(json['total']),
      category: _category(json['category']),
      items: List.unmodifiable(
        (rawItems as List? ?? const []).map(
          (item) => InvoiceItemModel.fromJson(item as Map<String, dynamic>),
        ),
      ),
    );
  }
  Map<String, dynamic> toJson() => {
    'merchant_name': merchantName,
    'invoice_number': invoiceNumber,
    'date':
        date == null
            ? null
            : '${date!.year.toString().padLeft(4, '0')}-${date!.month.toString().padLeft(2, '0')}-${date!.day.toString().padLeft(2, '0')}',
    'currency': currency,
    'subtotal': subtotal,
    'tax': tax,
    'discount': discount,
    'total': total,
    'category': category,
    'items': items.map((i) => i.toJson()).toList(),
  };
}
