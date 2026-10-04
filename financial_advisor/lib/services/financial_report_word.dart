import 'dart:convert';
import 'dart:typed_data' show Endian;

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';

import '../core/financial_report.dart';
import '../l10n/report_language.dart';

/// Creates an editable, self-contained Word report from the same immutable
/// snapshot used by the PDF export. No financial data leaves the device.
Future<Uint8List> buildFinancialReportWord(
  FinancialReport report, {
  required String language,
}) async {
  final builder = _WordReport(
    report,
    ReportCopy(languageCode: language == 'ar' ? 'ar' : 'en'),
  );
  await builder.embedFonts();
  return builder.build();
}

const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
const _r =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
const _a = 'http://schemas.openxmlformats.org/drawingml/2006/main';
const _c = 'http://schemas.openxmlformats.org/drawingml/2006/chart';
const _s = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
const _packageRels =
    'http://schemas.openxmlformats.org/package/2006/relationships';
const _contentTypes =
    'http://schemas.openxmlformats.org/package/2006/content-types';
const _xml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>';

// XML 1.0 rejects control characters even when escaped. User names, categories,
// and merchants are always text, never markup or spreadsheet formulas.
String _escape(String value) => String.fromCharCodes(
      value.runes.where(
        (rune) =>
            rune == 9 ||
            rune == 10 ||
            rune == 13 ||
            (rune >= 32 && rune <= 0xd7ff) ||
            (rune >= 0xe000 && rune <= 0xfffd) ||
            (rune >= 0x10000 && rune <= 0x10ffff),
      ),
    )
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');

String _relationships(Iterable<String> rows) =>
    '$_xml<Relationships xmlns="$_packageRels">${rows.join()}</Relationships>';

String _relationship(String id, String type, String target) =>
    '<Relationship Id="$id" Type="$_r/$type" Target="${_escape(target)}"/>';

Uint8List _encodeOfficePackage(Archive archive) {
  final bytes = ZipEncoder(filenameEncoding: ascii).encodeBytes(archive);
  final data = ByteData.sublistView(bytes);
  // archive 4.0.9 honors filenameEncoding in local headers, but always sets
  // the UTF-8 bit in the central directory. Keep both headers consistent for
  // Office's ZIP reader. All our part names are fixed ASCII; XML is UTF-8.
  final end = bytes.length - 22; // Our packages have no ZIP comment.
  if (data.getUint32(end, Endian.little) != 0x06054b50) {
    throw StateError('Invalid report package');
  }
  var position = data.getUint32(end + 16, Endian.little);
  for (var i = 0; i < archive.length; i++) {
    if (data.getUint32(position, Endian.little) != 0x02014b50) {
      throw StateError('Invalid report package directory');
    }
    final local = data.getUint32(position + 42, Endian.little);
    data.setUint16(
      position + 8,
      data.getUint16(position + 8, Endian.little) & ~0x800,
      Endian.little,
    );
    data.setUint16(
      local + 6,
      data.getUint16(local + 6, Endian.little) & ~0x800,
      Endian.little,
    );
    position +=
        46 +
        data.getUint16(position + 28, Endian.little) +
        data.getUint16(position + 30, Endian.little) +
        data.getUint16(position + 32, Endian.little);
  }
  return bytes;
}

class _WordReport {
  _WordReport(this.report, this.copy);

  final FinancialReport report;
  final ReportCopy copy;
  final archive = Archive();
  final documentRelationships = <String>[];
  final chartParts = <String>[];
  final body = StringBuffer();
  static const navy = '172D47';
  static const blue = '247CB6';
  static const orange = 'F28A32';
  static const muted = '63768C';
  static const pale = 'F1F6FA';
  static const rule = 'DCE6EE';
  static const width = 10226;
  bool get rtl => copy.isArabic;
  String get locale => rtl ? 'ar-SA' : 'en-US';
  String get font => rtl ? 'IBM Plex Sans Arabic' : 'Lato';
  // Word interprets this alignment relative to the paragraph's bidi direction.
  // Logical left is the physical right edge in an Arabic (w:bidi) paragraph.
  String get alignment => 'left';
  String amount(int value) => copy.amountNumber(value);
  String signed(int value) => '${value > 0 ? '+' : ''}${amount(value)}';
  String money(int value) => copy.amount(value, report.currency);
  void part(String name, String value) =>
      archive.addFile(ArchiveFile.string(name, value));

