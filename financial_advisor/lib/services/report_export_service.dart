import 'dart:typed_data';

import 'report_export_platform.dart'
    if (dart.library.js_interop) 'report_export_web.dart'
    as platform;

enum ReportExportResult { completed, cancelled, downloaded }

const reportWordMimeType =
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document';

Future<ReportExportResult> saveReportPdf(Uint8List bytes, String filename) =>
    platform.save(bytes, filename);

Future<ReportExportResult> shareReportPdf(Uint8List bytes, String filename) =>
    platform.share(bytes, filename);

Future<ReportExportResult> saveReportWord(Uint8List bytes, String filename) {
  _validateWordExport(bytes, filename);
  return platform.saveWord(bytes, filename);
}

Future<ReportExportResult> shareReportWord(Uint8List bytes, String filename) {
  _validateWordExport(bytes, filename);
  return platform.shareWord(bytes, filename);
}

void _validateWordExport(Uint8List bytes, String filename) {
  if (bytes.isEmpty) {
    throw ArgumentError('The Word report is empty.');
  }
  if (!filename.toLowerCase().endsWith('.docx') ||
      filename.length <= 5 ||
      RegExp(r'[<>:"/\\|?*\x00-\x1f]').hasMatch(filename)) {
    throw ArgumentError('The Word report needs a valid .docx filename.');
  }
}
