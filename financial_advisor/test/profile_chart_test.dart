import 'package:financial_advisor/core/finance_store.dart';
import 'package:financial_advisor/main.dart';
import 'package:financial_advisor/screens/transactions.dart';
import 'package:financial_advisor/screens/privacy_terms.dart';
import 'package:financial_advisor/widgets/design.dart';
import 'package:financial_advisor/widgets/finance_charts.dart';
import 'package:financial_advisor/widgets/profile_details.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget wrap(Widget child, {String language = 'en'}) => MaterialApp(
  theme: appTheme(),
  locale: Locale(language),
  supportedLocales: const [Locale('en'), Locale('ar')],
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  home: child,
);

Future<void> reveal(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      200,
      scrollable: find.byType(Scrollable).first,
    );
  } else {
    await tester.ensureVisible(finder);
  }
  await tester.pumpAndSettle();
}

Future<void> choose(WidgetTester tester, Key field, String label) async {
  final finder = find.byKey(field);
  await reveal(tester, finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

void expectReadOnlyProfile() {
  final card = find.byType(ProfileDetailsCard);
  expect(
    find.descendant(of: card, matching: find.byType(TextFormField)),
    findsNothing,
  );
  expect(
    find.descendant(
      of: card,
      matching: find.byType(DropdownButtonFormField<String>),
    ),
    findsNothing,
  );
  expect(find.byKey(const Key('profile-name')), findsNothing);
  expect(find.byKey(const Key('profile-currency')), findsNothing);
  expect(find.byKey(const Key('profile-country')), findsNothing);
}

void expectNoNameCounter() {
  expect(
    find.textContaining(RegExp(r'^[0-9٠-٩]+\s*/\s*(99|٩٩|100|١٠٠)$')),
    findsNothing,
  );
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en');
    await initializeDateFormatting('ar');
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('onboarding reports long pasted names and persists country', (
    tester,
  ) async {
    final store = FinanceStore(await SharedPreferences.getInstance());
    await tester.pumpWidget(wrap(WelcomePage(store: store)));
    await tester.pumpAndSettle();
    final field = find.descendant(
      of: find.byKey(const Key('welcome-name')),
      matching: find.byType(TextFormField),
    );
    await reveal(tester, field);
    expectNoNameCounter();
    expect(find.text('Name must be fewer than 100 characters.'), findsNothing);
    await tester.enterText(field, 'أ' * 99);
    await tester.pump();
    expectNoNameCounter();
    expect(find.text('Name must be fewer than 100 characters.'), findsNothing);
    final longName = 'أ' * 100;
    await tester.enterText(field, longName);
    await tester.pump();
    expect(
      find.text('Name must be fewer than 100 characters.'),
      findsOneWidget,
    );
    expect(tester.widget<TextFormField>(field).controller!.text, 'أ' * 99);
    expectNoNameCounter();
    await reveal(tester, field);
    await tester.enterText(field, 'أحمد');
    await tester.pump();
    expect(find.text('Name must be fewer than 100 characters.'), findsNothing);
    expectNoNameCounter();
    await choose(tester, const Key('welcome-country'), 'Kuwait');
    await reveal(tester, find.byKey(const Key('legal-acceptance-checkbox')));
    await tester.tap(find.byKey(const Key('legal-acceptance-checkbox')));
    await tester.pumpAndSettle();
    await reveal(tester, find.text('Get started'));
    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();
    expect(store.countryCode, 'KW');
    expect(store.name, 'أحمد');
    final restored = FinanceStore(store.prefs);
    await restored.load();
    expect(restored.countryCode, 'KW');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Get started rejects blank and 100-character names until corrected',
    (tester) async {
      final store = FinanceStore(await SharedPreferences.getInstance());
      await tester.pumpWidget(TadbeerApp(store: store));
      await tester.pumpAndSettle();
      final field = find.descendant(
        of: find.byKey(const Key('welcome-name')),
        matching: find.byType(TextFormField),
      );
      await reveal(tester, find.byKey(const Key('legal-acceptance-checkbox')));
      await tester.tap(find.byKey(const Key('legal-acceptance-checkbox')));
      await tester.pumpAndSettle();
      for (final attemptedName in ['', '   ', 'W' * 100]) {
        await reveal(tester, field);
        await tester.enterText(field, attemptedName);
        await reveal(tester, find.text('Get started'));
        await tester.tap(find.text('Get started'));
        await tester.pumpAndSettle();
        expect(store.onboarded, isFalse);
        expect(store.prefs.getString('numo_v1'), isNull);
        expect(find.byType(WelcomePage), findsOneWidget);
        expect(find.byType(AppShell), findsNothing);
        await reveal(tester, field);
        expect(
          find.text(
            attemptedName.trim().isEmpty
                ? 'Enter your name.'
                : 'Name must be fewer than 100 characters.',
          ),
          findsOneWidget,
        );
        expectNoNameCounter();
        expect(tester.takeException(), isNull);
      }
      expect(tester.widget<TextFormField>(field).controller!.text, 'W' * 99);
      final name = 'Z' * 99;
      await tester.enterText(field, name);
      await tester.pumpAndSettle();
      expect(
        find.text('Name must be fewer than 100 characters.'),
        findsNothing,
      );
      await reveal(tester, find.text('Get started'));
      await tester.tap(find.text('Get started'));
      await tester.pumpAndSettle();
      expect(store.onboarded, isTrue);
      expect(store.name, name);
      expect(find.byType(WelcomePage), findsNothing);
      expect(find.byType(AppShell), findsOneWidget);
      final restored = FinanceStore(store.prefs);
      await restored.load();
      expect(restored.onboarded, isTrue);
      expect(restored.name, name);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('profile updates currency and country without converting amounts', (
    tester,
  ) async {
    final store = FinanceStore(await SharedPreferences.getInstance());
    await store.start(
      userName: 'Alex',
      selectedCurrency: 'SAR',
      useDemo: false,
      acceptedLegal: true,
    );
    await store.saveEntry(
      Entry(
        id: 'coffee',
        merchant: 'Coffee',
        cents: 1200,
        date: DateTime.now(),
        category: 'Food',
      ),
    );
    await tester.pumpWidget(wrap(SettingsPage(store: store)));
    await tester.pumpAndSettle();
    expectReadOnlyProfile();
    expect(find.byType(AlertDialog), findsNothing);
    await reveal(tester, find.byKey(const Key('edit-profile')));
    await tester.tap(find.byKey(const Key('edit-profile')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('edit-profile-dialog')), findsOneWidget);
    expect(
      find.text(
        'Changing currency updates the account unit. Existing amounts are not converted.',
      ),
      findsOneWidget,
    );
    await choose(tester, const Key('profile-currency'), 'USD');
    await choose(tester, const Key('profile-country'), 'Kuwait');
    final name = find.descendant(
      of: find.byKey(const Key('profile-name')),
      matching: find.byType(TextFormField),
    );
    await reveal(tester, name);
    await tester.enterText(name, 'Samira');
    await reveal(tester, find.byKey(const Key('save-profile')));
    await tester.tap(find.byKey(const Key('save-profile')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('edit-profile-dialog')), findsNothing);
    expectReadOnlyProfile();
    expect(store.currency, 'USD');
    expect(store.countryCode, 'KW');
    expect(store.name, 'Samira');
    expect(store.entries.single.cents, 1200);
    final restored = FinanceStore(store.prefs);
    await restored.load();
    expect(restored.currency, 'USD');
    expect(restored.countryCode, 'KW');
    expect(restored.name, 'Samira');
    expect(
      find.text(
        'Changing currency updates the account unit. Existing amounts are not converted.',
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  for (final language in ['en', 'ar']) {
    testWidgets('$language long names keep phone controls usable', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final name = (language == 'ar' ? 'م' : 'W') * 100;
      final store = FinanceStore(await SharedPreferences.getInstance());
      await store.start(
        userName: name.substring(0, 99),
        selectedCurrency: 'SAR',
        useDemo: false,
        acceptedLegal: true,
      );
      await store.updateProfile(userName: name);
      await store.setLanguage(language);
      await tester.pumpWidget(TadbeerApp(store: store));
      await tester.pumpAndSettle();

      void expectVisible(Finder finder) {
        final rect = tester.getRect(finder);
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(320));
        expect(rect.top, greaterThanOrEqualTo(0));
        expect(rect.bottom, lessThanOrEqualTo(844));
        expect(finder.hitTestable(), findsOneWidget);
      }

      final notifications = find.widgetWithIcon(
        IconButton,
        Icons.notifications_none_rounded,
      );
      final profile = find.ancestor(
        of: find.byType(CircleAvatar),
        matching: find.byType(IconButton),
      );
      final greeting = find.textContaining(name);
      expect(greeting, findsOneWidget);
      for (final button in [notifications, profile]) {
        expectVisible(button);
        expect(
          tester.getRect(greeting).overlaps(tester.getRect(button)),
          isFalse,
        );
      }
      await tester.tap(notifications);
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      await tester.tap(profile);
      await tester.pumpAndSettle();
      expect(find.byType(SettingsPage), findsOneWidget);

      final edit = find.byKey(const Key('edit-profile'));
      await reveal(tester, edit);
      expectVisible(edit);
      for (final element in find.text(name).evaluate()) {
        final text = find.byWidget(element.widget);
        expect(tester.getRect(text).left, greaterThanOrEqualTo(0));
        expect(tester.getRect(text).right, lessThanOrEqualTo(320));
        expect(tester.getRect(text).overlaps(tester.getRect(edit)), isFalse);
      }
      await tester.tap(edit);
      await tester.pumpAndSettle();
      final field = find.descendant(
        of: find.byKey(const Key('profile-name')),
        matching: find.byType(TextFormField),
      );
      expect(tester.widget<TextFormField>(field).controller!.text, name);
      expectNoNameCounter();
      final save = find.byKey(const Key('save-profile'));
      final cancel = find.byKey(const Key('cancel-edit-profile'));
      expectVisible(save);
      expectVisible(cancel);
      expect(tester.getRect(save).overlaps(tester.getRect(cancel)), isFalse);
      await tester.tap(cancel);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('edit-profile-dialog')), findsNothing);
      await tester.tap(edit);
      await tester.pumpAndSettle();
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('edit-profile-dialog')), findsNothing);
      expect(store.name, name);
      final restored = FinanceStore(store.prefs);
      await restored.load();
      expect(restored.name, name);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('$language cancel discards profile edits on a narrow phone', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = FinanceStore(await SharedPreferences.getInstance());
      await store.start(
        userName: 'Alex',
        selectedCurrency: 'SAR',
        useDemo: false,
        acceptedLegal: true,
      );
      final saved = store.prefs.getString('numo_v1');
      await tester.pumpWidget(
        wrap(SettingsPage(store: store), language: language),
      );
      await tester.pumpAndSettle();
      expectReadOnlyProfile();
      await reveal(tester, find.byKey(const Key('edit-profile')));
      await tester.tap(find.byKey(const Key('edit-profile')));
      await tester.pumpAndSettle();
      final dialog = find.byKey(const Key('edit-profile-dialog'));
      expect(dialog, findsOneWidget);
      expect(
        Directionality.of(tester.element(dialog)),
        language == 'ar' ? TextDirection.rtl : TextDirection.ltr,
      );
      final name = find.descendant(
        of: find.byKey(const Key('profile-name')),
        matching: find.byType(TextFormField),
      );
      await reveal(tester, name);
      await tester.enterText(name, 'Unsaved name');
      await choose(tester, const Key('profile-currency'), 'USD');
      await choose(
        tester,
        const Key('profile-country'),
        language == 'ar' ? 'الكويت' : 'Kuwait',
      );
      await reveal(tester, find.byKey(const Key('cancel-edit-profile')));
      await tester.tap(find.byKey(const Key('cancel-edit-profile')));
      await tester.pumpAndSettle();
      expect(dialog, findsNothing);
      expectReadOnlyProfile();
      expect(store.name, 'Alex');
      expect(store.currency, 'SAR');
      expect(store.countryCode, 'SA');
      expect(store.prefs.getString('numo_v1'), saved);
      await tester.tap(find.byKey(const Key('edit-profile')));
      await tester.pumpAndSettle();
      expect(tester.widget<TextFormField>(name).controller!.text, 'Alex');
      final currency = find.descendant(
        of: find.byKey(const Key('profile-currency')),
        matching: find.byType(DropdownButtonFormField<String>),
      );
      final country = find.descendant(
        of: find.byKey(const Key('profile-country')),
        matching: find.byType(DropdownButtonFormField<String>),
      );
      expect(
        tester.widget<DropdownButtonFormField<String>>(currency).initialValue,
        'SAR',
      );
      expect(
        tester.widget<DropdownButtonFormField<String>>(country).initialValue,
        'SA',
      );
      await tester.tap(find.byKey(const Key('cancel-edit-profile')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'name limit counts complete grapheme clusters and gives Arabic feedback',
    (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        wrap(
          Scaffold(body: Form(child: ProfileNameField(controller: controller))),
          language: 'ar',
        ),
      );
      final field = find.byType(TextFormField);
      expectNoNameCounter();
      expect(find.text('يجب ألا يتجاوز الاسم 100 حرف.'), findsNothing);
      final fullName = '👨‍👩‍👧‍👦' * 100;
      await tester.enterText(field, fullName);
      await tester.pump();
      expect(controller.text, fullName);
      expect(tester.widget<TextFormField>(field).validator!(fullName), isNull);
      expectNoNameCounter();
      expect(find.text('يجب ألا يتجاوز الاسم 100 حرف.'), findsNothing);
      await tester.enterText(field, '$fullNameأ');
      await tester.pump();
      expect(controller.text.characters.length, 100);
      expect(find.text('يجب ألا يتجاوز الاسم 100 حرف.'), findsOneWidget);
      expectNoNameCounter();
      await tester.enterText(field, 'أحمد');
      await tester.pump();
      expect(find.text('يجب ألا يتجاوز الاسم 100 حرف.'), findsNothing);
      expectNoNameCounter();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('privacy and terms open from Profile and return with back', (
    tester,
  ) async {
    final store = FinanceStore(await SharedPreferences.getInstance());
    await tester.pumpWidget(wrap(SettingsPage(store: store)));
    await tester.pumpAndSettle();
    expect(find.byType(PrivacyTermsPage), findsNothing);
    await reveal(tester, find.byKey(const Key('view-privacy')));
    await tester.tap(find.byKey(const Key('view-privacy')));
    await tester.pumpAndSettle();
    expect(find.byType(PrivacyTermsPage), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byKey(const Key('privacy-tab')), findsOneWidget);
    await tester.tap(find.byKey(const Key('terms-tab')));
    await tester.pumpAndSettle();
    expect(find.byType(PrivacyTermsPage), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPage), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(PrivacyTermsPage), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'distribution uses all expense categories and current currency, not budget limits',
    (tester) async {
      final store = FinanceStore(await SharedPreferences.getInstance());
      final month = DateTime(2026, 9);
      await store.setCurrency('USD');
      for (final (index, category)
          in ['Food', 'Travel', 'Housing', 'Shopping', 'Utilities'].indexed) {
        await store.saveEntry(
          Entry(
            id: category,
            merchant: category,
            cents: (index + 1) * 1000,
            date: month,
            category: category,
          ),
        );
      }
      await store.saveEntry(
        Entry(
          id: 'salary',
          merchant: 'Salary',
          cents: 999999,
          date: month,
          category: 'Income',
          income: true,
        ),
      );
      await store.setBudget(month, 'Food', 999999);
      await tester.pumpWidget(
        wrap(
          Scaffold(
            body: SingleChildScrollView(
              child: BudgetDistribution(store: store, month: month),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Expense distribution'), findsOneWidget);
      expect(find.text('USD 150.00 spent across categories'), findsOneWidget);
      expect(find.text('Other categories'), findsNothing);
      for (final (category, percentage, amount) in [
        ('Food', '6.7%', 'USD 10.00'),
        ('Travel', '13.3%', 'USD 20.00'),
        ('Housing', '20%', 'USD 30.00'),
        ('Shopping', '26.7%', 'USD 40.00'),
        ('Utilities', '33.3%', 'USD 50.00'),
      ]) {
        final row = find.byKey(ValueKey('expense-share-$category'));
        expect(
          find.descendant(of: row, matching: find.text(percentage)),
          findsOneWidget,
        );
        expect(
          find.descendant(of: row, matching: find.text(amount)),
          findsOneWidget,
        );
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'future transactions are reachable using next month and month picker',
    (tester) async {
      final store = FinanceStore(await SharedPreferences.getInstance());
      await store.start(
        userName: 'Alex',
        selectedCurrency: 'SAR',
        useDemo: false,
        acceptedLegal: true,
      );
      final now = DateTime.now();
      final future = DateTime(now.year, now.month + 1, 15);
      await store.saveEntry(
        Entry(
          id: 'future',
          merchant: 'Planned payment',
          cents: 1234,
          date: future,
          category: 'Other',
        ),
      );
      await tester.pumpWidget(TadbeerApp(store: store));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Transactions'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('choose-month')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('choose-month-${now.month}')));
      await tester.pumpAndSettle();
      expect(find.text('Planned payment'), findsNothing);
      await tester.tap(find.byTooltip('Next month'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Planned payment'),
        200,
        scrollable:
            find
                .descendant(
                  of: find.byType(TransactionsPage),
                  matching: find.byType(Scrollable),
                )
                .first,
      );
      expect(find.text('Planned payment'), findsOneWidget);
      await tester.tap(find.byKey(const Key('choose-month')));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.byKey(ValueKey('choose-month-${future.month}')));
      await tester.pumpAndSettle();
      expect(find.byType(TransactionsPage), findsOneWidget);
      expect(find.text('Planned payment'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );
}
