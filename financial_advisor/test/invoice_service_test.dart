import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:financial_advisor/services/invoice_service.dart';

void main() {
  final image = Uint8List.fromList([255, 216, 255, 0]);
  test(
    'multipart uploads image to Flask and parses real response contract',
    () async {
      final service = InvoiceService(
        baseUrl: defaultInvoiceApiUrl(),
        clientFactory:
            () => MockClient((request) async {
              expect(
                request.url.toString(),
                'http://31.97.178.214:5001/api/invoice/analyze',
              );
              expect(request.method, 'POST');
              expect(
                request.headers['content-type'],
                contains('multipart/form-data'),
              );
              expect(
                latin1.decode(request.bodyBytes),
                contains('name="image"'),
              );
              return http.Response(
                jsonEncode({
                  'success': true,
                  'invoice': {
                    'merchant_name': 'متجر',
                    'date': '2026-09-08',
                    'currency': 'SAR',
                    'total': 115,
                    'tax': 15,
                    'category': 'Shopping',
                    'items': [
                      {
                        'name': 'Coffee',
                        'quantity': 2,
                        'unit_price': 20,
                        'total_price': 40,
                        'category': 'Food',
                      },
                    ],
                  },
                  'warnings': ['partial_data'],
                }),
                200,
                headers: {'content-type': 'application/json; charset=utf-8'},
              );
            }),
      );
      final result = await service.analyze(image, 'receipt.jpg');
      expect(result.invoice.merchantName, 'متجر');
      expect(result.invoice.totalCents, 11500);
      expect(result.invoice.items.single.name, 'Coffee');
      expect(result.warnings, ['partial_data']);
    },
  );

  test('server errors preserve safe code and invalid responses fail', () async {
    for (final response in [
      http.Response('{"success":false,"code":"model_not_installed"}', 503),
      http.Response('<html>proxy error</html>', 502),
      http.Response('{"success":true,"invoice":[]}', 200),
    ]) {
      final service = InvoiceService(
        baseUrl: 'http://localhost:5000',
        clientFactory: () => MockClient((_) async => response),
      );
      await expectLater(
        service.analyze(image, 'r.jpg'),
        throwsA(isA<InvoiceApiException>()),
      );
    }
  });
  test('timeout and duplicate in-flight requests are bounded', () async {
    final gate = Completer<http.Response>();
    final service = InvoiceService(
      baseUrl: 'http://localhost:5000',
      timeout: const Duration(milliseconds: 20),
      clientFactory: () => MockClient((_) => gate.future),
    );
    final first = service.analyze(image, 'r.jpg');
    final firstExpectation = expectLater(
      first,
      throwsA(
        isA<InvoiceApiException>().having(
          (e) => e.code,
          'code',
          'analysis_timeout',
        ),
      ),
    );
    await expectLater(
      service.analyze(image, 'r.jpg'),
      throwsA(
        isA<InvoiceApiException>().having((e) => e.code, 'code', 'server_busy'),
      ),
    );
    await firstExpectation;
  });
  test(
    'HTML responses give a safe error without exposing server details',
    () async {
      for (final response in [
        http.Response(
          '<!DOCTYPE html><html><script src="flutter_bootstrap.js"></script></html>',
          200,
          headers: {'content-type': 'text/html; charset=utf-8'},
        ),
        http.Response('  <html>Flutter application</html>', 200),
        http.Response.bytes(
          utf8.encode(
            '\uFEFF\n<!doctype html><html>Flutter application</html>',
          ),
          200,
          headers: {'content-type': 'application/json'},
        ),
      ]) {
        var requests = 0;
        final service = InvoiceService(
          baseUrl: 'http://localhost:59612',
          clientFactory:
              () => MockClient((_) async {
                requests++;
                return response;
              }),
        );
        await expectLater(
          service.analyze(image, 'r.jpg'),
          throwsA(
            isA<InvoiceApiException>()
                .having((e) => e.code, 'code', 'wrong_server_url')
                .having(
                  (e) => e.message,
                  'safe service message',
                  'The service returned an unexpected response. Please try again later.',
                ),
          ),
        );
        expect(requests, 1);
        expect(service.baseUrl, 'http://localhost:59612');
      }
    },
  );

  test('ordinary malformed JSON keeps its existing error', () async {
    final service = InvoiceService(
      baseUrl: 'http://localhost:5000',
      clientFactory:
          () => MockClient((_) async => http.Response('not JSON', 200)),
    );
    await expectLater(
      service.analyze(image, 'r.jpg'),
      throwsA(
        isA<InvoiceApiException>().having(
          (e) => e.code,
          'code',
          'invalid_response',
        ),
      ),
    );
    expect(
      isHtmlApiResponse(http.Response('{"message":"<html>"}', 200)),
      isFalse,
    );
  });

  test(
    'backend URL rules allow deployed hosts but reject malformed origins',
    () {
      for (final good in [
        'http://31.97.178.214:5001',
        'http://31.97.178.214:5001/',
        'https://api.example.com',
        'http://10.0.2.2:5000',
        'http://192.168.1.100:5000',
        'http://127.0.0.1:5000',
        'http://localhost:5000',
      ]) {
        expect(validateInvoiceApiUrl(good), isNull);
      }
      for (final bad in [
        '',
        '31.97.178.214:5001',
        'http://',
        'http://31.97.178.214:0',
        'http://31.97.178.214:65536',
        'http://31.97.178.214:invalid',
        'http://31.97.178.214:5001?key=value',
        'http://31.97.178.214:5001#fragment',
        'http://bad host:5001',
        'http://user:pass@localhost:5000',
        'http://localhost:5000/api',
        'file:///tmp/a',
      ]) {
        expect(
          validateInvoiceApiUrl(bad),
          'The service is not configured correctly. Please contact support.',
        );
      }
    },
  );

  test(
    'invoice errors never display upstream messages or request URLs',
    () async {
      for (final code in [
        'invalid_url',
        'wrong_server_url',
        'ollama_unavailable',
        'model_not_installed',
        'http://31.97.178.214:5001/private-trace',
      ]) {
        final service = InvoiceService(
          baseUrl: deployedInvoiceApiUrl,
          clientFactory:
              () => MockClient(
                (_) async => http.Response(
                  jsonEncode({
                    'success': false,
                    'code': code,
                    'message':
                        'Failed at $deployedInvoiceApiUrl; private server log',
                  }),
                  503,
                ),
              ),
        );
        await expectLater(
          service.analyze(image, 'receipt.jpg'),
          throwsA(
            isA<InvoiceApiException>()
                .having((error) => error.code, 'original diagnostic code', code)
                .having(
                  (error) => error.message,
                  'safe message',
                  isNot(
                    matches(
                      r'http|31\.97\.178\.214|private server log|Ollama|Flask',
                    ),
                  ),
                ),
          ),
        );
      }
    },
  );

  test(
    'fresh installs and legacy local settings use the deployed backend',
    () async {
      for (final old in [
        null,
        '',
        'http://127.0.0.1:5000',
        'http://localhost:59612/',
        'http://10.0.2.2:5000',
        'http://192.168.1.100:5000',
        'http://172.16.0.2:5000',
        'http://[::1]:5000',
      ]) {
        SharedPreferences.setMockInitialValues({
          if (old != null) invoiceApiPreference: old,
          'numo_v1': 'existing financial records',
        });
        final prefs = await SharedPreferences.getInstance();
        expect(
          configuredInvoiceApiUrl(prefs),
          deployedInvoiceApiUrl,
          reason: '$old',
        );
        await migrateInvoiceApiUrl(prefs);
        expect(prefs.getString(invoiceApiPreference), isNull);
        expect(prefs.getString('numo_v1'), 'existing financial records');
        await prefs.reload();
        expect(configuredInvoiceApiUrl(prefs), deployedInvoiceApiUrl);
      }
    },
  );

  test(
    'custom servers survive migration and manual selection survives restart',
    () async {
      SharedPreferences.setMockInitialValues({
        invoiceApiPreference: 'https://api.example.com',
      });
      final prefs = await SharedPreferences.getInstance();
      await migrateInvoiceApiUrl(prefs);
      expect(configuredInvoiceApiUrl(prefs), 'https://api.example.com');
      expect(await saveInvoiceApiUrl(prefs, 'http://localhost:5000'), isTrue);
      await prefs.reload();
      await migrateInvoiceApiUrl(prefs);
      expect(configuredInvoiceApiUrl(prefs), 'http://localhost:5000');
      expect(await saveInvoiceApiUrl(prefs, 'file:///tmp/a'), isFalse);
      expect(configuredInvoiceApiUrl(prefs), 'http://localhost:5000');
    },
  );
}
