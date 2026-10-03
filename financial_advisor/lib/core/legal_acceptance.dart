// Bump this shared version whenever a Terms or Privacy notice revision is published.
const currentLegalVersion = '2026-09-29.1';

class LegalAcceptance {
  final String version;
  final DateTime acceptedAt;
  final String language;

  LegalAcceptance({
    required this.version,
    required DateTime acceptedAt,
    required this.language,
  }) : acceptedAt = acceptedAt.toUtc() {
    if (version.trim().isEmpty ||
        version.length > 100 ||
        !['en', 'ar'].contains(language)) {
      throw ArgumentError('Invalid legal acceptance');
    }
  }

  Map<String, dynamic> toJson() => {
    'version': version,
    'acceptedAt': acceptedAt.toIso8601String(),
    'language': language,
  };

  static LegalAcceptance? fromJson(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    final version = value['version'];
    final timestamp = value['acceptedAt'];
    final language = value['language'];
    if (version is! String ||
        version.trim().isEmpty ||
        version.length > 100 ||
        timestamp is! String ||
        !RegExp(
          r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?Z$',
        ).hasMatch(timestamp) ||
        language is! String ||
        !['en', 'ar'].contains(language)) {
      return null;
    }
    final date = DateTime.tryParse(timestamp);
    if (date == null ||
        !date.isUtc ||
        date.toIso8601String().substring(0, 19) != timestamp.substring(0, 19)) {
      return null;
    }
    return LegalAcceptance(
      version: version,
      acceptedAt: date,
      language: language,
    );
  }
}
