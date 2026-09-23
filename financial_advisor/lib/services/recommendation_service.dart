import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../core/invoice.dart';
import '../core/product_search_options.dart';
import '../core/recommendation.dart';
import 'invoice_service.dart';

class RecommendationApiException implements Exception {
  final String code;
  const RecommendationApiException(this.code);
  String get message => switch (code) {
    'invalid_search_options' =>
      'Check the search country, language and maximum price.',
    'unsupported_search_country' =>
      'Product search is unavailable in this country. Please choose another country.',
    'invalid_search_query' => 'Enter one product name of up to 400 characters.',
    'serpapi_not_configured' ||
    'missing_serpapi_key' ||
    'serpapi_auth_failed' ||
    'price_cache_unavailable' =>
      'Price search is temporarily unavailable. Please try again later.',
    'serpapi_quota_exceeded' ||
    'serpapi_rate_limited' => 'Price search is busy. Please try again later.',
    'serpapi_unavailable' || 'serpapi_timeout' || 'search_failed' =>
      'Shopping search is unavailable. Your reviewed products are still here.',
    'invalid_text' || 'invalid_search_text' || 'text_too_long' =>
      'Enter a product name or a shopping list within the text limit.',
    'unreadable_list' ||
    'invalid_shopping_list_json' ||
    'invalid_shopping_list' ||
    'unidentified_shopping_list' ||
    'unidentified_list' =>
      'The list could not be read. Paste clearer text or choose a clearer image.',
    'no_products' || 'invalid_products' || 'invalid_request' =>
      'Check the product names, quantities, sizes and prices before searching.',
    'shop_link_unavailable' =>
      'A matching online shop link could not be found. Try another offer.',
    'combined_query_too_long' =>
      'This list is too long for one search. Select fewer items and try again.',
    'unsupported_currency' =>
      'Price comparisons currently support SAR invoices only. No currency conversion is performed.',
    'unreadable_product' || 'invalid_product_json' || 'unidentified_product' =>
      'The product could not be identified. Try a clearer photo of its label.',
    'search_timeout' => 'Price search timed out. Try again shortly.',
    'confirmation_required' || 'review_required' =>
      'Review your products before starting the price search.',
    _ => InvoiceApiException(code).message,
  };
}

/// Uses the same Flask URL, image limit and timeout as invoice scanning.
class RecommendationService {
  final String baseUrl;
  final Duration timeout;
  final http.Client Function() clientFactory;
  http.Client? _active;
  RecommendationService({
    required this.baseUrl,
    this.timeout = invoiceRequestTimeout,
    http.Client Function()? clientFactory,
  }) : clientFactory = clientFactory ?? http.Client.new;

  Future<Map<String, dynamic>> _send(http.BaseRequest request) async {
    if (validateInvoiceApiUrl(baseUrl) != null) {
      throw const RecommendationApiException('invalid_url');
    }
    if (_active != null) throw const RecommendationApiException('server_busy');
    final client = clientFactory();
    _active = client;
    try {
      final response = await (() async {
        final streamed = await client.send(request);
        return http.Response.fromStream(streamed);
      })().timeout(timeout);
      if (isHtmlApiResponse(response)) {
        throw const RecommendationApiException('wrong_server_url');
      }
      final dynamic body;
      try {
        body = jsonDecode(utf8.decode(response.bodyBytes));
      } catch (_) {
        throw const RecommendationApiException('invalid_response');
      }
      if (body is! Map<String, dynamic>) {
        throw const RecommendationApiException('invalid_response');
      }
      if (response.statusCode != 200 || body['success'] != true) {
        throw RecommendationApiException(
          body['code'] is String ? body['code'] : 'search_failed',
        );
      }
      return body;
    } on TimeoutException {
      throw const RecommendationApiException('search_timeout');
    } on http.ClientException {
      throw const RecommendationApiException('connection_error');
    } finally {
      client.close();
      _active = null;
    }
  }

  Uri _uri(String mode) {
    if (validateInvoiceApiUrl(baseUrl) != null) {
      throw const RecommendationApiException('invalid_url');
    }
    return Uri.parse(
      baseUrl.trim(),
    ).replace(path: '/api/recommendations/$mode');
  }

