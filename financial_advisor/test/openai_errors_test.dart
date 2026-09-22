import 'dart:convert';
import 'dart:typed_data';

import 'package:financial_advisor/l10n/app_language.dart';
import 'package:financial_advisor/services/invoice_service.dart';
import 'package:financial_advisor/services/recommendation_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const codes = [
    'ai_not_configured',
    'ai_authentication_failed',
    'ai_rate_limited',
    'ai_model_unavailable',
    'ai_configuration_error',
    'ai_unavailable',
    'analysis_refused',
  ];
  final image = Uint8List.fromList([255, 216, 255, 0]);

  for (final code in codes) {
    test(
      '$code is safe and localized for invoice and shopping analysis',
      () async {
        const privateDetail =
            'https://private.example/api OPENAI_API_KEY=secret private trace';
        http.Client clientFactory() => MockClient(
          (_) async => http.Response(
            jsonEncode({
              'success': false,
              'code': code,
              'message': privateDetail,
            }),
            503,
          ),
        );
        final invoiceService = InvoiceService(
          baseUrl: 'http://localhost:5000',
          clientFactory: clientFactory,
        );
        final shoppingService = RecommendationService(
          baseUrl: 'http://localhost:5000',
          clientFactory: clientFactory,
        );

        void expectSafeLocalizedMessage(String message) {
          expect(message, isNot('AI analysis failed. Please try again.'));
          expect(translate(message, 'en'), message);
          final arabicMessage = translate(message, 'ar');
          expect(arabicMessage, isNot(message));
          expect(arabicMessage, matches(RegExp(r'[\u0600-\u06FF]')));
          for (final text in [message, arabicMessage]) {
            expect(text, isNot(contains(privateDetail)));
            expect(
              text,
              isNot(matches(r'https?://|OPENAI_API_KEY|secret|trace')),
            );
          }
        }

        await expectLater(
          invoiceService.analyze(image, 'receipt.jpg'),
          throwsA(
            isA<InvoiceApiException>()
                .having((error) => error.code, 'error code', code)
                .having(
                  (error) {
                    expectSafeLocalizedMessage(error.message);
                    return error.message;
                  },
                  'safe message',
                  InvoiceApiException(code).message,
                ),
          ),
        );
        await expectLater(
          shoppingService.readShoppingImage(image, 'list.jpg'),
          throwsA(
            isA<RecommendationApiException>()
                .having((error) => error.code, 'error code', code)
                .having(
                  (error) {
                    expectSafeLocalizedMessage(error.message);
                    return error.message;
                  },
                  'safe message',
                  InvoiceApiException(code).message,
                ),
          ),
        );
      },
    );
  }
}
