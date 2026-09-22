import 'dart:convert';
import 'invoice.dart';
import 'recommendation.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

const categories = invoiceCategories;
String money(int cents) => NumberFormat('#,##0.00').format(cents / 100);
int? parseMoney(String value) {
  var input = value.trim().replaceAll('٫', '.').replaceAll('٬', ',');
  const arabicDigits = '٠١٢٣٤٥٦٧٨٩';
  const persianDigits = '۰۱۲۳۴۵۶۷۸۹';
  for (var i = 0; i < 10; i++) {
    input = input
        .replaceAll(arabicDigits[i], '$i')
        .replaceAll(persianDigits[i], '$i');
  }
  if (!RegExp(
    r'^(?:\d+|\d{1,3}(?:,\d{3})+)(?:\.\d{1,2})?'
    r'$',
  ).hasMatch(input)) {
    return null;
  }
  final text = input.replaceAll(',', '');
  if (!RegExp(r'^\d{1,9}(\.\d{1,2})?$').hasMatch(text)) return null;
  final parts = text.split('.');
  final result =
      int.parse(parts[0]) * 100 +
      (parts.length == 2 ? int.parse(parts[1].padRight(2, '0')) : 0);
  return result > 0 ? result : null;
}

String monthKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}';
String newId() => DateTime.now().microsecondsSinceEpoch.toString();

class Entry {
  final String id, merchant, category, note;
  final int cents;
  final DateTime date;
  final bool income;
  final String? receipt;
  final InvoiceModel? invoice;
  final String? recurringId;
  const Entry({
    required this.id,
    required this.merchant,
    required this.cents,
    required this.date,
    required this.category,
    this.income = false,
    this.note = '',
    this.receipt,
    this.invoice,
    this.recurringId,
  });
  Map<String, dynamic> toJson() => {
    'id': id,
    'merchant': merchant,
    'cents': cents,
    'date': date.toIso8601String(),
    'category': category,
    'income': income,
    'note': note,
    'receipt': receipt,
    if (invoice != null) 'invoice': invoice!.toJson(),
    if (recurringId != null) 'recurringId': recurringId,
  };
  factory Entry.fromJson(Map<String, dynamic> j) => Entry(
    id: j['id'],
    merchant: j['merchant'],
    cents: j['cents'],
    date: DateTime.parse(j['date']),
    category: j['category'],
    income: j['income'] ?? false,
    note: j['note'] ?? '',
    receipt: j['receipt'],
    recurringId: j['recurringId'],
    invoice:
        j['invoice'] is Map<String, dynamic>
            ? InvoiceModel.fromJson(j['invoice'])
            : null,
  );
}

enum RepeatFrequency {
  once('One time'),
  daily('Daily'),
  weekly('Weekly'),
  monthly('Monthly');

  const RepeatFrequency(this.label);
  final String label;
}

class RecurringTransaction {
  final String id, merchant, category, note;
  final int cents, nextOccurrence;
  final bool income;
  final DateTime startDate;
  final RepeatFrequency frequency;

  RecurringTransaction({
    required this.id,
    required this.merchant,
    required this.cents,
    required this.category,
    required this.income,
    required DateTime startDate,
    required this.frequency,
    this.note = '',
    this.nextOccurrence = 0,
  }) : startDate = DateTime(startDate.year, startDate.month, startDate.day) {
    if (id.isEmpty ||
        merchant.trim().isEmpty ||
        cents <= 0 ||
        nextOccurrence < 0 ||
        startDate.year < 2000 ||
        startDate.year > 9999 ||
        frequency == RepeatFrequency.once) {
      throw const FormatException('Invalid recurring transaction');
    }
    // Validate the persisted cursor before assigning any loaded financial data.
    nextDate;
  }

  DateTime get nextDate => dateForOccurrence(nextOccurrence);

  DateTime dateForOccurrence(int occurrence) {
    if (occurrence < 0) throw ArgumentError.value(occurrence);
    if (frequency == RepeatFrequency.monthly) {
      final month = DateTime(startDate.year, startDate.month + occurrence);
      final lastDay = DateTime(month.year, month.month + 1, 0).day;
      return DateTime(month.year, month.month, startDate.day.clamp(1, lastDay));
    }
    // Construct calendar dates rather than adding 24-hour durations across DST.
    return DateTime(
      startDate.year,
      startDate.month,
      startDate.day +
          occurrence * (frequency == RepeatFrequency.weekly ? 7 : 1),
    );
  }

