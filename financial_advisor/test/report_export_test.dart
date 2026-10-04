import 'dart:async';

import 'package:financial_advisor/core/finance_store.dart';
import 'package:financial_advisor/core/financial_report.dart';
import 'package:financial_advisor/l10n/app_language.dart';
import 'package:financial_advisor/main.dart';
import 'package:financial_advisor/screens/report_export.dart';
import 'package:financial_advisor/widgets/design.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<FinanceStore> makeStore() async {
  SharedPreferences.setMockInitialValues({});
  return FinanceStore(await SharedPreferences.getInstance())
    ..name = 'Report QA'
    ..currency = 'SAR'
    ..entries = [
      Entry(
        id: 'income',
        merchant: 'Salary',
        cents: 100000,
        date: DateTime(2026, 9, 30),
        category: 'Income',
        income: true,
      ),
      Entry(
        id: 'expense',
        merchant: 'Groceries',
        cents: 20000,
        date: DateTime(2026, 10, 2),
        category: 'Food',
        income: false,
      ),
      Entry(
        id: 'scheduled',
        merchant: 'Upcoming',
        cents: 90000,
        date: DateTime(2026, 10, 8),
        category: 'Other',
        income: false,
        isProjected: true,
      ),
    ];
}

Widget app(Widget child, {String language = 'en'}) => MaterialApp(
  theme: appTheme(),
  locale: Locale(language),
  supportedLocales: const [Locale('en'), Locale('ar')],
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  home: child,
);

