import 'package:flutter/material.dart';
import '../l10n/app_language.dart';
import '../screens/privacy_terms.dart';

class LegalAcceptanceField extends StatelessWidget {
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;
  final Key readButtonKey;

  const LegalAcceptanceField({
    super.key,
    required this.value,
    required this.onChanged,
    required this.readButtonKey,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextButton.icon(
        key: readButtonKey,
        icon: const Icon(Icons.article_outlined),
        label: const AppText('Privacy & terms'),
        onPressed:
            enabled
                ? () => Navigator.push<void>(
                  context,
                  MaterialPageRoute(builder: (_) => const PrivacyTermsPage()),
                )
                : null,
      ),
      CheckboxListTile(
        key: const Key('legal-acceptance-checkbox'),
        value: value,
        onChanged: enabled ? (checked) => onChanged(checked ?? false) : null,
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: EdgeInsets.zero,
        title: const AppText(
          'I agree to the Terms of use and acknowledge the Privacy notice.',
          style: TextStyle(fontSize: 14, height: 1.6),
        ),
      ),
    ],
  );
}
