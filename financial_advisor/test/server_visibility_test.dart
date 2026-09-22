import 'package:financial_advisor/core/finance_store.dart';
import 'package:financial_advisor/l10n/app_language.dart';
import 'package:financial_advisor/screens/recommendation_text.dart';
import 'package:financial_advisor/screens/scan.dart';
import 'package:financial_advisor/services/invoice_service.dart';
import 'package:financial_advisor/services/recommendation_service.dart';
import 'package:financial_advisor/widgets/design.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void expectNoServerDetails(WidgetTester tester) {
  final text = tester
      .widgetList<Text>(find.byType(Text))
      .map((widget) => widget.data ?? widget.textSpan?.toPlainText() ?? '')
      .join('\n');
  expect(
    text,
    isNot(
      matches(
        r'https?://|31\.97\.178\.214|192\.0\.2\.22|SERPAPI_KEY|Flask|Ollama',
      ),
    ),
  );
  expect(find.byIcon(Icons.settings_ethernet), findsNothing);
  expect(find.byTooltip('Backend server'), findsNothing);
  expect(find.byTooltip('خادم التطبيق'), findsNothing);
  expect(find.byType(AlertDialog), findsNothing);
}

Widget app(Widget page, String language) => MaterialApp(
  theme: appTheme(),
  locale: Locale(language),
  supportedLocales: const [Locale('en'), Locale('ar')],
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  home: page,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final language in ['en', 'ar']) {
    for (final mode in ['invoice', 'product', 'shopping-list']) {
      testWidgets('$language $mode scanner hides server address and settings', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(const Size(430, 1200));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final prefs = await SharedPreferences.getInstance();
        await saveInvoiceApiUrl(prefs, 'http://192.0.2.22:5001');
        final store = FinanceStore(prefs);
        await tester.pumpWidget(
          app(
            Scaffold(
              body: ScanPage(
                store: store,
                productMode: mode == 'product',
                shoppingListMode: mode == 'shopping-list',
              ),
            ),
            language,
          ),
        );
        await tester.pumpAndSettle();
        expectNoServerDetails(tester);
        await tester.drag(find.byType(ListView), const Offset(0, -1000));
        await tester.pumpAndSettle();
        expectNoServerDetails(tester);
        expect(configuredInvoiceApiUrl(prefs), 'http://192.0.2.22:5001');
        expect(tester.takeException(), isNull);
      });
    }

    for (final shoppingList in [false, true]) {
      testWidgets(
        '$language text search hides endpoint even after service error ($shoppingList)',
        (tester) async {
          await tester.binding.setSurfaceSize(const Size(430, 1200));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final store = FinanceStore(await SharedPreferences.getInstance());
          var calls = 0;
          await tester.pumpWidget(
            app(
              RecommendationTextPage(
                store: store,
                shoppingList: shoppingList,
                serviceFactory:
                    (baseUrl) => RecommendationService(
                      baseUrl: baseUrl,
                      clientFactory:
                          () => MockClient((request) async {
                            calls++;
                            expect(request.url.host, '31.97.178.214');
                            return http.Response(
                              '<html>Failed at $baseUrl; private server trace</html>',
                              502,
                              headers: {'content-type': 'text/html'},
                            );
                          }),
                    ),
              ),
              language,
            ),
          );
          await tester.pumpAndSettle();
          expectNoServerDetails(tester);
          await tester.enterText(
            find.byKey(const Key('shopping-text-input')),
            'Milk',
          );
          await tester.scrollUntilVisible(
            find.byKey(const Key('review-shopping-text')).hitTestable(),
            200,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.tap(find.byKey(const Key('review-shopping-text')));
          await tester.pumpAndSettle();
          expect(calls, 1);
          expect(
            find.text(
              translate(
                'The service returned an unexpected response. Please try again later.',
                language,
              ),
            ),
            findsOneWidget,
          );
          expectNoServerDetails(tester);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
