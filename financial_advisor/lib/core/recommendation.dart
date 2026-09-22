import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'invoice.dart';

double? recommendationNumber(dynamic value) {
  if (value is! num || !value.isFinite || value < 0) return null;
  return value.toDouble();
}

Map<String, dynamic> recommendationMap(dynamic value) =>
    value is Map<String, dynamic> ? value : const {};
List<Map<String, dynamic>> recommendationMaps(dynamic value) =>
    value is List ? value.whereType<Map<String, dynamic>>().toList() : [];
String? recommendationText(dynamic value) =>
    value is String && value.trim().isNotEmpty ? value.trim() : null;

/// Before currency-aware listings, saved offers came from a SAR-only API.
/// Explicit unknown currency or a new price label must never fall back to SAR.
String? shoppingOfferCurrency(Map<String, dynamic> offer) {
  if (!offer.containsKey('currency') && !offer.containsKey('price_label')) {
    return 'SAR';
  }
  final code = recommendationText(offer['currency'])?.toUpperCase();
  return code != null && RegExp(r'^[A-Z]{3}$').hasMatch(code) ? code : null;
}

/// New shopping aliases and old saved results share one display contract.
Map<String, dynamic> normalizedShoppingOffer(Map<String, dynamic> offer) => {
  ...offer,
  'title': recommendationText(offer['title']),
  'source':
      recommendationText(offer['source']) ?? recommendationText(offer['store']),
  'product_link':
      recommendationText(offer['product_link']) ??
      recommendationText(offer['product_url']),
  'source_icon': recommendationText(offer['source_icon']),
  'currency': shoppingOfferCurrency(offer),
  'price_label': recommendationText(offer['price_label']),
  'extracted_price':
      recommendationNumber(offer['extracted_price']) ??
      recommendationNumber(offer['price']) ??
      recommendationNumber(offer['unit_price']),
};

/// Preserve currency-group order from the backend. Prices can only be
/// sorted within a known currency; ambiguous labels are never compared.
List<Map<String, dynamic>> cheapestShoppingOffers(Map<String, dynamic> item) {
  final best = recommendationMap(item['best_offer']);
  final candidates = [
    ...recommendationMaps(item['offers']),
    if (best.isNotEmpty) best,
  ].map(normalizedShoppingOffer);
  final seen = <String>{};
  final groups = <String, List<Map<String, dynamic>>>{};
  final originalOrder = Map<Map<String, dynamic>, int>.identity();
  var index = 0;
  for (final offer in candidates) {
    final price = recommendationNumber(offer['extracted_price']);
    if (price == null || price <= 0) continue;
    final currency = offer['currency'] as String?;
    final identity = jsonEncode([
      offer['product_link'],
      offer['source'],
      offer['title'],
      price,
      currency,
      if (currency == null) offer['price_label'],
    ]);
    if (!seen.add(identity)) continue;
    originalOrder[offer] = index++;
    // Each unknown currency is its own group, retaining its exact input order.
    final group = currency ?? 'unknown-$index';
    groups.putIfAbsent(group, () => []).add(offer);
  }
  final ordered = <Map<String, dynamic>>[];
  for (final group in groups.values) {
    if (group.first['currency'] != null) {
      group.sort((a, b) {
        final byPrice = (a['extracted_price'] as double).compareTo(
          b['extracted_price'] as double,
        );
        return byPrice != 0
            ? byPrice
            : originalOrder[a]!.compareTo(originalOrder[b]!);
      });
    }
    ordered.addAll(group);
  }
  return ordered.take(2).toList(growable: false);
}

/// Reviewed identity and quantity. Unknown values remain null.
class ReviewProduct {
  final Map<String, dynamic> data;
  ReviewProduct(Map<String, dynamic> value)
    : data = Map<String, dynamic>.unmodifiable(value);
  factory ReviewProduct.fromInvoice(InvoiceItemModel item, int index) =>
      ReviewProduct({...item.toJson(), 'id': 'item-$index'});
  String get id => data['id']?.toString() ?? '';
  String get name => recommendationText(data['name']) ?? '';
  Map<String, dynamic> toJson() => Map<String, dynamic>.from(data);
}

