import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:financial_advisor/main.dart';
import 'package:financial_advisor/core/finance_store.dart';
import 'package:financial_advisor/screens/home.dart';
import 'package:financial_advisor/screens/transactions.dart';
import 'package:financial_advisor/widgets/language_selector.dart';

void main() {
  testWidgets('onboarding creates an empty workspace with one start action', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final store = FinanceStore(await SharedPreferences.getInstance());
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(TadbeerApp(store: store));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Get started'),
      200,
      scrollable:
          find
              .descendant(
                of: find.byType(WelcomePage),
                matching: find.byType(Scrollable),
              )
              .first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Explore with sample data'), findsNothing);
    expect(find.byType(LanguageSelector), findsNothing);
    expect(find.textContaining('Data stays on this device'), findsNothing);
    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();
    expect(store.onboarded, isTrue);
    expect(store.entries, isEmpty);
    expect(store.demo, isFalse);
    expect(find.textContaining('Hello,'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('all four money management destinations render on mobile', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final store = FinanceStore(await SharedPreferences.getInstance());
    await store.start(userName: 'Alex', selectedCurrency: 'SAR', useDemo: true);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(TadbeerApp(store: store));
    await tester.pumpAndSettle();
    expect(find.text('4,250.00'), findsOneWidget);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).destinations,
      hasLength(4),
    );
    for (final label in ['Transactions', 'Analysis', 'Profile', 'Home']) {
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text(label),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '$label layout');
    }
    expect(find.byType(HomePage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'home actions save income and expenses to the monthly cash flow',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final store = FinanceStore(await SharedPreferences.getInstance());
      await store.start(
        userName: 'Alex',
        selectedCurrency: 'SAR',
        useDemo: false,
      );
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(TadbeerApp(store: store));
      await tester.pumpAndSettle();

      for (final isIncome in [true, false]) {
        final label = isIncome ? 'Add income' : 'Add expense';
        await tester.scrollUntilVisible(
          find.text(label),
          200,
          scrollable:
              find
                  .descendant(
                    of: find.byType(HomePage),
                    matching: find.byType(Scrollable),
                  )
                  .first,
        );
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<SegmentedButton<bool>>(find.byType(SegmentedButton<bool>))
              .selected,
          {isIncome},
        );
        final fields = find.descendant(
          of: find.byType(EntryEditor),
          matching: find.byType(TextFormField),
        );
        await tester.enterText(fields.at(0), isIncome ? 'Salary' : 'Groceries');
        await tester.enterText(fields.at(1), isIncome ? '5000.00' : '150.00');
        await tester.ensureVisible(find.text('Save transaction'));
        await tester.tap(find.text('Save transaction'));
        await tester.pumpAndSettle();
        expect(find.byType(EntryEditor), findsNothing);
      }
      final month = DateTime.now();
      expect(store.incomeFor(month), 500000);
      expect(store.expensesFor(month), 15000);
      await tester.scrollUntilVisible(
        find.text('MONTHLY CASH FLOW'),
        -300,
        scrollable:
            find
                .descendant(
                  of: find.byType(HomePage),
                  matching: find.byType(Scrollable),
                )
                .first,
      );
      expect(find.text('4,850.00'), findsOneWidget);

      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Transactions'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Salary'), findsOneWidget);
      expect(find.text('Groceries'), findsOneWidget);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Income'));
      await tester.pumpAndSettle();
      expect(find.text('Salary'), findsOneWidget);
      expect(find.text('Groceries'), findsNothing);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Expenses'));
      await tester.pumpAndSettle();
      expect(find.text('Salary'), findsNothing);
      expect(find.text('Groceries'), findsOneWidget);

      final restored = FinanceStore(store.prefs);
      await restored.load();
      expect(restored.incomeFor(month), 500000);
      expect(restored.expensesFor(month), 15000);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'home budget summary follows the selected month and opens Analysis',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final store = FinanceStore(await SharedPreferences.getInstance());
      await store.start(
        userName: 'Alex',
        selectedCurrency: 'SAR',
        useDemo: false,
      );
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(TadbeerApp(store: store));
      await tester.pumpAndSettle();
      final manageBudget = find.byKey(const Key('home-manage-budget'));
      await tester.scrollUntilVisible(
        manageBudget,
        500,
        scrollable:
            find
                .descendant(
                  of: find.byType(HomePage),
                  matching: find.byType(Scrollable),
                )
                .first,
      );
      expect(find.text('No budget set for this month.'), findsOneWidget);

      final now = DateTime.now();
      await store.setBudget(now, 'Overall', 50000);
      await store.saveEntry(
        Entry(
          id: 'groceries',
          merchant: 'Groceries',
          cents: 12500,
          date: now,
          category: 'Food',
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(manageBudget);
      expect(find.text('Remaining budget'), findsOneWidget);
      expect(find.textContaining('375.00'), findsOneWidget);

      await store.saveEntry(
        Entry(
          id: 'groceries',
          merchant: 'Groceries',
          cents: 62500,
          date: now,
          category: 'Food',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Over budget'), findsOneWidget);
      expect(find.textContaining('125.00'), findsOneWidget);
      await tester.tap(find.byTooltip('Previous month'));
      await tester.pumpAndSettle();
      expect(find.text('No budget set for this month.'), findsOneWidget);

      await tester.ensureVisible(manageBudget);
      await tester.tap(manageBudget);
      await tester.pumpAndSettle();
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        2,
      );
      expect(find.text('Analysis & planning'), findsOneWidget);
      expect(find.text('No overall budget set'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
