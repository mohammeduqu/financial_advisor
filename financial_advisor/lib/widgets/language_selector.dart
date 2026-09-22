import 'package:flutter/material.dart';
import '../core/finance_store.dart';
import '../l10n/app_language.dart';
import 'design.dart';

class LanguageSelector extends StatelessWidget {
  final FinanceStore store;
  const LanguageSelector({super.key, required this.store});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: store,
    builder:
        (context, _) => ListTile(
          key: const Key('language-selector'),
          leading: const Icon(Icons.language),
          title: const AppText('Language'),
          subtitle:
              store.languageCode == null
                  ? const AppText('Automatic · device language')
                  : Text(store.languageCode == 'ar' ? 'العربية' : 'English'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () async {
            final selected = await showDialog<String>(
              context: context,
              builder:
                  (dialogContext) => SimpleDialog(
                    title: const AppText('Choose language'),
                    children: [
                      for (final code in ['auto', 'en', 'ar'])
                        SimpleDialogOption(
                          key: Key('language-option-$code'),
                          onPressed: () => Navigator.pop(dialogContext, code),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 16,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child:
                                    code == 'auto'
                                        ? const AppText(
                                          'Automatic · device language',
                                        )
                                        : Text(
                                          code == 'ar' ? 'العربية' : 'English',
                                        ),
                              ),
                              if ((store.languageCode ?? 'auto') == code)
                                const Icon(Icons.check, color: blue),
                            ],
                          ),
                        ),
                    ],
                  ),
            );
            if (selected != null) {
              await store.setLanguage(selected == 'auto' ? null : selected);
            }
          },
        ),
  );
}
