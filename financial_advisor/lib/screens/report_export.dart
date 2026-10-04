import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../core/finance_store.dart';
import '../core/financial_report.dart';
import '../l10n/app_language.dart';
import '../services/financial_report_pdf.dart';
import '../services/financial_report_word.dart';
import '../services/report_export_service.dart';
import '../widgets/design.dart';

typedef ReportPdfBuilder =
    Future<Uint8List> Function(
      FinancialReport report, {
      required String language,
    });

enum ReportFormat { pdf, word }

class ReportExportPage extends StatefulWidget {
  final FinanceStore store;
  final ReportPdfBuilder pdfBuilder;
  final ReportPdfBuilder wordBuilder;
  final DateTime Function()? clock;
  final Widget Function(Uint8List bytes, String filename)? previewBuilder;

  const ReportExportPage({
    super.key,
    required this.store,
    this.pdfBuilder = buildFinancialReportPdf,
    this.wordBuilder = buildFinancialReportWord,
    this.clock,
    this.previewBuilder,
  });

  @override
  State<ReportExportPage> createState() => _ReportExportPageState();
}

class _ReportExportPageState extends State<ReportExportPage> {
  ReportPeriodKind kind = ReportPeriodKind.allTime;
  ReportFormat format = ReportFormat.pdf;
  late DateTime selectedMonth, start, end;
  String? exportLanguage;
  bool busy = false;
  String? error;

  @override
  void initState() {
    super.initState();
    final now = widget.clock?.call() ?? DateTime.now();
    selectedMonth = DateTime(now.year, now.month);
    start = selectedMonth;
    end = DateTime(now.year, now.month, now.day);
  }

  ReportPeriod get period => switch (kind) {
    ReportPeriodKind.allTime => const ReportPeriod.allTime(),
    ReportPeriodKind.month => ReportPeriod.month(selectedMonth),
    ReportPeriodKind.custom => ReportPeriod.range(start, end),
  };

  bool get validRange =>
      kind != ReportPeriodKind.custom || !end.isBefore(start);

  Future<void> chooseDate(bool first) async {
    final selected = await showDatePicker(
      context: context,
      initialDate: first ? start : end,
      firstDate: DateTime(1),
      lastDate: DateTime(9999, 12, 31),
      helpText: tr(context, first ? 'Start date' : 'End date'),
    );
    if (!mounted || selected == null) return;
    setState(() {
      if (first) {
        start = selected;
      } else {
        end = selected;
      }
      error = null;
    });
  }

