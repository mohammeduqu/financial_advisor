import 'dart:async';
import 'package:flutter/widgets.dart';
import '../core/finance_store.dart';

/// Reconciles scheduled entries on launch, resume and while the app stays open.
class RecurringEntryScheduler extends StatefulWidget {
  final FinanceStore store;
  final Widget child;
  const RecurringEntryScheduler({
    super.key,
    required this.store,
    required this.child,
  });

  @override
  State<RecurringEntryScheduler> createState() =>
      _RecurringEntrySchedulerState();
}

class _RecurringEntrySchedulerState extends State<RecurringEntryScheduler>
    with WidgetsBindingObserver {
  Timer? _timer;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startTimer();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_catchUp());
    });
  }

  Future<void> _catchUp() async {
    if (!mounted || _running) return;
    _running = true;
    try {
      await widget.store.processRecurringEntries();
    } finally {
      _running = false;
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      unawaited(_catchUp());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_catchUp());
      _startTimer();
    } else {
      _timer?.cancel();
    }
  }

  @override
  void didUpdateWidget(covariant RecurringEntryScheduler oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_catchUp());
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
