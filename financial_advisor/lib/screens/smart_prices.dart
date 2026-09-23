import 'package:flutter/material.dart';
import '../core/finance_store.dart';
import '../core/recommendation.dart';
import '../l10n/app_language.dart';
import '../widgets/design.dart';
import 'recommendation_results.dart';
import 'recommendation_text.dart';

class SmartPricesPage extends StatefulWidget {
  final FinanceStore store;
  const SmartPricesPage({super.key, required this.store});
  @override
  State<SmartPricesPage> createState() => _SmartPricesPageState();
}

class _SmartPricesPageState extends State<SmartPricesPage> {
  bool changingHistory = false;

  Future<void> deleteComparison(RecommendationSnapshot snapshot) async {
    if (changingHistory) return;
    setState(() => changingHistory = true);
    try {
      if (!await confirm(
            context,
            'Delete comparison?',
            'This removes this saved result. Your expenses stay saved.',
            action: 'Delete',
          ) ||
          !mounted) {
        return;
      }
      await RecommendationHistory(widget.store.prefs).delete(snapshot.id);
      if (mounted) toast(context, 'Comparison deleted.');
    } catch (_) {
      if (mounted) toast(context, 'Could not delete comparison. Try again.');
    } finally {
      if (mounted) setState(() => changingHistory = false);
    }
  }

  Future<void> textEntry() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => RecommendationTextPage(store: widget.store),
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final repository = RecommendationHistory(widget.store.prefs);
    final history = repository.read();
    return Scaffold(
      appBar: AppBar(title: const AppText('Smart Price Recommendation')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const PageHeading('Shop with clarity', 'Find a better price'),
          Surface(
            color: ink,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.auto_awesome_outlined, color: blue, size: 36),
                const SizedBox(height: 16),
                const AppText(
                  'Same product. Smarter spending.',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                const AppText(
                  'Enter a product name to find prices from online stores.',
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    key: const Key('search-product-text'),
                    onPressed: textEntry,
                    icon: const Icon(Icons.search_rounded),
                    label: const AppText('Search by product name'),
                  ),
                ),
              ],
            ),
          ),
          const SectionHeading('Recent comparisons'),
          if (repository.error != null) ...[
            Surface(child: AppText(repository.error!)),
            const SizedBox(height: 12),
          ],
          if (history.isEmpty && repository.error == null)
            const EmptyState(
              icon: Icons.history,
              title: 'Your comparisons will appear here',
              body:
                  'Your latest 20 comparisons appear here. Potential savings never change your expense balance.',
            ),
          for (final snapshot in history)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Surface(
                padding: EdgeInsets.zero,
                child: ListTile(
                  key: ValueKey('comparison-${snapshot.id}'),
                  leading: Icon(
                    snapshot.result.mode == 'invoice'
                        ? Icons.receipt_long_outlined
                        : Icons.shopping_bag_outlined,
                    color: blue,
                  ),
                  title: AppText(
                    snapshot.result.isDirectSearch
                        ? recommendationText(snapshot.result.data['query']) ??
                            'Product search'
                        : snapshot.result.mode == 'invoice'
                        ? 'Invoice comparison'
                        : snapshot.result.mode == 'shopping-list'
                        ? 'Shopping list results'
                        : 'Product comparison',
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(recommendationTime(context, snapshot.savedAt)),
                      if (snapshot.result.isDirectSearch)
                        AppText(
                          '${snapshot.result.shoppingResults.length} results',
                        )
                      else
                        AppText(
                          snapshot.result.mode == 'shopping-list' ||
                                  (snapshot.result.mode == 'product' &&
                                      (recommendationNumber(
                                                snapshot
                                                    .result
                                                    .summary['compared_items'],
                                              ) ??
                                              0) ==
                                          0)
                              ? snapshot.result.summary['shopping_total'] ==
                                          null &&
                                      (recommendationNumber(
                                                snapshot
                                                    .result
                                                    .summary['found_items'],
                                              ) ??
                                              0) >
                                          0
                                  ? 'See prices on product cards'
                                  : 'Estimated shopping total: ${priceText(snapshot.result.summary['shopping_total'])}'
                              : 'Potential saving: ${priceText(snapshot.result.summary['potential_savings'])}',
                        ),
                    ],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        key: ValueKey('delete-comparison-${snapshot.id}'),
                        tooltip: tr(context, 'Delete comparison'),
                        onPressed:
                            changingHistory
                                ? null
                                : () => deleteComparison(snapshot),
                        icon: const Icon(Icons.delete_outline),
                      ),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                  onTap:
                      () => Navigator.push<void>(
                        context,
                        MaterialPageRoute(
                          builder:
                              (_) => RecommendationResultsPage(
                                result: snapshot.result,
                                historical: true,
                              ),
                        ),
                      ),
                ),
              ),
            ),
          if (history.isNotEmpty || repository.error != null)
            TextButton.icon(
              icon: const Icon(Icons.delete_outline),
              label: const AppText('Clear comparison history'),
              onPressed:
                  changingHistory
                      ? null
                      : () async {
                        setState(() => changingHistory = true);
                        try {
                          if (!await confirm(
                                context,
                                'Clear comparison history?',
                                'This removes comparison history. Your expenses stay saved.',
                              ) ||
                              !mounted) {
                            return;
                          }
                          await RecommendationHistory(
                            widget.store.prefs,
                          ).clear();
                        } catch (_) {
                          if (context.mounted) {
                            toast(
                              context,
                              'Could not clear comparison history.',
                            );
                          }
                        } finally {
                          if (mounted) setState(() => changingHistory = false);
                        }
                      },
            ),
        ],
      ),
    );
  }
}
