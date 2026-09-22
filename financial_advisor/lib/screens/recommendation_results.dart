import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show NumberFormat, DateFormat;
import '../widgets/offer_link.dart';
export '../widgets/offer_link.dart' show safeDealUri;
import '../core/recommendation.dart';
import '../l10n/app_language.dart';
import '../widgets/design.dart';

String priceText(dynamic value) {
  final number = recommendationNumber(value);
  return number == null
      ? '—'
      : '${NumberFormat('#,##0.00').format(number)} SAR';
}

String offerAmountText(dynamic value, String? currency) {
  final number = recommendationNumber(value);
  if (number == null) return '—';
  final amount = NumberFormat('#,##0.00').format(number);
  return currency == null ? amount : '$amount $currency';
}

String listedOfferPriceText(Map<String, dynamic> offer) =>
    recommendationText(offer['price_label']) ??
    offerAmountText(offer['extracted_price'], shoppingOfferCurrency(offer));

String normalizedPriceText(BuildContext context, dynamic value, dynamic unit) {
  final number = recommendationNumber(value);
  if (number == null) return '—';
  final dimension = unit is String ? unit.replaceFirst('SAR/', '') : 'item';
  return '${NumberFormat('#,##0.####').format(number)} ${tr(context, 'SAR')} / ${tr(context, dimension)}';
}

String recommendationTime(BuildContext context, String? value) {
  final date = value == null ? null : DateTime.tryParse(value);
  return date == null
      ? tr(context, 'Time unavailable')
      : DateFormat.yMMMd(languageOf(context)).add_jm().format(date.toLocal());
}