class RecommendationReview {
  final String mode;
  final List<ReviewProduct> products;
  final InvoiceModel? invoice;
  final List<String> warnings;
  RecommendationReview({
    required this.mode,
    required this.products,
    this.invoice,
    this.warnings = const [],
  });
  factory RecommendationReview.fromJson(Map<String, dynamic> json) {
    if (json['stage'] != 'review' ||
        !['product', 'invoice', 'shopping-list'].contains(json['mode']) ||
        json['products'] is! List) {
      throw const FormatException('Invalid review response');
    }
    return RecommendationReview(
      mode: json['mode'],
      products:
          recommendationMaps(json['products']).map(ReviewProduct.new).toList(),
      invoice:
          json['invoice'] is Map<String, dynamic>
              ? InvoiceModel.fromJson(json['invoice'])
              : null,
      warnings: (json['warnings'] as List? ?? []).whereType<String>().toList(),
    );
  }
  factory RecommendationReview.invoice(InvoiceModel invoice) =>
      RecommendationReview(
        mode: 'invoice',
        invoice: invoice,
        products: [
          for (var i = 0; i < invoice.items.length; i++)
            ReviewProduct.fromInvoice(invoice.items[i], i),
        ],
      );
}

/// Server-calculated amounts are display-only and never enter the expense ledger.
class RecommendationResult {
  final Map<String, dynamic> data;
  RecommendationResult._(this.data);
  factory RecommendationResult.fromJson(Map<String, dynamic> json) {
    if (json['stage'] != 'results' ||
        json['success'] != true ||
        json['summary'] is! Map<String, dynamic> ||
        json['recommendations'] is! List) {
      throw const FormatException('Invalid recommendation result');
    }
    return RecommendationResult._(Map<String, dynamic>.unmodifiable(json));
  }
  Map<String, dynamic> get summary => recommendationMap(data['summary']);
  List<Map<String, dynamic>> get recommendations =>
      recommendationMaps(data['recommendations']);
  String get mode =>
      ['invoice', 'shopping-list'].contains(data['mode'])
          ? data['mode'] as String
          : 'product';
  String? get searchedAt => recommendationText(data['searched_at']);
  List<String> get warnings =>
      (data['warnings'] as List? ?? []).whereType<String>().toList();
  Map<String, dynamic> toJson() => Map<String, dynamic>.from(data);
}

class RecommendationSnapshot {
  final String id, savedAt;
  final String? expenseId;
  final RecommendationResult result;
  RecommendationSnapshot({
    required this.id,
    required this.savedAt,
    required this.result,
    this.expenseId,
  });
  Map<String, dynamic> toJson() => {
    'id': id,
    'saved_at': savedAt,
    'expense_id': expenseId,
    'result': result.toJson(),
  };
  factory RecommendationSnapshot.fromJson(Map<String, dynamic> json) =>
      RecommendationSnapshot(
        id: json['id'] as String,
        savedAt: json['saved_at'] as String,
        expenseId: json['expense_id'] as String?,
        result: RecommendationResult.fromJson(
          recommendationMap(json['result']),
        ),
      );
}

class RecommendationHistory {
  static const preferenceKey = 'numo_recommendations_v1';
  static const maxEntries = 20;
  static const maxBytes = 1024 * 1024;
  final SharedPreferences prefs;
  String? error;
  RecommendationHistory(this.prefs);
  List<RecommendationSnapshot> read() {
    error = null;
    final raw = prefs.getString(preferenceKey);
    if (raw == null) return [];
    try {
      if (utf8.encode(raw).length > maxBytes) {
        throw const FormatException('History size exceeds limit');
      }
      final json = jsonDecode(raw) as Map<String, dynamic>;
      if (json['version'] != 1 ||
          json['entries'] is! List ||
          (json['entries'] as List).any(
            (entry) => entry is! Map<String, dynamic>,
          )) {
        throw const FormatException('Unsupported or unreadable history');
      }
      return recommendationMaps(
        json['entries'],
      ).take(maxEntries).map(RecommendationSnapshot.fromJson).toList();
    } catch (_) {
      error =
          'Comparison history could not be read. Clear it to save new comparisons. Your expenses are unaffected.';
      return [];
    }
  }

  Future<void> save(RecommendationResult result, {String? expenseId}) async {
    final previous = read();
    if (error != null) throw StateError(error!);
    final now = DateTime.now();
    final snapshot = RecommendationSnapshot(
      id: now.microsecondsSinceEpoch.toString(),
      savedAt: now.toIso8601String(),
      result: result,
      expenseId: expenseId,
    );
    final entries =
        [
          snapshot,
          ...previous,
        ].take(maxEntries).map((e) => e.toJson()).toList();
    String encode() => jsonEncode({'version': 1, 'entries': entries});
    var encoded = encode();
    while (utf8.encode(encoded).length > maxBytes && entries.length > 1) {
      entries.removeLast();
      encoded = encode();
    }
    if (utf8.encode(encoded).length > maxBytes) {
      throw StateError('This comparison is too large to save in history');
    }
    if (!await prefs.setString(preferenceKey, encoded)) {
      throw StateError('Recommendation history could not be saved');
    }
  }

  Future<void> clear() async {
    if (!await prefs.remove(preferenceKey)) {
      throw StateError('History could not be cleared');
    }
  }
}
