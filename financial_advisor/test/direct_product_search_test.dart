import 'dart:convert';

import 'package:financial_advisor/config/flask_config.dart';
import 'package:financial_advisor/core/finance_store.dart';
import 'package:financial_advisor/core/product_search_options.dart';
import 'package:financial_advisor/core/recommendation.dart';
import 'package:financial_advisor/screens/recommendation_results.dart';
import 'package:financial_advisor/screens/recommendation_review.dart';
import 'package:financial_advisor/screens/recommendation_text.dart';
import 'package:financial_advisor/services/recommendation_service.dart';
import 'package:financial_advisor/widgets/design.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> directSearchResponse() => {
  'success': true,
  'stage': 'results',
  'mode': 'product',
  'direct_search': true,
  'query': 'Tea',
  'shopping_results': <Map<String, dynamic>>[],
  'summary': {'total_results': 0},
  'recommendations': <Map<String, dynamic>>[],
  'warnings': <String>[],
};

Widget productForm(
  FinanceStore store,
  Future<http.Response> Function(http.Request) respond, {
  String language = 'en',
}) => MaterialApp(
  theme: appTheme(),
  locale: Locale(language),
  supportedLocales: const [Locale('en'), Locale('ar')],
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  home: RecommendationTextPage(
    store: store,
    serviceFactory:
        (baseUrl) => RecommendationService(
          baseUrl: baseUrl,
          clientFactory: () => MockClient(respond),
        ),
  ),
);

String fieldText(WidgetTester tester, String key) =>
    tester.widget<TextField>(find.byKey(Key(key))).controller!.text;

String? selectedValue(WidgetTester tester, String key) =>
    tester.state<FormFieldState<String>>(find.byKey(Key(key))).value;

