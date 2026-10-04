import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:financial_advisor/services/report_export_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _SavePicker extends FilePicker {
  String? path;
  Object? failure;
  String? filename;
  Uint8List? savedBytes;
  FileType? fileType;
  List<String>? extensions;

  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async {
    filename = fileName;
    savedBytes = bytes;
    fileType = type;
    extensions = allowedExtensions;
    if (failure != null) throw failure!;
    return path;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
  const shareChannel = MethodChannel('dev.fluttercommunity.plus/share');
  const launchChannel = MethodChannel('plugins.flutter.io/url_launcher');
  final bytes = Uint8List.fromList([80, 75, 3, 4, 10, 20, 30]);
  late Directory temporary;
  late _SavePicker picker;
  final shareCalls = <MethodCall>[];
  final launchCalls = <MethodCall>[];

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('tadbeer-word-test-');
    picker = _SavePicker();
    FilePicker.platform = picker;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    shareCalls.clear();
    launchCalls.clear();
    messenger.setMockMethodCallHandler(
      pathChannel,
      (_) async => temporary.path,
    );
    messenger.setMockMethodCallHandler(shareChannel, (call) async {
      shareCalls.add(call);
      return 'com.example.recipient';
    });
    messenger.setMockMethodCallHandler(launchChannel, (call) async {
      launchCalls.add(call);
      return true;
    });
  });

  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(pathChannel, null);
    messenger.setMockMethodCallHandler(shareChannel, null);
    messenger.setMockMethodCallHandler(launchChannel, null);
    await temporary.delete(recursive: true);
  });

  test(
    'Android passes report bytes to the user-selected document provider',
    () async {
      picker.path = 'content://documents/tree/selected/report.docx';
      expect(
        await saveReportWord(bytes, 'report.docx'),
        ReportExportResult.completed,
      );
      expect(picker.filename, 'report.docx');
      expect(picker.savedBytes, bytes);
      expect(picker.fileType, FileType.custom);
      expect(picker.extensions, ['docx']);
      expect(await temporary.list().isEmpty, isTrue);
    },
  );

  test(
    'save cancellation and provider failures never report success',
    () async {
      expect(
        await saveReportWord(bytes, 'report.docx'),
        ReportExportResult.cancelled,
      );
      picker.failure = PlatformException(code: 'write_failed');
      await expectLater(
        saveReportWord(bytes, 'report.docx'),
        throwsA(isA<PlatformException>()),
      );
    },
  );

  test('Windows writes exact report bytes to the chosen destination', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    picker.path = '${temporary.path}/Chosen name.docx';
    expect(
      await saveReportWord(bytes, 'report.docx'),
      ReportExportResult.completed,
    );
    expect(await File(picker.path!).readAsBytes(), bytes);
  });

  test(
    'desktop adds the Word extension without silently replacing another file',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      picker.path = '${temporary.path}/Chosen name';
      expect(
        await saveReportWord(bytes, 'report.docx'),
        ReportExportResult.completed,
      );
      expect(await File('${picker.path}.docx').readAsBytes(), bytes);
      await expectLater(
        saveReportWord(Uint8List.fromList([1, 2]), 'report.docx'),
        throwsA(isA<FileSystemException>()),
      );
      expect(await File('${picker.path}.docx').readAsBytes(), bytes);
    },
  );

  test('desktop write failure propagates for a retryable error', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    picker.path = '${temporary.path}/missing/report.docx';
    await expectLater(
      saveReportWord(bytes, 'report.docx'),
      throwsA(isA<FileSystemException>()),
    );
  });

  test(
    'Android shares a named Word file with the Office MIME and original bytes',
    () async {
      expect(
        await shareReportWord(bytes, 'تقرير.docx'),
        ReportExportResult.completed,
      );
      expect(shareCalls.single.method, 'shareFiles');
      final arguments = shareCalls.single.arguments as Map;
      expect(arguments['mimeTypes'], [reportWordMimeType]);
      final file = File((arguments['paths'] as List).single as String);
      expect(file.uri.pathSegments.last, 'تقرير.docx');
      expect(await file.readAsBytes(), bytes);
      expect(file.path, contains('tadbeer-word-reports'));
      expect(launchCalls, isEmpty);
    },
  );

  test('cancelled native share cleans its temporary file', () async {
    messenger.setMockMethodCallHandler(shareChannel, (call) async {
      shareCalls.add(call);
      return '';
    });
    expect(
      await shareReportWord(bytes, 'report.docx'),
      ReportExportResult.cancelled,
    );
    final file = File(
      (shareCalls.single.arguments['paths'] as List).single as String,
    );
    expect(await file.parent.exists(), isFalse);
  });

  test(
    'share plugin errors propagate and remove the failed temporary export',
    () async {
      messenger.setMockMethodCallHandler(shareChannel, (call) async {
        shareCalls.add(call);
        throw PlatformException(code: 'share_failed');
      });
      await expectLater(
        shareReportWord(bytes, 'report.docx'),
        throwsA(isA<PlatformException>()),
      );
      final file = File(
        (shareCalls.single.arguments['paths'] as List).single as String,
      );
      expect(await file.parent.exists(), isFalse);
    },
  );

  test(
    'Windows opens an independent Word file in the associated application',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      expect(
        await shareReportWord(bytes, 'report.docx'),
        ReportExportResult.completed,
      );
      final first = Uri.parse(launchCalls.single.arguments['url'] as String);
      expect(first.scheme, 'file');
      expect(await File.fromUri(first).readAsBytes(), bytes);
      expect(
        await shareReportWord(bytes, 'report.docx'),
        ReportExportResult.completed,
      );
      final second = Uri.parse(launchCalls.last.arguments['url'] as String);
      expect(first, isNot(second));
      expect(await File.fromUri(first).exists(), isTrue);
      expect(await File.fromUri(second).exists(), isTrue);
      expect(shareCalls, isEmpty);
    },
  );

  test(
    'missing Windows Word association is an error, not a cancellation',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      messenger.setMockMethodCallHandler(launchChannel, (call) async {
        launchCalls.add(call);
        return false;
      });
      await expectLater(
        shareReportWord(bytes, 'report.docx'),
        throwsStateError,
      );
      final uri = Uri.parse(launchCalls.single.arguments['url'] as String);
      expect(await File.fromUri(uri).parent.exists(), isFalse);
    },
  );

  test('empty or unsafe Word exports fail before reaching native dialogs', () {
    expect(
      () => saveReportWord(Uint8List(0), 'report.docx'),
      throwsArgumentError,
    );
    for (final filename in [
      'report.pdf',
      '../report.docx',
      r'C:\report.docx',
      '.docx',
    ]) {
      expect(() => shareReportWord(bytes, filename), throwsArgumentError);
    }
    expect(picker.filename, isNull);
    expect(shareCalls, isEmpty);
    expect(launchCalls, isEmpty);
  });
}
