import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../config/flask_config.dart';
import '../core/finance_store.dart';
import '../core/financial_insights.dart';
import '../l10n/app_language.dart';
import '../services/financial_insights_service.dart';
import 'design.dart';

class FinancialInsightsPanel extends StatefulWidget {
  final FinanceStore store;
  final DateTime month;
  final FinancialInsightsService Function(String)? serviceFactory;
  final DateTime Function()? now;

  const FinancialInsightsPanel({
    super.key,
    required this.store,
    required this.month,
    this.serviceFactory,
    this.now,
  });

  @override
  State<FinancialInsightsPanel> createState() => _FinancialInsightsPanelState();
}

class _FinancialInsightsPanelState extends State<FinancialInsightsPanel> {
  FinancialInsightsService? _service;
  FinancialInsightsResult? _result;
  String? _resultFingerprint;
  String? _error;
  bool _busy = false;

  FinancialInsightsRequest _request() => FinancialInsightsRequest.fromStore(
    widget.store,
    widget.month,
    language: languageOf(context),
    now: widget.now?.call(),
  );

  Future<void> _generate(FinancialInsightsRequest request) async {
    if (_busy || !request.canGenerate) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    _service?.close();
    _service =
        widget.serviceFactory?.call(flaskApiUrl()) ??
        FinancialInsightsService(baseUrl: flaskApiUrl());
    try {
      final result = await _service!.generate(request);
      if (!mounted) return;
      if (_request().fingerprint != request.fingerprint) {
        setState(
          () =>
              _error =
                  'Your expenses or language changed. Generate insights again.',
        );
        return;
      }
      setState(() {
        _result = result;
        _resultFingerprint = request.fingerprint;
      });
    } on FinancialInsightsException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not generate insights. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _service?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.store,
    builder: (context, _) {
      FinancialInsightsRequest? request;
      String? inputError;
      try {
        request = _request();
      } on FinancialInsightsException catch (e) {
        inputError = e.message;
      } catch (_) {
        inputError = 'Could not prepare your expenses for analysis.';
      }
      final result =
          _resultFingerprint == request?.fingerprint ? _result : null;
      final canGenerate = request?.canGenerate ?? false;
      final error = inputError ?? _error;
      final stale = _result != null && result == null;

      return Column(
        key: const Key('financial-insights-panel'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeading(
            'AI Financial Insights',
            action: Icon(
              Icons.auto_awesome_outlined,
              color: Color(0xFFCDBB93),
              size: 20,
            ),
          ),
          Surface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  DateFormat.yMMMM(languageOf(context)).format(widget.month),
                  style: const TextStyle(color: blue, fontSize: 12),
                ),
                const SizedBox(height: 10),
                const AppText(
                  'A little perspective. A better plan.',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 10),
                const AppText(
                  'Get practical ways to reduce spending based on your recorded expenses.',
                  style: TextStyle(fontSize: 13, color: muted, height: 1.6),
                ),
                if (!canGenerate && inputError == null) ...[
                  const SizedBox(height: 14),
                  const AppText(
                    'Add expenses for this month to get personalized insights.',
                    style: TextStyle(fontSize: 13, color: muted, height: 1.6),
                  ),
                ],
                if (stale && error == null) ...[
                  const SizedBox(height: 14),
                  const AppText(
                    'Your expenses or language changed. Generate insights again.',
                    style: TextStyle(fontSize: 12, color: muted, height: 1.6),
                  ),
                ],
                if (result != null) ...[
                  const SizedBox(height: 20),
                  Text(
                    result.summary,
                    key: const Key('financial-insights-result'),
                    style: const TextStyle(fontSize: 14, height: 1.7),
                  ),
                  for (var i = 0; i < result.insights.length; i++) ...[
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Divider(),
                    ),
                    _InsightCard(
                      key: ValueKey('financial-insight-$i'),
                      insight: result.insights[i],
                    ),
                  ],
                  const SizedBox(height: 18),
                  AppText(
                    'Based on ${result.basedOn.expenseCount} recorded expenses',
                    style: const TextStyle(color: muted, fontSize: 11),
                  ),
                  const SizedBox(height: 4),
                  AppText(
                    'Generated: ${DateFormat.yMd(languageOf(context)).add_jm().format(result.generatedAt.toLocal())}',
                    style: const TextStyle(color: muted, fontSize: 11),
                  ),
                ],
                if (error != null) ...[
                  const SizedBox(height: 16),
                  Semantics(
                    liveRegion: true,
                    child: AppText(
                      error,
                      key: const Key('financial-insights-error'),
                      style: const TextStyle(
                        color: Color(0xFFFFB4AB),
                        fontSize: 13,
                        height: 1.6,
                      ),
                    ),
                  ),
                ],
                if (_busy) ...[
                  const SizedBox(height: 18),
                  const LinearProgressIndicator(
                    key: Key('financial-insights-loading'),
                  ),
                  const SizedBox(height: 10),
                  Semantics(
                    liveRegion: true,
                    child: const AppText(
                      'Analyzing your expenses…',
                      style: TextStyle(color: muted, fontSize: 12),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    key: const Key('generate-financial-insights'),
                    onPressed:
                        _busy || !canGenerate || request == null
                            ? null
                            : () => _generate(request!),
                    icon: const Icon(Icons.auto_awesome_outlined, size: 20),
                    label: AppText(
                      _busy
                          ? 'Generating insights…'
                          : error != null && canGenerate
                          ? 'Try again'
                          : result != null
                          ? 'Refresh insights'
                          : 'Generate AI insights',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const AppText(
                  'An expense summary is using AI to generate insights.',
                  style: TextStyle(fontSize: 11, color: muted, height: 1.6),
                ),
              ],
            ),
          ),
        ],
      );
    },
  );
}

class _InsightCard extends StatelessWidget {
  final FinancialInsight insight;
  const _InsightCard({super.key, required this.insight});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (insight.category != null) ...[
        AppText(
          insight.category!,
          style: const TextStyle(color: blue, fontSize: 11),
        ),
        const SizedBox(height: 6),
      ],
      Text(
        insight.title,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
      const SizedBox(height: 8),
      Text(
        insight.observation,
        style: const TextStyle(color: muted, fontSize: 13, height: 1.6),
      ),
      const SizedBox(height: 12),
      const AppText(
        'Try this',
        style: TextStyle(
          color: blue,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 4),
      Text(insight.action, style: const TextStyle(fontSize: 13, height: 1.6)),
    ],
  );
}
