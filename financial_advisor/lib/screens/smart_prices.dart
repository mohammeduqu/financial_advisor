import 'package:flutter/material.dart';
import '../core/finance_store.dart';
import '../core/recommendation.dart';
import '../l10n/app_language.dart';
import '../widgets/design.dart';
import 'recommendation_results.dart';
import 'scan.dart';
import 'recommendation_text.dart';

class SmartPricesPage extends StatefulWidget {
  final FinanceStore store;
  const SmartPricesPage({super.key, required this.store});
  @override
  State<SmartPricesPage> createState() => _SmartPricesPageState();
}

class _SmartPricesPageState extends State<SmartPricesPage> {
  Future<void> textEntry(bool shoppingList) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder:
            (_) => RecommendationTextPage(
              store: widget.store,
              shoppingList: shoppingList,
            ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> scan(bool shoppingList) async {
    final entry = await Navigator.push<Entry>(
      context,
      MaterialPageRoute(
        builder:
            (_) => Scaffold(
              appBar: AppBar(
                title: AppText(
                  shoppingList ? 'Import list or invoice' : 'Scan Invoice',
                ),
              ),
              body: ScanPage(
                store: widget.store,
                shoppingListMode: shoppingList,
              ),
            ),
      ),
    );
    if (!mounted) return;
    if (entry != null) {
      Navigator.pop(context, entry);
    } else {
      setState(() {});
    }
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
                  'Search a product by name, paste your shopping list, or import a list image. Review the items, then find online stores.',
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    key: const Key('search-product-text'),
                    onPressed: () => textEntry(false),
                    icon: const Icon(Icons.search_rounded),
                    label: const AppText('Search by product name'),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    key: const Key('paste-shopping-list'),
                    onPressed: () => textEntry(true),
                    icon: const Icon(Icons.playlist_add_rounded),
                    label: const AppText('Paste a shopping list'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            key: const Key('import-shopping-image'),
            onPressed: () => scan(true),
            icon: const Icon(Icons.document_scanner_outlined),
            label: const AppText('Import list or invoice image'),
          ),
          const SizedBox(height: 10),
          const AppText(
            'A photo, screenshot or invoice can become a shopping list. Tap a product card to open its link.',
            style: TextStyle(color: muted),
          ),
          TextButton.icon(
            onPressed: () => scan(false),
            icon: const Icon(Icons.receipt_long_outlined),
            label: const AppText('Scan Invoice and add expense'),
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
                  leading: Icon(
                    snapshot.result.mode == 'invoice'
                        ? Icons.receipt_long_outlined
                        : Icons.shopping_bag_outlined,
                    color: blue,
                  ),
                  title: AppText(
                    snapshot.result.mode == 'invoice'
                        ? 'Invoice comparison'
                        : snapshot.result.mode == 'shopping-list'
                        ? 'Shopping list results'
                        : 'Product comparison',
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(recommendationTime(context, snapshot.savedAt)),
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
                  trailing: const Icon(Icons.chevron_right),
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
              onPressed: () async {
                if (!await confirm(
                  context,
                  'Clear comparison history?',
                  'This removes comparison history. Your expenses stay saved.',
                )) {
                  return;
                }
                try {
                  await RecommendationHistory(widget.store.prefs).clear();
                  if (mounted) setState(() {});
                } catch (_) {
                  if (context.mounted) {
                    toast(context, 'Could not clear comparison history.');
                  }
                }
              },
            ),
        ],
      ),
    );
  }
}
