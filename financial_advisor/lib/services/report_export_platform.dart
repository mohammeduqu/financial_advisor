import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'report_export_service.dart' show ReportExportResult, reportWordMimeType;

Future<ReportExportResult> save(Uint8List bytes, String filename) async {
  final completed = await Printing.layoutPdf(
    onLayout: (_) async => bytes,
    name: filename,
    format: PdfPageFormat.a4,
    dynamicLayout: false,
  );
  return completed
      ? ReportExportResult.completed
      : ReportExportResult.cancelled;
}

Future<ReportExportResult> share(Uint8List bytes, String filename) async {
  final completed = await Printing.sharePdf(bytes: bytes, filename: filename);
  // Windows opens the file in its associated viewer without a share dialog.
  // A false result is an OS launch failure, not a user cancellation.
  if (!completed && defaultTargetPlatform == TargetPlatform.windows) {
    throw StateError('The PDF viewer could not be opened.');
  }
  return completed
      ? ReportExportResult.completed
      : ReportExportResult.cancelled;
}

Future<ReportExportResult> saveWord(Uint8List bytes, String filename) async {
  final selectedPath = await FilePicker.platform.saveFile(
    fileName: filename,
    type: FileType.custom,
    allowedExtensions: const ['docx'],
    bytes: bytes,
    lockParentWindow: true,
  );
  if (selectedPath == null) return ReportExportResult.cancelled;

  // Mobile save pickers write the bytes through the user-selected document URI.
  // Desktop pickers return a path only, so the app must complete the write.
  if (defaultTargetPlatform != TargetPlatform.android &&
      defaultTargetPlatform != TargetPlatform.iOS) {
    var outputPath = selectedPath;
    if (!outputPath.toLowerCase().endsWith('.docx')) {
      outputPath = '$outputPath.docx';
      // This different path was not covered by the native overwrite prompt.
      if (await File(outputPath).exists()) {
        throw FileSystemException(
          'Choose the existing .docx file in the save dialog to replace it.',
        );
      }
    }
    await File(outputPath).writeAsBytes(bytes, flush: true);
  }
  return ReportExportResult.completed;
}

Future<ReportExportResult> shareWord(Uint8List bytes, String filename) async {
  final file = await _temporaryWordFile(bytes, filename);
  try {
    if (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      final opened = await launchUrl(
        Uri.file(file.path),
        mode: LaunchMode.externalApplication,
      );
      if (!opened) throw StateError('The Word document could not be opened.');
      return ReportExportResult.completed;
    }
    final result = await Share.shareXFiles(
      [XFile(file.path, mimeType: reportWordMimeType)],
      fileNameOverrides: [filename],
    );
    if (result.status == ShareResultStatus.dismissed) {
      await _removeTemporaryWordFile(file);
      return ReportExportResult.cancelled;
    }
    // Some OS versions cannot report the chosen target; the share dialog itself
    // still succeeded. Plugin failures throw and remain retryable in the UI.
    return ReportExportResult.completed;
  } catch (_) {
    await _removeTemporaryWordFile(file);
    rethrow;
  }
}

Future<File> _temporaryWordFile(Uint8List bytes, String filename) async {
  final cache = await getTemporaryDirectory();
  final reports = Directory('${cache.path}/tadbeer-word-reports');
  await reports.create(recursive: true);
  final cutoff = DateTime.now().subtract(const Duration(days: 1));
  // Keep files available to the receiving app after its launch. Only our stale
  // export folders are cleaned, never saved reports or other application files.
  await for (final item in reports.list(followLinks: false)) {
    if (item is Directory &&
        item.uri.pathSegments
            .where((part) => part.isNotEmpty)
            .last
            .startsWith('export-')) {
      try {
        if ((await item.stat()).modified.isBefore(cutoff)) {
          await item.delete(recursive: true);
        }
      } on FileSystemException {
        // An external viewer may still have this older document open.
      }
    }
  }
  final folder = await reports.createTemp('export-');
  final file = File('${folder.path}/$filename');
  try {
    return await file.writeAsBytes(bytes, flush: true);
  } catch (_) {
    await _removeTemporaryWordFile(file);
    rethrow;
  }
}

Future<void> _removeTemporaryWordFile(File file) async {
  try {
    await file.parent.delete(recursive: true);
  } on FileSystemException {
    // Best-effort cleanup must not mask the original export result or error.
  }
}
