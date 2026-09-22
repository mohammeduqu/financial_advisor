import 'package:flutter/material.dart';
import '../core/finance_store.dart';
import '../l10n/app_language.dart';
import '../config/flask_config.dart';
import '../services/recommendation_service.dart';
import '../widgets/design.dart';
import 'recommendation_review.dart';

class RecommendationTextPage extends StatefulWidget {
  final FinanceStore store;
  final bool shoppingList;
  final RecommendationService Function(String)? serviceFactory;
  const RecommendationTextPage({
    super.key,
    required this.store,
    this.shoppingList = false,
    this.serviceFactory,
  });
  @override
  State<RecommendationTextPage> createState() => _RecommendationTextPageState();
}

class _RecommendationTextPageState extends State<RecommendationTextPage> {
  final input = TextEditingController();
  RecommendationService? service;
  late String baseUrl;
  bool busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    baseUrl = flaskApiUrl();
  }

  @override
  void dispose() {
    service?.close();
    input.dispose();
    super.dispose();
  }

  Future<void> review() async {
    if (busy) return;
    if (input.text.trim().isEmpty) {
      setState(
        () =>
            error =
                widget.shoppingList
                    ? 'Paste your shopping list first.'
                    : 'Enter a product name.',
      );
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      busy = true;
      error = null;
    });
    service?.close();
    service =
        widget.serviceFactory?.call(baseUrl) ??
        RecommendationService(baseUrl: baseUrl);
    try {
      final result = await service!.reviewText(
        input.text,
        shoppingList: widget.shoppingList,
      );
      if (!mounted) return;
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder:
              (_) => RecommendationReviewPage(
                store: widget.store,
                review: result,
                service: service,
              ),
        ),
      );
    } on RecommendationApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Could not prepare your products. Try again.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: Scaffold(
      appBar: AppBar(
        title: AppText(
          widget.shoppingList ? 'Shopping list' : 'Search by product name',
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          PageHeading(
            'Smart Price Recommendation',
            widget.shoppingList
                ? 'What is on your list?'
                : 'What are you looking for?',
          ),
          Surface(
            color: ink,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  widget.shoppingList
                      ? Icons.playlist_add_check_rounded
                      : Icons.search_rounded,
                  color: blue,
                  size: 38,
                ),
                const SizedBox(height: 16),
                AppText(
                  widget.shoppingList
                      ? 'Paste a message, a checklist or a list of things you want to buy. Include quantities, brands and sizes when you know them.'
                      : 'Type the product name. Add the brand, model, capacity or size for more useful results.',
                ),
                const SizedBox(height: 20),
                TextField(
                  key: const Key('shopping-text-input'),
                  controller: input,
                  enabled: !busy,
                  minLines: widget.shoppingList ? 6 : 2,
                  maxLines: widget.shoppingList ? 14 : 3,
                  maxLength: widget.shoppingList ? 8000 : 400,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: tr(
                      context,
                      widget.shoppingList ? 'Paste your list' : 'Product name',
                    ),
                    hintText: tr(
                      context,
                      widget.shoppingList
                          ? '2 bottles of Almarai milk 2L\nCoffee beans 250g\nUSB-C charger 30W'
                          : 'Apple AirPods Pro 2 USB-C',
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          AppText(
            widget.shoppingList
                ? 'We organize the list first. You can edit every item before any price search starts.'
                : 'Review the name and optional current price before searching stores.',
            style: const TextStyle(color: muted),
          ),
          if (error != null) ...[
            const SizedBox(height: 16),
            Surface(
              child: AppText(
                error!,
                style: const TextStyle(color: Color(0xFFFFB4AB)),
              ),
            ),
          ],
          if (busy) ...[
            const SizedBox(height: 20),
            const LinearProgressIndicator(),
            const SizedBox(height: 12),
            AppText(
              widget.shoppingList
                  ? 'Organizing your shopping list…'
                  : 'Preparing your product…',
            ),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            key: const Key('review-shopping-text'),
            onPressed: busy ? null : review,
            icon: const Icon(Icons.arrow_forward_rounded),
            label: AppText(
              widget.shoppingList ? 'Review my list' : 'Review product',
            ),
          ),
          const SizedBox(height: 14),
          const AppText(
            'Shopping searches do not add expenses. Your budget changes only when you save an expense.',
            style: TextStyle(color: muted, fontSize: 12),
          ),
        ],
      ),
    ),
  );
}
