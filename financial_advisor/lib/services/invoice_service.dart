import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../core/invoice.dart';

const invoiceApiPreference = 'invoice_api_url';
const _deployedApiMigrationPreference = 'invoice_api_deployed_v1';
const deployedInvoiceApiUrl = 'http://31.97.178.214:5001';
const invoiceMaxImageBytes = 1500000;
const invoiceRequestTimeout = Duration(seconds: 330);

/// Flutter development servers can return their HTML shell for API paths.
/// Detect that response before JSON parsing so the user can fix the address.
bool isHtmlApiResponse(http.Response response) {
  final contentType =
      (response.headers['content-type'] ?? '')
          .split(';')
          .first
          .trim()
          .toLowerCase();
  if (contentType == 'text/html' || contentType == 'application/xhtml+xml') {
    return true;
  }
  final prefix =
      utf8
          .decode(response.bodyBytes.take(1024).toList(), allowMalformed: true)
          .replaceFirst(RegExp(r'^\uFEFF'), '')
          .trimLeft();
  return RegExp(
    r'^(?:<!doctype\s+html\b|<html\b)',
    caseSensitive: false,
  ).hasMatch(prefix);
}

String defaultInvoiceApiUrl() {
  const configured = String.fromEnvironment('INVOICE_API_URL');
  if (configured.isNotEmpty) return configured;
  return deployedInvoiceApiUrl;
}

/// Old installs stored a local address which would otherwise mask the new default.
/// After migration, manual server selections (including local ones) take precedence.
String configuredInvoiceApiUrl(SharedPreferences prefs) {
  final saved = prefs.getString(invoiceApiPreference)?.trim();
  if (saved == null || saved.isEmpty) return defaultInvoiceApiUrl();
  if (prefs.getBool(_deployedApiMigrationPreference) != true &&
      _isLegacyLocalApiUrl(saved)) {
    return defaultInvoiceApiUrl();
  }
  return saved;
}

Future<bool> saveInvoiceApiUrl(SharedPreferences prefs, String value) async {
  if (validateInvoiceApiUrl(value) != null) return false;
  if (!await prefs.setString(invoiceApiPreference, value.trim())) return false;
  return prefs.setBool(_deployedApiMigrationPreference, true);
}

Future<void> migrateInvoiceApiUrl(SharedPreferences prefs) async {
  if (prefs.getBool(_deployedApiMigrationPreference) == true) return;
  final saved = prefs.getString(invoiceApiPreference)?.trim();
  // Drop obsolete overrides so future deployments can still change the default.
  if (saved != null && (saved.isEmpty || _isLegacyLocalApiUrl(saved))) {
    if (!await prefs.remove(invoiceApiPreference)) return;
  }
  await prefs.setBool(_deployedApiMigrationPreference, true);
}

bool _isLegacyLocalApiUrl(String value) {
  final host = Uri.tryParse(value)?.host.toLowerCase();
  if (host == null) return false;
  if (host == 'localhost' || host == '[::1]' || host == '::1') return true;
  final parts = host.split('.').map(int.tryParse).toList();
  if (parts.length != 4 ||
      !parts.every((p) => p != null && p >= 0 && p <= 255)) {
    return false;
  }
  return parts[0] == 127 ||
      parts[0] == 10 ||
      (parts[0] == 192 && parts[1] == 168) ||
      (parts[0] == 172 && parts[1]! >= 16 && parts[1]! <= 31);
}

/// Accept a backend origin, without embedded credentials or API paths.
String? validateInvoiceApiUrl(String value) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null ||
      !['http', 'https'].contains(uri.scheme) ||
      uri.host.isEmpty ||
      RegExp(r'\s').hasMatch(value.trim()) ||
      uri.port < 1 ||
      uri.port > 65535 ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      (uri.path.isNotEmpty && uri.path != '/')) {
    return 'The service is not configured correctly. Please contact support.';
  }
  return null;
}