Future<void> chooseOption(WidgetTester tester, String key, String label) async {
  await tester.ensureVisible(find.byKey(Key(key)));
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en');
    await initializeDateFormatting('ar');
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'direct search uses one request with Saudi defaults and no AI review',
    () async {
      final requests = <http.Request>[];
      final service = RecommendationService(
        baseUrl: 'http://127.0.0.1:5000',
        clientFactory:
            () => MockClient((request) async {
              requests.add(request);
              return http.Response(jsonEncode(directSearchResponse()), 200);
            }),
      );

      final result = await service.searchProduct('  Tea  ');

      expect(requests, hasLength(1));
      expect(requests.single.method, 'POST');
      expect(requests.single.url.path, '/api/recommendations/search');
      expect(jsonDecode(requests.single.body), {
        'q': 'Tea',
        'gl': 'sa',
        'location': 'Saudi Arabia',
        'google_domain': 'google.com.sa',
        'hl': 'ar',
        'max_price': null,
      });
      expect(result.data['direct_search'], true);
      expect(result.mode, 'product');
    },
  );

  test(
    'search sends chosen country, location, language and optional maximum price',
    () async {
      final requests = <http.Request>[];
      final service = RecommendationService(
        baseUrl: deployedFlaskUrl,
        clientFactory:
            () => MockClient((request) async {
              requests.add(request);
              return http.Response(jsonEncode(directSearchResponse()), 200);
            }),
      );

      await service.searchProduct(
        'Tea',
        countryCode: 'us',
        location: 'United States',
        googleDomain: 'google.com',
        language: 'en',
        maxPrice: 100,
      );

      expect(requests, hasLength(1));
      expect(requests.single.url.origin, deployedFlaskUrl);
      expect(jsonDecode(requests.single.body), {
        'q': 'Tea',
        'gl': 'us',
        'location': 'United States',
        'google_domain': 'google.com',
        'hl': 'en',
        'max_price': 100,
      });
    },
  );

  test('a cleared maximum price is sent explicitly as unbounded', () async {
    final requests = <http.Request>[];
    final service = RecommendationService(
      baseUrl: flaskApiUrl(),
      clientFactory:
          () => MockClient((request) async {
            requests.add(request);
            return http.Response(jsonEncode(directSearchResponse()), 200);
          }),
    );
    await service.searchProduct('Tea', maxPrice: null);
    final body = jsonDecode(requests.single.body) as Map<String, dynamic>;
    expect(body.containsKey('max_price'), isTrue);
    expect(body['max_price'], isNull);
    expect(body.containsKey('sort_by'), isFalse);
  });

  for (final key in [
    ProductSearchOptions.legacyPreferenceKey,
    ProductSearchOptions.previousPreferenceKey,
  ]) {
    test(
      '$key migrates country and language without the old cap or city',
      () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          key,
          jsonEncode({
            'gl': 'us',
            'location': 'New York, United States',
            'hl': 'en',
            'max_price': 100,
          }),
        );
        final migrated = ProductSearchOptions.load(prefs);
        expect(migrated.countryCode, 'us');
        expect(migrated.location, 'United States');
        expect(migrated.googleDomain, 'google.com');
        expect(migrated.language, 'en');
        expect(migrated.maxPrice, isNull);
        await migrated.save(prefs);
        expect(ProductSearchOptions.load(prefs).maxPrice, isNull);
        await const ProductSearchOptions(maxPrice: 250.5).save(prefs);
        expect(ProductSearchOptions.load(prefs).maxPrice, 250.5);
        await const ProductSearchOptions().save(prefs);
        expect(ProductSearchOptions.load(prefs).maxPrice, isNull);
        // Old saved options cannot override a choice made in the simplified form.
        expect(prefs.containsKey(key), isTrue);
      },
    );
  }

  test(
    'current saved settings derive location from country and keep explicit cap',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        ProductSearchOptions.preferenceKey,
        jsonEncode({
          'gl': 'sa',
          'location': 'Riyadh, Saudi Arabia',
          'hl': 'ar',
          'max_price': 250.5,
        }),
      );
      expect(ProductSearchOptions.load(prefs).maxPrice, 250.5);
      expect(ProductSearchOptions.load(prefs).location, 'Saudi Arabia');
    },
  );

  test(
    'invalid names and prices are rejected without making requests',
    () async {
      var calls = 0;
      final service = RecommendationService(
        baseUrl: flaskApiUrl(),
        clientFactory:
            () => MockClient((request) async {
              calls++;
              return http.Response(jsonEncode(directSearchResponse()), 200);
            }),
      );
      for (final input in ['', '   ', 'x' * 401, 'Tea\nMilk', 'Tea\u0000']) {
        await expectLater(
          service.searchProduct(input),
          throwsA(isA<RecommendationApiException>()),
          reason:
              'A product name must be a single nonempty line within its limit.',
        );
      }
      for (final price in [
        0.0,
        -1.0,
        double.infinity,
        double.nan,
        12.345,
        1000000000.0,
        1000000001.0,
      ]) {
        await expectLater(
          service.searchProduct('Tea', maxPrice: price),
          throwsA(isA<RecommendationApiException>()),
        );
      }
      expect(calls, 0);
    },
  );

  test('quota failure is surfaced safely without an automatic retry', () async {
    var calls = 0;
    final service = RecommendationService(
      baseUrl: flaskApiUrl(),
      clientFactory:
          () => MockClient((request) async {
            calls++;
            return http.Response(
              jsonEncode({
                'success': false,
                'code': 'serpapi_quota_exceeded',
                'message':
                    'Private upstream diagnostics should not reach the UI',
              }),
              429,
            );
          }),
    );
    await expectLater(
      service.searchProduct('Tea'),
      throwsA(
        isA<RecommendationApiException>()
            .having((error) => error.code, 'code', 'serpapi_quota_exceeded')
            .having(
              (error) => error.message,
              'safe message',
              'Price search is busy. Please try again later.',
            ),
      ),
    );
    expect(calls, 1);
  });

  test('unsupported countries are rejected before contacting Flask', () async {
    var calls = 0;
    final service = RecommendationService(
      baseUrl: flaskApiUrl(),
      clientFactory:
          () => MockClient((request) async {
            calls++;
            return http.Response(jsonEncode(directSearchResponse()), 200);
          }),
    );
    for (final country in productSearchCountries.where(
      (country) => !country.shoppingSupported,
    )) {
      await expectLater(
        service.searchProduct(
          'Tea',
          countryCode: country.code,
          location: country.name,
          googleDomain: country.domain,
        ),
        throwsA(
          isA<RecommendationApiException>().having(
            (error) => error.code,
            'code',
            'unsupported_search_country',
          ),
        ),
      );
    }
    expect(calls, 0);
  });

  test('invalid search settings never start a network request', () async {
    var calls = 0;
    final service = RecommendationService(
      baseUrl: flaskApiUrl(),
      clientFactory:
          () => MockClient((request) async {
            calls++;
            return http.Response(jsonEncode(directSearchResponse()), 200);
          }),
    );
    for (final search in <Future<void> Function()>[
      () async => service.searchProduct('Tea', location: ''),
      () async =>
          service.searchProduct('Tea', location: 'Riyadh\nSaudi Arabia'),
      () async => service.searchProduct('Tea', countryCode: 'Saudi Arabia'),
      () async =>
          service.searchProduct('Tea', googleDomain: 'https://google.com'),
      () async => service.searchProduct('Tea', language: 'invalid'),
    ]) {
      await expectLater(search(), throwsA(isA<RecommendationApiException>()));
    }
    expect(calls, 0);
  });

  test('unreadable saved search settings restore Saudi defaults', () async {
    final prefs = await SharedPreferences.getInstance();
    for (final value in [
      'not-json',
      '[]',
      '{"gl":"invalid","location":"","max_price":-1}',
      '{"gl":"sa","location":"Saudi Arabia","max_price":12.345}',
      '{"gl":"sa","location":"Saudi Arabia","max_price":1000000000}',
    ]) {
      await prefs.setString(ProductSearchOptions.preferenceKey, value);
      final options = ProductSearchOptions.load(prefs);
      expect(options.countryCode, 'sa');
      expect(options.location, 'Saudi Arabia');
      expect(options.googleDomain, 'google.com.sa');
      expect(options.language, 'ar');
      expect(options.maxPrice, isNull);
    }
  });

  test(
    'an unexpected successful response cannot be treated as search results',
    () async {
      final service = RecommendationService(
        baseUrl: flaskApiUrl(),
        clientFactory:
            () => MockClient(
              (_) async => http.Response(
                jsonEncode({
                  'success': true,
                  'stage': 'review',
                  'products': [],
                }),
                200,
              ),
            ),
      );
      await expectLater(
        service.searchProduct('Tea'),
        throwsA(
          isA<RecommendationApiException>().having(
            (error) => error.code,
            'code',
            'invalid_response',
          ),
        ),
      );
    },
  );

  for (final language in ['en', 'ar']) {
    testWidgets(
      '$language form defaults to Saudi Arabic results without searching',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final store = FinanceStore(await SharedPreferences.getInstance());
        var calls = 0;
        await tester.pumpWidget(
          productForm(store, (request) async {
            calls++;
            return http.Response(jsonEncode(directSearchResponse()), 200);
          }, language: language),
        );
        await tester.pumpAndSettle();

        expect(selectedValue(tester, 'shopping-country'), 'sa');
        expect(find.byKey(const Key('shopping-location')), findsNothing);
        expect(selectedValue(tester, 'shopping-language'), 'ar');
        expect(fieldText(tester, 'shopping-max-price'), isEmpty);
        expect(
          tester
              .widget<TextField>(find.byKey(const Key('shopping-text-input')))
              .decoration
              ?.labelText,
          language == 'ar' ? 'اسم المنتج' : 'Product name',
        );
        expect(
          tester
              .widget<TextField>(find.byKey(const Key('shopping-text-input')))
              .decoration
              ?.hintText,
          language == 'ar' ? 'أدخل اسم المنتج' : 'Enter product name',
        );
        expect(
          find.text(
            language == 'ar'
                ? 'أدخل اسم المنتج للعثور على أسعاره في المتاجر الإلكترونية.'
                : 'Enter a product name to find prices from online stores.',
          ),
          findsOneWidget,
        );
        expect(find.byKey(const Key('review-shopping-text')), findsNothing);
        expect(
          store.prefs.getString(ProductSearchOptions.preferenceKey),
          isNull,
        );
        expect(calls, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'old capped search opens with no limit and uses the selected country',
    (tester) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        ProductSearchOptions.previousPreferenceKey,
        jsonEncode({
          'gl': 'us',
          'location': 'New York, United States',
          'hl': 'en',
          'max_price': 100,
        }),
      );
      final requests = <http.Request>[];
      await tester.pumpWidget(
        productForm(FinanceStore(prefs), (request) async {
          requests.add(request);
          return http.Response(jsonEncode(directSearchResponse()), 200);
        }),
      );
      await tester.pumpAndSettle();
      expect(selectedValue(tester, 'shopping-country'), 'us');
      expect(selectedValue(tester, 'shopping-language'), 'en');
      expect(find.byKey(const Key('shopping-location')), findsNothing);
      expect(fieldText(tester, 'shopping-max-price'), isEmpty);
      expect(requests, isEmpty);

      await tester.enterText(
        find.byKey(const Key('shopping-text-input')),
        'Tea',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(requests, hasLength(1));
      expect(jsonDecode(requests.single.body), {
        'q': 'Tea',
        'gl': 'us',
        'location': 'United States',
        'google_domain': 'google.com',
        'hl': 'en',
        'max_price': null,
      });
      expect(ProductSearchOptions.load(prefs).maxPrice, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'changing filters does not search until submitted and choices survive reopening',
    (tester) async {
      final store = FinanceStore(await SharedPreferences.getInstance());
      final requests = <http.Request>[];
      Future<http.Response> respond(http.Request request) async {
        requests.add(request);
        return http.Response(jsonEncode(directSearchResponse()), 200);
      }

      await tester.pumpWidget(productForm(store, respond));
      await tester.enterText(
        find.byKey(const Key('shopping-text-input')),
        'Tea',
      );
      await chooseOption(tester, 'shopping-country', 'United States');
      expect(find.byKey(const Key('shopping-location')), findsNothing);
      await chooseOption(tester, 'shopping-language', 'English');
      await tester.ensureVisible(find.byKey(const Key('shopping-max-price')));
      await tester.enterText(
        find.byKey(const Key('shopping-max-price')),
        '100',
      );
      await tester.pumpAndSettle();
      expect(requests, isEmpty);
      expect(store.prefs.getString(ProductSearchOptions.preferenceKey), isNull);

      await tester.ensureVisible(find.byKey(const Key('search-product')));
      await tester.tap(find.byKey(const Key('search-product')));
      await tester.pumpAndSettle();

      expect(requests, hasLength(1));
      expect(requests.single.url.path, '/api/recommendations/search');
      expect(jsonDecode(requests.single.body), {
        'q': 'Tea',
        'gl': 'us',
        'location': 'United States',
        'google_domain': 'google.com',
        'hl': 'en',
        'max_price': 100,
      });
      expect(find.byType(RecommendationResultsPage), findsOneWidget);
      expect(find.byType(RecommendationReviewPage), findsNothing);
      expect(RecommendationHistory(store.prefs).read(), hasLength(1));
      expect(store.entries, isEmpty);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.pumpWidget(productForm(store, respond));
      await tester.pumpAndSettle();
      expect(selectedValue(tester, 'shopping-country'), 'us');
      expect(find.byKey(const Key('shopping-location')), findsNothing);
      expect(selectedValue(tester, 'shopping-language'), 'en');
      expect(double.parse(fieldText(tester, 'shopping-max-price')), 100);
      expect(fieldText(tester, 'shopping-text-input'), isEmpty);
      expect(requests, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('invalid maximum price keeps the form open without a search', (
    tester,
  ) async {
    final store = FinanceStore(await SharedPreferences.getInstance());
    var calls = 0;
    await tester.pumpWidget(
      productForm(store, (request) async {
        calls++;
        return http.Response(jsonEncode(directSearchResponse()), 200);
      }),
    );
    await tester.enterText(find.byKey(const Key('shopping-text-input')), 'Tea');
    for (final price in ['-1', '12.345', '1000000000']) {
      await tester.ensureVisible(find.byKey(const Key('shopping-max-price')));
      await tester.enterText(
        find.byKey(const Key('shopping-max-price')),
        price,
      );
      await tester.ensureVisible(find.byKey(const Key('search-product')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('search-product')));
      await tester.pumpAndSettle();

      expect(calls, 0);
      expect(find.byType(RecommendationTextPage), findsOneWidget);
      expect(find.byType(RecommendationResultsPage), findsNothing);
      expect(
        find.text('Check the search country, language and maximum price.'),
        findsOneWidget,
      );
      expect(store.prefs.getString(ProductSearchOptions.preferenceKey), isNull);
      expect(tester.takeException(), isNull);
    }
  });

  for (final language in ['en', 'ar']) {
    testWidgets(
      '$language saved Kuwait choice is explained without a paid search',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final prefs = await SharedPreferences.getInstance();
        await const ProductSearchOptions(countryCode: 'kw').save(prefs);
        final requests = <http.Request>[];
        await tester.pumpWidget(
          productForm(FinanceStore(prefs), (request) async {
            requests.add(request);
            return http.Response(jsonEncode(directSearchResponse()), 200);
          }, language: language),
        );
        await tester.pumpAndSettle();
        expect(selectedValue(tester, 'shopping-country'), 'kw');
        expect(
          find.text(
            language == 'ar'
                ? 'البحث عن المنتجات غير متاح في هذا البلد. يرجى اختيار بلد آخر.'
                : 'Product search is unavailable in this country. Please choose another country.',
          ),
          findsOneWidget,
        );
        await tester.enterText(
          find.byKey(const Key('shopping-text-input')),
          'Tea',
        );
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
        expect(requests, isEmpty);
        expect(find.byType(RecommendationResultsPage), findsNothing);
        await tester.scrollUntilVisible(
          find.byKey(const Key('search-product')),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(
          tester
              .widget<FilledButton>(find.byKey(const Key('search-product')))
              .onPressed,
          isNull,
        );

        await chooseOption(
          tester,
          'shopping-country',
          language == 'ar'
              ? 'الإمارات العربية المتحدة'
              : 'United Arab Emirates',
        );
        await tester.scrollUntilVisible(
          find.byKey(const Key('search-product')),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(
          tester
              .widget<FilledButton>(find.byKey(const Key('search-product')))
              .onPressed,
          isNotNull,
        );
        expect(requests, isEmpty);
        await tester.ensureVisible(find.byKey(const Key('search-product')));
        await tester.tap(find.byKey(const Key('search-product')));
        await tester.pumpAndSettle();
        expect(requests, hasLength(1));
        expect(jsonDecode(requests.single.body), {
          'q': 'Tea',
          'gl': 'ae',
          'location': 'United Arab Emirates',
          'google_domain': 'google.ae',
          'hl': 'ar',
          'max_price': null,
        });
        expect(ProductSearchOptions.load(prefs).countryCode, 'ae');
        expect(tester.takeException(), isNull);
      },
    );
  }
}
