import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:financial_advisor/core/finance_store.dart';
import 'package:financial_advisor/core/invoice.dart';
import 'package:financial_advisor/core/recommendation.dart';
import 'package:financial_advisor/l10n/app_language.dart';
import 'package:financial_advisor/screens/recommendation_review.dart';
import 'package:financial_advisor/screens/recommendation_results.dart';
import 'package:financial_advisor/services/recommendation_service.dart';
import 'package:financial_advisor/widgets/design.dart';

Map<String, dynamic> resultJson() => {
  'success': true,
  'stage': 'results',
  'mode': 'invoice',
  'searched_at': '2026-09-08T08:00:00Z',
  'summary': {
    'original_total': 115,
    'comparable_original_total': 100,
    'recommended_total': 80,
    'potential_savings': 20,
    'saving_percentage': 20,
    'compared_items': 1,
    'total_items': 2,
    'partial': true,
  },
  'recommendations': [
    {
      'item_id': 'item-0',
      'item_name': 'Acme Coffee 250g',
      'quantity': 2,
      'original': {'unit_price': 50, 'total_price': 100},
      'best_offer': <String, dynamic>{
        'title': 'Acme Coffee 250g',
        'store': 'Test Store',
        'price': 40,
        'unit_price': 40,
        'total_price': 80,
        'currency': 'SAR',
        'product_url': 'https://example.com/coffee',
        'match_score': .95,
        'match_label': 'Strong Match',
        'purchase_quantity': 2,
      },
      'offers': [],
      'saving': {'amount': 20, 'percentage': 20, 'level': 'Excellent Saving'},
    },
  ],
  'warnings': [],
};

class _HistoryPreferences implements SharedPreferences {
  final Map<String, String> cached;
  final Map<String, String> durable;
  var writes = 0;
  var reloads = 0;
  var failWrites = false;
  var throwOnWrite = false;
  var failReload = false;

  _HistoryPreferences(Map<String, String> initial)
    : cached = Map.of(initial),
      durable = Map.of(initial);

  @override
  String? getString(String key) => cached[key];

  @override
  Future<bool> setString(String key, String value) async {
    writes++;
    // Match the real plugin: its cache changes before persistence is attempted.
    cached[key] = value;
    if (throwOnWrite) throw StateError('Storage unavailable');
    if (failWrites) return false;
    durable[key] = value;
    return true;
  }

