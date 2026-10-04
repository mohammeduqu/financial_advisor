import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'report_export_service.dart' show ReportExportResult, reportWordMimeType;

Future<ReportExportResult> save(Uint8List bytes, String filename) =>
    _save(bytes, filename, 'application/pdf');

Future<ReportExportResult> share(Uint8List bytes, String filename) =>
    _share(bytes, filename, 'application/pdf');

Future<ReportExportResult> saveWord(Uint8List bytes, String filename) =>
    _save(bytes, filename, reportWordMimeType);

Future<ReportExportResult> shareWord(Uint8List bytes, String filename) =>
    _share(bytes, filename, reportWordMimeType);

Future<ReportExportResult> _save(
  Uint8List bytes,
  String filename,
  String mimeType,
) async {
  final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: mimeType));
  final url = web.URL.createObjectURL(blob);
  final anchor =
      web.HTMLAnchorElement()
        ..href = url
        ..download = filename;
  try {
    web.document.body!.append(anchor);
    anchor.click();
  } finally {
    anchor.remove();
    // Give the browser time to consume the download before releasing it.
    Timer(const Duration(seconds: 30), () => web.URL.revokeObjectURL(url));
  }
  return ReportExportResult.downloaded;
}

Future<ReportExportResult> _share(
  Uint8List bytes,
  String filename,
  String mimeType,
) async {
  final navigator = web.window.navigator;
  final file = web.File(
    [bytes.toJS].toJS,
    filename,
    web.FilePropertyBag(type: mimeType),
  );
  final data = web.ShareData(files: [file].toJS);
  if (navigator.hasProperty('share'.toJS).toDart &&
      navigator.hasProperty('canShare'.toJS).toDart &&
      navigator.canShare(data)) {
    try {
      // Called directly from the tap handler while browser user activation is
      // still available. No financial data is sent before the user picks a target.
      await navigator.share(data).toDart;
      return ReportExportResult.completed;
    } catch (error) {
      if (error.toString().contains('AbortError')) {
        return ReportExportResult.cancelled;
      }
      rethrow;
    }
  }
  return _save(bytes, filename, mimeType);
}
