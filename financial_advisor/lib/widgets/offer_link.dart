import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../widgets/design.dart';

Uri? safeDealUri(dynamic value) {
  if (value is! String) return null;
  try {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !['https', 'http'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.port < 1 ||
        uri.port > 65535) {
      return null;
    }
    final host = uri.host.toLowerCase().replaceFirst(RegExp(r'\.$'), '');
    if (!host.contains('.') ||
        host.contains(':') ||
        RegExp(r'^[0-9.]+$').hasMatch(host) ||
        host.startsWith('0x') ||
        host == 'localhost' ||
        host.endsWith('.localhost') ||
        host.endsWith('.local') ||
        host.endsWith('.internal') ||
        host == 'serpapi.com' ||
        host.endsWith('.serpapi.com')) {
      return null;
    }
    if (uri.queryParameters.keys.any(
      (key) => [
        'key',
        'api_key',
        'apikey',
        'token',
        'access_token',
      ].contains(key.toLowerCase()),
    )) {
      return null;
    }
    return uri;
  } catch (_) {
    return null;
  }
}

/// Opens the supplied link only. Old lookup tokens never trigger a search.
Future<void> openRecommendationOffer(
  BuildContext context,
  Map<String, dynamic> offer,
) async {
  final url = safeDealUri(offer['product_link'] ?? offer['product_url']);
  if (url == null) {
    toast(context, 'Could not open the deal. Try again.');
    return;
  }
  await launchShopUrl(context, url);
}

Future<void> launchShopUrl(BuildContext context, Uri url) async {
  try {
    if (!await launchUrl(url, mode: LaunchMode.externalApplication) &&
        context.mounted) {
      toast(context, 'Could not open the deal. Try again.');
    }
  } catch (_) {
    if (context.mounted) toast(context, 'Could not open the deal. Try again.');
  }
}
