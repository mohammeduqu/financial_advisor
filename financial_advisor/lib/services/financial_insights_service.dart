import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/financial_insights.dart';
import 'invoice_service.dart';

export '../core/financial_insights.dart' show FinancialInsightsException;

class FinancialInsightsService {
  final String baseUrl;
  final Duration timeout;
  final http.Client Function() clientFactory;
  http.Client? _active;
  bool _closed = false;

  FinancialInsightsService({
    required this.baseUrl,
    this.timeout = const Duration(seconds: 180),
    http.Client Function()? clientFactory,
  }) : clientFactory = clientFactory ?? http.Client.new;

  Future<FinancialInsightsResult> generate(
    FinancialInsightsRequest snapshot,
  ) async {
    if (_closed) throw const FinancialInsightsException('cancelled');
    if (!snapshot.canGenerate) {
      throw const FinancialInsightsException('no_expenses');
    }
    if (validateInvoiceApiUrl(baseUrl) != null) {
      throw const FinancialInsightsException('invalid_url');
    }
    if (_active != null) {
      throw const FinancialInsightsException('server_busy');
    }
    final client = clientFactory();
    _active = client;
    try {
      final request =
          http.Request(
              'POST',
              Uri.parse(baseUrl.trim()).replace(path: '/api/insights/expenses'),
            )
            ..headers['Accept'] = 'application/json'
            ..headers['Content-Type'] = 'application/json'
            ..body = jsonEncode(snapshot.toJson());
      final response = await (() async {
        final streamed = await client.send(request);
        return http.Response.fromStream(streamed);
      })().timeout(
        timeout > invoiceRequestTimeout ? invoiceRequestTimeout : timeout,
      );
      if (_closed) throw const FinancialInsightsException('cancelled');
      if (isHtmlApiResponse(response)) {
        throw const FinancialInsightsException('wrong_server_url');
      }
      if (response.bodyBytes.length > 32768) {
        throw const FinancialInsightsException('invalid_insights_response');
      }
      final dynamic body;
      try {
        body = jsonDecode(utf8.decode(response.bodyBytes));
      } catch (_) {
        throw const FinancialInsightsException('invalid_insights_response');
      }
      if (body is! Map<String, dynamic>) {
        throw const FinancialInsightsException('invalid_insights_response');
      }
      if (response.statusCode != 200 || body['success'] != true) {
        // Only a recognized code selects copy; raw provider messages stay private.
        const knownCodes = {
          'no_expenses',
          'insights_too_large',
          'invalid_insights_request',
          'invalid_insights_response',
          'ai_not_configured',
          'ai_authentication_failed',
          'ai_configuration_error',
          'ai_rate_limited',
          'ai_model_unavailable',
          'ai_unavailable',
          'server_busy',
          'analysis_timeout',
          'analysis_refused',
          'incomplete_analysis',
        };
        throw FinancialInsightsException(
          knownCodes.contains(body['code']) ? body['code'] : 'insights_failed',
        );
      }
      return FinancialInsightsResult.fromJson(body, request: snapshot);
    } on FinancialInsightsException {
      rethrow;
    } on TimeoutException {
      throw const FinancialInsightsException('insights_timeout');
    } catch (_) {
      throw FinancialInsightsException(
        _closed ? 'cancelled' : 'connection_error',
      );
    } finally {
      client.close();
      _active = null;
    }
  }

  void close() {
    _closed = true;
    _active?.close();
  }
}
