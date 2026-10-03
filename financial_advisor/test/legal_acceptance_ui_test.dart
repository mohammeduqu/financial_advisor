import 'dart:convert';

import 'package:financial_advisor/core/finance_store.dart';
import 'package:financial_advisor/main.dart';
import 'package:financial_advisor/screens/legal_acceptance.dart';
import 'package:financial_advisor/screens/privacy_terms.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _checkboxKey = Key('legal-acceptance-checkbox');
const _continueKey = Key('accept-legal-continue');

Map<String, dynamic> _existingProfile({String language = 'en'}) => {
  'version': 1,
  'language': language,
  'name': 'Samira',
  'currency': 'USD',
  'countryCode': 'KW',
  'onboarded': true,
  'demo': false,
  'entries': [
    Entry(
      id: 'saved-expense',
      merchant: 'Saved groceries',
      cents: 4321,
      date: DateTime(2026, 9, 1),
      category: 'Food',
      note: 'Keep the original record',
    ).toJson(),
  ],
  'goals': [],
  'budgets': {
    '2026-09': {'Food': 10000},
  },
};

class _ControlledPreferences implements SharedPreferences {
  final Map<String, String> cached;
  final Map<String, String> durable;
  bool failWrites = false;

  _ControlledPreferences(Map<String, String> initial)
    : cached = Map.of(initial),
      durable = Map.of(initial);

  @override
  String? getString(String key) => cached[key];

  @override
  Set<String> getKeys() => cached.keys.toSet();

  @override
  Future<bool> setString(String key, String value) async {
    cached[key] = value;
    if (failWrites) return false;
    durable[key] = value;
    return true;
  }