  Future<void> embedFonts() async {
    const names = [
      'Lato-Regular.ttf',
      'Lato-Bold.ttf',
      'IBMPlexSansArabic-Regular.ttf',
      'IBMPlexSansArabic-SemiBold.ttf',
    ];
    final keys = <String>[];
    for (var i = 0; i < names.length; i++) {
      final data = await rootBundle.load('assets/fonts/${names[i]}');
      final bytes = Uint8List.fromList(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
      final key = 'E871745A-08E7-433A-A9A4-51534944410${i + 1}';
      keys.add(key);
      final hex = key.replaceAll('-', '');
      final mask = List.generate(
        16,
        (j) => int.parse(hex.substring(j * 2, j * 2 + 2), radix: 16),
      );
      // ECMA-376 font embedding: XOR the first 32 bytes with the GUID's
      // hexadecimal bytes in reverse order, repeating the sixteen-byte key.
      for (var j = 0; j < 32; j++) {
        bytes[j] ^= mask[15 - j % 16];
      }
      archive.addFile(
        ArchiveFile.bytes('word/fonts/font${i + 1}.odttf', bytes),
      );
    }
    part(
      'word/fontTable.xml',
      '$_xml<w:fonts xmlns:w="$_w" xmlns:r="$_r">'
          '${[for (var i = 0; i < 4; i += 2) '<w:font w:name="${i == 0 ? 'Lato' : 'IBM Plex Sans Arabic'}"><w:family w:val="swiss"/><w:pitch w:val="variable"/><w:embedRegular r:id="rFont${i + 1}" w:fontKey="{${keys[i]}}"/><w:embedBold r:id="rFont${i + 2}" w:fontKey="{${keys[i + 1]}}"/></w:font>'].join()}'
          '</w:fonts>',
    );
    part(
      'word/_rels/fontTable.xml.rels',
      _relationships([
        for (var i = 1; i <= 4; i++)
          _relationship('rFont$i', 'font', 'fonts/font$i.odttf'),
      ]),
    );
    for (final license in ['lato-OFL.txt', 'ibm-plex-sans-arabic-OFL.txt']) {
      part(
        'word/fonts/$license',
        await rootBundle.loadString('assets/fonts/$license'),
      );
    }
  }

  Uint8List build() {
    overview();
    spending();
    trends();
    commitments();
    insights();
    documentRelationships.addAll([
      _relationship('rStyles', 'styles', 'styles.xml'),
      _relationship('rSettings', 'settings', 'settings.xml'),
      _relationship('rFonts', 'fontTable', 'fontTable.xml'),
      _relationship('rHeader', 'header', 'header1.xml'),
      _relationship('rFooter', 'footer', 'footer1.xml'),
    ]);
    part(
      'word/document.xml',
      '$_xml<w:document xmlns:w="$_w" xmlns:r="$_r" '
          'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" '
          'xmlns:a="$_a" xmlns:c="$_c"><w:body>$body'
          '<w:sectPr><w:headerReference w:type="default" r:id="rHeader"/>'
          '<w:footerReference w:type="default" r:id="rFooter"/>'
          '<w:pgSz w:w="11906" w:h="16838"/>'
          '<w:pgMar w:top="1300" w:right="840" w:bottom="850" w:left="840" w:header="460" w:footer="400"/>'
          '<w:pgNumType w:fmt="decimal"/>'
          '${rtl ? '<w:bidi/>' : ''}</w:sectPr></w:body></w:document>',
    );
    part('word/_rels/document.xml.rels', _relationships(documentRelationships));
    part('word/styles.xml', styles());
    part(
      'word/settings.xml',
      '$_xml<w:settings xmlns:w="$_w">'
          '<w:embedTrueTypeFonts/><w:embedSystemFonts/><w:saveSubsetFonts w:val="0"/>'
          '<w:compat><w:compatSetting w:name="compatibilityMode" w:uri="http://schemas.microsoft.com/office/word" w:val="15"/></w:compat>'
          '<w:decimalSymbol w:val="${rtl ? '٫' : '.'}"/><w:listSeparator w:val="${rtl ? '؛' : ','}"/>'
          '</w:settings>',
    );
    part(
      'word/header1.xml',
      '$_xml<w:hdr xmlns:w="$_w">'
          '${paragraph(rtl ? 'تدبير.' : 'tadbeer.', size: 32, bold: true, color: blue, after: 35)}'
          '${paragraph(copy.t('Financial behavior report'), size: 15, color: muted, after: 0)}'
          '</w:hdr>',
    );
    final footerProperties =
        '<w:pPr><w:pBdr><w:top w:val="single" w:sz="4" w:color="$rule" w:space="7"/></w:pBdr>'
        '${rtl ? '<w:bidi/>' : ''}<w:jc w:val="$alignment"/></w:pPr>';
    part(
      'word/footer1.xml',
      '$_xml<w:ftr xmlns:w="$_w"><w:p>$footerProperties'
          '${run('${copy.period(report.period)} | ${rtl ? 'صفحة' : 'Page'} ', size: 14, color: muted)}'
          '${field('PAGE')}${run(rtl ? ' من ' : ' of ', size: 14, color: muted)}${field('NUMPAGES')}'
          '</w:p></w:ftr>',
    );
    final created = report.generatedAt.toUtc().toIso8601String();
    part(
      'docProps/core.xml',
      '$_xml<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" '
          'xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" '
          'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">'
          '<dc:title>${_escape(copy.t('Financial behavior report'))}</dc:title><dc:creator>Tadbeer</dc:creator>'
          '<dc:subject>${_escape(copy.periodDetail(report))}</dc:subject>'
          '<dc:language>$locale</dc:language><dcterms:created xsi:type="dcterms:W3CDTF">$created</dcterms:created>'
          '</cp:coreProperties>',
    );
    part(
      'docProps/app.xml',
      '$_xml<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties">'
          '<Application>Tadbeer</Application></Properties>',
    );
    part(
      '_rels/.rels',
      _relationships([
        _relationship('rDocument', 'officeDocument', 'word/document.xml'),
        '<Relationship Id="rCore" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>',
        _relationship('rApp', 'extended-properties', 'docProps/app.xml'),
      ]),
    );
    final overrides = <String, String>{
      '/word/document.xml':
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml',
      '/word/styles.xml':
          'application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml',
      '/word/settings.xml':
          'application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml',
      '/word/fontTable.xml':
          'application/vnd.openxmlformats-officedocument.wordprocessingml.fontTable+xml',
      '/word/header1.xml':
          'application/vnd.openxmlformats-officedocument.wordprocessingml.header+xml',
      '/word/footer1.xml':
          'application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml',
      '/docProps/core.xml':
          'application/vnd.openxmlformats-package.core-properties+xml',
      '/docProps/app.xml':
          'application/vnd.openxmlformats-officedocument.extended-properties+xml',
      for (final path in chartParts)
        '/$path':
            'application/vnd.openxmlformats-officedocument.drawingml.chart+xml',
    };
    part(
      '[Content_Types].xml',
      '$_xml<Types xmlns="$_contentTypes">'
          '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
          '<Default Extension="xml" ContentType="application/xml"/>'
          '<Default Extension="txt" ContentType="text/plain"/>'
          '<Default Extension="odttf" ContentType="application/vnd.openxmlformats-officedocument.obfuscatedFont"/>'
          '<Default Extension="xlsx" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"/>'
          '${overrides.entries.map((e) => '<Override PartName="${e.key}" ContentType="${e.value}"/>').join()}'
          '</Types>',
    );
    return _encodeOfficePackage(archive);
  }

  String run(
    String text, {
    int size = 19,
    bool bold = false,
    String color = navy,
  }) {
    final arabic = RegExp(
      r'[\u0600-\u06ff\u0750-\u077f\u08a0-\u08ff]',
    ).hasMatch(text);
    return '<w:r><w:rPr><w:rFonts w:ascii="$font" w:hAnsi="$font" w:cs="IBM Plex Sans Arabic"/>'
        '${bold ? '<w:b/><w:bCs/>' : ''}<w:color w:val="$color"/><w:sz w:val="$size"/>'
        '<w:szCs w:val="$size"/>${arabic ? '<w:rtl/>' : ''}<w:lang w:val="$locale" w:bidi="ar-SA"/></w:rPr>'
        '${text.split('\n').map((line) => '<w:t xml:space="preserve">${_escape(line)}</w:t>').join('<w:br/>')}'
        '</w:r>';
  }

  String paragraph(
    String text, {
    int size = 19,
    bool bold = false,
    String color = navy,
    int after = 120,
    int before = 0,
    String? style,
    bool keep = false,
    bool pageBreak = false,
    String? align,
    String? shade,
  }) =>
      '<w:p><w:pPr>${style == null ? '' : '<w:pStyle w:val="$style"/>'}'
      '${keep ? '<w:keepNext/>' : ''}<w:keepLines/>'
      '${pageBreak ? '<w:pageBreakBefore/>' : ''}'
      '${shade == null ? '' : '<w:shd w:val="clear" w:fill="$shade"/>'}'
      '${rtl ? '<w:bidi/>' : ''}<w:spacing w:before="$before" w:after="$after" w:line="270" w:lineRule="auto"/>'
      '<w:jc w:val="${align ?? alignment}"/></w:pPr>${run(text, size: size, bold: bold, color: color)}</w:p>';

  String field(String instruction) =>
      '<w:fldSimple w:instr=" $instruction \\* Arabic ">${run('1', size: 14, color: muted)}</w:fldSimple>';

  void text(
    String value, {
    bool mutedText = false,
    int size = 19,
    int after = 120,
  }) => body.write(
    paragraph(value, color: mutedText ? muted : navy, size: size, after: after),
  );

  void heading(String key) => body.write(
    paragraph(
      copy.t(key),
      size: 24,
      bold: true,
      before: 200,
      after: 120,
      keep: true,
      style: 'Heading2',
    ),
  );

  void note(String key) => text(copy.t(key), mutedText: true, size: 16);

  void startSection(int index, String label, String title, String subtitle) {
    body.write(
      paragraph(
        '${copy.number(index)} / ${copy.t(label)}',
        size: 17,
        bold: true,
        color: blue,
        before: 120,
        after: 100,
        keep: true,
        pageBreak: index > 1,
      ),
    );
    body.write(
      paragraph(
        copy.t(title),
        size: 46,
        bold: true,
        after: 140,
        keep: true,
        style: index == 1 ? 'Title' : 'Heading1',
      ),
    );
    body.write(
      paragraph(subtitle, size: 17, color: muted, after: 240, keep: true),
    );
  }

  void metrics(List<(String, String, String)> items) {
    final cellWidth = width ~/ items.length;
    body.write(
      '<w:tbl><w:tblPr>${rtl ? '<w:bidiVisual/>' : ''}<w:tblW w:w="$width" w:type="dxa"/>'
      '<w:tblLayout w:type="fixed"/>'
      '<w:tblCellMar><w:top w:w="150" w:type="dxa"/><w:left w:w="140" w:type="dxa"/>'
      '<w:bottom w:w="130" w:type="dxa"/><w:right w:w="140" w:type="dxa"/></w:tblCellMar></w:tblPr>'
      '<w:tblGrid>${items.map((_) => '<w:gridCol w:w="$cellWidth"/>').join()}</w:tblGrid><w:tr><w:trPr><w:cantSplit/></w:trPr>',
    );
    for (final item in items) {
      body.write(
        '<w:tc><w:tcPr><w:tcW w:w="$cellWidth" w:type="dxa"/><w:shd w:val="clear" w:fill="$pale"/></w:tcPr>'
        '${paragraph(copy.t(item.$1), size: 15, bold: true, color: muted, after: 90)}'
        '${paragraph(item.$2, size: 29, bold: true, after: 70)}'
        '${paragraph(item.$3, size: 14, color: muted, after: 0)}</w:tc>',
      );
    }
    body.write('</w:tr></w:tbl>${paragraph('', size: 4, after: 70)}');
  }

  void table(
    List<String> headings,
    List<List<String>> rows, {
    List<int>? widths,
    bool totalLast = false,
  }) {
    final weights = widths ?? List.filled(headings.length, 1);
    final total = weights.reduce((a, b) => a + b);
    final columns = weights.map((value) => width * value ~/ total).toList();
    body.write(
      '<w:tbl><w:tblPr>${rtl ? '<w:bidiVisual/>' : ''}<w:tblW w:w="$width" w:type="dxa"/>'
      '<w:tblBorders><w:insideH w:val="single" w:sz="3" w:color="$rule"/></w:tblBorders>'
      '<w:tblLayout w:type="fixed"/><w:tblCellMar><w:top w:w="85" w:type="dxa"/>'
      '<w:left w:w="105" w:type="dxa"/><w:bottom w:w="85" w:type="dxa"/>'
      '<w:right w:w="105" w:type="dxa"/></w:tblCellMar></w:tblPr>'
      '<w:tblGrid>${columns.map((value) => '<w:gridCol w:w="$value"/>').join()}</w:tblGrid>',
    );
    for (var row = -1; row < rows.length; row++) {
      final header = row == -1;
      final values = header ? headings.map(copy.t).toList() : rows[row];
      body.write(
        '<w:tr><w:trPr><w:cantSplit/>${header ? '<w:tblHeader/>' : ''}</w:trPr>',
      );
      for (var column = 0; column < values.length; column++) {
        body.write(
          '<w:tc><w:tcPr><w:tcW w:w="${columns[column]}" w:type="dxa"/>'
          '<w:shd w:val="clear" w:fill="${header
              ? navy
              : row.isEven
              ? pale
              : 'FFFFFF'}"/><w:vAlign w:val="center"/></w:tcPr>'
          '${paragraph(values[column], size: 17, bold: header || (totalLast && row == rows.length - 1), color: header ? 'FFFFFF' : navy, after: 0, keep: header || row == 0)}'
          '</w:tc>',
        );
      }
      body.write('</w:tr>');
    }
    body.write('</w:tbl>${paragraph('', size: 4, after: 50)}');
  }

