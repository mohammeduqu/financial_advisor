import 'package:flutter/material.dart';
import '../core/finance_store.dart';
import '../core/invoice.dart' show parseInvoiceNumber;
import '../core/product_search_options.dart';
import '../core/recommendation.dart';
import '../l10n/app_language.dart';
import '../config/flask_config.dart';
import '../services/recommendation_service.dart';
import '../widgets/design.dart';
import 'recommendation_review.dart';
import 'recommendation_results.dart';

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
  final maxPrice = TextEditingController();
  late String countryCode, searchLanguage;
  RecommendationService? service;
  late String baseUrl;
  bool busy = false;
  String? error;
  bool get unsupportedCountry =>
      !widget.shoppingList && isKnownUnsupportedSearchCountry(countryCode);
  @override
  void initState() {
    super.initState();
    baseUrl = flaskApiUrl();
    final options = ProductSearchOptions.load(widget.store.prefs);
    countryCode = options.countryCode;
    searchLanguage = options.language;
    maxPrice.text = options.maxPrice?.toString() ?? '';
  }

  @override
  void dispose() {
    service?.close();
    input.dispose();
    maxPrice.dispose();
    super.dispose();
  }

  Future<void> review() async {
    if (busy || unsupportedCountry) return;
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
    final limitText = maxPrice.text.trim();
    final limit = limitText.isEmpty ? null : parseInvoiceNumber(limitText);
    if (!widget.shoppingList &&
        limitText.isNotEmpty &&
        (limit == null || !isValidProductSearchPrice(limit))) {
      setState(
        () => error = 'Check the search country, language and maximum price.',
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
      if (!widget.shoppingList) {
        final options = ProductSearchOptions(
          countryCode: countryCode,
          language: searchLanguage,
          maxPrice: limit,
        );
        if (!await options.save(widget.store.prefs)) {
          if (mounted) {
            setState(
              () => error = 'Could not save search settings. Try again.',
            );
          }
          return;
        }
        final result = await service!.searchProduct(
          input.text,
          countryCode: options.countryCode,
          location: options.location,
          googleDomain: options.googleDomain,
          language: options.language,
          maxPrice: options.maxPrice,
        );
        String? notice;
        try {
          await RecommendationHistory(widget.store.prefs).save(result);
        } catch (_) {
          notice = 'Results are available, but history could not be saved.';
        }
        if (!mounted) return;
        await Navigator.push<void>(
          context,
          MaterialPageRoute(
            builder:
                (_) =>
                    RecommendationResultsPage(result: result, notice: notice),
          ),
        );
        return;
      }
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
        setState(
          () =>
              error =
                  widget.shoppingList
                      ? 'Could not prepare your products. Try again.'
                      : 'Price search failed. Try again.',
        );
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
                      : 'Enter a product name to find prices from online stores.',
                ),
                const SizedBox(height: 20),
                TextField(
                  key: const Key('shopping-text-input'),
                  controller: input,
                  enabled: !busy,
                  minLines: widget.shoppingList ? 6 : 1,
                  maxLines: widget.shoppingList ? 14 : 1,
                  maxLength: widget.shoppingList ? 8000 : 400,
                  keyboardType:
                      widget.shoppingList
                          ? TextInputType.multiline
                          : TextInputType.text,
                  textInputAction:
                      widget.shoppingList
                          ? TextInputAction.newline
                          : TextInputAction.done,
                  onSubmitted: widget.shoppingList ? null : (_) => review(),
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: tr(
                      context,
                      widget.shoppingList ? 'Paste your list' : 'Product name',
                    ),
                    hintText: tr(context, 'Enter product name'),
                  ),
                ),
                if (!widget.shoppingList) ...[
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    key: const Key('shopping-country'),
                    value: countryCode,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: tr(context, 'Search country'),
                      errorText:
                          unsupportedCountry
                              ? tr(
                                context,
                                const RecommendationApiException(
                                  'unsupported_search_country',
                                ).message,
                              )
                              : null,
                      errorMaxLines: 3,
                    ),
                    items: [
                      for (final country in productSearchCountries)
                        DropdownMenuItem(
                          value: country.code,
                          child: AppText(country.name),
                        ),
                    ],
                    onChanged:
                        busy
                            ? null
                            : (value) {
                              if (value == null) return;
                              setState(() {
                                countryCode = value;
                                error = null;
                              });
                            },
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    key: const Key('shopping-language'),
                    value: searchLanguage,
                    decoration: InputDecoration(
                      labelText: tr(context, 'Results language'),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'ar', child: Text('العربية')),
                      DropdownMenuItem(value: 'en', child: Text('English')),
                    ],
                    onChanged:
                        busy
                            ? null
                            : (value) {
                              if (value != null) {
                                setState(() => searchLanguage = value);
                              }
                            },
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    key: const Key('shopping-max-price'),
                    controller: maxPrice,
                    enabled: !busy,
                    textDirection: TextDirection.ltr,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => review(),
                    decoration: InputDecoration(
                      labelText: tr(context, 'Maximum price (optional)'),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          AppText(
            widget.shoppingList
                ? 'We organize the list first. You can edit every item before any price search starts.'
                : 'Lowest prices first within each currency. Prices may exclude shipping.',
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
                  : 'Searching stores…',
            ),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            key: Key(
              widget.shoppingList ? 'review-shopping-text' : 'search-product',
            ),
            onPressed: busy || unsupportedCountry ? null : review,
            icon: Icon(
              widget.shoppingList
                  ? Icons.arrow_forward_rounded
                  : Icons.search_rounded,
            ),
            label: AppText(
              widget.shoppingList ? 'Review my list' : 'Search stores',
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