  @override
  Future<void> reload() async {
    cached
      ..clear()
      ..addAll(durable);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pumpApp(WidgetTester tester, FinanceStore store) async {
  await tester.pumpWidget(TadbeerApp(store: store));
  await tester.pumpAndSettle();
}

Future<void> _reveal(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      300,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 60,
    );
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await _reveal(tester, finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _toggleAcceptance(WidgetTester tester) =>
    _tap(tester, find.byKey(_checkboxKey));

bool _checked(WidgetTester tester) {
  final field = tester.widget(find.byKey(_checkboxKey));
  if (field is CheckboxListTile) return field.value!;
  return (field as Checkbox).value!;
}

Finder _welcomeButton() => find.widgetWithText(FilledButton, 'Get started');

Future<void> _enterName(WidgetTester tester, String name) async {
  final field = find.descendant(
    of: find.byKey(const Key('welcome-name')),
    matching: find.byType(TextFormField),
  );
  await _reveal(tester, field);
  await tester.enterText(field, name);
  await tester.pumpAndSettle();
}

Future<void> _choose(WidgetTester tester, String key, String value) async {
  await _tap(tester, find.byKey(Key(key)));
  await tester.tap(find.text(value).last);
  await tester.pumpAndSettle();
}

Future<void> _readDocuments(WidgetTester tester, String linkKey) async {
  await _tap(tester, find.byKey(Key(linkKey)));
  expect(find.byType(PrivacyTermsPage), findsOneWidget);
  await _tap(tester, find.byKey(const Key('terms-tab')));
  await tester.tap(find.byType(BackButton));
  await tester.pumpAndSettle();
  expect(find.byType(PrivacyTermsPage), findsNothing);
}

void _expectProfileIntact(FinanceStore store) {
  expect(store.name, 'Samira');
  expect(store.currency, 'USD');
  expect(store.countryCode, 'KW');
  expect(store.entries, hasLength(1));
  expect(store.entries.single.id, 'saved-expense');
  expect(store.entries.single.cents, 4321);
  expect(store.entries.single.note, 'Keep the original record');
  expect(store.budgets['2026-09']?['Food'], 10000);
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en');
    await initializeDateFormatting('ar');
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'Welcome requires a checked agreement and reading preserves input',
    (tester) async {
      final store = FinanceStore(await SharedPreferences.getInstance());
      await _pumpApp(tester, store);
      await _enterName(tester, 'Samira');
      await _choose(tester, 'welcome-currency', 'USD');
      await _choose(tester, 'welcome-country', 'Kuwait');
      await _reveal(tester, _welcomeButton());
      expect(_checked(tester), isFalse);
      expect(tester.widget<FilledButton>(_welcomeButton()).onPressed, isNull);
      await tester.tap(_welcomeButton());
      await tester.pumpAndSettle();
      expect(store.onboarded, isFalse);
      expect(store.hasAcceptedCurrentLegal, isFalse);
      expect(store.prefs.getString('numo_v1'), isNull);

      await _readDocuments(tester, 'welcome-privacy');
      expect(find.byType(WelcomePage), findsOneWidget);
      await _reveal(tester, find.byKey(_checkboxKey));
      expect(_checked(tester), isFalse);
      expect(store.hasAcceptedCurrentLegal, isFalse);
      expect(store.prefs.getString('numo_v1'), isNull);
      final field = find.descendant(
        of: find.byKey(const Key('welcome-name')),
        matching: find.byType(TextFormField),
      );
      await _reveal(tester, field);
      expect(tester.widget<TextFormField>(field).controller!.text, 'Samira');
      for (final (key, value) in [
        ('welcome-currency', 'USD'),
        ('welcome-country', 'KW'),
      ]) {
        final dropdown = find.descendant(
          of: find.byKey(Key(key)),
          matching: find.byType(DropdownButtonFormField<String>),
        );
        await _reveal(tester, dropdown);
        expect(
          tester.widget<DropdownButtonFormField<String>>(dropdown).initialValue,
          value,
        );
      }

      await _toggleAcceptance(tester);
      await _reveal(tester, _welcomeButton());
      expect(
        tester.widget<FilledButton>(_welcomeButton()).onPressed,
        isNotNull,
      );
      await _toggleAcceptance(tester);
      await _reveal(tester, _welcomeButton());
      expect(_checked(tester), isFalse);
      expect(tester.widget<FilledButton>(_welcomeButton()).onPressed, isNull);
      expect(store.onboarded, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'accepted onboarding enters app and remains accepted after restart',
    (tester) async {
      final store = FinanceStore(await SharedPreferences.getInstance());
      await _pumpApp(tester, store);
      await _enterName(tester, 'Samira');
      await _toggleAcceptance(tester);
      await _readDocuments(tester, 'welcome-privacy');
      await _reveal(tester, find.byKey(_checkboxKey));
      expect(_checked(tester), isTrue);
      expect(store.hasAcceptedCurrentLegal, isFalse);
      await _tap(tester, _welcomeButton());
      expect(store.onboarded, isTrue);
      expect(store.hasAcceptedCurrentLegal, isTrue);
      expect(find.byType(AppShell), findsOneWidget);
      expect(find.byType(WelcomePage), findsNothing);
      await tester.pumpWidget(const SizedBox());
      final restored = FinanceStore(store.prefs);
      await restored.load();
      await _pumpApp(tester, restored);
      expect(restored.hasAcceptedCurrentLegal, isTrue);
      expect(restored.name, 'Samira');
      expect(find.byType(AppShell), findsOneWidget);
      expect(find.byType(LegalAcceptancePage), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'existing profile is gated until acceptance without losing data',
    (tester) async {
      final saved = jsonEncode(_existingProfile());
      SharedPreferences.setMockInitialValues({'numo_v1': saved});
      final store = FinanceStore(await SharedPreferences.getInstance());
      await store.load();
      await _pumpApp(tester, store);
      expect(find.byType(LegalAcceptancePage), findsOneWidget);
      expect(find.byType(AppShell), findsNothing);
      expect(store.onboarded, isTrue);
      _expectProfileIntact(store);
      await _reveal(tester, find.byKey(_continueKey));
      expect(_checked(tester), isFalse);
      expect(
        tester.widget<FilledButton>(find.byKey(_continueKey)).onPressed,
        isNull,
      );
      await _readDocuments(tester, 'read-legal-documents');
      expect(store.hasAcceptedCurrentLegal, isFalse);
      expect(store.prefs.getString('numo_v1'), saved);
      await _toggleAcceptance(tester);
      await _toggleAcceptance(tester);
      await _reveal(tester, find.byKey(_continueKey));
      expect(
        tester.widget<FilledButton>(find.byKey(_continueKey)).onPressed,
        isNull,
      );
      await _toggleAcceptance(tester);
      await _tap(tester, find.byKey(_continueKey));
      expect(find.byType(AppShell), findsOneWidget);
      expect(store.hasAcceptedCurrentLegal, isTrue);
      _expectProfileIntact(store);
      final restored = FinanceStore(store.prefs);
      await restored.load();
      expect(restored.hasAcceptedCurrentLegal, isTrue);
      _expectProfileIntact(restored);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('an earlier legal version requires fresh explicit acceptance', (
    tester,
  ) async {
    final profile =
        _existingProfile()
          ..['legalAcceptance'] = {
            'version': '2025-01-01.1',
            'acceptedAt': '2025-01-01T12:00:00.000Z',
            'language': 'en',
          };
    final saved = jsonEncode(profile);
    SharedPreferences.setMockInitialValues({'numo_v1': saved});
    final store = FinanceStore(await SharedPreferences.getInstance());
    await store.load();
    await _pumpApp(tester, store);
    expect(find.byType(LegalAcceptancePage), findsOneWidget);
    expect(find.byType(AppShell), findsNothing);
    expect(store.hasAcceptedCurrentLegal, isFalse);
    await _reveal(tester, find.byKey(_checkboxKey));
    expect(_checked(tester), isFalse);
    expect(store.prefs.getString('numo_v1'), saved);
    _expectProfileIntact(store);
    await _toggleAcceptance(tester);
    await _tap(tester, find.byKey(_continueKey));
    expect(find.byType(AppShell), findsOneWidget);
    expect(store.hasAcceptedCurrentLegal, isTrue);
    _expectProfileIntact(store);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (final existing in [false, true]) {
    testWidgets(
      'Arabic ${existing ? 'gate' : 'Welcome'} supports narrow large text',
      (tester) async {
        tester.view.physicalSize = const Size(320, 844);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        if (existing) {
          SharedPreferences.setMockInitialValues({
            'numo_v1': jsonEncode(_existingProfile(language: 'ar')),
          });
        }
        final store = FinanceStore(await SharedPreferences.getInstance());
        if (existing) {
          await store.load();
        } else {
          store.languageCode = 'ar';
        }
        await _pumpApp(tester, store);
        await _reveal(tester, find.byKey(_checkboxKey));
        expect(
          Directionality.of(tester.element(find.byKey(_checkboxKey))),
          TextDirection.rtl,
        );
        expect(_checked(tester), isFalse);
        expect(tester.takeException(), isNull);
        await _toggleAcceptance(tester);
        expect(_checked(tester), isTrue);
        await _readDocuments(
          tester,
          existing ? 'read-legal-documents' : 'welcome-privacy',
        );
        await _reveal(tester, find.byKey(_checkboxKey));
        expect(_checked(tester), isTrue);
        final checkboxBounds = tester.getRect(find.byKey(_checkboxKey));
        expect(checkboxBounds.left, greaterThanOrEqualTo(0));
        expect(checkboxBounds.right, lessThanOrEqualTo(320));
        expect(store.hasAcceptedCurrentLegal, isFalse);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets('failed acceptance save stays gated and supports retry', (
    tester,
  ) async {
    final saved = jsonEncode(_existingProfile());
    final prefs = _ControlledPreferences({'numo_v1': saved});
    final store = FinanceStore(prefs);
    await store.load();
    prefs.failWrites = true;
    await _pumpApp(tester, store);
    await _toggleAcceptance(tester);
    await _tap(tester, find.byKey(_continueKey));
    expect(find.byType(LegalAcceptancePage), findsOneWidget);
    expect(find.byType(AppShell), findsNothing);
    expect(store.hasAcceptedCurrentLegal, isFalse);
    expect(prefs.durable['numo_v1'], saved);
    expect(store.error, isNotNull);
    expect(
      find.text('Could not save your agreement. Please try again.'),
      findsOneWidget,
    );
    _expectProfileIntact(store);
    prefs.failWrites = false;
    await _tap(tester, find.byKey(_continueKey));
    expect(find.byType(AppShell), findsOneWidget);
    expect(store.hasAcceptedCurrentLegal, isTrue);
    final restored = FinanceStore(prefs);
    await restored.load();
    expect(restored.hasAcceptedCurrentLegal, isTrue);
    _expectProfileIntact(restored);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'failed onboarding save keeps input and requires a successful retry',
    (tester) async {
      final prefs = _ControlledPreferences({})..failWrites = true;
      final store = FinanceStore(prefs);
      await _pumpApp(tester, store);
      await _enterName(tester, 'Samira');
      await _toggleAcceptance(tester);
      await _tap(tester, _welcomeButton());
      expect(find.byType(WelcomePage), findsOneWidget);
      expect(find.byType(AppShell), findsNothing);
      expect(store.onboarded, isFalse);
      expect(store.hasAcceptedCurrentLegal, isFalse);
      expect(prefs.durable, isEmpty);
      expect(
        find.text('Could not save your agreement. Please try again.'),
        findsOneWidget,
      );
      final field = find.descendant(
        of: find.byKey(const Key('welcome-name')),
        matching: find.byType(TextFormField),
      );
      await _reveal(tester, field);
      expect(tester.widget<TextFormField>(field).controller!.text, 'Samira');
      prefs.failWrites = false;
      await _tap(tester, _welcomeButton());
      expect(find.byType(AppShell), findsOneWidget);
      expect(store.onboarded, isTrue);
      expect(store.hasAcceptedCurrentLegal, isTrue);
      expect(store.name, 'Samira');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