  void overview() {
    startSection(
      1,
      'Overview',
      'Your money, in focus.',
      '${report.name}\n${copy.periodDetail(report)} | ${copy.t('Generated on')}: ${copy.date(report.generatedAt)}',
    );
    metrics([
      (
        'Total income',
        amount(report.incomeCents),
        '${report.currency} | ${copy.t('Recorded income')}',
      ),
      (
        'Total expenses',
        amount(report.expenseCents),
        '${report.currency} | ${copy.t('Recorded expenses')}',
      ),
      (
        'Net amount',
        amount(report.netCents),
        '${report.currency} | ${copy.t('Income less expenses')}',
      ),
      (
        'Retained share',
        copy.retainedShare(report),
        copy.t('Surplus as a share of income'),
      ),
    ]);
    text(copy.transactionBreakdown(report), mutedText: true, size: 18);
    if (report.hasRecordedFutureEntries) {
      note(
        'Saved future-dated transactions are included in recorded totals, matching the dashboard. Scheduled projections are excluded.',
      );
    }
    heading('Income versus expenses');
    if (report.entries.isEmpty) {
      note('No recorded transactions in this period.');
    } else {
      chart(
        'Income versus expenses',
        report.trends.map(copy.chartTrendLabel).toList(),
        [
          report.trends.map((e) => e.incomeCents).toList(),
          report.trends.map((e) => e.expenseCents).toList(),
        ],
        ['Income', 'Expenses'],
        height: 185,
      );
    }
    text(copy.overviewNarrative(report), mutedText: true, size: 18);
    heading('Recorded results');
    text(copy.summary(report).first, size: 18);
    heading('Spending focus');
    text(
      copy.summary(report).skip(1).firstOrNull ??
          copy.overviewNarrative(report),
      size: 18,
    );
    heading('How to read this report');
    note(
      'The net amount is recorded income less recorded expenses. It is not a verified bank balance or confirmed savings. Scheduled projections are shown separately.',
    );
  }

