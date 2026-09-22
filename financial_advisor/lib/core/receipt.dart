import 'package:intl/intl.dart';
import 'finance_store.dart';

class ReceiptDraft {
  final String merchant, category;
  final int? cents;
  final DateTime? date;
  const ReceiptDraft({
    required this.merchant,
    required this.category,
    this.cents,
    this.date,
  });
  static ReceiptDraft parse(String text) {
    final lines =
        text
            .split('\n')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();
    int? total;
    DateTime? date;
    for (var i = 0; i < lines.length; i++) {
      final l = lines[i];
      if (RegExp(
        r'^(grand\s+total|total\s*(amount|due)?|amount\s+due)\b',
        caseSensitive: false,
      ).hasMatch(l)) {
        final matches = RegExp(r'\d[\d,]*\.\d{2}\b').allMatches(l);
        if (matches.isNotEmpty) {
          total = parseMoney(matches.last.group(0)!);
        } else if (i + 1 < lines.length) {
          final next = RegExp(
            r'^\s*(?:SAR\s*)?(\d[\d,]*\.\d{2})\s*$',
            caseSensitive: false,
          ).firstMatch(lines[i + 1]);
          if (next != null) total = parseMoney(next.group(1)!);
        }
      }
      final iso = RegExp(r'\b(20\d{2})[-/](\d{2})[-/](\d{2})\b').firstMatch(l);
      if (iso != null) {
        try {
          date = DateFormat(
            'yyyy-MM-dd',
          ).parseStrict('${iso[1]}-${iso[2]}-${iso[3]}');
        } catch (_) {}
      }
    }
    final merchant = lines.isEmpty ? '' : lines.first;
    return ReceiptDraft(
      merchant: merchant,
      category: suggestCategory(merchant),
      cents: total,
      date: date,
    );
  }
}

String suggestCategory(String merchant) {
  final m = merchant.toLowerCase();
  if (RegExp('market|grocery|restaurant|cafe|coffee|food').hasMatch(m)) {
    return 'Food';
  }
  if (RegExp('uber|careem|fuel|petrol|transport').hasMatch(m)) {
    return 'Transportation';
  }
  if (RegExp('pharmacy|clinic|hospital').hasMatch(m)) return 'Healthcare';
  return 'Other';
}
