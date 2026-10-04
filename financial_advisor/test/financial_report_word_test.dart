import 'dart:convert';
import 'dart:io';
import 'dart:typed_data' show Endian;

import 'package:archive/archive.dart';
import 'package:financial_advisor/core/finance_store.dart';
import 'package:financial_advisor/core/financial_report.dart';
import 'package:financial_advisor/l10n/report_language.dart';
import 'package:financial_advisor/services/financial_report_word.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xml/xml.dart';

import 'support/report_design_fixture.dart';

String contents(Archive archive, String path) =>
    utf8.decode(archive.findFile(path)!.content);
XmlDocument document(Archive archive, String path) =>
    XmlDocument.parse(contents(archive, path));
Iterable<XmlElement> elements(XmlNode node, String name) =>
    node.descendants.whereType<XmlElement>().where((e) => e.name.local == name);
String editableText(Archive archive) => elements(
  document(archive, 'word/document.xml'),
  't',
).map((e) => e.innerText).join('\n');

void validateOfficeZip(List<int> bytes) {
  final data = ByteData.sublistView(Uint8List.fromList(bytes));
  var end = bytes.length - 22;
  while (end >= 0 && data.getUint32(end, Endian.little) != 0x06054b50) {
    end--;
  }
  expect(end, greaterThanOrEqualTo(0));
  final count = data.getUint16(end + 10, Endian.little);
  var cursor = data.getUint32(end + 16, Endian.little);
  for (var i = 0; i < count; i++) {
    expect(data.getUint32(cursor, Endian.little), 0x02014b50);
    final local = data.getUint32(cursor + 42, Endian.little);
    expect(data.getUint32(local, Endian.little), 0x04034b50);
    // Word rejects archive's UTF-8 filename bit for these ASCII part names,
    // even when other ZIP readers can open the otherwise valid package.
    expect(data.getUint16(cursor + 8, Endian.little) & 0x800, 0);
    expect(data.getUint16(local + 6, Endian.little) & 0x800, 0);
    cursor +=
        46 +
        data.getUint16(cursor + 28, Endian.little) +
        data.getUint16(cursor + 30, Endian.little) +
        data.getUint16(cursor + 32, Endian.little);
  }
}