  void spending() {
    startSection(
      2,
      'Spending & budget',
      'Where your money goes',
      '${copy.periodDetail(report)} | ${copy.t('Amounts in')} ${report.currency}',
    );
    heading('Spending by category');
    if (report.categories.isEmpty) {
      note('No expenses in this period.');
    } else {
      chart(
        'Spending by category',
        report.categories.map((e) => copy.category(e.category)).toList(),
        [report.categories.map((e) => e.cents).toList()],
        ['Expenses'],
        kind: _ChartKind.horizontal,
        height: (report.categories.length * 20 + 38).clamp(145, 275),
      );
      text(
        '${copy.t('Total expenses')}: ${money(report.expenseCents)}',
        mutedText: true,
        size: 17,
      );
    }
    heading('Budget performance across the selected period');
    if (report.budgetSummaries.isEmpty) {
      note('No budgets are available for this reporting period.');
      return;
    }
    text(copy.budgetNarrative(report), mutedText: true, size: 17);
    final categories =
        report.budgetSummaries.where((e) => !e.isOverall).toList();
    if (categories.isNotEmpty) {
      table(
        ['Category', 'Budget', 'Actual', 'Over / under'],
        [
          for (final row in categories)
            [
              copy.category(row.category),
              amount(row.limitCents),
              amount(row.spentCents),
              signed(row.varianceCents),
            ],
          [
            copy.t('Total'),
            amount(report.categoryBudgetLimitCents),
            amount(report.categoryBudgetSpentCents),
            signed(
              report.categoryBudgetSpentCents - report.categoryBudgetLimitCents,
            ),
          ],
        ],
        widths: [4, 3, 3, 3],
        totalLast: true,
      );
    }
    final overall = report.budgetSummaries.where((e) => e.isOverall).toList();
    if (overall.isNotEmpty) {
      heading('Overall budget comparison');
      table(
        ['Budget', 'Actual', 'Over / under'],
        [
          for (final row in overall)
            [
              amount(row.limitCents),
              amount(row.spentCents),
              signed(row.varianceCents),
            ],
        ],
      );
    }
    note('Positive variance means over budget; negative means under budget.');
    text(copy.budgetCoverageNote(report), mutedText: true, size: 16);
    if (report.budgetSummaries.any((e) => e.partial || e.isOngoing) ||
        report.budgetSummaries.map((e) => e.monthCount).toSet().length > 1) {
      heading('Budget coverage');
      table(
        ['Category', 'Covered months', 'Coverage'],
        [
          for (final row in report.budgetSummaries)
            [
              copy.category(row.category),
              copy.number(row.monthCount),
              [
                if (row.partial) copy.t('Partial coverage'),
                if (row.isOngoing) copy.t('Open month'),
                if (!row.partial && !row.isOngoing) copy.t('Full month'),
              ].join(' / '),
            ],
        ],
        widths: [3, 2, 4],
      );
    }
  }

