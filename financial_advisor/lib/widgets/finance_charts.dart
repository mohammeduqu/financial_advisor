import '../l10n/app_language.dart';
import 'dart:math' as math;
import 'package:flutter/material.dart';
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
  final DateTime month;
  const SpendingTrend({super.key, required this.store, required this.month});
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final days =
        monthKey(now) == monthKey(month)
            ? now.day
            : DateTime(month.year, month.month + 1, 0).day;
    final values = List<double>.filled(days, 0);
    for (final entry in store
        .forMonth(month)
        .where((e) => !e.income && e.date.day <= days)) {
      values[entry.date.day - 1] += entry.cents / 100;
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
                child: const AppText(
                  'Selected month',
                  style: TextStyle(fontSize: 10, color: blue),
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
                    'Cumulative spending over $days days: ${store.currency} ${money((values.last * 100).round())}',
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
              const AppText(
                'Day 1',
                style: TextStyle(fontSize: 10, color: muted),
              ),
              AppText(
                'Day $days',
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
  final DateTime month;
  const BudgetDistribution({
    super.key,
    required this.store,
    required this.month,
  });
  @override
  Widget build(BuildContext context) {
    final items =
        categories.where((c) => store.budgetFor(month, c) > 0).toList()..sort(
          (a, b) =>
              store.budgetFor(month, b).compareTo(store.budgetFor(month, a)),
        );
    final labels = items.take(3).toList();
    final amounts = labels.map((c) => store.budgetFor(month, c)).toList();
    if (items.length > 3) {
      labels.add('Other categories');
      amounts.add(
        items.skip(3).fold(0, (v, c) => v + store.budgetFor(month, c)),
      );
    }
    final total = amounts.fold(0, (a, b) => a + b);
    return Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppText(
            'Budget distribution',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          const AppText(
            'Your category allocations',
            style: TextStyle(fontSize: 11, color: muted),
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              SizedBox(
                width: 116,
                height: 116,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned.fill(
                      child: ExcludeSemantics(
                        child: CustomPaint(painter: _DonutPainter(amounts)),
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AppText(
                          '${items.length}',
                          style: const TextStyle(
                            fontSize: 27,
                            fontWeight: FontWeight.w700,
                            color: ink,
                          ),
                        ),
                        const AppText(
                          'categories',
                          style: TextStyle(fontSize: 10, color: muted),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 22),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (total == 0)
                      const AppText(
                        'Set category budgets in Plan to see your allocation.',
                        style: TextStyle(fontSize: 12, color: muted),
                      ),
                    for (var i = 0; i < labels.length; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Row(
                          children: [
                            Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                color: chartColors[i],
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 7),
                            Expanded(
                              child: AppText(
                                labels[i],
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: muted,
                                ),
                              ),
                            ),
                            AppText(
                              '${(amounts[i] / total * 100).round()}%',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          AppText(
            '${store.currency} ${money(total)} allocated across categories',
            style: const TextStyle(fontSize: 11, color: muted),
          ),
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
    final rect = (Offset.zero & size).deflate(9);
    final paint =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 12
          ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, math.pi * 2, false, paint..color = line);
    final total = amounts.fold(0, (a, b) => a + b);
    var start = -math.pi / 2;
    for (var i = 0; i < amounts.length; i++) {
      final sweep = amounts[i] / total * math.pi * 2;
      canvas.drawArc(
        rect,
        start + .035,
        math.max(.001, sweep - .07),
        false,
        paint..color = chartColors[i],
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) => true;
}
