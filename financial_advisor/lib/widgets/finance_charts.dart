import '../l10n/app_language.dart';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import '../core/finance_store.dart';
import 'design.dart';

const chartColors = [
  Color(0xFF73CBB0),
  Color(0xFF729DCF),
  Color(0xFFC5B185),
  Color(0xFF9C8ABB),
  Color(0xFFB88875),
];

class SpendingTrend extends StatelessWidget {
  final FinanceStore store;
  final DateTime? month;
  const SpendingTrend({super.key, required this.store, required this.month});
  @override
  Widget build(BuildContext context) {
    final selectedMonth = month;
    final entries = store.forPeriod(selectedMonth);
    final List<double> values;
    final String firstLabel, lastLabel;
    final String semantics;
    if (selectedMonth != null) {
      final days = DateTime(selectedMonth.year, selectedMonth.month + 1, 0).day;
      values = List<double>.filled(days, 0);
      for (final entry in entries.where((entry) => !entry.income)) {
        values[entry.date.day - 1] += entry.cents / 100;
      }
      firstLabel = 'Day 1';
      lastLabel = 'Day $days';
      semantics = 'Cumulative spending over $days days';
    } else {
      // The extent comes from saved history, so a calendar rollover cannot
      // replace earlier data or change the displayed reporting period.
      final firstDate = entries.lastOrNull?.date;
      final lastDate = entries.firstOrNull?.date;
      final months =
          firstDate == null || lastDate == null
              ? 0
              : (lastDate.year - firstDate.year) * 12 +
                  lastDate.month -
                  firstDate.month +
                  1;
      values = List<double>.filled(months + 1, 0);
      if (firstDate != null) {
        for (final entry in entries.where((entry) => !entry.income)) {
          final index =
              (entry.date.year - firstDate.year) * 12 +
              entry.date.month -
              firstDate.month +
              1;
          values[index] += entry.cents / 100;
        }
      }
      final dateFormat = DateFormat.yMMM(languageOf(context));
      firstLabel = firstDate == null ? '' : dateFormat.format(firstDate);
      lastLabel = lastDate == null ? '' : dateFormat.format(lastDate);
      semantics = 'Cumulative spending across all dates';
    }
    for (var i = 1; i < values.length; i++) {
      values[i] += values[i - 1];
    }
    return Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: AppText(
                  'Spending trends',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: blue.withValues(alpha: .09),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: AppText(
                  selectedMonth == null ? 'All time' : 'Selected month',
                  style: const TextStyle(fontSize: 10, color: blue),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          AppText(
            'Cumulative expenses · ${store.currency}',
            style: const TextStyle(color: muted, fontSize: 11),
          ),
          const SizedBox(height: 22),
          Row(
            textDirection: TextDirection.ltr,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 54,
                height: 130,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppText(
                      money((values.last * 100).round()),
                      style: const TextStyle(fontSize: 9, color: muted),
                    ),
                    const AppText(
                      '0',
                      style: TextStyle(fontSize: 9, color: muted),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Semantics(
                  label: tr(
                    context,
                    '$semantics: ${store.currency} ${money((values.last * 100).round())}',
                  ),
                  child: SizedBox(
                    height: 130,
                    child: CustomPaint(painter: _TrendPainter(values)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            textDirection: TextDirection.ltr,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              AppText(
                firstLabel,
                style: const TextStyle(fontSize: 10, color: muted),
              ),
              AppText(
                lastLabel,
                style: const TextStyle(fontSize: 10, color: muted),
              ),
            ],
          ),
          if (values.last == 0)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: AppText(
                'Add expenses to see your spending trend.',
                style: TextStyle(color: muted, fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }
}

class _TrendPainter extends CustomPainter {
  final List<double> values;
  _TrendPainter(this.values);
  @override
  void paint(Canvas canvas, Size size) {
    final grid =
        Paint()
          ..color = const Color(0xFF293444)
          ..strokeWidth = 1;
    for (var i = 0; i < 4; i++) {
      final y = size.height * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final maxValue = math.max(1.0, values.reduce(math.max));
    Offset point(int i) => Offset(
      values.length == 1 ? size.width : i * size.width / (values.length - 1),
      size.height - values[i] / maxValue * (size.height - 12),
    );
    final path = Path()..moveTo(point(0).dx, point(0).dy);
    for (var i = 1; i < values.length; i++) {
      path.lineTo(point(i).dx, point(i).dy);
    }
    final area =
        Path.from(path)
          ..lineTo(size.width, size.height)
          ..lineTo(point(0).dx, size.height)
          ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x3073CBB0), Color(0x0073CBB0)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = blue
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(
      point(values.length - 1),
      5,
      Paint()..color = Colors.white,
    );
    canvas.drawCircle(point(values.length - 1), 3, Paint()..color = blue);
  }

  @override
  bool shouldRepaint(covariant _TrendPainter oldDelegate) => true;
}

class BudgetDistribution extends StatelessWidget {
  final FinanceStore store;
  final DateTime? month;
  const BudgetDistribution({
    super.key,
    required this.store,
    required this.month,
  });

  @override
  Widget build(BuildContext context) {
    final totals = <String, int>{};
    for (final entry in store.forPeriod(month)) {
      if (!entry.income && entry.cents > 0) {
        totals.update(
          entry.category,
          (value) => value + entry.cents,
          ifAbsent: () => entry.cents,
        );
      }
    }
    final items =
        totals.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final amounts = items.map((item) => item.value).toList();
    final total = amounts.fold(0, (a, b) => a + b);
    String percentage(int amount) {
      final percent = amount / total * 100;
      if (percent < .1) return '<0.1%';
      return '${percent.toStringAsFixed(percent == percent.roundToDouble() ? 0 : 1)}%';
    }

    return Surface(
      key: const Key('expense-distribution'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppText(
            'Expense distribution',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          AppText(
            month == null
                ? 'Share of all expenses'
                : 'Share of selected month’s expenses',
            style: const TextStyle(fontSize: 11, color: muted),
          ),
          const SizedBox(height: 22),
          Center(
            child: SizedBox(
              width: 190,
              height: 190,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned.fill(
                    child: ExcludeSemantics(
                      child: CustomPaint(painter: _DonutPainter(amounts)),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(36),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const AppText(
                          'Total expenses',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 11, color: muted),
                        ),
                        const SizedBox(height: 6),
                        FittedBox(
                          child: AppText(
                            money(total),
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        AppText(
                          store.currency,
                          style: const TextStyle(fontSize: 11, color: muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          if (total == 0)
            const AppText(
              'Add an expense to see your distribution.',
              style: TextStyle(fontSize: 12, color: muted),
            ),
          for (var i = 0; i < items.length; i++)
            Padding(
              key: ValueKey('expense-share-${items[i].key}'),
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: chartColors[i % chartColors.length],
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: AppText(
                      items[i].key,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      AppText(
                        percentage(items[i].value),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      AppText(
                        '${store.currency} ${money(items[i].value)}',
                        style: const TextStyle(fontSize: 11, color: muted),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          if (total > 0) ...[
            const SizedBox(height: 12),
            AppText(
              '${store.currency} ${money(total)} spent across categories',
              style: const TextStyle(fontSize: 11, color: muted),
            ),
          ],
        ],
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  final List<int> amounts;
  _DonutPainter(this.amounts);
  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(16);
    final paint =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 26;
    canvas.drawArc(rect, 0, math.pi * 2, false, paint..color = line);
    final total = amounts.fold(0, (a, b) => a + b);
    if (total <= 0) return;
    var start = -math.pi / 2;
    for (var i = 0; i < amounts.length; i++) {
      final sweep = amounts[i] / total * math.pi * 2;
      final gap = math.min(.035, sweep / 5);
      canvas.drawArc(
        rect,
        start + gap / 2,
        sweep - gap,
        false,
        paint..color = chartColors[i % chartColors.length],
      );
      // Small segments retain a readable exact percentage in the legend.
      if (amounts[i] / total >= .07) {
        final label = TextPainter(
          text: TextSpan(
            text: '${(amounts[i] / total * 100).round()}%',
            style: const TextStyle(
              color: Color(0xFF090F18),
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        final angle = start + sweep / 2;
        final center =
            rect.center +
            Offset(math.cos(angle), math.sin(angle)) * (rect.width / 2);
        label.paint(canvas, center - Offset(label.width / 2, label.height / 2));
      }
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) => true;
}