  void trends() {
    startSection(
      3,
      'Spending trends',
      'The pattern behind the totals',
      copy.periodDetail(report),
    );
    metrics([
      (
        'Average monthly spend',
        report.averageMonthlyExpenseCents == null
            ? copy.t('Not available')
            : amount(report.averageMonthlyExpenseCents!),
        report.currency,
      ),
      (
        'Highest spending month',
        report.highestExpenseMonth == null
            ? copy.t('Not available')
            : amount(report.highestExpenseMonth!.expenseCents),
        report.highestExpenseMonth == null
            ? copy.t('No expenses in this period.')
            : copy.month(report.highestExpenseMonth!.start),
      ),
      (
        'Months over budget',
        report.comparableBudgetMonthCount == 0
            ? copy.t('Not available')
            : '${copy.number(report.overBudgetMonthCount)} / ${copy.number(report.comparableBudgetMonthCount)}',
        copy.t('Comparable months'),
      ),
    ]);
    text(copy.monthlyAverageCaption(report), mutedText: true, size: 16);
    heading('Expenses by period');
    final limits = matchingTrendBudgets();
    if (report.entries.isEmpty) {
      note('No recorded transactions in this period.');
    } else {
      chart(
        'Expenses by period',
        report.trends.map(copy.chartTrendLabel).toList(),
        [
          report.trends.map((e) => e.expenseCents).toList(),
          if (limits != null) limits,
        ],
        ['Expenses', if (limits != null) 'Saved monthly budget'],
        kind: _ChartKind.line,
        height: 150,
      );
    }
    text(copy.trendNarrative(report), mutedText: true, size: 17);
    heading('Net amount by period');
    if (report.entries.isEmpty) {
      note('No recorded transactions in this period.');
    } else {
      chart(
        'Net amount by period',
        report.trends.map(copy.chartTrendLabel).toList(),
        [report.trends.map((e) => e.netCents).toList()],
        ['Net amount'],
        height: 145,
      );
    }
    note(
      'The net amount is recorded income less recorded expenses. It is not a verified bank balance or confirmed savings. Scheduled projections are shown separately.',
    );
    if (report.trends.length > 8) {
      heading('Expense trend details');
      table(
        ['Interval', 'Income', 'Expenses', 'Net amount'],
        [
          for (final bucket in report.trends)
            [
              copy.trendLabel(bucket),
              amount(bucket.incomeCents),
              amount(bucket.expenseCents),
              amount(bucket.netCents),
            ],
        ],
        widths: [5, 2, 2, 2],
      );
    }
  }

  void commitments() {
    startSection(
      4,
      'Recurring & upcoming',
      'What is already committed',
      copy.t(
        'Only recorded transactions are included in totals. Scheduled projections are shown separately.',
      ),
    );
    metrics([
      (
        'Recorded recurring costs',
        amount(report.recurringExpenseCents),
        '${report.currency} | ${copy.t('Already included in expenses')}',
      ),
      (
        'Recorded occurrences',
        copy.number(report.recurringExpenses.length),
        copy.t('Each occurrence is counted once'),
      ),
      (
        'Share of all expenses',
        report.expenseCents == 0
            ? copy.t('Not available')
            : copy.percentage(
              report.recurringExpenseCents,
              report.expenseCents,
            ),
        copy.t('Recorded expenses'),
      ),
    ]);
    final categoryTotals = <String, int>{};
    for (final entry in report.recurringExpenses) {
      categoryTotals.update(
        entry.category,
        (value) => value + entry.cents,
        ifAbsent: () => entry.cents,
      );
    }
    final categories =
        categoryTotals.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
    if (categories.isEmpty) {
      note('No recurring expenses were recorded in this reporting period.');
    } else {
      text(
        categories
            .map((e) => '${copy.category(e.key)}: ${money(e.value)}')
            .join(' | '),
        mutedText: true,
        size: 17,
      );
    }
    heading('Upcoming commitments');
    if (report.commitmentStart != null && report.commitmentEnd != null) {
      text(
        '${copy.date(report.commitmentStart!)} - ${copy.date(report.commitmentEnd!)}',
        mutedText: true,
        size: 18,
      );
    }
    if (report.scheduledTransactions.isEmpty) {
      note('No scheduled transactions fall within this report window.');
    } else {
      metrics([
        (
          'Scheduled income',
          amount(report.scheduledIncomeCents),
          report.currency,
        ),
        (
          'Scheduled expenses',
          amount(report.scheduledExpenseCents),
          report.currency,
        ),
        (
          'Before variable costs',
          amount(report.scheduledIncomeCents - report.scheduledExpenseCents),
          copy.t('Not confirmed savings'),
        ),
      ]);
      table(
        ['Date', 'Scheduled item', 'Type', 'Amount'],
        [
          for (final entry in report.scheduledTransactions)
            [
              copy.date(entry.date),
              entry.merchant,
              copy.t(entry.income ? 'Income' : 'Expense'),
              signed(entry.income ? entry.cents : -entry.cents),
            ],
        ],
        widths: [3, 5, 2, 3],
      );
    }
    heading('A schedule is not a completed payment');
    note(
      'Scheduled income and expenses are projections, excluded from recorded totals. Variable costs are not included in the difference.',
    );
  }

