import 'dart:convert';

import 'package:financial_advisor/core/finance_store.dart';
import 'package:financial_advisor/core/recommendation.dart';
import 'package:financial_advisor/screens/recommendation_results.dart';
import 'package:financial_advisor/screens/smart_prices.dart';
import 'package:financial_advisor/widgets/design.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget historyPage(FinanceStore store, String language) => MaterialApp(
  theme: appTheme(),
  locale: Locale(language),
  supportedLocales: const [Locale('en'), Locale('ar')],
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  home: SmartPricesPage(store: store),
);

Future<void> tapDelete(WidgetTester tester, String id) async {
  final button = find.byKey(ValueKey('delete-comparison-$id'));
  await tester.scrollUntilVisible(
    button,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.tap(button);
  await tester.pumpAndSettle();
}

Future<void> dialogAction(WidgetTester tester, String text) async {
  await tester.tap(
    find.descendant(of: find.byType(AlertDialog), matching: find.text(text)),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en');
    await initializeDateFormatting('ar');
  });

  for (final language in ['en', 'ar']) {
    testWidgets(
      '$language deletes only the chosen comparison and persists after reopening',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        SharedPreferences.setMockInitialValues({
          RecommendationHistory.preferenceKey: jsonEncode({
            'version': 1,
            'entries': [
              for (final id in ['newer', 'older'])
                {
                  'id': id,
                  'saved_at': '2026-09-23T12:00:00Z',
                  'expense_id': 'expense-$id',
                  'result': {
                    'success': true,
                    'stage': 'results',
                    'mode': 'product',
                    'direct_search': true,
                    'query': 'Tea',
                    'shopping_results': [],
                    'summary': {'total_results': 0},
                    'recommendations': [],
                  },
                },
            ],
          }),
        });
        final prefs = await SharedPreferences.getInstance();
        final store = FinanceStore(prefs);
        await tester.pumpWidget(historyPage(store, language));
        await tester.pumpAndSettle();

        await tapDelete(tester, 'newer');
        expect(
          find.text(language == 'ar' ? 'حذف المقارنة؟' : 'Delete comparison?'),
          findsOneWidget,
        );
        expect(find.byType(RecommendationResultsPage), findsNothing);
        await dialogAction(tester, language == 'ar' ? 'إلغاء' : 'Cancel');
        expect(RecommendationHistory(prefs).read().map((entry) => entry.id), [
          'newer',
          'older',
        ]);

        await tapDelete(tester, 'newer');
        await dialogAction(tester, language == 'ar' ? 'حذف' : 'Delete');
        expect(find.byKey(const ValueKey('comparison-newer')), findsNothing);
        expect(find.byKey(const ValueKey('comparison-older')), findsOneWidget);
        expect(RecommendationHistory(prefs).read().single.id, 'older');
        expect(
          RecommendationHistory(prefs).read().single.expenseId,
          'expense-older',
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await prefs.reload();
        await tester.pumpWidget(historyPage(FinanceStore(prefs), language));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('comparison-older')),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.byKey(const ValueKey('comparison-newer')), findsNothing);
        await tester.tap(find.byKey(const ValueKey('comparison-older')));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<RecommendationResultsPage>(
                find.byType(RecommendationResultsPage),
              )
              .historical,
          isTrue,
        );
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();

        await tapDelete(tester, 'older');
        await dialogAction(tester, language == 'ar' ? 'حذف' : 'Delete');
        expect(RecommendationHistory(prefs).read(), isEmpty);
        expect(
          find.text(
            language == 'ar'
                ? 'ستظهر مقارناتك هنا'
                : 'Your comparisons will appear here',
          ),
          findsOneWidget,
        );
        expect(
          find.byTooltip(
            language == 'ar' ? 'حذف المقارنة' : 'Delete comparison',
          ),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