void validatePackage(Archive archive) {
  final names = archive.files.map((e) => e.name).toSet();
  for (final file in archive.files) {
    if (file.name.endsWith('.xml') || file.name.endsWith('.rels')) {
      final xml = XmlDocument.parse(utf8.decode(file.content));
      if (file.name.endsWith('.rels')) {
        final base =
            file.name == '_rels/.rels'
                ? Uri.parse('package:///')
                : Uri.parse(
                  'package:///${file.name.replaceFirst('/_rels/', '/').replaceFirst(RegExp(r'\.rels$'), '')}',
                );
        for (final rel in elements(xml, 'Relationship')) {
          expect(rel.getAttribute('TargetMode'), isNot('External'));
          final target = base
              .resolve(rel.getAttribute('Target')!)
              .path
              .substring(1);
          expect(
            names,
            contains(target),
            reason: '${file.name} must resolve $target',
          );
        }
      }
    }
    if (file.name.endsWith('.xlsx')) {
      validateOfficeZip(file.content);
      validatePackage(ZipDecoder().decodeBytes(file.content));
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FinanceStore store;
  final generatedAt = DateTime(2026, 10, 4, 12);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = FinanceStore(await SharedPreferences.getInstance())
      ..currency = 'SAR';
  });

  for (final language in ['en', 'ar']) {
    test(
      'editable $language Word document preserves approved report data and native charts',
      () async {
        seedApprovedReportDesign(store);
        final report = FinancialReport.fromStore(
          store,
          generatedAt: generatedAt,
        );
        final bytes = await buildFinancialReportWord(
          report,
          language: language,
        );
        final archive = ZipDecoder().decodeBytes(bytes);
        validateOfficeZip(bytes);
        final copy = ReportCopy(languageCode: language);
        validatePackage(archive);
        final text = editableText(archive);
        expect(text, contains(copy.amountNumber(7550000)));
        expect(text, contains(copy.amountNumber(5620000)));
        expect(text, contains(copy.amountNumber(1930000)));
        expect(text, contains(copy.transactionBreakdown(report)));
        expect(text, contains(copy.amountNumber(2729000)));
        expect(text, contains(copy.scenarioNarrative(report)));
        for (final entry in report.scheduledTransactions) {
          expect(text, contains(entry.merchant));
        }
        final charts =
            archive.files
                .where(
                  (e) =>
                      RegExp(r'^word/charts/chart\d+\.xml$').hasMatch(e.name),
                )
                .toList();
        expect(charts, hasLength(5));
        expect(
          archive.files.where((e) => e.name.endsWith('.xlsx')),
          hasLength(5),
        );
        expect(
          archive.files.where((e) => e.name.startsWith('word/media/')),
          isEmpty,
          reason:
              'The report must contain editable text and charts, not page screenshots',
        );
        final chart = document(archive, 'word/charts/chart1.xml');
        final series = elements(chart, 'ser').toList();
        final income = elements(
          elements(series[0], 'numCache').single,
          'v',
        ).map((e) => double.parse(e.innerText)).reduce((a, b) => a + b);
        final expense = elements(
          elements(series[1], 'numCache').single,
          'v',
        ).map((e) => double.parse(e.innerText)).reduce((a, b) => a + b);
        expect(income, 75500);
        expect(expense, 56200);
        expect(report.scheduledExpenseCents, greaterThan(0));
        final body = document(archive, 'word/document.xml');
        expect(elements(body, 'pageBreakBefore'), hasLength(4));
        expect(elements(body, 'bidi').isNotEmpty, language == 'ar');
        expect(elements(body, 'bidiVisual').isNotEmpty, language == 'ar');
        expect(contents(archive, 'word/footer1.xml'), contains('NUMPAGES'));
        expect(contents(archive, 'word/footer1.xml'), isNot(contains('Hindi')));
        expect(
          contents(archive, 'word/document.xml'),
          contains('w:pgNumType w:fmt="decimal"'),
        );
        expect(
          contents(archive, 'word/document.xml'),
          contains('w:pStyle w:val="Title"'),
        );
        for (final item in charts) {
          final parsed = XmlDocument.parse(utf8.decode(item.content));
          expect(
            elements(parsed, 'lang').single.getAttribute('val'),
            language == 'ar' ? 'ar-SA' : 'en-US',
          );
        }
        if (const bool.fromEnvironment('WRITE_REPORT_FIXTURES')) {
          final directory = Directory('.dart_tool/word-qa')
            ..createSync(recursive: true);
          File(
            '${directory.path}/report-$language.docx',
          ).writeAsBytesSync(bytes);
        }
      },
    );
  }

  test(
    'both report fonts are embedded in full and reverse to their original assets',
    () async {
      final report = FinancialReport.fromStore(store, generatedAt: generatedAt);
      final archive = ZipDecoder().decodeBytes(
        await buildFinancialReportWord(report, language: 'ar'),
      );
      final table = document(archive, 'word/fontTable.xml');
      const paths = [
        'Lato-Regular.ttf',
        'Lato-Bold.ttf',
        'IBMPlexSansArabic-Regular.ttf',
        'IBMPlexSansArabic-SemiBold.ttf',
      ];
      final links =
          table.descendants
              .whereType<XmlElement>()
              .where((e) => e.name.local.startsWith('embed'))
              .toList();
      expect(links, hasLength(4));
      for (var i = 0; i < links.length; i++) {
        final key = links[i].attributes
            .singleWhere((e) => e.name.local == 'fontKey')
            .value
            .replaceAll(RegExp(r'[{}-]'), '');
        final data = List<int>.from(
          archive.findFile('word/fonts/font${i + 1}.odttf')!.content,
        );
        final mask = List.generate(
          16,
          (j) => int.parse(key.substring(j * 2, j * 2 + 2), radix: 16),
        );
        for (var j = 0; j < 32; j++) {
          data[j] ^= mask[15 - j % 16];
        }
        final asset = await rootBundle.load('assets/fonts/${paths[i]}');
        expect(
          data,
          orderedEquals(
            asset.buffer.asUint8List(asset.offsetInBytes, asset.lengthInBytes),
          ),
        );
      }
      expect(
        contents(archive, 'word/settings.xml'),
        contains('saveSubsetFonts w:val="0"'),
      );
      expect(
        archive.findFile('word/fonts/ibm-plex-sans-arabic-OFL.txt'),
        isNotNull,
      );
    },
  );

  test(
    'monthly Word charts and embedded worksheets contain only the selected month',
    () async {
      seedApprovedReportDesign(store);
      final report = FinancialReport.fromStore(
        store,
        period: ReportPeriod.month(DateTime(2026, 9)),
        generatedAt: generatedAt,
      );
      final bytes = await buildFinancialReportWord(report, language: 'ar');
      final archive = ZipDecoder().decodeBytes(bytes);
      final copy = ReportCopy(languageCode: 'ar');
      final text = editableText(archive);
      expect(text, contains(copy.transactionBreakdown(report)));
      expect(text, contains(copy.amountNumber(1050000)));
      expect(text, isNot(contains(copy.amountNumber(5620000))));
      expect(
        text,
        contains(
          copy.t('No scheduled transactions fall within this report window.'),
        ),
      );
      final workbook = ZipDecoder().decodeBytes(
        archive.findFile('word/embeddings/chart1.xlsx')!.content,
      );
      final cells =
          elements(
            document(workbook, 'xl/worksheets/sheet1.xml'),
            'c',
          ).toList();
      final income = cells
          .where(
            (e) =>
                e.getAttribute('r')!.startsWith('B') &&
                e.getAttribute('t') != 'inlineStr',
          )
          .map((e) => double.parse(e.innerText))
          .reduce((a, b) => a + b);
      final expense = cells
          .where(
            (e) =>
                e.getAttribute('r')!.startsWith('C') &&
                e.getAttribute('t') != 'inlineStr',
          )
          .map((e) => double.parse(e.innerText))
          .reduce((a, b) => a + b);
      expect(income, 12000);
      expect(expense, 10500);
      validatePackage(archive);
      if (const bool.fromEnvironment('WRITE_REPORT_FIXTURES')) {
        File('.dart_tool/word-qa/monthly-ar.docx').writeAsBytesSync(bytes);
      }
    },
  );

  test(
    'empty range uses translated no-data statements without fabricated charts',
    () async {
      final report = FinancialReport.fromStore(
        store,
        period: ReportPeriod.range(DateTime(2026, 1, 5), DateTime(2026, 1, 7)),
        generatedAt: generatedAt,
      );
      final bytes = await buildFinancialReportWord(report, language: 'ar');
      final archive = ZipDecoder().decodeBytes(bytes);
      final text = editableText(archive);
      expect(
        text,
        contains(
          const ReportCopy(
            languageCode: 'ar',
          ).t('No recorded transactions in this period.'),
        ),
      );
      expect(
        archive.files.where((e) => e.name.startsWith('word/charts/')),
        isEmpty,
      );
      validatePackage(archive);
      if (const bool.fromEnvironment('WRITE_REPORT_FIXTURES')) {
        File('.dart_tool/word-qa/empty-ar.docx').writeAsBytesSync(bytes);
      }
    },
  );

  test(
    'long upcoming table includes every occurrence without changing recorded totals',
    () async {
      store.recurringTransactions = [
        for (var i = 0; i < 500; i++)
          RecurringTransaction(
            id: 'future-$i',
            merchant: 'Unique scheduled merchant $i',
            cents: 12345,
            category: 'Other',
            income: false,
            startDate: DateTime(2026, 10, 5),
            endDate: DateTime(2026, 10, 5),
            frequency: RepeatFrequency.monthly,
          ),
      ];
      final report = FinancialReport.fromStore(store, generatedAt: generatedAt);
      final archive = ZipDecoder().decodeBytes(
        await buildFinancialReportWord(report, language: 'en'),
      );
      final text = editableText(archive);
      expect(report.expenseCents, 0);
      expect(report.transactionCount, 0);
      expect(report.scheduledTransactions, hasLength(500));
      final words =
          elements(
            document(archive, 'word/document.xml'),
            't',
          ).map((e) => e.innerText).toList();
      for (var i = 0; i < 500; i++) {
        expect(
          words.where((text) => text == 'Unique scheduled merchant $i'),
          hasLength(1),
        );
      }
      expect(text, contains('61,725'));
      expect(
        contents(archive, 'word/document.xml'),
        contains('<w:tblHeader/>'),
      );
      validatePackage(archive);
    },
  );

  test(
    'negative amounts and untrusted text remain safe editable text',
    () async {
      store.name = '<w:p>Owner & "user"\u0001</w:p>';
      store.entries = [
        Entry(
          id: 'expense',
          merchant: 'Expense',
          cents: 32199,
          date: DateTime(2026, 9, 15),
          category: '=HYPERLINK("unsafe") < & >',
        ),
      ];
      store.recurringTransactions = [
        RecurringTransaction(
          id: 'future',
          merchant: '</w:t> & <script>\u0002',
          cents: 1000,
          category: 'Other',
          income: false,
          startDate: DateTime(2026, 10, 5),
          endDate: DateTime(2026, 10, 5),
          frequency: RepeatFrequency.monthly,
        ),
      ];
      final report = FinancialReport.fromStore(store, generatedAt: generatedAt);
      final archive = ZipDecoder().decodeBytes(
        await buildFinancialReportWord(report, language: 'ar'),
      );
      final text = editableText(archive);
      expect(text, contains('<w:p>Owner & "user"</w:p>'));
      expect(text, contains('</w:t> & <script>'));
      expect(text, contains('−٣٢١٫٩٩'));
      final chart = document(archive, 'word/charts/chart4.xml');
      expect(
        elements(elements(chart, 'numCache').single, 'v').single.innerText,
        '-321.99',
      );
      validatePackage(archive);
    },
  );
}
