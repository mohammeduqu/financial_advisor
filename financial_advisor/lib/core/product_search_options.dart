import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

bool isValidProductSearchPrice(num value) =>
    value.isFinite &&
    value > 0 &&
    value < 1e9 &&
    value.toDouble() == double.parse(value.toStringAsFixed(2));

class ProductSearchCountry {
  final String code, name, domain;
  final bool shoppingSupported;
  const ProductSearchCountry(
    this.code,
    this.name,
    this.domain, {
    this.shoppingSupported = true,
  });
}

const productSearchCountries = [
  ProductSearchCountry('sa', 'Saudi Arabia', 'google.com.sa'),
  ProductSearchCountry('ae', 'United Arab Emirates', 'google.ae'),
  ProductSearchCountry('us', 'United States', 'google.com'),
  ProductSearchCountry('gb', 'United Kingdom', 'google.co.uk'),
  // Keep saved selections recognizable, but do not submit unsupported markets.
  // https://serpapi.com/google-shopping-countries
  ProductSearchCountry(
    'eg',
    'Egypt',
    'google.com.eg',
    shoppingSupported: false,
  ),
  ProductSearchCountry(
    'kw',
    'Kuwait',
    'google.com.kw',
    shoppingSupported: false,
  ),
  ProductSearchCountry(
    'qa',
    'Qatar',
    'google.com.qa',
    shoppingSupported: false,
  ),
  ProductSearchCountry(
    'bh',
    'Bahrain',
    'google.com.bh',
    shoppingSupported: false,
  ),
  ProductSearchCountry('om', 'Oman', 'google.com.om', shoppingSupported: false),
];

bool isKnownUnsupportedSearchCountry(String code) => productSearchCountries.any(
  (country) => country.code == code && !country.shoppingSupported,
);

class ProductSearchOptions {
  static const preferenceKey = 'numo_product_search_options_v3';
  static const previousPreferenceKey = 'numo_product_search_options_v2';
  static const legacyPreferenceKey = 'numo_product_search_options_v1';
  final String countryCode, language;
  final double? maxPrice;
  const ProductSearchOptions({
    this.countryCode = 'sa',
    this.language = 'ar',
    this.maxPrice,
  });

  ProductSearchCountry get country => productSearchCountries.firstWhere(
    (country) => country.code == countryCode,
    orElse: () => productSearchCountries.first,
  );
  String get googleDomain => country.domain;
  String get location => country.name;

  factory ProductSearchOptions.load(SharedPreferences prefs) {
    try {
      final current = prefs.getString(preferenceKey);
      final raw =
          current ??
          prefs.getString(previousPreferenceKey) ??
          prefs.getString(legacyPreferenceKey);
      if (raw == null) return const ProductSearchOptions();
      final data = jsonDecode(raw);
      if (data is! Map<String, dynamic>) return const ProductSearchOptions();
      final country = productSearchCountries.firstWhere(
        (value) => value.code == data['gl'],
        orElse: () => productSearchCountries.first,
      );
      // Earlier versions prefilled a price cap. Start the simplified form empty
      // while preserving the user's country and result language.
      final price = current == null ? null : data['max_price'];
      return ProductSearchOptions(
        countryCode: country.code,
        language: data['hl'] == 'en' ? 'en' : 'ar',
        maxPrice:
            price is num && isValidProductSearchPrice(price)
                ? price.toDouble()
                : null,
      );
    } catch (_) {
      return const ProductSearchOptions();
    }
  }

  Future<bool> save(SharedPreferences prefs) => prefs.setString(
    preferenceKey,
    jsonEncode({'gl': countryCode, 'hl': language, 'max_price': maxPrice}),
  );
}