  RecurringTransaction withNextOccurrence(int value) => RecurringTransaction(
    id: id,
    merchant: merchant,
    cents: cents,
    category: category,
    income: income,
    startDate: startDate,
    frequency: frequency,
    note: note,
    nextOccurrence: value,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'merchant': merchant,
    'cents': cents,
    'category': category,
    'income': income,
    'note': note,
    'startDate': startDate.toIso8601String(),
    'frequency': frequency.name,
    'nextOccurrence': nextOccurrence,
  };

  factory RecurringTransaction.fromJson(Map<String, dynamic> json) =>
      RecurringTransaction(
        id: json['id'],
        merchant: json['merchant'],
        cents: json['cents'],
        category: json['category'],
        income: json['income'],
        note: json['note'] ?? '',
        startDate: DateTime.parse(json['startDate']),
        frequency: RepeatFrequency.values.byName(json['frequency']),
        nextOccurrence: json['nextOccurrence'],
      );
}

class Contribution {
  final String id;
  final int cents;
  final DateTime date;
  Contribution(this.id, this.cents, this.date);
  Map<String, dynamic> toJson() => {
    'id': id,
    'cents': cents,
    'date': date.toIso8601String(),
  };
  factory Contribution.fromJson(Map<String, dynamic> j) =>
      Contribution(j['id'], j['cents'], DateTime.parse(j['date']));
}

class Goal {
  final String id, name;
  final int target;
  final DateTime? deadline;
  final List<Contribution> contributions;
  Goal({
    required this.id,
    required this.name,
    required this.target,
    this.deadline,
    List<Contribution>? contributions,
  }) : contributions = contributions ?? [];
  int get saved => contributions.fold(0, (a, b) => a + b.cents);
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'target': target,
    'deadline': deadline?.toIso8601String(),
    'contributions': contributions.map((e) => e.toJson()).toList(),
  };
  factory Goal.fromJson(Map<String, dynamic> j) => Goal(
    id: j['id'],
    name: j['name'],
    target: j['target'],
    deadline: j['deadline'] == null ? null : DateTime.parse(j['deadline']),
    contributions:
        (j['contributions'] as List)
            .map((v) => Contribution.fromJson(v))
            .toList(),
  );
}