class InvoiceApiException implements Exception {
  final String code;
  const InvoiceApiException(this.code);
  String get message => switch (code) {
    'connection_error' => 'Could not connect to the invoice analysis server.',
    'analysis_timeout' => 'Analysis timed out. Try a smaller, clearer photo.',
    'ollama_unavailable' || 'model_not_installed' =>
      'Invoice analysis is temporarily unavailable. Please try again later.',
    'server_busy' =>
      'The server is analyzing another invoice. Try again shortly.',
    'image_too_large' => 'Image is too large. Choose a smaller image.',
    'unsupported_image' => 'Choose a JPG or PNG image.',
    'invalid_image' || 'unreadable_invoice' =>
      'Invoice could not be read. Please retake the photo.',
    'invalid_invoice_json' || 'invalid_response' =>
      'AI returned an invalid result. Please analyze the invoice again.',
    'incomplete_analysis' =>
      'Analysis was incomplete. Try a clearer photo with fewer items.',
    'invalid_url' =>
      'The service is not configured correctly. Please contact support.',
    'wrong_server_url' =>
      'The service returned an unexpected response. Please try again later.',
    _ => 'AI analysis failed. Please try again.',
  };
}

class InvoiceAnalysis {
  final InvoiceModel invoice;
  final List<String> warnings;
  const InvoiceAnalysis(this.invoice, this.warnings);
}

class InvoiceService {
  final String baseUrl;
  final Duration timeout;
  final http.Client Function() clientFactory;
  http.Client? _active;
  InvoiceService({
    required this.baseUrl,
    this.timeout = invoiceRequestTimeout,
    http.Client Function()? clientFactory,
  }) : clientFactory = clientFactory ?? http.Client.new;

  Future<InvoiceAnalysis> analyze(Uint8List bytes, String filename) async {
    if (validateInvoiceApiUrl(baseUrl) != null) {
      throw const InvoiceApiException('invalid_url');
    }
    if (bytes.length > invoiceMaxImageBytes) {
      throw const InvoiceApiException('image_too_large');
    }
    if (_active != null) throw const InvoiceApiException('server_busy');
    final client = clientFactory();
    _active = client;
    try {
      final uri = Uri.parse(
        baseUrl.trim(),
      ).replace(path: '/api/invoice/analyze');
      final request =
          http.MultipartRequest('POST', uri)
            ..headers['Accept'] = 'application/json'
            ..files.add(
              http.MultipartFile.fromBytes('image', bytes, filename: filename),
            );
      final response = await (() async {
        final streamed = await client.send(request);
        return http.Response.fromStream(streamed);
      })().timeout(timeout);
      if (isHtmlApiResponse(response)) {
        throw const InvoiceApiException('wrong_server_url');
      }
      final dynamic body;
      try {
        body = jsonDecode(utf8.decode(response.bodyBytes));
      } catch (_) {
        throw const InvoiceApiException('invalid_response');
      }
      if (body is! Map<String, dynamic>) {
        throw const InvoiceApiException('invalid_response');
      }
      if (response.statusCode != 200 || body['success'] != true) {
        throw InvoiceApiException(
          body['code'] is String ? body['code'] : 'analysis_failed',
        );
      }
      if (body['invoice'] is! Map<String, dynamic>) {
        throw const InvoiceApiException('invalid_response');
      }
      try {
        return InvoiceAnalysis(
          InvoiceModel.fromJson(body['invoice']),
          (body['warnings'] is List ? body['warnings'] as List : const [])
              .whereType<String>()
              .toList(),
        );
      } catch (_) {
        throw const InvoiceApiException('invalid_response');
      }
    } on TimeoutException {
      throw const InvoiceApiException('analysis_timeout');
    } on http.ClientException {
      throw const InvoiceApiException('connection_error');
    } finally {
      client.close();
      _active = null;
    }
  }

  void close() => _active?.close();
}