  void insights() {
    startSection(
      5,
      'Insights & next steps',
      'Small changes, visible impact',
      copy.t('Budget comparison'),
    );
    final scenario = report.budgetScenario;
    if (scenario != null) {
      heading('Categories above their saved limits');
      chart(
        'Categories above their saved limits',
        scenario.categories.map((e) => copy.category(e.category)).toList(),
        [
          scenario.categories.map((e) => e.spentCents).toList(),
          scenario.categories.map((e) => e.limitCents).toList(),
        ],
        ['Recorded spending', 'Saved budget'],
        height: 175,
      );
      metrics([
        (
          'Combined budget gap',
          amount(scenario.reductionCents),
          report.currency,
        ),
        (
          'Illustrative net amount',
          amount(scenario.netCents),
          copy.t('If these limits were met'),
        ),
        (
          'Illustrative share',
          scenario.incomeCents <= 0
              ? copy.t('Not available')
              : copy.percentage(scenario.netCents, scenario.incomeCents),
          copy.t('With every other amount unchanged'),
        ),
      ]);
      text(copy.scenarioNarrative(report), mutedText: true, size: 17);
      if (scenario.categories.length > 8) {
        table(
          ['Category', 'Saved budget', 'Recorded spending', 'Over / under'],
          [
            for (final row in scenario.categories)
              [
                copy.category(row.category),
                amount(row.limitCents),
                amount(row.spentCents),
                signed(row.varianceCents),
              ],
          ],
          widths: [4, 3, 3, 3],
        );
      }
    } else {
      heading('Financial behavior summary');
      for (final item in copy.summary(report)) {
        text(item, size: 18);
      }
    }
    heading('Suggested next steps');
    for (final (index, item) in copy.recommendations(report).indexed) {
      text('${copy.number(index + 1)}. $item', size: 19, after: 160);
    }
    note('This report reflects data recorded in Tadbeer at generation time.');
    note(
      'All amounts use the account currency; no exchange-rate conversion is applied.',
    );
  }

  List<int>? matchingTrendBudgets() {
    if (report.trends.length < 2) return null;
    final months = <(int, int)>{};
    final limits = <int>[];
    for (final bucket in report.trends) {
      if (bucket.start.year != bucket.end.year ||
          bucket.start.month != bucket.end.month ||
          !months.add((bucket.start.year, bucket.start.month))) {
        return null;
      }
      final row =
          report.monthlyBudgets
              .where(
                (row) =>
                    row.month.year == bucket.start.year &&
                    row.month.month == bucket.start.month &&
                    !row.partial &&
                    !row.isOngoing &&
                    row.fullyCovered,
              )
              .firstOrNull;
      if (row == null) return null;
      limits.add(row.limitCents);
    }
    return limits;
  }

  String styles() =>
      '$_xml<w:styles xmlns:w="$_w"><w:docDefaults><w:rPrDefault><w:rPr>'
      '<w:rFonts w:ascii="$font" w:hAnsi="$font" w:cs="IBM Plex Sans Arabic"/>'
      '<w:color w:val="$navy"/><w:sz w:val="19"/><w:szCs w:val="19"/>'
      '<w:lang w:val="$locale" w:bidi="ar-SA"/></w:rPr></w:rPrDefault>'
      '<w:pPrDefault><w:pPr>${rtl ? '<w:bidi/>' : ''}<w:spacing w:after="120" w:line="270" w:lineRule="auto"/>'
      '</w:pPr></w:pPrDefault></w:docDefaults>'
      '<w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:qFormat/></w:style>'
      '<w:style w:type="paragraph" w:styleId="Title"><w:name w:val="Title"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/><w:pPr><w:keepNext/></w:pPr><w:rPr><w:b/><w:bCs/><w:sz w:val="46"/><w:szCs w:val="46"/></w:rPr></w:style>'
      '${[1, 2].map((level) => '<w:style w:type="paragraph" w:styleId="Heading$level"><w:name w:val="heading $level"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/><w:pPr><w:keepNext/><w:keepLines/><w:outlineLvl w:val="${level - 1}"/></w:pPr><w:rPr><w:b/><w:bCs/></w:rPr></w:style>').join()}'
      '</w:styles>';

