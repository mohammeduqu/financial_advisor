import 'package:financial_advisor/core/recommendation.dart';
import 'package:financial_advisor/l10n/app_language.dart';
import 'package:financial_advisor/screens/recommendation_results.dart';
import 'package:financial_advisor/widgets/design.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

RecommendationResult directResult(
  List<Map<String, dynamic>> offers, {
  String query = 'Tea',
  bool cached = false,
}) => RecommendationResult.fromJson({
  'success': true,
  'stage': 'results',
  'mode': 'product',
  'direct_search': true,
  'query': query,
  'shopping_results': offers,
  'summary': {'total_results': offers.length},
  'recommendations': <Map<String, dynamic>>[],
  'searched_at': '2026-09-23T10:00:00Z',
  'cached': cached,
});

Widget directApp(Widget page, {String language = 'en'}) => MaterialApp(
  theme: appTheme(),
  locale: Locale(language),
  supportedLocales: const [Locale('en'), Locale('ar')],
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  home: page,
);

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en');
    await initializeDateFormatting('ar');
  });

  test(
    'sorts prices stably, keeps unavailable prices last and raw data intact',
    () {
      final offers = List<Map<String, dynamic>>.unmodifiable(
        [
          {'title': 'No price', 'currency': 'SAR'},
          {'title': 'Expensive', 'extracted_price': 90, 'currency': 'SAR'},
          {'title': 'First tie', 'extracted_price': 20, 'currency': 'SAR'},
          {'title': 'Zero', 'extracted_price': 0, 'currency': 'SAR'},
          {'title': 'Negative', 'extracted_price': -1, 'currency': 'SAR'},
          {'title': 'Second tie', 'extracted_price': 20.0, 'currency': 'SAR'},
          {
            'title': 'Not finite',
            'extracted_price': double.nan,
            'currency': 'SAR',
          },
          {
            'title': 'Infinity',
            'extracted_price': double.infinity,
            'currency': 'SAR',
          },
          {'title': 'Text price', 'extracted_price': '5', 'currency': 'SAR'},
          {'title': 'Cheapest', 'extracted_price': 3.5, 'currency': 'SAR'},
        ].map((offer) => Map<String, dynamic>.unmodifiable(offer)),
      );
      final originalOrder = offers.map((offer) => offer['title']).toList();
      final result = directResult(offers, cached: true);

      expect(result.sortedShoppingResults.map((offer) => offer['title']), [
        'Cheapest',
        'First tie',
        'Second tie',
        'Expensive',
        'No price',
        'Zero',
        'Negative',
        'Not finite',
        'Infinity',
        'Text price',
      ]);
      expect(result.sortedShoppingResults.length, offers.length);
      expect(
        result.shoppingResults.map((offer) => offer['title']),
        originalOrder,
      );
      expect(result.toJson()['shopping_results'], same(offers));
      expect(result.sortedShoppingResults.first, same(offers.last));
    },
  );

  test(
    'sorts within currencies without comparing unrelated or unknown money',
    () {
      final result = directResult([
        {'title': 'SAR expensive', 'extracted_price': 100, 'currency': 'SAR'},
        {'title': 'Unknown expensive', 'extracted_price': 500},
        {'title': 'USD expensive', 'extracted_price': 5, 'currency': 'USD'},
        {'title': 'No price', 'currency': 'SAR'},
        {'title': 'USD cheap', 'extracted_price': 1, 'currency': 'USD'},
        {'title': 'SAR cheap', 'extracted_price': 30, 'currency': 'sar'},
        {'title': 'Unknown cheap', 'extracted_price': 0.5, 'currency': '?'},
      ]);
      expect(result.sortedShoppingResults.map((offer) => offer['title']), [
        'SAR cheap',
        'SAR expensive',
        'USD cheap',
        'USD expensive',
        'Unknown expensive',
        'Unknown cheap',
        'No price',
      ]);
      expect(directShoppingOfferCurrency({'extracted_price': 20}), isNull);
    },
  );

  test(
    'provider image URLs allow static formats without allowing API endpoints',
    () {
      for (final url in [
        'https://serpapi.com/images/url/ZBpyXnicDclXDoIwAADQE_9-u-n0',
        'https://serpapi.com/images/i/iVBORw0KGgo_A-A.png',
        'https://serpapi.com/searches/abc/images/products/hash.webp',
      ]) {
        expect(sourceIconUri(url)?.toString(), url);
      }
      for (final url in [
        'http://serpapi.com/images/url/abc',
        'https://serpapi.com:444/images/url/abc',
        'https://user@serpapi.com/images/url/abc',
        'https://serpapi.com/images/url/abc?api_key=secret',
        'https://serpapi.com/images/i/abc.png#fragment',
        'https://serpapi.com/images/i/abc.svg',
        'https://serpapi.com/images/url/abc/other',
        'https://serpapi.com/search.json',
        'https://serpapi.com/searches/abc/images/../../search.json',
      ]) {
        expect(sourceIconUri(url), isNull, reason: url);
      }
    },
  );

  testWidgets(
    'all 36 provider cards show cheapest first with matching product and store images',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        directApp(
          RecommendationResultsPage(
            result: directResult(
              List.generate(
                36,
                (index) => {
                  'title': 'Tea provider result $index',
                  'source': 'Tea store $index',
                  'serpapi_thumbnail':
                      'https://serpapi.com/images/url/Tea_$index-opaque',
                  'source_icon':
                      'https://serpapi.com/images/i/Tea_$index-icon.png',
                  'product_link': 'https://store.example/tea/$index',
                  'extracted_price': 36 - index,
                  'currency': 'SAR',
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('36 results'), findsOneWidget);
      expect(find.text('Price: low to high'), findsOneWidget);
      for (var index = 0; index < 36; index++) {
        final providerIndex = 35 - index;
        final card = find.byKey(ValueKey('direct-shopping-offer-$index'));
        await tester.scrollUntilVisible(card, 350);
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: card,
            matching: find.text('Tea provider result $providerIndex'),
          ),
          findsOneWidget,
        );
        expect(find.text('Tea store $providerIndex'), findsOneWidget);
        expect(
          find.byKey(ValueKey('direct-product-image-$index')),
          findsOneWidget,
        );
        expect(
          (tester
                      .widget<Image>(
                        find.byKey(ValueKey('direct-product-image-$index')),
                      )
                      .image
                  as NetworkImage)
              .url,
          'https://serpapi.com/images/url/Tea_$providerIndex-opaque',
        );
        expect(
          (tester
                      .widget<Image>(
                        find.byKey(ValueKey('direct-source-icon-$index')),
                      )
                      .image
                  as NetworkImage)
              .url,
          'https://serpapi.com/images/i/Tea_$providerIndex-icon.png',
        );
        expect(
          find.byKey(ValueKey('direct-source-icon-$index')),
          findsOneWidget,
        );
      }
      expect(
        find.byKey(const ValueKey('direct-shopping-offer-36')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('renders every provider card and preserves its listing fields', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      directApp(
        RecommendationResultsPage(
          result: directResult([
            {
              'title': 'Premium tea',
              'source': 'First merchant',
              'source_icon': 'https://serpapi.com/images/i/iVBORw0KGgo_A-A.png',
              'serpapi_thumbnail':
                  'https://serpapi.com/images/url/ZBpyXnicDclXDoIwAADQE_9-u-n0',
              'product_link': 'https://first.example/tea',
              'extracted_price': 35,
              'price_label': 'SAR 35.00',
              'currency': 'SAR',
            },
            {
              'title': 'Loose tea',
              'source': 'Second merchant',
              'source_icon': 'http://127.0.0.1/private.png',
              'serpapi_thumbnail': 'http://127.0.0.1/private-product.png',
              'product_link': 'https://second.example/tea',
              'extracted_price': 20,
              'currency': 'USD',
            },
            {
              'title': 'Third provider result',
              'source': 'Third merchant',
              'product_link': 'https://third.example/tea',
              'extracted_price': 12,
              'currency': 'EUR',
            },
            {
              'title': 'Unpriced tea remains visible',
              'product_link': 'https://fourth.example/tea',
              'extracted_price': null,
            },
          ]),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Premium tea'), findsOneWidget);
    expect(find.text('First merchant'), findsOneWidget);
    expect(find.text('SAR 35.00'), findsOneWidget);
    expect(find.text('20.00 USD'), findsOneWidget);
    expect(find.text('Third provider result'), findsOneWidget);
    expect(find.text('12.00 EUR'), findsOneWidget);
    expect(find.text('Unpriced tea remains visible'), findsOneWidget);
    expect(find.text('Price unavailable'), findsOneWidget);
    expect(find.text('Unknown store'), findsOneWidget);
    expect(find.text('Open shop'), findsNWidgets(4));
    expect(
      find.text(
        'Prices sorted within each currency. Unspecified currencies appear last.',
      ),
      findsOneWidget,
    );
    final sourceImage = tester.widget<Image>(
      find.byKey(const ValueKey('direct-source-icon-0')),
    );
    expect(
      (sourceImage.image as NetworkImage).url,
      'https://serpapi.com/images/i/iVBORw0KGgo_A-A.png',
    );
    // Provider images do not permit CORS byte fetching. The browser must use
    // an HTML image element; native platforms ignore this strategy.
    expect(
      (sourceImage.image as NetworkImage).webHtmlElementStrategy,
      WebHtmlElementStrategy.prefer,
    );
    final productImage = tester.widget<Image>(
      find.byKey(const ValueKey('direct-product-image-0')),
    );
    expect(
      (productImage.image as NetworkImage).url,
      'https://serpapi.com/images/url/ZBpyXnicDclXDoIwAADQE_9-u-n0',
    );
    expect(
      (productImage.image as NetworkImage).webHtmlElementStrategy,
      WebHtmlElementStrategy.prefer,
    );
    expect(productImage.fit, BoxFit.contain);
    // Widget tests reject external image loads; failed images have fallbacks.
    expect(
      find.byKey(const ValueKey('direct-product-image-fallback-0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('direct-product-image-fallback-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('direct-source-icon-fallback-0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('direct-source-icon-fallback-1')),
      findsOneWidget,
    );
    expect(
      tester.getTopLeft(find.text('Premium tea')).dy,
      lessThan(tester.getTopLeft(find.text('Loose tea')).dy),
    );
    expect(find.textContaining('Match:'), findsNothing);
    expect(find.text('Potential saving'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty and missing images use distinct product and store icons', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      directApp(
        RecommendationResultsPage(
          result: directResult([
            {'title': 'Missing images'},
            {
              'title': 'Empty images',
              'serpapi_thumbnail': '',
              'source_icon': '   ',
            },
          ]),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (var index = 0; index < 2; index++) {
      expect(
        tester
            .widget<Icon>(
              find.byKey(ValueKey('direct-product-image-fallback-$index')),
            )
            .icon,
        Icons.image_outlined,
      );
      expect(
        tester
            .widget<Icon>(
              find.byKey(ValueKey('direct-source-icon-fallback-$index')),
            )
            .icon,
        Icons.storefront_outlined,
      );
    }
    expect(find.byType(Image), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('card and Open shop launch the exact product link directly', (
    tester,
  ) async {
    final launched = <String>[];
    const channel = MethodChannel('plugins.flutter.io/url_launcher');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.arguments is Map && (call.arguments as Map)['url'] is String) {
        launched.add((call.arguments as Map)['url'] as String);
      }
      return true;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    const productLink = 'https://www.google.com/shopping/product/123?offer=456';
    await tester.pumpWidget(
      directApp(
        RecommendationResultsPage(
          result: directResult([
            {
              'title': 'Tea to open',
              'source': 'Merchant',
              'product_link': productLink,
              'product_url': 'https://legacy.example/wrong',
              'shop_lookup_token': 'never-resolve-this-token',
              'extracted_price': 25,
              'currency': 'SAR',
            },
          ]),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(launched, isEmpty);
    await tester.ensureVisible(find.text('Tea to open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tea to open'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('direct-open-shop-0')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('direct-open-shop-0')));
    await tester.pumpAndSettle();
    expect(launched, [productLink, productLink]);
    expect(find.text('Finding the online shop…'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a missing product link disables opening without hiding a card', (
    tester,
  ) async {
    await tester.pumpWidget(
      directApp(
        RecommendationResultsPage(
          result: directResult([
            {
              'title': 'Listing without a link',
              'extracted_price': 0,
              'currency': 'USD',
            },
          ]),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Listing without a link'), findsOneWidget);
    expect(find.text('0.00 USD'), findsOneWidget);
    expect(
      tester
          .widget<InkWell>(
            find.byKey(const ValueKey('direct-shopping-offer-0')),
          )
          .onTap,
      isNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const ValueKey('direct-open-shop-0')),
          )
          .onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('foreign and unknown prices never assume SAR or combine totals', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      directApp(
        RecommendationResultsPage(
          result: directResult([
            {'title': 'US offer', 'extracted_price': 12, 'currency': 'USD'},
            {
              'title': 'Ambiguous dollar offer',
              'extracted_price': 15,
              'price_label': r'$15.00',
            },
            {'title': 'Unknown currency offer', 'extracted_price': 19},
          ]),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('12.00 USD'), findsOneWidget);
    expect(find.text(r'$15.00'), findsOneWidget);
    expect(find.text('19.00'), findsOneWidget);
    expect(find.textContaining('SAR'), findsNothing);
    expect(find.text('Estimated shopping total'), findsNothing);
    expect(find.textContaining('lowest'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty result includes the query and returns to search', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      directApp(
        Builder(
          builder:
              (context) => Scaffold(
                body: TextButton(
                  onPressed:
                      () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder:
                              (_) => RecommendationResultsPage(
                                result: directResult(
                                  [],
                                  query: 'Unusual tea blend',
                                ),
                              ),
                        ),
                      ),
                  child: const Text('Search form'),
                ),
              ),
        ),
      ),
    );
    await tester.tap(find.text('Search form'));
    await tester.pumpAndSettle();
    expect(find.text('Unusual tea blend'), findsOneWidget);
    expect(find.text('No shopping options found'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('direct-search-retry')));
    await tester.pumpAndSettle();
    expect(find.text('Search form'), findsOneWidget);
    expect(find.text('No shopping options found'), findsNothing);
  });

  testWidgets('cached historical results retain their saved-price context', (
    tester,
  ) async {
    await tester.pumpWidget(
      directApp(
        RecommendationResultsPage(
          historical: true,
          result: directResult([], cached: true),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Cached search results'), findsOneWidget);
    expect(
      find.text(
        'Saved comparison. These are historical prices, not a live quote.',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Arabic direct results fit a narrow mobile screen', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      directApp(
        RecommendationResultsPage(
          result: directResult([
            {
              'title': 'شاي أخضر بأوراق طبيعية وعبوة عائلية كبيرة',
              'source': 'متجر المنتجات الطبيعية والمستلزمات المنزلية',
              'extracted_price': 95,
              'price_label': '95.00 ر.س.',
              'currency': 'SAR',
              'product_link': 'https://merchant.example/tea',
            },
          ], query: 'شاي أخضر'),
        ),
        language: 'ar',
      ),
    );
    await tester.pumpAndSettle();
    expect(
      Directionality.of(tester.element(find.text('شاي أخضر'))),
      TextDirection.rtl,
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('direct-open-shop-0')),
    );
    expect(find.text(translate('Open shop', 'ar')), findsOneWidget);
    expect(find.text('95.00 ر.س.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
