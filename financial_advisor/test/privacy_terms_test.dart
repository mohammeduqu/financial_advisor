import 'package:financial_advisor/core/finance_store.dart';
import 'package:financial_advisor/core/legal_content.dart';
import 'package:financial_advisor/main.dart';
import 'package:financial_advisor/screens/privacy_terms.dart';
import 'package:financial_advisor/widgets/design.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> pumpPage(
  WidgetTester tester,
  Widget home, {
  String language = 'en',
  double width = 390,
  double scale = 1,
}) async {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: appTheme(),
      locale: Locale(language),
      supportedLocales: const [Locale('en'), Locale('ar')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      builder:
          (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
      home: home,
    ),
  );
  await tester.pumpAndSettle();
}

Finder documentScroll(String key) =>
    find
        .descendant(
          of: find.byKey(PageStorageKey<String>(key)),
          matching: find.byType(Scrollable),
        )
        .first;

Finder documentText(String key, String text) => find.descendant(
  of: find.byKey(PageStorageKey<String>(key)),
  matching: find.text(text),
);

Future<void> openWelcomePolicy(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.byKey(const Key('welcome-privacy')),
    300,
    scrollable: find.byType(Scrollable).first,
    maxScrolls: 40,
  );
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.byKey(const Key('welcome-privacy')));
  await tester.tap(find.byKey(const Key('welcome-privacy')));
  await tester.pumpAndSettle();
}

Future<void> selectDocumentTab(WidgetTester tester, String key) async {
  final tab = find.byKey(Key(key));
  await tester.ensureVisible(tab);
  await tester.pumpAndSettle();
  await tester.tap(tab);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'Welcome allows reading both documents before setup without saving data',
    (tester) async {
      final store = FinanceStore(await SharedPreferences.getInstance());
      await pumpPage(tester, WelcomePage(store: store));
      await openWelcomePolicy(tester);
      expect(find.byType(PrivacyTermsPage), findsOneWidget);
      expect(find.byType(SelectionArea), findsWidgets);
      expect(
        documentText('privacy-en', privacyDocument('en').title),
        findsOneWidget,
      );
      await selectDocumentTab(tester, 'terms-tab');
      await tester.pumpAndSettle();
      expect(
        documentText('terms-en', termsDocument('en').title),
        findsOneWidget,
      );
      expect(store.onboarded, isFalse);
      expect(store.entries, isEmpty);
      expect(store.prefs.getKeys(), isEmpty);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(WelcomePage), findsOneWidget);
      expect(find.byType(PrivacyTermsPage), findsNothing);
      expect(store.prefs.getKeys(), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Arabic documents remain readable at 320 pixels with large text',
    (tester) async {
      final store = FinanceStore(await SharedPreferences.getInstance());
      await pumpPage(
        tester,
        WelcomePage(store: store),
        language: 'ar',
        width: 320,
        scale: 2,
      );
      await openWelcomePolicy(tester);
      expect(
        Directionality.of(tester.element(find.byType(PrivacyTermsPage))),
        TextDirection.rtl,
      );
      expect(
        documentText('privacy-ar', privacyDocument('ar').title),
        findsOneWidget,
      );
      final privacyLast = privacyDocument('ar').sections.last;
      await tester.scrollUntilVisible(
        find.byKey(ValueKey('privacy-ar-${privacyLast.id}')),
        600,
        scrollable: documentScroll('privacy-ar'),
        maxScrolls: 300,
      );
      await tester.pumpAndSettle();
      expect(documentText('privacy-ar', privacyLast.body), findsOneWidget);
      expect(tester.takeException(), isNull);
      await selectDocumentTab(tester, 'terms-tab');
      await tester.pumpAndSettle();
      final termsLast = termsDocument('ar').sections.last;
      await tester.scrollUntilVisible(
        find.byKey(ValueKey('terms-ar-${termsLast.id}')),
        600,
        scrollable: documentScroll('terms-ar'),
        maxScrolls: 300,
      );
      await tester.pumpAndSettle();
      expect(documentText('terms-ar', termsLast.body), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byType(WelcomePage), findsOneWidget);
      expect(store.onboarded, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Privacy and terms retain independent reading positions', (
    tester,
  ) async {
    await pumpPage(tester, const PrivacyTermsPage());
    await tester.drag(documentScroll('privacy-en'), const Offset(0, -500));
    await tester.pumpAndSettle();
    final privacyOffset =
        tester
            .state<ScrollableState>(documentScroll('privacy-en'))
            .position
            .pixels;
    expect(privacyOffset, greaterThan(100));
    await selectDocumentTab(tester, 'terms-tab');
    await tester.pumpAndSettle();
    expect(
      tester.state<ScrollableState>(documentScroll('terms-en')).position.pixels,
      0,
    );
    await tester.drag(documentScroll('terms-en'), const Offset(0, -300));
    await tester.pumpAndSettle();
    final termsOffset =
        tester
            .state<ScrollableState>(documentScroll('terms-en'))
            .position
            .pixels;
    expect(termsOffset, greaterThan(100));
    await selectDocumentTab(tester, 'privacy-tab');
    await tester.pumpAndSettle();
    expect(
      tester
          .state<ScrollableState>(documentScroll('privacy-en'))
          .position
          .pixels,
      closeTo(privacyOffset, 1),
    );
    await selectDocumentTab(tester, 'terms-tab');
    await tester.pumpAndSettle();
    expect(
      tester.state<ScrollableState>(documentScroll('terms-en')).position.pixels,
      closeTo(termsOffset, 1),
    );
    expect(tester.takeException(), isNull);
  });
}