  void chart(
    String title,
    List<String> labels,
    List<List<int>> series,
    List<String> names, {
    int height = 170,
    _ChartKind kind = _ChartKind.columns,
  }) {
    final id = chartParts.length + 1;
    final chartPath = 'word/charts/chart$id.xml';
    chartParts.add(chartPath);
    documentRelationships.add(
      _relationship('rChart$id', 'chart', 'charts/chart$id.xml'),
    );
    final translated = names.map(copy.t).toList();
    part(chartPath, chartXml(labels, series, translated, kind));
    part(
      'word/charts/_rels/chart$id.xml.rels',
      _relationships([
        _relationship('rWorkbook', 'package', '../embeddings/chart$id.xlsx'),
      ]),
    );
    archive.addFile(
      ArchiveFile.bytes(
        'word/embeddings/chart$id.xlsx',
        workbook(labels, series, translated),
      ),
    );
    final cy = height * 12700;
    body.write(
      '<w:p><w:pPr><w:keepLines/><w:spacing w:after="120"/><w:jc w:val="center"/></w:pPr><w:r><w:drawing>'
      '<wp:inline distT="0" distB="0" distL="0" distR="0"><wp:extent cx="6477000" cy="$cy"/>'
      '<wp:docPr id="$id" name="${_escape(copy.t(title))}" descr="${_escape('${copy.t(title)} | ${copy.periodDetail(report)} | ${report.currency}')}"/>'
      '<wp:cNvGraphicFramePr><a:graphicFrameLocks noChangeAspect="1"/></wp:cNvGraphicFramePr>'
      '<a:graphic><a:graphicData uri="$_c"><c:chart r:id="rChart$id"/></a:graphicData></a:graphic>'
      '</wp:inline></w:drawing></w:r></w:p>',
    );
  }

  String chartText({int size = 900}) =>
      '<c:txPr><a:bodyPr/><a:lstStyle/><a:p><a:pPr rtl="${rtl ? 1 : 0}">'
      '<a:defRPr sz="$size"><a:solidFill><a:srgbClr val="$muted"/></a:solidFill><a:latin typeface="$font"/>'
      '<a:cs typeface="IBM Plex Sans Arabic"/></a:defRPr></a:pPr><a:endParaRPr lang="$locale"/></a:p></c:txPr>';

  String chartXml(
    List<String> labels,
    List<List<int>> values,
    List<String> names,
    _ChartKind kind,
  ) {
    final horizontal = kind == _ChartKind.horizontal;
    final lineChart = kind == _ChartKind.line;
    final hasCents = values.any(
      (series) => series.any((value) => value % 100 != 0),
    );
    final numberFormat =
        '${rtl ? r'[$-2000401]' : ''}${hasCents ? '#,##0.00' : '#,##0'}';
    final seriesXml = StringBuffer();
    for (var i = 0; i < values.length; i++) {
      final column = String.fromCharCode(66 + i);
      final color = i.isEven ? blue : orange;
      seriesXml.write(
        '<c:ser><c:idx val="$i"/><c:order val="$i"/>'
        '<c:tx><c:strRef><c:f>Data!\$$column\$1</c:f><c:strCache><c:ptCount val="1"/><c:pt idx="0"><c:v>${_escape(names[i])}</c:v></c:pt></c:strCache></c:strRef></c:tx>'
        '<c:spPr>${lineChart ? '' : '<a:solidFill><a:srgbClr val="$color"/></a:solidFill>'}'
        '<a:ln w="${lineChart ? 25400 : 0}">${lineChart ? '<a:solidFill><a:srgbClr val="$color"/></a:solidFill>' : '<a:noFill/>'}</a:ln></c:spPr>'
        '${lineChart ? '<c:marker><c:symbol val="circle"/><c:size val="4"/><c:spPr><a:solidFill><a:srgbClr val="$color"/></a:solidFill><a:ln><a:noFill/></a:ln></c:spPr></c:marker>' : '<c:invertIfNegative val="0"/>'}'
        '<c:cat><c:strRef><c:f>Data!\$A\$2:\$A\$${labels.length + 1}</c:f><c:strCache><c:ptCount val="${labels.length}"/>'
        '${labels.indexed.map((item) => '<c:pt idx="${item.$1}"><c:v>${_escape(item.$2)}</c:v></c:pt>').join()}'
        '</c:strCache></c:strRef></c:cat><c:val><c:numRef><c:f>Data!\$$column\$2:\$$column\$${labels.length + 1}</c:f>'
        '<c:numCache><c:formatCode>${_escape(numberFormat)}</c:formatCode><c:ptCount val="${labels.length}"/>'
        '${values[i].indexed.map((item) => '<c:pt idx="${item.$1}"><c:v>${decimal(item.$2)}</c:v></c:pt>').join()}'
        '</c:numCache></c:numRef></c:val>${lineChart ? '<c:smooth val="0"/>' : ''}</c:ser>',
      );
    }
    final seriesTag = lineChart ? 'lineChart' : 'barChart';
    final chartType =
        lineChart
            ? '<c:grouping val="standard"/>'
            : '<c:barDir val="${horizontal ? 'bar' : 'col'}"/><c:grouping val="clustered"/>';
    final thinLine =
        '<c:spPr><a:ln w="6350"><a:solidFill><a:srgbClr val="$rule"/></a:solidFill></a:ln></c:spPr>';
    final axisCatPos = horizontal ? (rtl ? 'r' : 'l') : 'b';
    final axisValPos = horizontal ? 'b' : (rtl ? 'r' : 'l');
    return '$_xml<c:chartSpace xmlns:c="$_c" xmlns:a="$_a" xmlns:r="$_r">'
        '<c:date1904 val="0"/><c:lang val="$locale"/><c:roundedCorners val="0"/>'
        '<c:chart><c:autoTitleDeleted val="1"/><c:plotArea><c:layout/>'
        '<c:$seriesTag>$chartType<c:varyColors val="0"/>$seriesXml'
        '${lineChart ? '<c:marker val="1"/><c:smooth val="0"/>' : '<c:gapWidth val="75"/><c:overlap val="0"/>'}'
        '<c:axId val="100001"/><c:axId val="100002"/></c:$seriesTag>'
        '<c:catAx><c:axId val="100001"/><c:scaling><c:orientation val="${horizontal || rtl ? 'maxMin' : 'minMax'}"/></c:scaling>'
        '<c:delete val="0"/><c:axPos val="$axisCatPos"/><c:majorTickMark val="none"/><c:minorTickMark val="none"/>'
        '<c:tickLblPos val="${horizontal ? 'nextTo' : 'low'}"/>$thinLine${chartText(size: 850)}<c:crossAx val="100002"/>'
        '<c:crosses val="autoZero"/><c:auto val="1"/><c:lblAlgn val="ctr"/><c:lblOffset val="100"/>'
        '<c:tickLblSkip val="${labels.length > 10 && !horizontal ? (labels.length / 8).ceil() : 1}"/><c:noMultiLvlLbl val="0"/></c:catAx>'
        '<c:valAx><c:axId val="100002"/><c:scaling><c:orientation val="${rtl && horizontal ? 'maxMin' : 'minMax'}"/></c:scaling>'
        '<c:delete val="0"/><c:axPos val="$axisValPos"/><c:majorGridlines>$thinLine</c:majorGridlines>'
        '<c:numFmt formatCode="${_escape(numberFormat)}" sourceLinked="0"/><c:majorTickMark val="none"/><c:minorTickMark val="none"/>'
        '<c:tickLblPos val="nextTo"/><c:spPr><a:ln><a:noFill/></a:ln></c:spPr>${chartText(size: 850)}'
        '<c:crossAx val="100001"/><c:crosses val="${horizontal ? 'max' : 'autoZero'}"/><c:crossBetween val="between"/></c:valAx>'
        '<c:spPr><a:noFill/><a:ln><a:noFill/></a:ln></c:spPr></c:plotArea>'
        '${names.length > 1 ? '<c:legend><c:legendPos val="b"/><c:layout/><c:overlay val="0"/>${chartText()}</c:legend>' : ''}'
        '<c:plotVisOnly val="1"/><c:dispBlanksAs val="gap"/><c:showDLblsOverMax val="0"/></c:chart>'
        '<c:spPr><a:solidFill><a:srgbClr val="FFFFFF"/></a:solidFill><a:ln><a:noFill/></a:ln></c:spPr>'
        '${chartText()}<c:externalData r:id="rWorkbook"><c:autoUpdate val="0"/></c:externalData></c:chartSpace>';
  }