  Future<void> preview() async {
    if (busy || !validRange) return;
    final language = exportLanguage ?? languageOf(context);
    final selectedFormat = format;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      // Capture once, before any asynchronous work. Every page and action then
      // uses this same snapshot even if the store changes while rendering.
      final report = FinancialReport.fromStore(
        widget.store,
        period: period,
        generatedAt: widget.clock?.call() ?? DateTime.now(),
      );
      await Future<void>.delayed(Duration.zero);
      final bytes =
          await (selectedFormat == ReportFormat.word
              ? widget.wordBuilder(report, language: language)
              : widget.pdfBuilder(report, language: language));
      if (bytes.isEmpty) throw StateError('Empty report');
      if (!mounted) return;
      Uint8List? previewBytes;
      if (selectedFormat == ReportFormat.word &&
          widget.previewBuilder == null) {
        try {
          // Preview and editable document use the identical frozen snapshot.
          previewBytes = await widget.pdfBuilder(report, language: language);
          if (previewBytes.isEmpty) previewBytes = null;
        } catch (_) {
          // A preview failure must not discard a successfully generated DOCX.
        }
      }
      if (!mounted) return;
      final extension = selectedFormat == ReportFormat.word ? 'docx' : 'pdf';
      final filename =
          'tadbeer-report-${DateFormat('yyyy-MM-dd').format(report.generatedAt)}-$language.$extension';
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder:
              (_) =>
                  widget.previewBuilder?.call(bytes, filename) ??
                  ReportPreviewPage(
                    bytes: bytes,
                    filename: filename,
                    format: selectedFormat,
                    previewBytes: previewBytes,
                  ),
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Could not create the report. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final locale = languageOf(context);
    final years =
        <int>{
            for (var y = 1900; y <= 2100; y++) y,
            selectedMonth.year,
            for (final e in widget.store.entries) e.date.year,
            for (final rule in widget.store.recurringTransactions)
              rule.startDate.year,
          }.toList()
          ..sort();
    return Scaffold(
      appBar: AppBar(title: const AppText('Export report')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const AppText('A report based on your saved financial data.'),
              const SizedBox(height: 20),
              Surface(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<ReportFormat>(
                      key: const Key('report-format'),
                      value: format,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: tr(context, 'File format'),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: ReportFormat.pdf,
                          child: Text('PDF'),
                        ),
                        DropdownMenuItem(
                          value: ReportFormat.word,
                          child: AppText('Microsoft Word (.docx)'),
                        ),
                      ],
                      onChanged:
                          busy
                              ? null
                              : (value) => setState(() {
                                format = value!;
                                error = null;
                              }),
                    ),
                    const SizedBox(height: 20),
                    DropdownButtonFormField<ReportPeriodKind>(
                      key: const Key('report-period'),
                      value: kind,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: tr(context, 'Reporting period'),
                      ),
                      items: [
                        for (final item
                            in const {
                              ReportPeriodKind.allTime: 'All Time',
                              ReportPeriodKind.month: 'Month and year',
                              ReportPeriodKind.custom: 'Custom date range',
                            }.entries)
                          DropdownMenuItem(
                            value: item.key,
                            child: AppText(item.value),
                          ),
                      ],
                      onChanged:
                          busy
                              ? null
                              : (value) => setState(() {
                                kind = value!;
                                error = null;
                              }),
                    ),
                    if (kind == ReportPeriodKind.month) ...[
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<int>(
                              key: const Key('report-month'),
                              value: selectedMonth.month,
                              isExpanded: true,
                              decoration: InputDecoration(
                                labelText: tr(context, 'Month'),
                              ),
                              items: [
                                for (var m = 1; m <= 12; m++)
                                  DropdownMenuItem(
                                    value: m,
                                    child: Text(
                                      DateFormat.MMMM(
                                        locale,
                                      ).format(DateTime(2000, m)),
                                    ),
                                  ),
                              ],
                              onChanged:
                                  busy
                                      ? null
                                      : (m) => setState(
                                        () =>
                                            selectedMonth = DateTime(
                                              selectedMonth.year,
                                              m!,
                                            ),
                                      ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<int>(
                              key: const Key('report-year'),
                              value: selectedMonth.year,
                              isExpanded: true,
                              decoration: InputDecoration(
                                labelText: tr(context, 'Year'),
                              ),
                              items: [
                                for (final y in years)
                                  DropdownMenuItem(
                                    value: y,
                                    child: Text(
                                      NumberFormat('0', locale).format(y),
                                    ),
                                  ),
                              ],
                              onChanged:
                                  busy
                                      ? null
                                      : (y) => setState(
                                        () =>
                                            selectedMonth = DateTime(
                                              y!,
                                              selectedMonth.month,
                                            ),
                                      ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (kind == ReportPeriodKind.custom) ...[
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        key: const Key('report-start-date'),
                        onPressed: busy ? null : () => chooseDate(true),
                        icon: const Icon(Icons.calendar_today_outlined),
                        label: Text(
                          '${tr(context, 'Start date')}: ${DateFormat.yMMMd(locale).format(start)}',
                        ),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        key: const Key('report-end-date'),
                        onPressed: busy ? null : () => chooseDate(false),
                        icon: const Icon(Icons.calendar_today_outlined),
                        label: Text(
                          '${tr(context, 'End date')}: ${DateFormat.yMMMd(locale).format(end)}',
                        ),
                      ),
                      if (!validRange)
                        const AppText(
                          'End date must be on or after start date.',
                          style: TextStyle(color: Colors.orangeAccent),
                        ),
                    ],
                    const SizedBox(height: 24),
                    DropdownButtonFormField<String>(
                      key: const Key('report-language'),
                      value: exportLanguage ?? 'app',
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: tr(context, 'Report language'),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'app',
                          child: AppText('App language'),
                        ),
                        DropdownMenuItem(value: 'en', child: Text('English')),
                        DropdownMenuItem(value: 'ar', child: Text('العربية')),
                      ],
                      onChanged:
                          busy
                              ? null
                              : (value) => setState(
                                () =>
                                    exportLanguage =
                                        value == 'app' ? null : value,
                              ),
                    ),
                    const SizedBox(height: 12),
                    const AppText(
                      'Report language affects the exported file only.',
                      style: TextStyle(color: muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const AppText(
                'Scheduled transactions are shown separately. Upcoming commitments cover up to 90 days within your selected period.',
                style: TextStyle(color: muted, fontSize: 12, height: 1.5),
              ),
              const SizedBox(height: 20),
              if (error != null) ...[
                Semantics(
                  liveRegion: true,
                  child: AppText(
                    error!,
                    style: const TextStyle(color: Colors.orangeAccent),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              FilledButton.icon(
                key: const Key('preview-report'),
                onPressed: busy || !validRange ? null : preview,
                icon:
                    busy
                        ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                        : Icon(
                          format == ReportFormat.word
                              ? Icons.description_outlined
                              : Icons.picture_as_pdf_outlined,
                        ),
                label: AppText(
                  busy
                      ? 'Preparing your report…'
                      : error == null
                      ? 'Preview report'
                      : 'Retry',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ReportPreviewPage extends StatefulWidget {
  final Uint8List bytes;
  final String filename;
  final ReportFormat format;
  final Uint8List? previewBytes;
  const ReportPreviewPage({
    super.key,
    required this.bytes,
    required this.filename,
    this.format = ReportFormat.pdf,
    this.previewBytes,
  });

  @override
  State<ReportPreviewPage> createState() => _ReportPreviewPageState();
}

class _ReportPreviewPageState extends State<ReportPreviewPage> {
  late Future<PrintingInfo> capabilities;
  bool busy = false;
  bool get isWord => widget.format == ReportFormat.word;
  bool get hasPreview => !isWord || widget.previewBytes != null;
  String get previewUnavailable =>
      isWord
          ? 'Preview is unavailable. You can still save or share the Word document.'
          : 'Preview is unavailable. You can still save or share the PDF.';

  bool get opensPdfViewer =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  @override
  void initState() {
    super.initState();
    if (hasPreview) {
      capabilities = Printing.info().timeout(const Duration(seconds: 20));
    }
  }

  Future<void> export(bool share) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final result =
          isWord
              ? (share
                  ? await shareReportWord(widget.bytes, widget.filename)
                  : await saveReportWord(widget.bytes, widget.filename))
              : share
              ? await shareReportPdf(widget.bytes, widget.filename)
              : await saveReportPdf(widget.bytes, widget.filename);
      if (mounted && result == ReportExportResult.downloaded) {
        toast(
          context,
          isWord
              ? (share
                  ? 'Word document downloaded. You can share the saved file.'
                  : 'Word document downloaded.')
              : share
              ? 'PDF downloaded. You can share the saved file.'
              : 'PDF downloaded.',
        );
      } else if (mounted &&
          isWord &&
          !share &&
          result == ReportExportResult.completed) {
        toast(context, 'Word document saved.');
      }
    } catch (_) {
      if (mounted) {
        toast(
          context,
          isWord
              ? 'Could not export the Word document. Please try again.'
              : 'Could not export the PDF. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const AppText('Preview report')),
    body: Column(
      children: [
        if (isWord && hasPreview)
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 12, 20, 8),
            child: AppText(
              'Word layout may differ from this preview.',
              textAlign: TextAlign.center,
              style: TextStyle(color: muted, fontSize: 12),
            ),
          ),
        Expanded(
          child:
              !hasPreview
                  ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: AppText(
                        'Your Word document is ready. Open the saved file in Microsoft Word or a compatible app.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                  : FutureBuilder<PrintingInfo>(
                    future: capabilities,
                    builder: (context, snapshot) {
                      if (snapshot.hasError ||
                          (snapshot.hasData && !snapshot.data!.canRaster)) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                AppText(
                                  previewUnavailable,
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 12),
                                if (kIsWeb)
                                  const AppText(
                                    'Refresh this page to try the preview again.',
                                    textAlign: TextAlign.center,
                                  )
                                else
                                  TextButton(
                                    onPressed:
                                        () => setState(
                                          () =>
                                              capabilities = Printing.info()
                                                  .timeout(
                                                    const Duration(seconds: 20),
                                                  ),
                                        ),
                                    child: const AppText('Retry'),
                                  ),
                              ],
                            ),
                          ),
                        );
                      }
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      return PdfPreview(
                        build: (_) async => widget.previewBytes ?? widget.bytes,
                        initialPageFormat: PdfPageFormat.a4,
                        useActions: false,
                        canDebug: false,
                        canChangeOrientation: false,
                        canChangePageFormat: false,
                        maxPageWidth: 760,
                        pdfFileName:
                            isWord
                                ? widget.filename.replaceAll('.docx', '.pdf')
                                : widget.filename,
                        onError:
                            (_, __) => Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: AppText(
                                  previewUnavailable,
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                      );
                    },
                  ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                if (!kIsWeb && !isWord) ...[
                  AppText(
                    opensPdfViewer
                        ? 'Choose Microsoft Print to PDF in the print dialog.'
                        : 'Choose Save as PDF in the print dialog.',
                    style: const TextStyle(fontSize: 12, color: muted),
                  ),
                  const SizedBox(height: 8),
                ],
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    FilledButton.icon(
                      key: Key(isWord ? 'save-report-word' : 'save-report-pdf'),
                      onPressed: busy ? null : () => export(false),
                      icon: const Icon(Icons.download_outlined),
                      label: AppText(isWord ? 'Save Word' : 'Save PDF'),
                    ),
                    OutlinedButton.icon(
                      key: Key(
                        isWord ? 'share-report-word' : 'share-report-pdf',
                      ),
                      onPressed: busy ? null : () => export(true),
                      icon: Icon(
                        opensPdfViewer
                            ? Icons.open_in_new
                            : Icons.share_outlined,
                      ),
                      label: AppText(
                        isWord
                            ? (opensPdfViewer ? 'Open Word' : 'Share Word')
                            : (opensPdfViewer ? 'Open PDF' : 'Share PDF'),
                      ),
                    ),
                  ],
                ),
                if (opensPdfViewer && !isWord) ...[
                  const SizedBox(height: 8),
                  const AppText(
                    'Share from your PDF viewer.',
                    style: TextStyle(fontSize: 12, color: muted),
                  ),
                ],
                if (busy)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: LinearProgressIndicator(),
                  ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
