import 'package:financial_advisor/screens/transactions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:financial_advisor/core/finance_store.dart';
import 'package:financial_advisor/l10n/app_language.dart';
import 'package:financial_advisor/main.dart';
import 'package:financial_advisor/widgets/language_selector.dart';

void main() {
  test('device language resolves Arabic regions and falls back to English', () {
    const supported = [Locale('en'), Locale('ar')];
    expect(
      resolveDeviceLocale([const Locale('ar', 'SA')], supported),
      const Locale('ar'),
    );
    expect(
      resolveDeviceLocale([const Locale('ar', 'EG')], supported),
      const Locale('ar'),
    );
    expect(
      resolveDeviceLocale([const Locale('fr')], supported),
      const Locale('en'),
    );
    expect(resolveDeviceLocale([], supported), const Locale('en'));
    expect(resolveDeviceLocale(null, supported), const Locale('en'));
  });
  test('Arabic and Persian digits retain exact minor units and validation', () {
    expect(parseMoney('١٬٢٣٤٫٥٠'), 123450);
    expect(parseMoney('۱۲۳۴٫۵۰'), 123450);
    expect(parseMoney('١٢٫٣٤٥'), isNull);
    expect(parseMoney('١٬٢٣٫٤٥'), isNull);
    expect(parseMoney('٠'), isNull);
  });
  test('translated templates retain amounts and translate category labels', () {
    expect(translate('Food · September 7', 'ar'), 'الطعام · September 7');
    expect(translate('Amount (SAR)', 'ar'), 'المبلغ (SAR)');
    expect(translate('Hello, أحمد', 'ar'), 'مرحباً، أحمد');
  });
  test('manual language persists and automatic clears the override', () async {
    SharedPreferences.setMockInitialValues({});
    final store = FinanceStore(await SharedPreferences.getInstance());
    await store.setLanguage('ar');
    final restored = FinanceStore(store.prefs);
    await restored.load();
    expect(restored.languageCode, 'ar');
    await restored.setLanguage(null);
    final automatic = FinanceStore(store.prefs);
    await automatic.load();
    expect(automatic.languageCode, isNull);
    expect(() => store.setLanguage('fr'), throwsArgumentError);
  });
  testWidgets(
    'profile language selector overrides device and returns to automatic',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final store = FinanceStore(await SharedPreferences.getInstance());
      await store.start(
        userName: 'Alex',
        selectedCurrency: 'SAR',
        useDemo: true,
      );
      tester.binding.platformDispatcher.localesTestValue = [const Locale('en')];
      addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
      await tester.pumpWidget(TadbeerApp(store: store));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Profile'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('language-selector')));
      await tester.tap(find.byKey(const Key('language-selector')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('language-option-ar')));
      await tester.pumpAndSettle();
      expect(store.languageCode, 'ar');
      expect(
        Directionality.of(tester.element(find.byType(NavigationBar))),
        TextDirection.rtl,
      );
      tester.binding.platformDispatcher.localesTestValue = [const Locale('fr')];
      await tester.pumpAndSettle();
      expect(
        Directionality.of(tester.element(find.byType(NavigationBar))),
        TextDirection.rtl,
      );
      await tester.ensureVisible(find.byKey(const Key('language-selector')));
      await tester.tap(find.byKey(const Key('language-selector')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('language-option-auto')));
      await tester.pumpAndSettle();
      expect(store.languageCode, isNull);
      expect(
        Directionality.of(tester.element(find.byType(NavigationBar))),
        TextDirection.ltr,
      );
      expect(find.text('Automatic · device language'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Arabic expense entry saves Arabic digits under canonical categories',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final store = FinanceStore(await SharedPreferences.getInstance());
      await store.start(
        userName: 'أحمد',
        selectedCurrency: 'SAR',
        useDemo: false,
      );
      tester.binding.platformDispatcher.localesTestValue = [const Locale('ar')];
      addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
      await tester.pumpWidget(TadbeerApp(store: store));
      await tester.pumpAndSettle();
      editEntry(tester.element(find.byType(AppShell)), store);
      await tester.pumpAndSettle();
      final fields = find.descendant(
        of: find.byType(EntryEditor),
        matching: find.byType(TextFormField),
      );
      await tester.enterText(fields.at(0), 'متجر الاختبار');
      await tester.enterText(fields.at(1), '١٢٫٥٠');
      await tester.scrollUntilVisible(
        find.text('حفظ المعاملة'),
        200,
        scrollable:
            find
                .descendant(
                  of: find.byType(EntryEditor),
                  matching: find.byType(Scrollable),
                )
                .first,
      );
      await tester.tap(find.text('حفظ المعاملة'));
      await tester.pumpAndSettle();
      expect(store.entries.single.cents, 1250);
      expect(store.entries.single.merchant, 'متجر الاختبار');
      expect(categories, contains(store.entries.single.category));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Arabic device starts RTL and responds to a live language change',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final store = FinanceStore(await SharedPreferences.getInstance());
      await store.start(
        userName: 'أحمد',
        selectedCurrency: 'SAR',
        useDemo: true,
      );
      tester.binding.platformDispatcher.localesTestValue = [
        const Locale('ar', 'SA'),
      ];
      addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(TadbeerApp(store: store));
      await tester.pumpAndSettle();
      expect(find.text('مرحباً، أحمد'), findsOneWidget);
      expect(
        Directionality.of(tester.element(find.byType(NavigationBar))),
        TextDirection.rtl,
      );
      for (final label in ['المعاملات', 'التحليل', 'الملف الشخصي']) {
        await tester.tap(
          find.descendant(
            of: find.byType(NavigationBar),
            matching: find.text(label),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: label);
      }
      tester.binding.platformDispatcher.localesTestValue = [
        const Locale('en', 'US'),
      ];
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Transactions'),
        ),
        findsOneWidget,
      );
      expect(
        Directionality.of(tester.element(find.byType(NavigationBar))),
        TextDirection.ltr,
      );
      expect(store.entries.first.category, 'Income');
      expect(store.name, 'أحمد');
    },
  );
  testWidgets(
    'Arabic onboarding labels and material date locale are available',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final store = FinanceStore(await SharedPreferences.getInstance());
      tester.binding.platformDispatcher.localesTestValue = [const Locale('ar')];
      addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
      await tester.pumpWidget(TadbeerApp(store: store));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('ابدأ الآن'),
        200,
        scrollable:
            find
                .descendant(
                  of: find.byType(WelcomePage),
                  matching: find.byType(Scrollable),
                )
                .first,
      );
      expect(find.text('ابدأ الآن'), findsOneWidget);
      expect(find.byType(LanguageSelector), findsNothing);
      expect(find.text('عملتك'), findsOneWidget);
      final context = tester.element(find.byType(WelcomePage));
      expect(
        MaterialLocalizations.of(context).cancelButtonLabel,
        isNot('Cancel'),
      );
      expect(tester.takeException(), isNull);
    },
  );
}