class FinanceStore extends ChangeNotifier {
  final SharedPreferences prefs;
  List<Entry> entries = [];
  List<RecurringTransaction> recurringTransactions = [];
  List<Goal> goals = [];
  Map<String, Map<String, int>> budgets = {};
  bool onboarded = false, demo = false;
  String name = 'Alex', currency = 'SAR';
  String? error;
  String? languageCode;
  Future<void> _writes = Future.value();
  Future<void>? _clearing;
  FinanceStore(this.prefs);
  Future<void> load({DateTime? now}) async {
    final raw = prefs.getString('numo_v1');
    if (raw == null) return;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      if (j['version'] != 1) {
        throw const FormatException('Unsupported data version');
      }
      final loadedEntries =
          (j['entries'] as List).map((v) => Entry.fromJson(v)).toList();
      final loadedRecurring =
          ((j['recurringTransactions'] ?? []) as List)
              .map((v) => RecurringTransaction.fromJson(v))
              .toList();
      final loadedGoals =
          (j['goals'] as List).map((v) => Goal.fromJson(v)).toList();
      final loadedBudgets = (j['budgets'] as Map<String, dynamic>).map(
        (k, v) => MapEntry(k, Map<String, int>.from(v)),
      );
      if (loadedEntries.any(
            (e) => e.cents <= 0 || e.merchant.trim().isEmpty || e.id.isEmpty,
          ) ||
          loadedEntries.map((e) => e.id).toSet().length !=
              loadedEntries.length ||
          loadedRecurring.map((e) => e.id).toSet().length !=
              loadedRecurring.length ||
          loadedGoals.any(
            (g) =>
                g.target <= 0 ||
                g.name.trim().isEmpty ||
                g.contributions.any((c) => c.cents <= 0),
          ) ||
          loadedGoals.map((g) => g.id).toSet().length != loadedGoals.length ||
          loadedBudgets.values.any((b) => b.values.any((v) => v <= 0))) {
        throw const FormatException('Invalid financial records');
      }
      final loadedName = j['name'] as String? ?? 'Alex';
      final loadedCurrency = j['currency'] as String? ?? 'SAR';
      final loadedOnboarded = j['onboarded'] as bool? ?? true;
      final loadedDemo = j['demo'] as bool? ?? false;
      final savedLanguage = j['language'];
      languageCode =
          savedLanguage == 'en' || savedLanguage == 'ar'
              ? savedLanguage as String
              : null;
      entries = loadedEntries;
      recurringTransactions = loadedRecurring;
      goals = loadedGoals;
      budgets = loadedBudgets;
      name = loadedName;
      currency = loadedCurrency;
      onboarded = loadedOnboarded;
      demo = loadedDemo;
      error = null;
    } catch (_) {
      error =
          'Saved data could not be read. It has not been overwritten. Restart or clear saved data from Profile.';
      return;
    }
    await processRecurringEntries(now: now);
  }

  Future<void> setLanguage(String? code) {
    if (code != null && code != 'en' && code != 'ar') {
      throw ArgumentError('Unsupported language');
    }
    languageCode = code;
    return persist();
  }

  Future<void> persist() {
    if (_clearing != null) return _clearing!;
    if (error?.startsWith('Saved data') ?? false) {
      notifyListeners();
      return Future.value();
    }
    final data = jsonEncode({
      'version': 1,
      'language': languageCode,
      'entries': entries.map((e) => e.toJson()).toList(),
      if (recurringTransactions.isNotEmpty)
        'recurringTransactions':
            recurringTransactions.map((e) => e.toJson()).toList(),
      'goals': goals.map((e) => e.toJson()).toList(),
      'budgets': budgets,
      'name': name,
      'currency': currency,
      'onboarded': onboarded,
      'demo': demo,
    });
    notifyListeners();
    _writes = _writes.then((_) async {
      try {
        final ok = await prefs.setString('numo_v1', data);
        if (!ok) throw StateError('save failed');
        error = null;
      } catch (_) {
        error = 'Changes could not be saved. Keep the app open and tap Retry.';
      }
      notifyListeners();
    });
    return _writes;
  }

  ({int current, int previous, int days, bool partial}) spendingComparison(
    DateTime month, {
    DateTime? now,
  }) {
    now ??= DateTime.now();
    final previous = DateTime(month.year, month.month - 1);
    final partial = monthKey(month) == monthKey(now);
    final currentDays = DateTime(month.year, month.month + 1, 0).day;
    final previousDays = DateTime(previous.year, previous.month + 1, 0).day;
    final days = partial ? now.day.clamp(1, previousDays) : currentDays;
    int total(DateTime m, int lastDay) => forMonth(m)
        .where((e) => !e.income && e.date.day <= lastDay)
        .fold(0, (a, b) => a + b.cents);
    return (
      current: total(month, days),
      previous: total(previous, partial ? days : previousDays),
      days: days,
      partial: partial,
    );
  }

  List<Entry> forMonth(DateTime month) =>
      entries.where((e) => monthKey(e.date) == monthKey(month)).toList()
        ..sort((a, b) => b.date.compareTo(a.date));
  int incomeFor(DateTime month) =>
      forMonth(month).where((e) => e.income).fold(0, (a, b) => a + b.cents);
  int expensesFor(DateTime month) =>
      forMonth(month).where((e) => !e.income).fold(0, (a, b) => a + b.cents);
  int categorySpent(DateTime month, String category) => forMonth(month)
      .where((e) => !e.income && e.category == category)
      .fold(0, (a, b) => a + b.cents);
  int budgetFor(DateTime month, [String category = 'Overall']) =>
      budgets[monthKey(month)]?[category] ?? 0;
  Future<void> setBudget(DateTime month, String category, int cents) {
    if (cents < 0 ||
        (category != 'Overall' && !categories.contains(category))) {
      throw ArgumentError('Invalid budget');
    }
    if (cents == 0) {
      budgets[monthKey(month)]?.remove(category);
    } else {
      budgets.putIfAbsent(monthKey(month), () => {})[category] = cents;
    }
    return persist();
  }

  Future<int> copyPreviousBudgets(DateTime month) async {
    final previous = budgets[monthKey(DateTime(month.year, month.month - 1))];
    if (previous == null || previous.isEmpty) return 0;
    final target = budgets.putIfAbsent(monthKey(month), () => {});
    var added = 0;
    for (final entry in previous.entries) {
      if (!target.containsKey(entry.key)) {
        target[entry.key] = entry.value;
        added++;
      }
    }
    if (added > 0) await persist();
    return added;
  }

  bool isDuplicate(Entry value) => entries.any(
    (e) =>
        e.id != value.id &&
        ((value.receipt != null && e.receipt == value.receipt) ||
            (e.merchant.toLowerCase() == value.merchant.toLowerCase() &&
                e.cents == value.cents &&
                DateUtilsCompat.sameDay(e.date, value.date) &&
                e.income == value.income)),
  );
  Future<void> saveEntry(Entry e) {
    if (e.cents <= 0 || e.merchant.trim().isEmpty) {
      throw ArgumentError('Invalid entry');
    }
    entries.removeWhere((v) => v.id == e.id);
    entries.add(e);
    return persist();
  }

  Future<void> saveScheduledEntry(
    Entry entry,
    RepeatFrequency frequency, {
    DateTime? now,
  }) async {
    if (_clearing != null || (error?.startsWith('Saved data') ?? false)) {
      throw StateError('Resolve saved data error first');
    }
    if (frequency == RepeatFrequency.once) {
      await saveEntry(entry);
      return;
    }
    // Reusing a form submission ID must not reset an existing rule's cursor.
    if (!recurringTransactions.any((rule) => rule.id == entry.id)) {
      if (entries.any((saved) => saved.id == entry.id)) {
        throw ArgumentError('Only new entries can start a recurring schedule');
      }
      recurringTransactions.add(
        RecurringTransaction(
          id: entry.id,
          merchant: entry.merchant,
          cents: entry.cents,
          category: entry.category,
          income: entry.income,
          note: entry.note,
          startDate: entry.date,
          frequency: frequency,
        ),
      );
    }
    _postRecurringEntries(now ?? DateTime.now());
    // One snapshot holds both the posted records and their advanced cursors.
    await persist();
  }

  Future<int> processRecurringEntries({DateTime? now}) async {
    if (_clearing != null || (error?.startsWith('Saved data') ?? false)) {
      return 0;
    }
    final result = _postRecurringEntries(now ?? DateTime.now());
    if (result.changed || error != null) await persist();
    return result.added;
  }

  ({int added, bool changed}) _postRecurringEntries(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final ids = entries.map((entry) => entry.id).toSet();
    var added = 0;
    var changed = false;
    // No asynchronous work happens until all cursors and entries are updated.
    // Another processor therefore sees the new cursors, even during a write.
    for (var i = 0; i < recurringTransactions.length; i++) {
      final rule = recurringTransactions[i];
      var occurrence = rule.nextOccurrence;
      var due = rule.dateForOccurrence(occurrence);
      while (!due.isAfter(today)) {
        final id = 'recurring:${rule.id}:$occurrence';
        if (ids.add(id)) {
          entries.add(
            Entry(
              id: id,
              merchant: rule.merchant,
              cents: rule.cents,
              date: due,
              category: rule.category,
              income: rule.income,
              note: rule.note,
              recurringId: rule.id,
            ),
          );
          added++;
        }
        occurrence++;
        due = rule.dateForOccurrence(occurrence);
      }
      if (occurrence != rule.nextOccurrence) {
        recurringTransactions[i] = rule.withNextOccurrence(occurrence);
        changed = true;
      }
    }
    return (added: added, changed: changed);
  }

  Future<void> stopRecurringTransaction(String id) {
    if (_clearing != null) return _clearing!;
    recurringTransactions.removeWhere((rule) => rule.id == id);
    return persist();
  }

  Future<void> saveInvoice(
    InvoiceModel invoice, {
    required String id,
    String? receipt,
    String note = '',
  }) async {
    final now = DateTime.now();
    bool validNumber(double? value, {bool positive = false}) =>
        value == null ||
        (value.isFinite &&
            value >= 0 &&
            value < 1000000000 &&
            (!positive || value > 0));
    if (id.isEmpty ||
        invoice.merchantName?.trim().isNotEmpty != true ||
        invoice.totalCents == null ||
        invoice.date == null ||
        invoice.date!.isBefore(DateTime(2000)) ||
        invoice.date!.isAfter(
          DateTime(now.year, now.month, now.day, 23, 59, 59, 999),
        ) ||
        invoice.currency?.toUpperCase() != currency.toUpperCase() ||
        !categories.contains(invoice.category) ||
        ![invoice.subtotal, invoice.tax, invoice.discount].every(validNumber) ||
        invoice.items.length > 200 ||
        invoice.items.any(
          (i) =>
              i.name?.trim().isNotEmpty != true ||
              !categories.contains(i.category) ||
              !validNumber(i.quantity, positive: true) ||
              !validNumber(i.unitPrice) ||
              !validNumber(i.totalPrice),
        )) {
      throw ArgumentError('Invalid invoice');
    }
    if (error?.startsWith('Saved data') ?? false) {
      throw StateError('Resolve saved data error first');
    }
    final previous = entries.where((e) => e.id == id).firstOrNull;
    final entry = Entry(
      id: id,
      merchant: invoice.merchantName!.trim(),
      cents: invoice.totalCents!,
      date: invoice.date!,
      category: invoice.category,
      note: note,
      receipt: receipt,
      invoice: invoice,
    );
    await saveEntry(entry);
    if (error != null && entries.any((e) => identical(e, entry))) {
      // A failed preference write must not appear as a successfully added expense.
      entries.removeWhere((e) => identical(e, entry));
      if (previous != null) entries.add(previous);
      notifyListeners();
    }
  }

  Future<void> deleteEntry(String id) {
    entries.removeWhere((e) => e.id == id);
    return persist();
  }

  Future<void> saveGoal(Goal g) {
    if (g.target <= 0 ||
        g.name.trim().isEmpty ||
        g.contributions.any((c) => c.cents <= 0)) {
      throw ArgumentError('Invalid goal');
    }
    final index = goals.indexWhere((e) => e.id == g.id);
    if (index < 0) {
      goals.add(g);
    } else {
      goals[index] = g;
    }
    return persist();
  }

  Future<void> contribute(Goal g, int cents) =>
      saveContribution(g.id, Contribution(newId(), cents, DateTime.now()));

  Future<void> saveContribution(String goalId, Contribution contribution) {
    if (contribution.cents <= 0) throw ArgumentError('Invalid contribution');
    final goal = goals.firstWhere((g) => g.id == goalId);
    final index = goal.contributions.indexWhere((c) => c.id == contribution.id);
    if (index < 0) {
      goal.contributions.add(contribution);
    } else {
      goal.contributions[index] = contribution;
    }
    return persist();
  }

  Future<void> removeContribution(String goalId, String contributionId) {
    goals
        .firstWhere((g) => g.id == goalId)
        .contributions
        .removeWhere((c) => c.id == contributionId);
    return persist();
  }

  Future<void> deleteGoal(String id) {
    goals.removeWhere((g) => g.id == id);
    return persist();
  }

  Future<void> start({
    required String userName,
    required String selectedCurrency,
    required bool useDemo,
  }) async {
    name = userName.trim().isEmpty ? 'Alex' : userName.trim();
    currency = selectedCurrency;
    onboarded = true;
    if (useDemo) seed();
    await persist();
  }

  void seed() {
    demo = true;
    final now = DateTime.now();
    final m = DateTime(now.year, now.month, 1);
    entries = [
      Entry(
        id: 'salary',
        merchant: 'Monthly salary',
        cents: 1200000,
        date: m,
        category: 'Income',
        income: true,
      ),
      Entry(
        id: 'rent',
        merchant: 'Home rent',
        cents: 420000,
        date: m,
        category: 'Housing',
      ),
      Entry(
        id: 'market',
        merchant: 'Palm Market',
        cents: 124500,
        date: m,
        category: 'Food',
      ),
      Entry(
        id: 'transport',
        merchant: 'Transport',
        cents: 55000,
        date: m,
        category: 'Transportation',
      ),
      Entry(
        id: 'utilities',
        merchant: 'Electricity & internet',
        cents: 65000,
        date: m,
        category: 'Utilities',
      ),
      Entry(
        id: 'shopping',
        merchant: 'Everyday essentials',
        cents: 80000,
        date: m,
        category: 'Shopping',
      ),
      Entry(
        id: 'subscriptions',
        merchant: 'Monthly subscriptions',
        cents: 30500,
        date: m,
        category: 'Subscriptions',
      ),
    ];
    budgets = {
      monthKey(m): {
        'Overall': 1000000,
        'Food': 150000,
        'Transportation': 80000,
        'Housing': 450000,
        'Shopping': 100000,
        'Utilities': 100000,
        'Subscriptions': 40000,
      },
    };
    goals = [
      Goal(
        id: 'emergency',
        name: 'Emergency fund',
        target: 3000000,
        deadline: DateTime(now.year + 1, now.month, 1),
        contributions: [Contribution('opening', 900000, m)],
      ),
      Goal(
        id: 'travel',
        name: 'Japan adventure',
        target: 1500000,
        deadline: DateTime(now.year + 1, now.month, 1),
        contributions: [Contribution('opening2', 450000, m)],
      ),
    ];
  }

  Future<void> clear() =>
      _clearing ??= _clearData().whenComplete(() {
        _clearing = null;
      });

  Future<void> _clearData() async {
    await _writes;
    try {
      await RecommendationHistory(prefs).clear();
      if (!await prefs.remove('numo_v1')) {
        throw StateError('clear failed');
      }
    } catch (_) {
      error = 'Saved data could not be cleared. Try clearing it again.';
      notifyListeners();
      return;
    }
    entries = [];
    recurringTransactions = [];
    goals = [];
    budgets = {};
    languageCode = null;
    onboarded = false;
    demo = false;
    error = null;
    notifyListeners();
  }
}

class DateUtilsCompat {
  static bool sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