class RecommendationResultsPage extends StatelessWidget {
  final RecommendationResult result;
  final String? notice;
  final bool historical;
  const RecommendationResultsPage({
    super.key,
    required this.result,
    this.notice,
    this.historical = false,
  });
  Widget metric(String label, dynamic value, {bool accent = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppText(label, style: const TextStyle(fontSize: 12, color: muted)),
        const SizedBox(height: 6),
        Text(
          priceText(value),
          textDirection: TextDirection.ltr,
          style: TextStyle(
            fontSize: accent ? 30 : 21,
            fontWeight: FontWeight.w700,
            color: accent ? blue : ink,
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final summary = result.summary;
    final shopping =
        result.mode == 'shopping-list' ||
        (result.mode == 'product' &&
            (recommendationNumber(summary['compared_items']) ?? 0) == 0);
    final canCalculate =
        recommendationNumber(summary['original_total']) != null &&
        (recommendationNumber(summary['compared_items']) ?? 0) > 0;
    final percentage = recommendationNumber(summary['saving_percentage']);
    final found =
        summary['found_items'] ??
        result.recommendations
            .where((item) => recommendationMap(item['best_offer']).isNotEmpty)
            .length;
    final searchIncomplete = result.recommendations.any(
      (item) =>
          item['status'] == 'search_failed' ||
          item['reason_code'] == 'search_limit_reached',
    );
    final currencyNotComparable = result.warnings.contains(
      'shopping_currency_not_comparable',
    );
    final missingQuantity = result.recommendations.any(
      (item) =>
          cheapestShoppingOffers(item).isNotEmpty &&
          (recommendationNumber(item['quantity']) ?? 0) <= 0,
    );
    final title = shopping ? 'Shopping results' : 'Smart Savings';
    return Scaffold(
      appBar: AppBar(title: AppText(title)),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          PageHeading('Smart Price Recommendation', title),
          if (historical) ...[
            const Surface(
              child: AppText(
                'Saved comparison. These are historical prices, not a live quote.',
              ),
            ),
            const SizedBox(height: 16),
          ],
          Text(
            recommendationTime(context, result.searchedAt),
            style: const TextStyle(color: muted, fontSize: 12),
          ),
          const SizedBox(height: 16),
          Surface(
            color: ink,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (shopping) ...[
                  if (summary['shopping_total'] == null &&
                      (recommendationNumber(found) ?? 0) > 0)
                    const AppText(
                      'See prices on product cards',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: blue,
                      ),
                    )
                  else
                    metric(
                      'Estimated shopping total',
                      summary['shopping_total'],
                      accent: true,
                    ),
                  AppText(
                    'Found offers for $found of ${summary['total_items'] ?? result.recommendations.length} items',
                  ),
                  const SizedBox(height: 12),
                  const AppText(
                    'Tap a product card to open its supplied link. Check the product and final price before buying.',
                  ),
                  if (!currencyNotComparable &&
                      (summary['shopping_partial'] == true ||
                          summary['shopping_estimate_partial'] == true ||
                          summary['shopping_total'] == null)) ...[
                    const SizedBox(height: 10),
                    const AppText(
                      'Partial estimate. Items without a usable price or quantity are not included.',
                    ),
                  ],
                  if (missingQuantity) ...[
                    const SizedBox(height: 10),
                    const AppText(
                      'Some quantities are unknown. Listed prices may represent one pack rather than your full requirement.',
                    ),
                  ],
                ] else ...[
                  if (canCalculate)
                    metric(
                      'Potential saving',
                      summary['potential_savings'],
                      accent: true,
                    )
                  else
                    const AppText(
                      'Savings unavailable. Add an original price and quantity, then compare matching offers.',
                    ),
                  if (canCalculate && percentage != null)
                    AppText('You could save ${percentage.toStringAsFixed(1)}%'),
                  const Divider(),
                  metric(
                    result.mode == 'invoice'
                        ? 'Original invoice total'
                        : 'Current price',
                    summary['original_total'],
                  ),
                  metric(
                    'Comparable item total',
                    canCalculate ? summary['comparable_original_total'] : null,
                  ),
                  metric(
                    'Alternative total for compared items',
                    canCalculate ? summary['recommended_total'] : null,
                  ),
                  AppText(
                    '${summary['compared_items'] ?? 0} of ${summary['total_items'] ?? 0} items compared',
                  ),
                  if (summary['partial'] == true)
                    const AppText(
                      'Partial comparison: unpriced or unmatched items, tax and fees are not savings.',
                    ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          AppText(
            shopping
                ? 'Shopping options are suggestions for your list. A broad result is not a verified equivalent, and an estimate is not a saving.'
                : 'Potential savings are estimates, not money already saved. Match scores are comparison rules, not a probability of accuracy.',
            style: const TextStyle(color: muted, fontSize: 12),
          ),
          const SizedBox(height: 10),
          const AppText(
            'Check the exact product, pack quantity, final tax, delivery cost and stock at the store. Shipping and availability may be unverified.',
            style: TextStyle(color: muted, fontSize: 12),
          ),
          if (notice != null) ...[
            const SizedBox(height: 16),
            Surface(child: AppText(notice!)),
          ],
          if (searchIncomplete) ...[
            const SizedBox(height: 16),
            const Surface(
              child: AppText(
                'Some searches were unavailable or skipped. Results cover only comparable items.',
              ),
            ),
          ],
          if (result.warnings.contains('shopping_currency_not_comparable')) ...[
            const SizedBox(height: 16),
            const Surface(
              child: AppText(
                'Prices use different or unconfirmed currencies; no combined total is calculated.',
              ),
            ),
          ],
          if (result.warnings.contains('combined_search_limited_coverage')) ...[
            const SizedBox(height: 16),
            const Surface(
              child: AppText(
                'One combined search covers this list. Some items may have no matching results.',
              ),
            ),
          ],
          const SizedBox(height: 12),
          AppText(
            currencyNotComparable
                ? 'Up to two matching listings. Prices in different currencies are not ranked against each other.'
                : 'Up to two lowest matching listed prices from these search results.',
            style: TextStyle(color: muted, fontSize: 12),
          ),
          SectionHeading(shopping ? 'Your items' : 'Product comparisons'),
          if (result.recommendations.isEmpty)
            EmptyState(
              icon: Icons.search_off,
              title:
                  shopping
                      ? 'No shopping options found'
                      : 'No reliable cheaper alternative found.',
              body: 'Try a clearer product name with brand, model and size.',
            ),
          for (final item in result.recommendations)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: _RecommendationCard(item: item, shopping: shopping),
            ),
        ],
      ),
    );
  }
}

class _RecommendationCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final bool shopping;
  const _RecommendationCard({required this.item, required this.shopping});
  @override
  Widget build(BuildContext context) {
    final original = recommendationMap(item['original']);
    final saving = recommendationMap(item['saving']);
    final offers = cheapestShoppingOffers(item);
    final best = offers.firstOrNull;
    final itemId = item['item_id'] ?? item['item_name'];
    return Surface(
      key: ValueKey('shopping-result-$itemId'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            recommendationText(item['item_name']) ??
                tr(context, 'Unknown product'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          if (!shopping) ...[
            AppText(
              'Original line total: ${priceText(original['total_price'])}',
            ),
            AppText(
              'Original unit price: ${priceText(original['unit_price'])}',
            ),
          ],
          if (item['quantity'] != null)
            AppText('Quantity: ${item['quantity']}'),
          const SizedBox(height: 16),
          if (offers.isEmpty) ...[
            AppText(
              shopping
                  ? 'No shopping options found'
                  : 'No reliable cheaper alternative found.',
            ),
            if (recommendationText(item['reason']) case final String reason)
              AppText(
                reason,
                style: const TextStyle(color: muted, fontSize: 12),
              ),
          ],
          for (var index = 0; index < offers.length; index++)
            Padding(
              padding: EdgeInsets.only(
                bottom: index == offers.length - 1 ? 0 : 12,
              ),
              child: _OfferCard(
                offer: offers[index],
                cardKey: ValueKey('shopping-offer-$itemId-$index'),
              ),
            ),
          if (!shopping &&
              best != null &&
              best['currency'] == 'SAR' &&
              best['broad_match'] != true) ...[
            const SizedBox(height: 16),
            if (item['status'] == 'offers_found')
              const AppText(
                'Offers found; enter the original price and quantity to calculate savings.',
              )
            else
              AppText(
                recommendationText(saving['level']) ?? 'No significant saving',
                style: const TextStyle(
                  color: blue,
                  fontWeight: FontWeight.w600,
                ),
              ),
            if (recommendationNumber(saving['amount']) case final double amount)
              AppText('Potential saving: ${priceText(amount)}'),
            if (recommendationNumber(saving['percentage'])
                case final double percent)
              AppText('${percent.toStringAsFixed(1)}% cheaper'),
          ],
          if (item['cached'] == true) ...[
            const SizedBox(height: 12),
            const AppText(
              'Cached search results',
              style: TextStyle(color: muted, fontSize: 11),
            ),
          ],
          if (item['fetched_at'] is String) ...[
            const SizedBox(height: 6),
            Text(
              recommendationTime(context, item['fetched_at']),
              style: const TextStyle(color: muted, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }
}

/// Static provider-hosted icons do not use the paid search API.
Uri? sourceIconUri(dynamic value) {
  final publicUri = safeDealUri(value);
  if (publicUri != null) return publicUri;
  if (value is! String) return null;
  try {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host != 'serpapi.com' ||
        uri.port != 443 ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.pathSegments.any((segment) => segment == '..') ||
        !RegExp(
          r'^/searches/[A-Za-z0-9_-]+/images/[A-Za-z0-9_./-]+\.(png|jpg|jpeg|webp|gif|ico)$',
          caseSensitive: false,
        ).hasMatch(uri.path)) {
      return null;
    }
    return uri;
  } catch (_) {
    return null;
  }
}

class _OfferCard extends StatelessWidget {
  final Map<String, dynamic> offer;
  final Key cardKey;
  const _OfferCard({required this.offer, required this.cardKey});
  @override
  Widget build(BuildContext context) {
    final url = safeDealUri(offer['product_link']);
    final icon = sourceIconUri(offer['source_icon']);
    final listedPrice = recommendationNumber(offer['extracted_price']);
    final currency = shoppingOfferCurrency(offer);
    final total = recommendationNumber(offer['total_price']);
    final normalized = recommendationNumber(offer['normalized_price']);
    final score = recommendationNumber(offer['match_score']);
    final broad = offer['broad_match'] == true;
    final title =
        recommendationText(offer['title']) ?? tr(context, 'Unknown product');
    final source =
        recommendationText(offer['source']) ?? tr(context, 'Unknown store');
    final fallbackIcon = Icon(
      Icons.storefront_outlined,
      size: 20,
      color: blue,
      key: ValueKey('source-icon-fallback-$source'),
    );
    void openLink() {
      if (url != null) openRecommendationOffer(context, offer);
    }

    return Material(
      color: const Color(0xFF101923),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: line),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: cardKey,
        onTap: url == null ? null : openLink,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: const Color(0xFF21332F),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    alignment: Alignment.center,
                    child:
                        icon == null
                            ? fallbackIcon
                            : ClipRRect(
                              borderRadius: BorderRadius.circular(7),
                              child: Image.network(
                                icon.toString(),
                                width: 26,
                                height: 26,
                                fit: BoxFit.contain,
                                excludeFromSemantics: true,
                                errorBuilder: (_, __, ___) => fallbackIcon,
                              ),
                            ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      source,
                      style: const TextStyle(color: muted, fontSize: 13),
                    ),
                  ),
                  if (url != null)
                    const Icon(
                      Icons.open_in_new_rounded,
                      size: 16,
                      color: muted,
                    ),
                ],
              ),
              const SizedBox(height: 16),
              const AppText(
                'Listed price',
                style: TextStyle(color: muted, fontSize: 11),
              ),
              const SizedBox(height: 3),
              Text(
                listedOfferPriceText(offer),
                textDirection: TextDirection.ltr,
                style: const TextStyle(
                  fontSize: 27,
                  fontWeight: FontWeight.w700,
                  color: blue,
                ),
              ),
              if (currency != null &&
                  total != null &&
                  listedPrice != null &&
                  (total - listedPrice).abs() > .005)
                AppText(
                  'For the required quantity: ${offerAmountText(total, currency)}',
                  style: const TextStyle(color: muted, fontSize: 12),
                ),
              if (currency == null)
                const AppText(
                  'Currency unconfirmed',
                  style: TextStyle(color: muted, fontSize: 12),
                ),
              if (broad) ...[
                const SizedBox(height: 8),
                const AppText(
                  'Shopping option',
                  style: TextStyle(color: muted, fontSize: 12),
                ),
              ] else ...[
                if (currency == 'SAR' && normalized != null)
                  AppText(
                    'Normalized price: ${normalizedPriceText(context, normalized, offer['normalized_unit'])}',
                    style: const TextStyle(color: muted, fontSize: 12),
                  ),
                if (currency == 'SAR' &&
                    offer['original_normalized_price'] != null)
                  AppText(
                    'Original normalized price: ${normalizedPriceText(context, offer['original_normalized_price'], offer['normalized_unit'])}',
                    style: const TextStyle(color: muted, fontSize: 12),
                  ),
                if (score != null)
                  AppText(
                    'Match: ${tr(context, recommendationText(offer['match_label']) ?? 'Similar Product')} (${score.toStringAsFixed(2)})',
                    style: const TextStyle(color: muted, fontSize: 12),
                  ),
                if (offer['quantity_adjusted'] == true)
                  const AppText(
                    'Quantity adjusted: buying whole packs may provide more than the original quantity.',
                    style: TextStyle(color: muted, fontSize: 12),
                  ),
              ],
              if (offer['unverified_attributes'] is List &&
                  (offer['unverified_attributes'] as List).contains(
                    'condition',
                  ))
                const AppText(
                  'Condition not verified',
                  style: TextStyle(color: muted, fontSize: 12),
                ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: url == null ? null : openLink,
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const AppText('View product'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