  @override
  Future<void> reload() async {
    reloads++;
    if (failReload) throw StateError('Storage unavailable');
    cached
      ..clear()
      ..addAll(durable);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

String _savedComparisons() => jsonEncode({
  'version': 1,
  'entries': [
    for (final id in ['newest', 'middle', 'oldest'])
      {
        'id': id,
        'saved_at': '2026-09-23T12:00:00',
        'expense_id': 'expense-$id',
        // Identical search queries must still be independently deletable.
        'result': {...resultJson(), 'query': 'Tea'},
      },
  ],
});

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en');
  });
  test(
    'product recognition is review-only; confirmed search sends edited identity through Flask',
    () async {
      final requests = <http.Request>[];
      final service = RecommendationService(
        baseUrl: 'http://127.0.0.1:5000',
        clientFactory:
            () => MockClient((request) async {
              requests.add(request);
              if (request.headers['content-type']!.contains('multipart')) {
                expect(request.url.path, '/api/recommendations/product');
                expect(request.body, contains('name="optional_current_price"'));
                return http.Response(
                  jsonEncode({
                    'success': true,
                    'stage': 'review',
                    'mode': 'product',
                    'products': [
                      {'id': 'product', 'name': 'AirPods', 'quantity': 1},
                    ],
                    'warnings': [],
                  }),
                  200,
                );
              }
              final body = jsonDecode(request.body);
              expect(body['confirmed'], true);
              expect(body['products'][0]['name'], 'Apple AirPods Pro 2 USB-C');
              expect(body.containsKey('image'), false);
              return http.Response(
                jsonEncode({...resultJson(), 'mode': 'product'}),
                200,
              );
            }),
      );
      final review = await service.identify(
        Uint8List.fromList([1, 2]),
        'photo.jpg',
        currentPrice: 849,
      );
      expect(review.products.single.name, 'AirPods');
      expect(requests.length, 1);
      await service.search(
        mode: 'product',
        products: [
          ReviewProduct({
            'id': 'product',
            'name': 'Apple AirPods Pro 2 USB-C',
            'quantity': 1,
          }),
        ],
      );
      expect(requests.length, 2);
      expect(requests.every((r) => r.url.host == '127.0.0.1'), true);
    },
  );

  test(
    'invoice confirmed search reuses extracted invoice and preserves metadata',
    () async {
      final invoice = InvoiceModel.fromJson({
        'merchant_name': 'Store',
        'currency': 'SAR',
        'total': 100,
        'items': [
          {
            'name': 'Coffee',
            'brand': 'Acme',
            'size_value': 250,
            'size_unit': 'g',
            'pack_size': 2,
            'condition': 'new',
            'confidence': .9,
            'model': 'Dark',
            'variant': 'Beans',
            'search_query': 'Acme dark coffee',
            'quantity': 1,
            'unit_price': 100,
            'total_price': 100,
            'category': 'Food',
          },
        ],
      });
      final roundTrip = InvoiceModel.fromJson(
        jsonDecode(jsonEncode(invoice.toJson())),
      );
      expect(roundTrip.items.single.sizeValue, 250);
      expect(roundTrip.items.single.brand, 'Acme');
      expect(roundTrip.items.single.packSize, 2);
      final review = RecommendationReview.invoice(roundTrip);
      final service = RecommendationService(
        baseUrl: 'http://10.0.2.2:5000',
        clientFactory:
            () => MockClient((request) async {
              expect(request.url.path, '/api/recommendations/invoice');
              expect(
                request.headers['content-type'],
                contains('application/json'),
              );
              final body = jsonDecode(request.body);
              expect(body['invoice']['total'], 100);
              expect(body['products'][0]['size_unit'], 'g');
              expect(body.containsKey('image'), false);
              return http.Response(jsonEncode(resultJson()), 200);
            }),
      );
      final result = await service.search(
        mode: review.mode,
        products: review.products,
        invoice: roundTrip,
      );
      expect(result.summary['potential_savings'], 20);
      expect(InvoiceItemModel.fromJson({'name': 'Legacy'}).brand, isNull);
    },
  );

  test(
    'service rejects invalid endpoints and malformed data and maps missing key',
    () async {
      var requests = 0;
      final invalid = RecommendationService(
        baseUrl: 'https://api.example.com/not-an-origin',
        clientFactory:
            () => MockClient((_) async {
              requests++;
              return http.Response('{}', 200);
            }),
      );
      await expectLater(
        invalid.search(mode: 'product', products: []),
        throwsA(
          isA<RecommendationApiException>().having(
            (e) => e.code,
            'code',
            'invalid_url',
          ),
        ),
      );
      expect(requests, 0);
      final missing = RecommendationService(
        baseUrl: 'http://127.0.0.1:5000',
        clientFactory:
            () => MockClient(
              (_) async => http.Response(
                '{"success":false,"code":"serpapi_not_configured"}',
                503,
              ),
            ),
      );
      await expectLater(
        missing.search(mode: 'product', products: []),
        throwsA(
          isA<RecommendationApiException>().having(
            (e) => e.message,
            'message',
            'Price search is temporarily unavailable. Please try again later.',
          ),
        ),
      );
      final malformed = RecommendationService(
        baseUrl: 'http://127.0.0.1:5000',
        clientFactory:
            () => MockClient(
              (_) async =>
                  http.Response('{"success":true,"stage":"results"}', 200),
            ),
      );
      await expectLater(
        malformed.search(mode: 'product', products: []),
        throwsA(
          isA<RecommendationApiException>().having(
            (e) => e.code,
            'code',
            'invalid_response',
          ),
        ),
      );
    },
  );

  test(
    'history is bounded, reloadable and separate from expense ledger',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = FinanceStore(prefs);
      await store.start(
        userName: 'Alex',
        selectedCurrency: 'SAR',
        useDemo: false,
      );
      final ledger = prefs.getString('numo_v1');
      final history = RecommendationHistory(prefs);
      for (var i = 0; i < 23; i++) {
        await history.save(
          RecommendationResult.fromJson(resultJson()),
          expenseId: 'expense-1',
        );
      }
      final reloaded =
          RecommendationHistory(await SharedPreferences.getInstance()).read();
      expect(reloaded.length, RecommendationHistory.maxEntries);
      expect(reloaded.first.expenseId, 'expense-1');
      expect(reloaded.first.result.summary['potential_savings'], 20);
      expect(prefs.getString('numo_v1'), ledger);
      expect(store.entries, isEmpty);
      await history.clear();
      expect(history.read(), isEmpty);
      expect(prefs.getString('numo_v1'), ledger);
    },
  );

  test(
    'deleting one comparison preserves other snapshots and expenses',
    () async {
      SharedPreferences.setMockInitialValues({
        RecommendationHistory.preferenceKey: _savedComparisons(),
        'numo_v1': 'unchanged expense ledger',
      });
      final prefs = await SharedPreferences.getInstance();
      final history = RecommendationHistory(prefs);
      final before = history.read().map((entry) => entry.toJson()).toList();

      await history.delete('middle');
      await prefs.reload();
      final remaining = RecommendationHistory(prefs).read();
      expect(remaining.map((entry) => entry.id), ['newest', 'oldest']);
      expect(remaining.map((entry) => entry.toJson()), [before[0], before[2]]);
      expect(prefs.getString('numo_v1'), 'unchanged expense ledger');

      await history.delete('newest');
      await history.delete('oldest');
      await prefs.reload();
      expect(RecommendationHistory(prefs).read(), isEmpty);
      expect(prefs.getString('numo_v1'), 'unchanged expense ledger');
    },
  );

  test(
    'deleting an absent ID leaves history unchanged without writing',
    () async {
      for (final raw in [null, _savedComparisons()]) {
        final prefs = _HistoryPreferences({
          if (raw != null) RecommendationHistory.preferenceKey: raw,
        });
        await RecommendationHistory(prefs).delete('missing');
        expect(prefs.writes, 0);
        expect(prefs.getString(RecommendationHistory.preferenceKey), raw);
      }
    },
  );

  test('deleting rejects unreadable history without replacing it', () async {
    final malformedTail =
        jsonDecode(_savedComparisons()) as Map<String, dynamic>;
    final entries = malformedTail['entries'] as List;
    while (entries.length < RecommendationHistory.maxEntries) {
      entries.add(entries.first);
    }
    entries.add({'id': 'unreadable'});
    for (final raw in [
      '{broken',
      '{"version":2,"entries":[]}',
      jsonEncode(malformedTail),
    ]) {
      final prefs = _HistoryPreferences({
        RecommendationHistory.preferenceKey: raw,
      });
      final history = RecommendationHistory(prefs);
      await expectLater(history.delete('middle'), throwsStateError);
      expect(history.error, isNotNull);
      expect(prefs.writes, 0);
      expect(prefs.getString(RecommendationHistory.preferenceKey), raw);
    }
  });

  test(
    'deleting preserves snapshots beyond the visible history limit',
    () async {
      final json = jsonDecode(_savedComparisons()) as Map<String, dynamic>;
      final entries = json['entries'] as List;
      for (var i = 0; i < RecommendationHistory.maxEntries; i++) {
        entries.add({
          ...entries.first as Map<String, dynamic>,
          'id': 'older-$i',
        });
      }
      final prefs = _HistoryPreferences({
        RecommendationHistory.preferenceKey: jsonEncode(json),
      });
      await RecommendationHistory(prefs).delete('middle');
      final saved = jsonDecode(
        prefs.getString(RecommendationHistory.preferenceKey)!,
      );
      expect(
        saved['entries'],
        entries.where((entry) => entry['id'] != 'middle').toList(),
      );
    },
  );

  for (final throws in [false, true]) {
    for (final reloadFails in [false, true]) {
      test(
        'failed deletion retains cached history for retry (throws: $throws, reload fails: $reloadFails)',
        () async {
          final raw = _savedComparisons();
          final prefs =
              _HistoryPreferences({
                  RecommendationHistory.preferenceKey: raw,
                  'numo_v1': 'unchanged expense ledger',
                })
                ..failWrites = true
                ..throwOnWrite = throws
                ..failReload = reloadFails;
          final history = RecommendationHistory(prefs);
          await expectLater(history.delete('middle'), throwsStateError);
          expect(prefs.reloads, 1);
          expect(prefs.getString(RecommendationHistory.preferenceKey), raw);
          expect(prefs.durable[RecommendationHistory.preferenceKey], raw);
          expect(history.read().map((entry) => entry.id), [
            'newest',
            'middle',
            'oldest',
          ]);
          expect(prefs.getString('numo_v1'), 'unchanged expense ledger');

          prefs
            ..failWrites = false
            ..throwOnWrite = false
            ..failReload = false;
          await history.delete('middle');
          await prefs.reload();
          expect(history.read().map((entry) => entry.id), ['newest', 'oldest']);
        },
      );
    }
  }

  testWidgets(
    'review waits for confirmation, sends edited price and keeps expenses unchanged',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final store = FinanceStore(await SharedPreferences.getInstance());
      var calls = 0;
      final service = RecommendationService(
        baseUrl: 'http://127.0.0.1:5000',
        clientFactory:
            () => MockClient((request) async {
              calls++;
              final json = jsonDecode(request.body);
              expect(json['products'][0]['name'], 'Corrected Coffee');
              expect(json['products'][0]['unit_price'], 90);
              expect(json['products'][0]['total_price'], 90);
              expect(json['products'][0]['quantity'], 1);
              return http.Response(
                jsonEncode({...resultJson(), 'mode': 'product'}),
                200,
              );
            }),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: RecommendationReviewPage(
            store: store,
            service: service,
            review: RecommendationReview(
              mode: 'product',
              products: [
                ReviewProduct({
                  'id': 'product',
                  'name': 'Coffee',
                  'quantity': 1,
                  'unit_price': 100,
                }),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(calls, 0);
      await tester.enterText(
        find.byKey(const ValueKey('product-name')),
        'Corrected Coffee',
      );
      await tester.enterText(
        find.byKey(const ValueKey('product-unit_price')),
        '90',
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
      expect(RecommendationHistory(store.prefs).read().length, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Arabic mobile results show partial totals and no invented offer',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final json = resultJson();
      json['recommendations'] = [
        {
          'item_name': 'حليب',
          'original': {'total_price': 8},
          'best_offer': null,
          'offers': [],
          'reason': 'No reliable matching alternative was found.',
        },
      ];
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          locale: const Locale('ar'),
          supportedLocales: const [Locale('en'), Locale('ar')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: RecommendationResultsPage(
            result: RecommendationResult.fromJson(json),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(translate('Comparable item total', 'ar')),
        findsOneWidget,
      );
      expect(find.text('115.00 SAR'), findsOneWidget);
      expect(find.text('100.00 SAR'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('حليب'), 300);
      expect(
        find.text(translate('No reliable cheaper alternative found.', 'ar')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      expect(safeDealUri('javascript:alert(1)'), isNull);
      expect(safeDealUri('https://user:password@example.com/'), isNull);
      expect(safeDealUri('https://example.com/product')?.host, 'example.com');
    },
  );

  test(
    'unreadable history is preserved and clear-all removes comparison snapshots',
    () async {
      SharedPreferences.setMockInitialValues({
        RecommendationHistory.preferenceKey: '{broken',
      });
      final prefs = await SharedPreferences.getInstance();
      final history = RecommendationHistory(prefs);
      expect(history.read(), isEmpty);
      expect(history.error, isNotNull);
      await expectLater(
        history.save(RecommendationResult.fromJson(resultJson())),
        throwsStateError,
      );
      expect(prefs.getString(RecommendationHistory.preferenceKey), '{broken');
      await history.clear();
      await history.save(RecommendationResult.fromJson(resultJson()));
      final store = FinanceStore(prefs);
      await store.clear();
      expect(prefs.getString(RecommendationHistory.preferenceKey), isNull);
    },
  );

  test(
    'deal links reject private hosts, credentials, provider endpoints and secrets',
    () {
      for (final url in [
        'http://localhost:5000',
        'http://127.0.0.1:5000',
        'http://10.0.0.2',
        'http://192.168.1.1',
        'http://[::1]',
        'http://printer.local',
        'http://store.example:99999',
        'https://serpapi.com/search.json',
        'https://example.com/product?api_key=secret',
        'javascript:alert(1)',
        'https://user:pass@example.com',
      ]) {
        expect(safeDealUri(url), isNull, reason: url);
      }
      expect(safeDealUri('https://store.example/product?id=123'), isNotNull);
    },
  );

  testWidgets(
    'unknown original price shows offers without zero savings or provider-failure claims',
    (tester) async {
      final json = resultJson();
      json['mode'] = 'product';
      json['summary'] = {
        'original_total': null,
        'compared_items': 0,
        'total_items': 1,
        'potential_savings': 0,
        'saving_percentage': 0,
        'recommended_total': 0,
        'comparable_original_total': 0,
        'partial': true,
      };
      json['warnings'] = [
        'listed_prices_may_exclude_shipping_or_tax',
        'match_scores_are_heuristic',
      ];
      final item =
          (json['recommendations'] as List).first as Map<String, dynamic>;
      item['status'] = 'offers_found';
      item['saving'] = {
        'amount': null,
        'percentage': null,
        'level': 'No Better Price Found',
      };
      item['original'] = {'unit_price': null, 'total_price': null};
      (item['best_offer'] as Map<String, dynamic>).addAll({
        'normalized_price': 4.5,
        'normalized_unit': 'SAR/liter',
        'original_normalized_price': null,
        'unverified_attributes': ['condition'],
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: RecommendationResultsPage(
            result: RecommendationResult.fromJson(json),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('See prices on product cards'), findsOneWidget);
      expect(find.text('You could save 0.0%'), findsNothing);
      expect(
        find.text(
          'Some searches were unavailable or skipped. Results cover only comparable items.',
        ),
        findsNothing,
      );
      await tester.scrollUntilVisible(
        find.text('Condition not verified'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('No Better Price Found'), findsNothing);
      expect(find.text('Normalized price: 4.5 SAR / liter'), findsOneWidget);
      expect(find.text('Condition not verified'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('search error keeps reviewed products available for retry', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final store = FinanceStore(await SharedPreferences.getInstance());
    final service = RecommendationService(
      baseUrl: 'http://127.0.0.1:5000',
      clientFactory:
          () => MockClient(
            (_) async => http.Response(
              '{"success":false,"code":"serpapi_not_configured"}',
              503,
            ),
          ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: RecommendationReviewPage(
          store: store,
          service: service,
          review: RecommendationReview(
            mode: 'product',
            products: [
              ReviewProduct({
                'id': 'product',
                'name': 'Apple AirPods Pro 2',
                'quantity': 1,
              }),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
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
    expect(
      find.text(
        'Price search is temporarily unavailable. Please try again later.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('SERPAPI_KEY'), findsNothing);
    expect(find.byType(RecommendationResultsPage), findsNothing);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('confirm-price-search')))
          .onPressed,
      isNotNull,
    );
    expect(store.entries, isEmpty);
    expect(tester.takeException(), isNull);
  });

  test(
    'oversized comparison never replaces existing bounded history',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final history = RecommendationHistory(prefs);
      await history.save(RecommendationResult.fromJson(resultJson()));
      final previous = prefs.getString(RecommendationHistory.preferenceKey);
      final oversized = resultJson();
      oversized['oversized_field'] = 'x' * RecommendationHistory.maxBytes;
      await expectLater(
        history.save(RecommendationResult.fromJson(oversized)),
        throwsStateError,
      );
      expect(prefs.getString(RecommendationHistory.preferenceKey), previous);
      final larger = resultJson();
      larger['extra_field'] = 'x' * (RecommendationHistory.maxBytes ~/ 3);
      for (var i = 0; i < 5; i++) {
        await history.save(RecommendationResult.fromJson(larger));
      }
      expect(
        utf8
            .encode(prefs.getString(RecommendationHistory.preferenceKey)!)
            .length,
        lessThanOrEqualTo(RecommendationHistory.maxBytes),
      );
      expect(history.read().length, 2);
    },
  );
}
