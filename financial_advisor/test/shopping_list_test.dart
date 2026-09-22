import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:financial_advisor/core/finance_store.dart';
import 'package:financial_advisor/core/recommendation.dart';
import 'package:financial_advisor/screens/recommendation_text.dart';
import 'package:financial_advisor/screens/recommendation_review.dart';
import 'package:financial_advisor/screens/recommendation_results.dart';
import 'package:financial_advisor/screens/smart_prices.dart';
import 'package:financial_advisor/services/invoice_service.dart';
import 'package:financial_advisor/services/recommendation_service.dart';
import 'package:financial_advisor/widgets/design.dart';
import 'package:financial_advisor/widgets/offer_link.dart';

Map<String, dynamic> shoppingResult() => {
  'success': true,
  'stage': 'results',
  'mode': 'shopping-list',
  'warnings': [],
  'summary': {
    'original_total': null,
    'shopping_total': 24.0,
    'found_items': 1,
    'total_items': 1,
    'shopping_partial': false,
    'shopping_estimate_partial': false,
    'shopping_estimated_items': 1,
    'compared_items': 0,
    'potential_savings': 0,
  },
  'recommendations': <Map<String, dynamic>>[
    {
      'item_id': 'item-1',
      'item_name': 'Milk',
      'quantity': 3,
      'status': 'search_result',
      'original': <String, dynamic>{},
      'saving': {'amount': null, 'percentage': null},
      'best_offer': <String, dynamic>{
        'title': 'Milk 2L',
        'store': 'Example shop',
        'price': 8.0,
        'unit_price': 8.0,
        'total_price': 24.0,
        'currency': 'SAR',
        'product_url': 'https://shop.example/milk',
        'link_kind': 'merchant',
        'broad_match': true,
        'comparable': false,
        'match_score': .8,
        'purchase_quantity': 3,
      },
      'offers': <Map<String, dynamic>>[],
    },
  ],
};
Map<String, dynamic> reviewJson(String mode) => {
  'success': true,
  'stage': 'review',
  'mode': mode,
  'source_type': 'shopping_list',
  'products': [
    {'id': 'item-1', 'name': 'Milk', 'quantity': 2, 'unit_price': null},
  ],
  'warnings': [],
};
void main() {
  setUpAll(() async {
    await initializeDateFormatting('en');
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'text and list-image extraction are review-only requests through Flask',
    () async {
      final requests = <http.Request>[];
      final service = RecommendationService(
        baseUrl: 'http://127.0.0.1:5000',
        clientFactory:
            () => MockClient((request) async {
              requests.add(request);
              final mode = request.url.path.split('/').last;
              if (request.headers['content-type']!.contains(
                'application/json',
              )) {
                final json = jsonDecode(request.body) as Map;
                expect(json.containsKey('confirmed'), false);
                expect(json.containsKey('image'), false);
                expect(json['text'], isNotEmpty);
              } else {
                expect(mode, 'shopping-list');
                expect(request.body, contains('name="image"'));
              }
              return http.Response(jsonEncode(reviewJson(mode)), 200);
            }),
      );
      expect((await service.reviewText('Apple AirPods Pro 2')).mode, 'product');
      expect(
        (await service.reviewText('Milk x2\nCoffee', shoppingList: true)).mode,
        'shopping-list',
      );
      expect(
        (await service.readShoppingImage(
          Uint8List.fromList([1]),
          'list.png',
        )).products.length,
        1,
      );
      expect(requests.length, 3);
      expect(requests.every((r) => r.url.host == '127.0.0.1'), true);
      await expectLater(
        service.reviewText('x' * 401),
        throwsA(isA<RecommendationApiException>()),
      );
      await expectLater(
        service.reviewText('x' * 8001, shoppingList: true),
        throwsA(isA<RecommendationApiException>()),
      );
      expect(requests.length, 3);
    },
  );

  test(
    'list confirmation keeps reviewed quantities and shopping history mode',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final service = RecommendationService(
        baseUrl: 'http://10.0.2.2:5000',
        clientFactory:
            () => MockClient((request) async {
              expect(request.url.path, '/api/recommendations/shopping-list');
              final json = jsonDecode(request.body);
              expect(json['confirmed'], true);
              expect(json.containsKey('text'), false);
              expect(json['products'][0]['quantity'], 3);
              return http.Response(jsonEncode(shoppingResult()), 200);
            }),
      );
      final result = await service.search(
        mode: 'shopping-list',
        products: [
          ReviewProduct({'id': 'item-1', 'name': 'Milk', 'quantity': 3}),
        ],
      );
      await RecommendationHistory(prefs).save(result);
      final saved = RecommendationHistory(prefs).read().single.result;
      expect(saved.mode, 'shopping-list');
      expect(saved.summary['shopping_total'], 24);
      expect(prefs.getString('numo_v1'), isNull);
    },
  );

  testWidgets('shared link helper ignores old seller lookup tokens', (
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
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder:
                (context) => TextButton(
                  onPressed:
                      () => openRecommendationOffer(context, {
                        'product_link':
                            'https://www.google.com/shopping/product/123',
                        'product_url': 'https://legacy.example/other',
                        'link_kind': 'shopping',
                        'shop_lookup_token': 'old-lookup-token',
                      }),
                  child: const Text('Open'),
                ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(launched, ['https://www.google.com/shopping/product/123']);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'product-name entry opens editable review without performing a price search',
    (tester) async {
      final store = FinanceStore(await SharedPreferences.getInstance());
      await store.prefs.setString(
        invoiceApiPreference,
        'http://localhost:5000',
      );
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: RecommendationTextPage(
            store: store,
            serviceFactory:
                (baseUrl) => RecommendationService(
                  baseUrl: baseUrl,
                  clientFactory:
                      () => MockClient((request) async {
                        calls++;
                        expect(request.url.host, '31.97.178.214');
                        expect(request.url.port, 5001);
                        expect(jsonDecode(request.body), {'text': 'Milk'});
                        return http.Response(
                          jsonEncode(reviewJson('product')),
                          200,
                        );
                      }),
                ),
          ),
        ),
      );
      await tester.enterText(
        find.byKey(const Key('shopping-text-input')),
        'Milk',
      );
      await tester.scrollUntilVisible(
        find.byKey(const Key('review-shopping-text')).hitTestable(),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(
        find.byKey(const Key('review-shopping-text')).hitTestable(),
      );
      await tester.pumpAndSettle();
      expect(find.byType(RecommendationReviewPage), findsOneWidget);
      expect(calls, 1);
      expect(store.entries, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'list review edits quantity and confirms shopping mode only on button press',
    (tester) async {
      final store = FinanceStore(await SharedPreferences.getInstance());
      var calls = 0;
      final service = RecommendationService(
        baseUrl: defaultInvoiceApiUrl(),
        clientFactory:
            () => MockClient((request) async {
              calls++;
              expect(request.url.host, '31.97.178.214');
              expect(request.url.port, 5001);
              expect(request.url.path, '/api/recommendations/shopping-list');
              expect(jsonDecode(request.body)['products'][0]['quantity'], 3);
              expect(
                jsonDecode(request.body)['products'][0]['total_price'],
                24,
              );
              return http.Response(jsonEncode(shoppingResult()), 200);
            }),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: RecommendationReviewPage(
            store: store,
            service: service,
            review: RecommendationReview.fromJson({
              ...reviewJson('shopping-list'),
              'products': [
                {
                  'id': 'item-1',
                  'name': 'Milk',
                  'quantity': 2,
                  'unit_price': 8,
                  'total_price': 16,
                },
              ],
            }),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(calls, 0);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('item-1-quantity')),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(
        find.byKey(const ValueKey('item-1-quantity')),
        '3',
      );
      await tester.scrollUntilVisible(
        find.byKey(const Key('confirm-price-search')).hitTestable(),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('confirm-price-search')).hitTestable(),
      );
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(find.byType(RecommendationResultsPage), findsOneWidget);
      expect(store.entries, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'unpriced list shows estimates and opens a tapped item shop without fake savings',
    (tester) async {
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
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: RecommendationResultsPage(
            result: RecommendationResult.fromJson(shoppingResult()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Estimated shopping total'), findsOneWidget);
      expect(find.text('Found offers for 1 of 1 items'), findsOneWidget);
      expect(
        find.text(
          'Savings unavailable. Add an original price and quantity, then compare matching offers.',
        ),
        findsNothing,
      );
      expect(
        find.text(
          'Some quantities are unknown. Listed prices may represent one pack rather than your full requirement.',
        ),
        findsNothing,
      );
      expect(find.textContaining('You could save'), findsNothing);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('shopping-offer-item-1-0')).hitTestable(),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Shopping option'), findsOneWidget);
      expect(find.textContaining('Match:'), findsNothing);
      expect(launched, isEmpty);
      await tester.tap(
        find.byKey(const ValueKey('shopping-offer-item-1-0')).hitTestable(),
      );
      await tester.pumpAndSettle();
      expect(launched, contains('https://shop.example/milk'));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Arabic hub offers text, list and image import while preserving expense scanner',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = FinanceStore(await SharedPreferences.getInstance());
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          locale: const Locale('ar'),
          supportedLocales: const [Locale('en'), Locale('ar')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: SmartPricesPage(store: store),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('search-product-text')), findsOneWidget);
      expect(find.text('مسح منتج'), findsNothing);
      await tester.scrollUntilVisible(
        find.byKey(const Key('import-shopping-image')).hitTestable(),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('مسح فاتورة وإضافة مصروف'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'priced broad product still shows shopping estimate instead of unavailable savings',
    (tester) async {
      final json = shoppingResult();
      json['mode'] = 'product';
      (json['summary'] as Map<String, dynamic>)['original_total'] = 30.0;
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: RecommendationResultsPage(
            result: RecommendationResult.fromJson(json),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Estimated shopping total'), findsOneWidget);
      expect(find.text('Found offers for 1 of 1 items'), findsOneWidget);
      expect(
        find.text(
          'Savings unavailable. Add an original price and quantity, then compare matching offers.',
        ),
        findsNothing,
      );
      expect(find.textContaining('You could save'), findsNothing);
    },
  );

  test(
    'equal listed prices preserve the offer used by the backend summary',
    () {
      final selected = {
        'title': 'Milk',
        'source': 'Z Store',
        'product_link': 'https://example.com/selected',
        'extracted_price': 10,
        'total_price': 20,
        'match_score': .95,
      };
      final alternative = {
        'title': 'Milk',
        'source': 'A Store',
        'product_link': 'https://example.com/alternative',
        'extracted_price': 10,
        'total_price': 30,
        'match_score': .85,
      };
      final offers = cheapestShoppingOffers({
        'offers': [selected, alternative],
        'best_offer': selected,
      });
      expect(offers.map((offer) => offer['source']), ['Z Store', 'A Store']);
      expect(offers.first['total_price'], 20);
    },
  );

  test(
    'offer aliases and old history choose at most two positive listed prices',
    () {
      final item = <String, dynamic>{
        'best_offer': {
          'title': 'Costliest',
          'store': 'Old store',
          'price': 30,
          'product_url': 'https://old.example/high',
        },
        'offers': [
          {
            'title': 'Second',
            'source': 'New store',
            'extracted_price': 10,
            'total_price': 10,
            'product_link': 'https://new.example/second',
          },
          {
            'title': 'First',
            'store': 'Old store',
            'price': 5,
            'total_price': 50,
            'product_url': 'https://old.example/first',
          },
          {
            'title': 'Third',
            'store': 'Old store',
            'price': 20,
            'product_url': 'https://old.example/third',
          },
          {'title': 'Missing price', 'total_price': 1, 'source': 'Unknown'},
          {'title': 'Zero price', 'extracted_price': 0},
        ],
      };
      final offers = cheapestShoppingOffers(item);
      expect(offers.map((offer) => offer['title']), ['First', 'Second']);
      expect(offers.first['extracted_price'], 5);
      expect(offers.first['source'], 'Old store');
      expect(offers.first['product_link'], 'https://old.example/first');
      expect(
        sourceIconUri('https://serpapi.com/searches/abc/images/hash.png'),
        isNotNull,
      );
      expect(
        sourceIconUri('https://serpapi.com/search.json?api_key=secret'),
        isNull,
      );
      expect(
        sourceIconUri(
          'https://serpapi.com/searches/abc/images/hash.png?api_key=secret',
        ),
        isNull,
      );
      expect(sourceIconUri('http://127.0.0.1/icon.png'), isNull);
    },
  );

  testWidgets(
    'two lowest cards show listing fields and open supplied links without seller lookup',
    (tester) async {
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
      final result = shoppingResult();
      result['warnings'] = ['combined_search_limited_coverage'];
      final item =
          (result['recommendations'] as List).first as Map<String, dynamic>;
      final first = <String, dynamic>{
        'title': 'First listed product',
        'source': 'First source',
        'store': 'Legacy source ignored',
        'source_icon': 'http://127.0.0.1/blocked.png',
        'extracted_price': 5,
        'price': 99,
        'total_price': 50,
        'product_link': 'https://www.google.com/shopping/product/123',
        'product_url': 'https://legacy.example/wrong',
        'link_kind': 'shopping',
        'shop_lookup_token': 'do-not-resolve',
        'broad_match': true,
      };
      final second = <String, dynamic>{
        'title': 'Second listed product',
        'source': 'Second source',
        'extracted_price': 10,
        'product_link': 'https://second.example/product',
        'broad_match': true,
      };
      item['best_offer'] = first;
      item['offers'] = [
        {
          'title': 'Third excluded product',
          'source': 'Third source',
          'extracted_price': 20,
          'product_link': 'https://third.example/product',
        },
        second,
        first,
      ];
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: RecommendationResultsPage(
            result: RecommendationResult.fromJson(result),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('shopping-offer-item-1-0')).hitTestable(),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('First listed product'), findsOneWidget);
      expect(find.text('Second listed product'), findsOneWidget);
      expect(find.text('Third excluded product'), findsNothing);
      expect(find.text('First source'), findsOneWidget);
      expect(find.text('Legacy source ignored'), findsNothing);
      expect(
        find.byKey(const ValueKey('source-icon-fallback-First source')),
        findsOneWidget,
      );
      expect(find.text('5.00 SAR'), findsOneWidget);
      expect(find.text('For the required quantity: 50.00 SAR'), findsOneWidget);
      expect(find.text('Other offers'), findsNothing);
      expect(
        tester.getTopLeft(find.text('First listed product')).dy,
        lessThan(tester.getTopLeft(find.text('Second listed product')).dy),
      );
      expect(launched, isEmpty);
      await tester.tap(
        find.byKey(const ValueKey('shopping-offer-item-1-0')).hitTestable(),
      );
      await tester.pumpAndSettle();
      expect(launched, ['https://www.google.com/shopping/product/123']);
      expect(find.text('Finding the online shop…'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  test('too-long combined list produces an actionable review error', () async {
    final service = RecommendationService(
      baseUrl: 'http://127.0.0.1:5000',
      clientFactory:
          () => MockClient(
            (_) async => http.Response(
              '{"success":false,"code":"combined_query_too_long"}',
              422,
            ),
          ),
    );
    await expectLater(
      service.search(
        mode: 'shopping-list',
        products: [
          ReviewProduct({'id': 'a', 'name': 'Item', 'quantity': 1}),
        ],
      ),
      throwsA(
        isA<RecommendationApiException>().having(
          (error) => error.message,
          'message',
          'This list is too long for one search. Select fewer items and try again.',
        ),
      ),
    );
  });

  test(
    'currencies are never ranked against each other and unknown labels stay ordered',
    () {
      Map<String, dynamic> offer(
        String title,
        double price,
        String? currency, {
        String? label,
      }) => {
        'title': title,
        'source': 'Store',
        'product_link': 'https://store.example/$title',
        'extracted_price': price,
        'currency': currency,
        'price_label': label,
      };
      final mixed = cheapestShoppingOffers({
        'offers': [offer('Dollar', 100, 'USD'), offer('Riyal', 1, 'SAR')],
      });
      expect(mixed.map((o) => o['title']), ['Dollar', 'Riyal']);
      final unknown = cheapestShoppingOffers({
        'offers': [
          offer('Unknown-first', 444.99, null, label: r'$444.99'),
          offer('Unknown-second', 1, null, label: r'$1.00'),
        ],
      });
      expect(unknown.map((o) => o['title']), [
        'Unknown-first',
        'Unknown-second',
      ]);
      expect(listedOfferPriceText(unknown.first), r'$444.99');
      expect(shoppingOfferCurrency(unknown.first), isNull);
      final known = cheapestShoppingOffers({
        'offers': [offer('Higher', 100, 'USD'), offer('Lower', 50, 'USD')],
      });
      expect(known.map((o) => o['title']), ['Lower', 'Higher']);
      expect(listedOfferPriceText(known.first), '50.00 USD');
      expect(
        shoppingOfferCurrency({'price': 10}),
        'SAR',
      ); // Legacy SAR-only history.
      expect(shoppingOfferCurrency({'price': 10, 'currency': null}), isNull);
    },
  );

  testWidgets(
    'foreign and ambiguous prices remain visible without SAR relabeling or a false total',
    (tester) async {
      final result = shoppingResult();
      result['warnings'] = ['shopping_currency_not_comparable'];
      result['summary'] = <String, dynamic>{
        'original_total': null,
        'shopping_total': null,
        'found_items': 1,
        'total_items': 1,
        'shopping_partial': false,
        'shopping_estimate_partial': true,
        'shopping_estimated_items': 0,
        'compared_items': 0,
        'potential_savings': 0,
      };
      final item =
          (result['recommendations'] as List).first as Map<String, dynamic>;
      final unknown = <String, dynamic>{
        'title': 'Ambiguous dollar listing', 'source': 'First store',
        'extracted_price': 444.99, 'currency': null, 'price_label': r'$444.99',
        'product_link': 'https://first.example/product', 'broad_match': true,
        'total_price': 999, // Must not invent a currency for unknown totals.
      };
      final usd = <String, dynamic>{
        'title': 'Confirmed USD listing',
        'source': 'Second store',
        'extracted_price': 199,
        'currency': 'USD',
        'price_label': null,
        'product_link': 'https://second.example/product',
        'broad_match': true,
        'total_price': 597,
      };
      item['best_offer'] = unknown;
      item['offers'] = [unknown, usd];
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: RecommendationResultsPage(
            result: RecommendationResult.fromJson(result),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('See prices on product cards'), findsOneWidget);
      expect(find.textContaining('Some quantities are unknown.'), findsNothing);
      await tester.scrollUntilVisible(
        find.text(
          'Prices use different or unconfirmed currencies; no combined total is calculated.',
        ),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.text(
          'Prices use different or unconfirmed currencies; no combined total is calculated.',
        ),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('shopping-offer-item-1-0')).hitTestable(),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text(r'$444.99'), findsOneWidget);
      expect(find.text('199.00 USD'), findsOneWidget);
      expect(find.text('Currency unconfirmed'), findsOneWidget);
      expect(
        find.text('For the required quantity: 597.00 USD'),
        findsOneWidget,
      );
      expect(find.textContaining('999.00'), findsNothing);
      expect(find.textContaining('444.99 SAR'), findsNothing);
      expect(find.textContaining('199.00 SAR'), findsNothing);
      expect(find.textContaining('You could save'), findsNothing);
      expect(
        tester.getTopLeft(find.text('Ambiguous dollar listing')).dy,
        lessThan(tester.getTopLeft(find.text('Confirmed USD listing')).dy),
      );
      expect(tester.takeException(), isNull);
    },
  );

  test('HTML from a Flutter port returns a safe service error', () async {
    final service = RecommendationService(
      baseUrl: 'http://localhost:59612',
      clientFactory:
          () => MockClient(
            (_) async => http.Response(
              '<!doctype html><html><body>Flutter</body></html>',
              200,
              headers: {'content-type': 'text/html'},
            ),
          ),
    );
    await expectLater(
      service.reviewText('iPhone'),
      throwsA(
        isA<RecommendationApiException>()
            .having((error) => error.code, 'code', 'wrong_server_url')
            .having(
              (error) => error.message,
              'message',
              'The service returned an unexpected response. Please try again later.',
            ),
      ),
    );
  });

  test(
    'shopping configuration errors keep private diagnostics out of messages',
    () async {
      for (final code in [
        'serpapi_not_configured',
        'missing_serpapi_key',
        'serpapi_auth_failed',
        'price_cache_unavailable',
        'serpapi_quota_exceeded',
        'serpapi_rate_limited',
        'http://31.97.178.214:5001/private-trace',
      ]) {
        final service = RecommendationService(
          baseUrl: deployedInvoiceApiUrl,
          clientFactory:
              () => MockClient(
                (_) async => http.Response(
                  jsonEncode({
                    'success': false,
                    'code': code,
                    'message': 'SERPAPI_KEY failed at $deployedInvoiceApiUrl',
                  }),
                  503,
                ),
              ),
        );
        await expectLater(
          service.reviewText('Milk'),
          throwsA(
            isA<RecommendationApiException>()
                .having((error) => error.code, 'original diagnostic code', code)
                .having(
                  (error) => error.message,
                  'safe message',
                  isNot(
                    matches(
                      r'http|31\.97\.178\.214|SERPAPI_KEY|Flask|\.env|logs',
                    ),
                  ),
                ),
          ),
        );
      }
    },
  );
}
