import 'dart:convert';

import 'package:financial_advisor/config/flask_config.dart';
import 'package:financial_advisor/core/finance_store.dart';
import 'package:financial_advisor/core/recommendation.dart';
import 'package:financial_advisor/services/invoice_service.dart';
import 'package:financial_advisor/services/recommendation_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the selected target controls the default Flask endpoint', () {
    expect(
      flaskApiUrl(platform: TargetPlatform.windows, isWeb: false),
      activeFlaskTarget == FlaskTarget.local ? localFlaskUrl : deployedFlaskUrl,
    );
  });

  test('local Flask uses loopback on desktop, iOS, and web', () {
    for (final platform in TargetPlatform.values) {
      expect(
        flaskApiUrl(target: FlaskTarget.local, platform: platform, isWeb: true),
        localFlaskUrl,
      );
      if (platform != TargetPlatform.android) {
        expect(
          flaskApiUrl(
            target: FlaskTarget.local,
            platform: platform,
            isWeb: false,
          ),
          localFlaskUrl,
        );
      }
    }
  });

  test(
    'native Android maps loopback to its host while keeping protocol and port',
    () {
      for (final host in ['localhost', 'LOCALHOST', '127.0.0.1', '[::1]']) {
        for (final scheme in ['http', 'https']) {
          expect(
            flaskApiUrl(
              target: FlaskTarget.local,
              localUrl: '$scheme://$host:5050',
              platform: TargetPlatform.android,
              isWeb: false,
            ),
            '$scheme://10.0.2.2:5050',
          );
        }
      }
    },
  );

  test('a physical-device LAN address is preserved on all platforms', () {
    for (final platform in TargetPlatform.values) {
      expect(
        flaskApiUrl(
          target: FlaskTarget.local,
          localUrl: 'http://192.168.1.40:5050',
          platform: platform,
          isWeb: false,
        ),
        'http://192.168.1.40:5050',
      );
    }
  });

  test('deployed endpoint ignores local values and Android remapping', () {
    for (final url in [
      deployedFlaskUrl,
      'https://api.example.com:8443',
      'http://localhost:5050',
    ]) {
      for (final platform in TargetPlatform.values) {
        expect(
          flaskApiUrl(
            target: FlaskTarget.deployed,
            localUrl: 'http://unused.example.com:5000',
            deployedUrl: url,
            platform: platform,
            isWeb: false,
          ),
          url,
        );
      }
    }
  });

  test(
    'stale saved server choices cannot override config or change financial data',
    () async {
      for (final oldUrl in [
        deployedFlaskUrl,
        'http://localhost:59612',
        'https://old-api.example.com',
      ]) {
        for (final migrated in [false, true]) {
          SharedPreferences.setMockInitialValues({
            'invoice_api_url': oldUrl,
            'invoice_api_deployed_v1': migrated,
          });
          final prefs = await SharedPreferences.getInstance();
          final store = FinanceStore(prefs);
          await store.saveEntry(
            Entry(
              id: 'existing-expense',
              merchant: 'Grocer',
              cents: 2450,
              date: DateTime(2026, 9, 22),
              category: 'Food',
            ),
          );
          final savedData = prefs.getString('numo_v1');

          expect(
            flaskApiUrl(
              target: FlaskTarget.local,
              platform: TargetPlatform.windows,
              isWeb: false,
            ),
            localFlaskUrl,
          );
          expect(flaskApiUrl(target: FlaskTarget.deployed), deployedFlaskUrl);
          await prefs.reload();
          final reloaded = FinanceStore(prefs);
          await reloaded.load();

          expect(reloaded.error, isNull);
          expect(reloaded.entries.single.id, 'existing-expense');
          expect(reloaded.entries.single.cents, 2450);
          expect(prefs.getString('numo_v1'), savedData);
          expect(prefs.getString('invoice_api_url'), oldUrl);
          expect(
            flaskApiUrl(
              target: FlaskTarget.local,
              platform: TargetPlatform.windows,
              isWeb: false,
            ),
            localFlaskUrl,
          );
          store.dispose();
          reloaded.dispose();
        }
      }
    },
  );

  for (final target in FlaskTarget.values) {
    test(
      '$target routes invoice, product and shopping-list requests to one Flask origin',
      () async {
        final url = flaskApiUrl(
          target: target,
          platform: TargetPlatform.windows,
          isWeb: false,
        );
        final expectedOrigin =
            target == FlaskTarget.local ? localFlaskUrl : deployedFlaskUrl;
        final paths = <String>[];
        http.Client clientFactory() => MockClient((request) async {
          expect(request.url.origin, expectedOrigin);
          expect(request.method, 'POST');
          paths.add(request.url.path);
          if (request.url.path == '/api/invoice/analyze') {
            return http.Response(
              jsonEncode({
                'success': true,
                'invoice': {
                  'merchant_name': 'Grocer',
                  'total': 24.5,
                  'currency': 'SAR',
                  'items': [],
                },
              }),
              200,
            );
          }
          final confirmed =
              request.headers['content-type']?.contains('application/json') ==
                  true &&
              (jsonDecode(request.body) as Map)['confirmed'] == true;
          return http.Response(
            jsonEncode({
              'success': true,
              'stage': confirmed ? 'results' : 'review',
              'mode': request.url.path.split('/').last,
              if (confirmed) ...{
                'summary': {},
                'recommendations': [],
              } else
                'products': [
                  {'id': 'milk', 'name': 'Milk', 'quantity': 1},
                ],
            }),
            200,
          );
        });
        final image = Uint8List.fromList([255, 216, 255, 0]);
        final invoice = InvoiceService(
          baseUrl: url,
          clientFactory: clientFactory,
        );
        final shopping = RecommendationService(
          baseUrl: url,
          clientFactory: clientFactory,
        );
        expect(
          (await invoice.analyze(image, 'receipt.jpg')).invoice.totalCents,
          2450,
        );
        await shopping.reviewText('Milk');
        await shopping.reviewText('Milk\nCoffee', shoppingList: true);
        await shopping.identify(image, 'product.jpg');
        await shopping.readShoppingImage(image, 'list.jpg');
        for (final mode in ['product', 'shopping-list', 'invoice']) {
          await shopping.search(
            mode: mode,
            products: [
              ReviewProduct({'id': 'milk', 'name': 'Milk', 'quantity': 1}),
            ],
          );
        }
        expect(paths, [
          '/api/invoice/analyze',
          '/api/recommendations/product',
          '/api/recommendations/shopping-list',
          '/api/recommendations/product',
          '/api/recommendations/shopping-list',
          '/api/recommendations/product',
          '/api/recommendations/shopping-list',
          '/api/recommendations/invoice',
        ]);
      },
    );
  }
}
