import 'dart:async';

import 'package:financial_advisor/core/finance_store.dart';
import 'package:financial_advisor/core/financial_report.dart';
import 'package:financial_advisor/l10n/app_language.dart';
import 'package:financial_advisor/screens/report_export.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'report_export_test.dart' as helpers;

void main() {
  testWidgets(
    'report starts with PDF and can switch format without losing filters',
    (tester) async {
      final store = await helpers.makeStore();
      await tester.pumpWidget(
        helpers.app(
          ReportExportPage(store: store, clock: () => DateTime(2026, 10, 4)),
        ),
      );
      expect(
        tester
            .widget<DropdownButtonFormField<ReportFormat>>(
              find.byKey(const Key('report-format')),
            )
            .initialValue,
        ReportFormat.pdf,
      );
      expect(find.text('All Time'), findsOneWidget);
      await helpers.tap(tester, find.byKey(const Key('report-period')));
      await helpers.tap(tester, find.text('Month and year').last);
      await helpers.tap(tester, find.byKey(const Key('report-language')));
      await helpers.tap(tester, find.text('English').last);
      await helpers.tap(tester, find.byKey(const Key('report-format')));
      await helpers.tap(tester, find.text('Microsoft Word (.docx)').last);
      expect(find.text('Month and year'), findsOneWidget);
      expect(find.byKey(const Key('report-month')), findsOneWidget);
      expect(find.text('English'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Word and preview share one snapshot and English export preserves Arabic app language',
    (tester) async {
      const printing = MethodChannel('net.nfet.printing');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            printing,
            (_) async => {'canRaster': false},
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(printing, null),
      );
      final store = await helpers.makeStore();
      store.languageCode = 'ar';
      final pending = Completer<Uint8List>();
      final docx = Uint8List.fromList([80, 75, 3, 4]);
      final pdf = Uint8List.fromList([37, 80, 68, 70]);
      FinancialReport? wordSnapshot;
      FinancialReport? previewSnapshot;
      await tester.pumpWidget(
        helpers.app(
          ReportExportPage(
            store: store,
            clock: () => DateTime(2026, 10, 4),
            wordBuilder: (report, {required language}) {
              expect(language, 'en');
              wordSnapshot = report;
              return pending.future;
            },
            pdfBuilder: (report, {required language}) async {
              expect(language, 'en');
              previewSnapshot = report;
              return pdf;
            },
          ),
          language: 'ar',
        ),
      );
      await helpers.tap(tester, find.byKey(const Key('report-period')));
      await helpers.tap(tester, find.text('الشهر والسنة').last);
      await helpers.tap(tester, find.byKey(const Key('report-language')));
      await helpers.tap(tester, find.text('English').last);
      await helpers.tap(tester, find.byKey(const Key('report-format')));
      await helpers.tap(tester, find.text('Microsoft Word (.docx)').last);
      final button = find.byKey(const Key('preview-report'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));
      expect(tester.widget<FilledButton>(button).onPressed, isNull);
      store.entries.add(
        Entry(
          id: 'after-snapshot',
          merchant: 'Later',
          cents: 9900,
          date: DateTime(2026, 10, 3),
          category: 'Food',
        ),
      );
      pending.complete(docx);
      await tester.pumpAndSettle();
      expect(identical(wordSnapshot, previewSnapshot), isTrue);
      expect(wordSnapshot!.transactionCount, 1);
      expect(wordSnapshot!.expenseCents, 20000);
      expect(store.languageCode, 'ar');
      final page = tester.widget<ReportPreviewPage>(
        find.byType(ReportPreviewPage),
      );
      expect(page.format, ReportFormat.word);
      expect(page.filename, 'tadbeer-report-2026-10-04-en.docx');
      expect(page.bytes, docx);
      expect(page.previewBytes, pdf);
      expect(find.text('حفظ Word'), findsOneWidget);
      expect(find.byKey(const Key('save-report-pdf')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('valid Word remains exportable when PDF preview generation fails', (
    tester,
  ) async {
    final store = await helpers.makeStore();
    final bytes = Uint8List.fromList([80, 75, 3, 4]);
    await tester.pumpWidget(
      helpers.app(
        ReportExportPage(
          store: store,
          wordBuilder: (_, {required language}) async => bytes,
          pdfBuilder:
              (_, {required language}) async =>
                  throw StateError('preview only failed'),
        ),
      ),
    );
    await helpers.tap(tester, find.byKey(const Key('report-format')));
    await helpers.tap(tester, find.text('Microsoft Word (.docx)').last);
    await helpers.tap(tester, find.byKey(const Key('preview-report')));
    final page = tester.widget<ReportPreviewPage>(
      find.byType(ReportPreviewPage),
    );
    expect(page.bytes, bytes);
    expect(page.previewBytes, isNull);
    expect(
      find.text(
        'Your Word document is ready. Open the saved file in Microsoft Word or a compatible app.',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('save-report-word')), findsOneWidget);
    expect(find.byKey(const Key('share-report-word')), findsOneWidget);
    expect(
      find.text('Could not create the report. Please try again.'),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Word generation failure permits retry with the selected format',
    (tester) async {
      final store = await helpers.makeStore();
      var attempts = 0;
      await tester.pumpWidget(
        helpers.app(
          ReportExportPage(
            store: store,
            wordBuilder: (_, {required language}) async {
              attempts++;
              if (attempts == 1) throw StateError('word generation failed');
              return Uint8List.fromList([80, 75]);
            },
            previewBuilder: (_, filename) => Scaffold(body: Text(filename)),
            clock: () => DateTime(2026, 10, 4),
          ),
        ),
      );
      await helpers.tap(tester, find.byKey(const Key('report-format')));
      await helpers.tap(tester, find.text('Microsoft Word (.docx)').last);
      await helpers.tap(tester, find.byKey(const Key('preview-report')));
      expect(
        find.text('Could not create the report. Please try again.'),
        findsOneWidget,
      );
      await helpers.tap(tester, find.byKey(const Key('preview-report')));
      expect(attempts, 2);
      expect(find.text('tadbeer-report-2026-10-04-en.docx'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Word preview has platform-appropriate actions and no PDF print instructions',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        helpers.app(
          ReportPreviewPage(
            bytes: Uint8List.fromList([80, 75]),
            filename: 'report.docx',
            format: ReportFormat.word,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Save Word'), findsOneWidget);
      expect(
        find.text(
          defaultTargetPlatform == TargetPlatform.windows
              ? 'Open Word'
              : 'Share Word',
        ),
        findsOneWidget,
      );
      expect(
        find.text('Choose Microsoft Print to PDF in the print dialog.'),
        findsNothing,
      );
      expect(
        find.text('Choose Save as PDF in the print dialog.'),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.windows,
    }),
  );

  test('Word export copy is localized', () {
    for (final text in [
      'Export report',
      'File format',
      'Save Word',
      'Share Word',
      'Open Word',
      'Word document saved.',
      'Word document downloaded.',
      'Could not export the Word document. Please try again.',
      'Word layout may differ from this preview.',
    ]) {
      expect(translate(text, 'ar'), isNot(text));
    }
  });
}
