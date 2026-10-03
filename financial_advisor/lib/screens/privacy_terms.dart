import 'package:flutter/material.dart';
import '../core/legal_content.dart';
import '../l10n/app_language.dart';
import '../widgets/design.dart';

class PrivacyTermsPage extends StatelessWidget {
  const PrivacyTermsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final language = languageOf(context);
    final textScaler = MediaQuery.textScalerOf(context);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: canvas,
        appBar: AppBar(
          toolbarHeight: textScaler.scale(kToolbarHeight),
          title: const AppText(
            'Privacy & terms',
            maxLines: 2,
            style: TextStyle(fontSize: 20, height: 1.3),
          ),
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.center,
            tabs: [
              Tab(
                key: const Key('privacy-tab'),
                height: textScaler.scale(48),
                child: const AppText('Privacy'),
              ),
              Tab(
                key: const Key('terms-tab'),
                height: textScaler.scale(48),
                child: const AppText('Terms of use'),
              ),
            ],
          ),
        ),
        body: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: TabBarView(
                children: [
                  _DocumentView(
                    document: privacyDocument(language),
                    storageKey: 'privacy-$language',
                  ),
                  _DocumentView(
                    document: termsDocument(language),
                    storageKey: 'terms-$language',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DocumentView extends StatelessWidget {
  final LegalDocument document;
  final String storageKey;
  const _DocumentView({required this.document, required this.storageKey});

  @override
  Widget build(BuildContext context) => SelectionArea(
    child: ListView(
      key: PageStorageKey(storageKey),
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
      children: [
        Semantics(
          header: true,
          child: Text(
            document.title,
            style: Theme.of(
              context,
            ).textTheme.headlineMedium?.copyWith(letterSpacing: 0, height: 1.4),
            textAlign: TextAlign.start,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          document.introduction,
          style: const TextStyle(color: muted, fontSize: 15, height: 1.7),
          textAlign: TextAlign.start,
        ),
        const SizedBox(height: 24),
        for (final section in document.sections)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Surface(
              key: ValueKey('$storageKey-${section.id}'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      section.title,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        letterSpacing: 0,
                        height: 1.5,
                      ),
                      textAlign: TextAlign.start,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    section.body,
                    style: const TextStyle(fontSize: 15, height: 1.7),
                    textAlign: TextAlign.start,
                  ),
                ],
              ),
            ),
          ),
      ],
    ),
  );
}