  Future<RecommendationReview> identify(
    Uint8List bytes,
    String filename, {
    double? currentPrice,
  }) async {
    if (bytes.length > invoiceMaxImageBytes) {
      throw const RecommendationApiException('image_too_large');
    }
    final request =
        http.MultipartRequest('POST', _uri('product'))
          ..headers['Accept'] = 'application/json'
          ..files.add(
            http.MultipartFile.fromBytes('image', bytes, filename: filename),
          );
    if (currentPrice != null) {
      request.fields['optional_current_price'] = '$currentPrice';
    }
    final body = await _send(request);
    try {
      return RecommendationReview.fromJson(body);
    } catch (_) {
      throw const RecommendationApiException('invalid_response');
    }
  }

  Future<RecommendationReview> reviewText(
    String text, {
    bool shoppingList = false,
  }) async {
    final input = text.trim();
    if (input.isEmpty || input.length > (shoppingList ? 8000 : 400)) {
      throw const RecommendationApiException('invalid_text');
    }
    final request =
        http.Request('POST', _uri(shoppingList ? 'shopping-list' : 'product'))
          ..headers['Content-Type'] = 'application/json'
          ..headers['Accept'] = 'application/json'
          ..body = jsonEncode({'text': input});
    final body = await _send(request);
    try {
      return RecommendationReview.fromJson(body);
    } catch (_) {
      throw const RecommendationApiException('invalid_response');
    }
  }

  Future<RecommendationResult> searchProduct(
    String query, {
    String countryCode = 'sa',
    String location = 'Saudi Arabia',
    String googleDomain = 'google.com.sa',
    String language = 'ar',
    double? maxPrice,
  }) async {
    final input = query.trim();
    if (input.isEmpty ||
        input.length > 400 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(input)) {
      throw const RecommendationApiException('invalid_search_query');
    }
    if (!RegExp(r'^[a-z]{2}$').hasMatch(countryCode) ||
        !['en', 'ar'].contains(language) ||
        !RegExp(
          r'^google\.[a-z]{2,3}(?:\.[a-z]{2})?$',
        ).hasMatch(googleDomain) ||
        location.trim().isEmpty ||
        location.length > 200 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(location) ||
        (maxPrice != null && !isValidProductSearchPrice(maxPrice))) {
      throw const RecommendationApiException('invalid_search_options');
    }
    if (isKnownUnsupportedSearchCountry(countryCode)) {
      throw const RecommendationApiException('unsupported_search_country');
    }
    final request =
        http.Request('POST', _uri('search'))
          ..headers['Content-Type'] = 'application/json'
          ..headers['Accept'] = 'application/json'
          ..body = jsonEncode({
            'q': input,
            'gl': countryCode,
            'location': location.trim(),
            'google_domain': googleDomain,
            'hl': language,
            'max_price': maxPrice,
          });
    final body = await _send(request);
    try {
      if (body['direct_search'] != true ||
          body['shopping_results'] is! List ||
          (body['shopping_results'] as List).any(
            (item) => item is! Map<String, dynamic>,
          )) {
        throw const FormatException('Invalid product search result');
      }
      return RecommendationResult.fromJson(body);
    } catch (_) {
      throw const RecommendationApiException('invalid_response');
    }
  }

  Future<RecommendationReview> readShoppingImage(
    Uint8List bytes,
    String filename,
  ) async {
    if (bytes.length > invoiceMaxImageBytes) {
      throw const RecommendationApiException('image_too_large');
    }
    final request =
        http.MultipartRequest('POST', _uri('shopping-list'))
          ..headers['Accept'] = 'application/json'
          ..files.add(
            http.MultipartFile.fromBytes('image', bytes, filename: filename),
          );
    final body = await _send(request);
    try {
      return RecommendationReview.fromJson(body);
    } catch (_) {
      throw const RecommendationApiException('invalid_response');
    }
  }

  Future<RecommendationResult> search({
    required String mode,
    required List<ReviewProduct> products,
    InvoiceModel? invoice,
  }) async {
    if (!['product', 'invoice', 'shopping-list'].contains(mode)) {
      throw const RecommendationApiException('invalid_request');
    }
    final request =
        http.Request('POST', _uri(mode))
          ..headers['Content-Type'] = 'application/json'
          ..headers['Accept'] = 'application/json'
          ..body = jsonEncode({
            'confirmed': true,
            'products': products.map((e) => e.toJson()).toList(),
            if (invoice != null) 'invoice': invoice.toJson(),
          });
    final body = await _send(request);
    try {
      return RecommendationResult.fromJson(body);
    } catch (_) {
      throw const RecommendationApiException('invalid_response');
    }
  }

  void close() => _active?.close();
}