  static String decimal(int cents) =>
      '${cents < 0 ? '-' : ''}${cents.abs() ~/ 100}.${(cents.abs() % 100).toString().padLeft(2, '0')}';

  Uint8List workbook(
    List<String> labels,
    List<List<int>> values,
    List<String> names,
  ) {
    final book = Archive();
    void add(String path, String text) =>
        book.addFile(ArchiveFile.string(path, text));
    String stringCell(String reference, String text) =>
        '<c r="$reference" t="inlineStr"><is><t xml:space="preserve">${_escape(text)}</t></is></c>';
    final rows = StringBuffer(
      '<row r="1">${stringCell('A1', copy.t('Interval'))}',
    );
    for (var i = 0; i < names.length; i++) {
      rows.write(stringCell('${String.fromCharCode(66 + i)}1', names[i]));
    }
    rows.write('</row>');
    for (var row = 0; row < labels.length; row++) {
      rows.write(
        '<row r="${row + 2}">${stringCell('A${row + 2}', labels[row])}',
      );
      for (var column = 0; column < values.length; column++) {
        rows.write(
          '<c r="${String.fromCharCode(66 + column)}${row + 2}" s="1"><v>${decimal(values[column][row])}</v></c>',
        );
      }
      rows.write('</row>');
    }
    add(
      'xl/worksheets/sheet1.xml',
      '$_xml<worksheet xmlns="$_s"><sheetViews><sheetView workbookViewId="0" rightToLeft="${rtl ? 1 : 0}"/></sheetViews>'
          '<cols><col min="1" max="1" width="30" customWidth="1"/><col min="2" max="${names.length + 1}" width="20" customWidth="1"/></cols><sheetData>$rows</sheetData></worksheet>',
    );
    add(
      'xl/workbook.xml',
      '$_xml<workbook xmlns="$_s" xmlns:r="$_r"><bookViews><workbookView/></bookViews><sheets><sheet name="Data" sheetId="1" r:id="rSheet"/></sheets></workbook>',
    );
    add(
      'xl/styles.xml',
      '$_xml<styleSheet xmlns="$_s"><fonts count="1"><font><sz val="11"/><name val="$font"/></font></fonts>'
          '<fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills>'
          '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>'
          '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
          '<cellXfs count="2"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="4" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/></cellXfs>'
          '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>',
    );
    add(
      'xl/_rels/workbook.xml.rels',
      _relationships([
        _relationship('rSheet', 'worksheet', 'worksheets/sheet1.xml'),
        _relationship('rStyles', 'styles', 'styles.xml'),
      ]),
    );
    add(
      '_rels/.rels',
      _relationships([
        _relationship('rBook', 'officeDocument', 'xl/workbook.xml'),
      ]),
    );
    add(
      '[Content_Types].xml',
      '$_xml<Types xmlns="$_contentTypes"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
          '<Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
          '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
          '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/></Types>',
    );
    return _encodeOfficePackage(book);
  }
}

enum _ChartKind { columns, horizontal, line }
