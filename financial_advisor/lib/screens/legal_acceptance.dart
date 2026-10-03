import 'package:flutter/material.dart';
import '../core/finance_store.dart';
import '../l10n/app_language.dart';
import '../widgets/design.dart';
import '../widgets/legal_acceptance_field.dart';
import '../widgets/tadbeer_logo.dart';

class LegalAcceptancePage extends StatefulWidget {
  final FinanceStore store;
  const LegalAcceptancePage({super.key, required this.store});

  @override
  State<LegalAcceptancePage> createState() => _LegalAcceptancePageState();
}

class _LegalAcceptancePageState extends State<LegalAcceptancePage> {
  bool accepted = false, busy = false;
  String? error;

  Future<void> continueToApp() async {
    if (busy || !accepted) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.store.acceptLegalTerms(
        accepted: accepted,
        language: languageOf(context),
      );
      if (!widget.store.hasAcceptedCurrentLegal) {
        throw StateError('Agreement was not saved');
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          error = 'Could not save your agreement. Please try again.';
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(32),
            children: [
              const Align(
                alignment: AlignmentDirectional.centerStart,
                child: TadbeerLogo(size: 64),
              ),
              const SizedBox(height: 24),
              AppText(
                'Privacy & terms',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 16),
              const AppText(
                'Please review the Privacy notice and Terms of use. Check the box below to continue using Tadbeer.',
                style: TextStyle(color: muted, fontSize: 16, height: 1.6),
              ),
              const SizedBox(height: 24),
              LegalAcceptanceField(
                value: accepted,
                enabled: !busy,
                readButtonKey: const Key('read-legal-documents'),
                onChanged: (value) => setState(() => accepted = value),
              ),
              if (error != null) ...[
                const SizedBox(height: 12),
                Semantics(
                  liveRegion: true,
                  child: AppText(
                    error!,
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              FilledButton(
                key: const Key('accept-legal-continue'),
                onPressed: busy || !accepted ? null : continueToApp,
                child: const AppText('Continue'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