Future<void> tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'missing printing plugin fails gracefully and keeps export retryable',
    (tester) async {
      const channel = MethodChannel('net.nfet.printing');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async {
            throw MissingPluginException(
              'Printing is unavailable in this test',
            );
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      await tester.pumpWidget(
        app(
          ReportPreviewPage(
            bytes: Uint8List.fromList([37, 80, 68, 70]),
            filename: 'qa-report.pdf',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Preview is unavailable. You can still save or share the PDF.',
        ),
        findsOneWidget,
      );
      await tap(tester, find.byKey(const Key('share-report-pdf')));
      expect(
        find.text('Could not export the PDF. Please try again.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const Key('share-report-pdf')))
            .onPressed,
        isNotNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Windows opens the PDF viewer and explains how to save and share',
    (tester) async {
      const channel = MethodChannel('net.nfet.printing');
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            if (call.method == 'printingInfo') {
              return {'canRaster': false, 'canPrint': true, 'canShare': true};
            }
            if (call.method == 'sharePdf') return 1;
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final bytes = Uint8List.fromList([37, 80, 68, 70]);
      await tester.pumpWidget(
        app(ReportPreviewPage(bytes: bytes, filename: 'qa-report.pdf')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Open PDF'), findsOneWidget);
      expect(find.text('Share PDF'), findsNothing);
      expect(find.text('Share from your PDF viewer.'), findsOneWidget);
      expect(
        find.text('Choose Microsoft Print to PDF in the print dialog.'),
        findsOneWidget,
      );
      expect(
        find.text('Choose Save as PDF in the print dialog.'),
        findsNothing,
      );
      await tap(tester, find.text('Open PDF'));
      final open = calls.singleWhere((call) => call.method == 'sharePdf');
      expect(open.arguments['name'], 'qa-report.pdf');
      expect(open.arguments['doc'], bytes);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({TargetPlatform.windows}),
  );

  testWidgets(
    'native open failure reports an error while Android share cancellation stays quiet',
    (tester) async {
      const channel = MethodChannel('net.nfet.printing');
      var shareCalls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'printingInfo') {
              return {'canRaster': false, 'canPrint': true, 'canShare': true};
            }
            if (call.method == 'sharePdf') {
              shareCalls++;
              return 0;
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      await tester.pumpWidget(
        app(
          ReportPreviewPage(
            bytes: Uint8List.fromList([37, 80, 68, 70]),
            filename: 'qa-report.pdf',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Retry'), findsOneWidget);
      expect(
        find.text('Refresh this page to try the preview again.'),
        findsNothing,
      );
      final button = find.byKey(const Key('share-report-pdf'));
      await tap(tester, button);
      expect(shareCalls, 1);
      expect(
        find.text('Could not export the PDF. Please try again.'),
        defaultTargetPlatform == TargetPlatform.windows
            ? findsOneWidget
            : findsNothing,
      );
      expect(tester.widget<OutlinedButton>(button).onPressed, isNotNull);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.windows,
      TargetPlatform.android,
    }),
  );

  test('web preview recovery instruction has English and Arabic text', () {
    const text = 'Refresh this page to try the preview again.';
    expect(translate(text, 'en'), text);
    expect(
      translate(text, 'ar'),
      'أعد تحميل هذه الصفحة للمحاولة مجددًا في عرض المعاينة.',
    );
  });

  testWidgets(
    'preview failure preserves save/share and export errors can be retried',
    (tester) async {
      const channel = MethodChannel('net.nfet.printing');
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            if (call.method == 'printingInfo') {
              return {'canRaster': false, 'canPrint': true, 'canShare': true};
            }
            if (call.method == 'sharePdf') return 1;
            if (call.method == 'printPdf') {
              throw PlatformException(code: 'test_print_failure');
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final bytes = Uint8List.fromList([37, 80, 68, 70]);
      await tester.pumpWidget(
        app(ReportPreviewPage(bytes: bytes, filename: 'qa-report.pdf')),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Preview is unavailable. You can still save or share the PDF.',
        ),
        findsOneWidget,
      );
      await tap(tester, find.text('Share PDF'));
      final share = calls.singleWhere((call) => call.method == 'sharePdf');
      expect(share.arguments['name'], 'qa-report.pdf');
      expect(share.arguments['doc'], bytes);
      await tap(tester, find.text('Save PDF'));
      expect(calls.where((call) => call.method == 'printPdf'), hasLength(1));
      expect(
        find.text('Could not export the PDF. Please try again.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('save-report-pdf')))
            .onPressed,
        isNotNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Arabic report controls fit a narrow phone screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = await makeStore();
    await tester.pumpWidget(
      app(ReportExportPage(store: store), language: 'ar'),
    );
    await tap(tester, find.byKey(const Key('report-period')));
    await tap(tester, find.text('الشهر والسنة').last);
    expect(find.byKey(const Key('report-month')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Profile export button opens an All Time report', (tester) async {
    final store = await makeStore();
    await tester.pumpWidget(app(SettingsPage(store: store)));
    await tap(tester, find.byKey(const Key('export-pdf-report')));
    expect(find.byType(ReportExportPage), findsOneWidget);
    expect(find.text('All Time'), findsOneWidget);
    expect(find.text('App language'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'English export in Arabic app leaves app language and data intact',
    (tester) async {
      final store = await makeStore();
      store.languageCode = 'ar';
      FinancialReport? report;
      String? selectedLanguage;
      await tester.pumpWidget(
        app(
          ReportExportPage(
            store: store,
            clock: () => DateTime(2026, 10, 3),
            pdfBuilder: (snapshot, {required language}) async {
              report = snapshot;
              selectedLanguage = language;
              return Uint8List.fromList([37, 80, 68, 70]);
            },
            previewBuilder: (_, filename) => Scaffold(body: Text(filename)),
          ),
          language: 'ar',
        ),
      );
      await tap(tester, find.byKey(const Key('report-language')));
      await tap(tester, find.text('English').last);
      await tap(tester, find.byKey(const Key('preview-report')));
      expect(selectedLanguage, 'en');
      expect(report!.period.kind, ReportPeriodKind.allTime);
      expect(report!.incomeCents, 100000);
      expect(report!.expenseCents, 20000);
      expect(report!.transactionCount, 2);
      expect(store.languageCode, 'ar');
      expect(store.entries.length, 3);
      expect(find.text('tadbeer-report-2026-10-03-en.pdf'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'month filter is passed to report builder with the current app language',
    (tester) async {
      final store = await makeStore();
      FinancialReport? report;
      await tester.pumpWidget(
        app(
          ReportExportPage(
            store: store,
            clock: () => DateTime(2026, 10, 3),
            pdfBuilder: (snapshot, {required language}) async {
              expect(language, 'en');
              report = snapshot;
              return Uint8List.fromList([37, 80, 68, 70]);
            },
            previewBuilder:
                (_, __) => const Scaffold(body: Text('Preview fixture')),
          ),
        ),
      );
      await tap(tester, find.byKey(const Key('report-period')));
      await tap(tester, find.text('Month and year').last);
      await tap(tester, find.byKey(const Key('preview-report')));
      expect(report!.period.start, DateTime(2026, 10));
      expect(report!.incomeCents, 0);
      expect(report!.expenseCents, 20000);
      expect(report!.transactionCount, 1);
    },
  );

  testWidgets(
    'custom date controls reject reversed ranges before PDF generation',
    (tester) async {
      final store = await makeStore();
      await tester.pumpWidget(
        app(ReportExportPage(store: store, clock: () => DateTime(2026, 10, 3))),
      );
      await tap(tester, find.byKey(const Key('report-period')));
      await tap(tester, find.text('Custom date range').last);
      await tap(tester, find.byKey(const Key('report-start-date')));
      await tap(tester, find.byIcon(Icons.edit_outlined));
      await tester.enterText(find.byType(TextField), '10/20/2026');
      await tap(tester, find.text('OK'));
      expect(
        find.text('End date must be on or after start date.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('preview-report')))
            .onPressed,
        isNull,
      );
    },
  );

  testWidgets(
    'failed generation allows retry and duplicate taps cannot start another export',
    (tester) async {
      final store = await makeStore();
      final first = Completer<Uint8List>();
      var calls = 0;
      await tester.pumpWidget(
        app(
          ReportExportPage(
            store: store,
            pdfBuilder: (report, {required language}) {
              calls++;
              return calls == 1
                  ? first.future
                  : Future.value(Uint8List.fromList([37, 80, 68, 70]));
            },
            previewBuilder:
                (_, __) => const Scaffold(body: Text('Preview fixture')),
          ),
        ),
      );
      final button = find.byKey(const Key('preview-report'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));
      expect(calls, 1);
      expect(tester.widget<FilledButton>(button).onPressed, isNull);
      first.completeError(StateError('fixture generation failure'));
      await tester.pumpAndSettle();
      expect(
        find.text('Could not create the report. Please try again.'),
        findsOneWidget,
      );
      await tap(tester, button);
      expect(calls, 2);
      expect(find.text('Preview fixture'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
