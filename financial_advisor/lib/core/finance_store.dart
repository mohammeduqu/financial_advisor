import 'dart:convert';
import 'invoice.dart';
import 'legal_acceptance.dart';
import 'recommendation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show StringCharacters;
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

InvoiceModel _invoiceWith(InvoiceModel invoice, {String? currency}) =>
    InvoiceModel(
      merchantName: invoice.merchantName,
      invoiceNumber: invoice.invoiceNumber,
      currency: currency ?? invoice.currency,
      date: invoice.date,
      subtotal: invoice.subtotal,
      tax: invoice.tax,
      discount: invoice.discount,
      total: invoice.total,
      category: invoice.category,
      items: invoice.items,
    );

class Entry {
  final String id, merchant, category, note;
  final int cents;
  final DateTime date;
  final bool income;
  final String? receipt;
  final InvoiceModel? invoice;
  final String? recurringId;
  String? get parentRecurringTransactionId => recurringId;
  final String? recurringScheduleId;
  final DateTime? recurringScheduledDate;
  final bool isProjected;
  final bool recurrenceDisabled;
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
    String? recurringId,
    String? parentRecurringTransactionId,
    this.recurringScheduleId,
    this.recurringScheduledDate,
    this.isProjected = false,
    this.recurrenceDisabled = false,
  }) : recurringId = parentRecurringTransactionId ?? recurringId;

  Entry copyWith({
    String? id,
    String? merchant,
    int? cents,
    DateTime? date,
    String? category,
    bool? income,
    String? note,
    String? parentRecurringTransactionId,
    String? recurringScheduleId,
    DateTime? recurringScheduledDate,
    bool? isProjected,
    bool? recurrenceDisabled,
    InvoiceModel? invoice,
    bool detachRecurring = false,
  }) => Entry(
    id: id ?? this.id,
    merchant: merchant ?? this.merchant,
    cents: cents ?? this.cents,
    date: date ?? this.date,
    category: category ?? this.category,
    income: income ?? this.income,
    note: note ?? this.note,
    receipt: receipt,
    invoice: invoice ?? this.invoice,
    parentRecurringTransactionId:
        detachRecurring ? null : parentRecurringTransactionId ?? recurringId,
    recurringScheduleId:
        detachRecurring
            ? null
            : recurringScheduleId ?? this.recurringScheduleId,
    recurringScheduledDate:
        detachRecurring
            ? null
            : recurringScheduledDate ?? this.recurringScheduledDate,
    isProjected: isProjected ?? this.isProjected,
    recurrenceDisabled:
        detachRecurring ? false : recurrenceDisabled ?? this.recurrenceDisabled,
  );
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
    if (recurringId != null) 'parent_recurring_transaction_id': recurringId,
    if (recurringScheduleId != null)
      'recurring_schedule_id': recurringScheduleId,
    if (recurringScheduledDate != null)
      'recurring_scheduled_date': recurringScheduledDate!.toIso8601String(),
    if (recurrenceDisabled) 'recurrence_disabled': true,
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
    parentRecurringTransactionId:
        j['parent_recurring_transaction_id'] ?? j['recurringId'],
    recurringScheduleId: j['recurring_schedule_id'],
    recurringScheduledDate:
        j['recurring_scheduled_date'] == null
            ? null
            : DateTime.parse(j['recurring_scheduled_date']),
    recurrenceDisabled: j['recurrence_disabled'] ?? false,
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
  monthly('Monthly'),
  yearly('Yearly');

  const RepeatFrequency(this.label);
  final String label;
}

enum RecurringScope { onlyThis, thisAndFuture, all }

class RecurringTransaction {
  final String id, rootId, merchant, category, note;
  final int cents, nextOccurrence, interval, anchorDay;
  final bool income, active;
  final DateTime startDate;
  final DateTime? endDate;
  final RepeatFrequency frequency;

  RecurringTransaction({
    required this.id,
    required this.merchant,
    required this.cents,
    required this.category,
    required this.income,
    required DateTime startDate,
    required this.frequency,
    String? rootId,
    this.note = '',
    this.nextOccurrence = 0,
    this.interval = 1,
    int? anchorDay,
    DateTime? endDate,
    this.active = true,
  }) : rootId = rootId ?? id,
       anchorDay = anchorDay ?? startDate.day,
       startDate = DateTime(startDate.year, startDate.month, startDate.day),
       endDate =
           endDate == null
               ? null
               : DateTime(endDate.year, endDate.month, endDate.day) {
    if (id.isEmpty ||
        this.rootId.isEmpty ||
        merchant.trim().isEmpty ||
        cents <= 0 ||
        interval < 1 ||
        interval > 1000 ||
        this.anchorDay < 1 ||
        this.anchorDay > 31 ||
        nextOccurrence < 0 ||
        startDate.year < 2000 ||
        startDate.year > 9999 ||
        frequency == RepeatFrequency.once ||
        (endDate != null &&
            (endDate.year > 9999 ||
                endDate.year < 2000 ||
                this.endDate!.isBefore(this.startDate)))) {
      throw const FormatException('Invalid recurring transaction');
    }
    // Validate the persisted cursor before assigning any loaded financial data.
    nextDate;
  }

  DateTime get nextDate => dateForOccurrence(nextOccurrence);

  DateTime dateForOccurrence(int occurrence) {
    if (occurrence < 0) throw ArgumentError.value(occurrence);
    if (frequency == RepeatFrequency.monthly ||
        frequency == RepeatFrequency.yearly) {
      final step = interval * (frequency == RepeatFrequency.yearly ? 12 : 1);
      final month = DateTime(
        startDate.year,
        startDate.month + occurrence * step,
      );
      final lastDay = DateTime(month.year, month.month + 1, 0).day;
      return DateTime(month.year, month.month, anchorDay.clamp(1, lastDay));
    }
    // Construct calendar dates rather than adding 24-hour durations across DST.
    return DateTime(
      startDate.year,
      startDate.month,
      startDate.day +
          occurrence * interval * (frequency == RepeatFrequency.weekly ? 7 : 1),
    );
  }

  int firstOccurrenceOnOrAfter(DateTime date) {
    final target = DateTime(date.year, date.month, date.day);
    if (!target.isAfter(startDate)) return 0;
    int estimate;
    if (frequency == RepeatFrequency.monthly ||
        frequency == RepeatFrequency.yearly) {
      final months =
          (target.year - startDate.year) * 12 + target.month - startDate.month;
      estimate =
          months ~/ (interval * (frequency == RepeatFrequency.yearly ? 12 : 1));
    } else {
      final days =
          DateTime.utc(target.year, target.month, target.day)
              .difference(
                DateTime.utc(startDate.year, startDate.month, startDate.day),
              )
              .inDays;
      estimate =
          days ~/ (interval * (frequency == RepeatFrequency.weekly ? 7 : 1));
    }
    while (dateForOccurrence(estimate).isBefore(target)) {
      estimate++;
    }
    return estimate;
  }

  bool includes(DateTime date) =>
      active &&
      !date.isBefore(startDate) &&
      (endDate == null || !date.isAfter(endDate!));

  RecurringTransaction copyWith({
    String? id,
    String? rootId,
    String? merchant,
    int? cents,
    String? category,
    bool? income,
    DateTime? startDate,
    RepeatFrequency? frequency,
    String? note,
    int? nextOccurrence,
    int? interval,
    int? anchorDay,
    DateTime? endDate,
    bool clearEndDate = false,
    bool? active,
  }) => RecurringTransaction(
    id: id ?? this.id,
    rootId: rootId ?? this.rootId,
    merchant: merchant ?? this.merchant,
    cents: cents ?? this.cents,
    category: category ?? this.category,
    income: income ?? this.income,
    startDate: startDate ?? this.startDate,
    frequency: frequency ?? this.frequency,
    note: note ?? this.note,
    nextOccurrence: nextOccurrence ?? this.nextOccurrence,
    interval: interval ?? this.interval,
    anchorDay: anchorDay ?? this.anchorDay,
    endDate: clearEndDate ? null : endDate ?? this.endDate,
    active: active ?? this.active,
  );

  RecurringTransaction withNextOccurrence(int value) => RecurringTransaction(
    id: id,
    rootId: rootId,
    merchant: merchant,
    cents: cents,
    category: category,
    income: income,
    startDate: startDate,
    frequency: frequency,
    note: note,
    nextOccurrence: value,
    interval: interval,
    anchorDay: anchorDay,
    endDate: endDate,
    active: active,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'rootId': rootId,
    'merchant': merchant,
    'cents': cents,
    'category': category,
    'income': income,
    'note': note,
    'startDate': startDate.toIso8601String(),
    'frequency': frequency.name,
    'nextOccurrence': nextOccurrence,
    'interval': interval,
    'anchorDay': anchorDay,
    'endDate': endDate?.toIso8601String(),
    'active': active,
  };

  factory RecurringTransaction.fromJson(Map<String, dynamic> json) =>
      RecurringTransaction(
        id: json['id'],
        rootId: json['rootId'],
        merchant: json['merchant'],
        cents: json['cents'],
        category: json['category'],
        income: json['income'],
        note: json['note'] ?? '',
        startDate: DateTime.parse(json['startDate']),
        frequency: RepeatFrequency.values.byName(json['frequency']),
        nextOccurrence: json['nextOccurrence'] ?? 0,
        interval: json['interval'] ?? 1,
        anchorDay: json['anchorDay'],
        endDate:
            json['endDate'] == null ? null : DateTime.parse(json['endDate']),
        active: json['active'] ?? true,
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
  final Set<String> _deletedRecurringOccurrenceIds = {};
  final Set<String> _deletedRecurringDates = {};
  List<Goal> goals = [];
  Map<String, Map<String, int>> budgets = {};
  bool onboarded = false, demo = false;
  String name = 'Alex', currency = 'SAR', countryCode = 'SA';
  String? error;
  String? languageCode;
  LegalAcceptance? _legalAcceptance;
  LegalAcceptance? get legalAcceptance => _legalAcceptance;
  bool get hasAcceptedCurrentLegal =>
      _legalAcceptance?.version == currentLegalVersion;
  Future<void> _writes = Future.value();
  Future<void>? _clearing;
  Future<void>? _legalWritePending;
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
      final loadedCountry = j['countryCode'] as String? ?? 'SA';
      final validatedCurrency = _validatedCurrency(loadedCurrency);
      final validatedCountry = _validatedCountry(loadedCountry);
      final deletedRecurring = Set<String>.from(
        j['deletedRecurringOccurrenceIds'] as List? ?? const [],
      );
      final deletedDates = Set<String>.from(
        j['deletedRecurringDates'] as List? ?? const [],
      );
      final loadedOnboarded = j['onboarded'] as bool? ?? true;
      final loadedDemo = j['demo'] as bool? ?? false;
      final loadedAcceptance = LegalAcceptance.fromJson(j['legalAcceptance']);
      final savedLanguage = j['language'];
      languageCode =
          savedLanguage == 'en' || savedLanguage == 'ar'
              ? savedLanguage as String
              : null;
      entries = loadedEntries;
      recurringTransactions = loadedRecurring;
      goals = loadedGoals;
      budgets = loadedBudgets;
      name =
          loadedName.trim().isEmpty
              ? 'Alex'
              : loadedName.trim().characters.take(100).toString();
      currency = validatedCurrency;
      countryCode = validatedCountry;
      _deletedRecurringOccurrenceIds
        ..clear()
        ..addAll(deletedRecurring);
      _deletedRecurringDates
        ..clear()
        ..addAll(deletedDates);
      onboarded = loadedOnboarded;
      demo = loadedDemo;
      _legalAcceptance = loadedAcceptance;
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

  static String _validatedName(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed.characters.length > 100) {
      throw ArgumentError('Name must contain between 1 and 100 characters');
    }
    return trimmed;
  }

  static String _validatedCurrency(String value) {
    final normalized = value.trim().toUpperCase();
    if (!RegExp(r'^[A-Z]{3}$').hasMatch(normalized)) {
      throw ArgumentError('Invalid currency code');
    }
    return normalized;
  }

  static String _validatedCountry(String value) {
    final normalized = value.trim().toUpperCase();
    if (!RegExp(r'^[A-Z]{2}$').hasMatch(normalized)) {
      throw ArgumentError('Invalid country code');
    }
    return normalized;
  }

  Future<void> setCurrency(String value) =>
      updateProfile(selectedCurrency: value);
  Future<void> setCountry(String value) =>
      updateProfile(selectedCountry: value);

  Future<void> updateProfile({
    String? userName,
    String? selectedCurrency,
    String? selectedCountry,
  }) {
    final updatedName = _validatedName(userName ?? name);
    final updatedCurrency = _validatedCurrency(selectedCurrency ?? currency);
    final updatedCountry = _validatedCountry(selectedCountry ?? countryCode);
    name = updatedName;
    if (updatedCurrency != currency) {
      entries =
          entries
              .map(
                (entry) =>
                    entry.invoice == null
                        ? entry
                        : entry.copyWith(
                          invoice: _invoiceWith(
                            entry.invoice!,
                            currency: updatedCurrency,
                          ),
                        ),
              )
              .toList();
    }
    currency = updatedCurrency;
    countryCode = updatedCountry;
    return persist();
  }

  Future<void> persist() {
    if (_clearing != null) return _clearing!;
    if (_legalWritePending != null) {
      return _legalWritePending!.then((_) => persist());
    }
    if (error?.startsWith('Saved data') ?? false) {
      notifyListeners();
      return Future.value();
    }
    _validatedName(name);
    final data = jsonEncode(_snapshot());
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

  Map<String, dynamic> _snapshot() => {
    'version': 1,
    'language': languageCode,
    'entries': entries.map((e) => e.toJson()).toList(),
    if (recurringTransactions.isNotEmpty)
      'recurringTransactions':
          recurringTransactions.map((e) => e.toJson()).toList(),
    if (_deletedRecurringOccurrenceIds.isNotEmpty)
      'deletedRecurringOccurrenceIds': _deletedRecurringOccurrenceIds.toList(),
    if (_deletedRecurringDates.isNotEmpty)
      'deletedRecurringDates': _deletedRecurringDates.toList(),
    'goals': goals.map((e) => e.toJson()).toList(),
    'budgets': budgets,
    'name': name,
    'currency': currency,
    'countryCode': countryCode,
    'onboarded': onboarded,
    'demo': demo,
    if (_legalAcceptance != null) 'legalAcceptance': _legalAcceptance!.toJson(),
  };

  void _requireExplicitAcceptance(bool accepted, String language) {
    if (!accepted) {
      throw ArgumentError(
        'Accept the Terms of use and Privacy notice to continue.',
      );
    }
    if (!['en', 'ar'].contains(language)) {
      throw ArgumentError('Unsupported legal language');
    }
    if (_clearing != null || (error?.startsWith('Saved data') ?? false)) {
      throw StateError('Resolve saved data error first');
    }
  }

  Future<void> acceptLegalTerms({
    required bool accepted,
    required String language,
  }) {
    _requireExplicitAcceptance(accepted, language);
    if (!onboarded) throw StateError('Complete profile setup first');
    return _saveLegalAcceptance(language: language);
  }

  Future<void> _saveLegalAcceptance({
    required String language,
    String? initialName,
    String? initialCurrency,
    String? initialCountry,
    bool useDemo = false,
  }) {
    if (_legalWritePending != null) return _legalWritePending!;
    final acceptance = LegalAcceptance(
      version: currentLegalVersion,
      acceptedAt: DateTime.now().toUtc(),
      language: language,
    );
    final task = _writes.then((_) async {
      if (_clearing != null || (error?.startsWith('Saved data') ?? false)) {
        return;
      }
      final data = _snapshot();
      FinanceStore? example;
      if (initialName != null) {
        data.addAll({
          'name': initialName,
          'currency': initialCurrency,
          'countryCode': initialCountry,
          'onboarded': true,
        });
        if (useDemo) {
          example = FinanceStore(prefs)..seed();
          data.addAll({
            'entries': example.entries.map((entry) => entry.toJson()).toList(),
            'goals': example.goals.map((goal) => goal.toJson()).toList(),
            'budgets': example.budgets,
            'demo': true,
          });
        }
      }
      data['legalAcceptance'] = acceptance.toJson();
      final previousRaw = prefs.getString('numo_v1');
      final encoded = jsonEncode(data);
      try {
        final ok = await prefs.setString('numo_v1', encoded);
        if (!ok) throw StateError('save failed');
        _legalAcceptance = acceptance;
        if (initialName != null) {
          name = initialName;
          currency = initialCurrency!;
          countryCode = initialCountry!;
          onboarded = true;
          if (example != null) {
            entries = example.entries;
            goals = example.goals;
            budgets = example.budgets;
            demo = true;
          }
        }
        error = null;
      } catch (_) {
        // SharedPreferences can update its in-memory cache before a platform
        // write fails. A failed checkbox submission must not survive as accepted.
        try {
          await prefs.reload();
        } catch (_) {}
        if (prefs.getString('numo_v1') == encoded) {
          try {
            if (previousRaw == null) {
              await prefs.remove('numo_v1');
            } else {
              await prefs.setString('numo_v1', previousRaw);
            }
          } catch (_) {}
        }
        error = 'Changes could not be saved. Keep the app open and tap Retry.';
      }
      notifyListeners();
    });
    _writes = task;
    _legalWritePending = task.whenComplete(() => _legalWritePending = null);
    return _legalWritePending!;
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

  // A missing period always means the complete recorded history. Projected
  // recurring occurrences are previews and are never included in these totals.
  Iterable<Entry> _entriesForPeriod(DateTime? month) => entries.where(
    (e) =>
        !e.isProjected &&
        (month == null ||
            (e.date.year == month.year && e.date.month == month.month)),
  );
  List<Entry> forPeriod(DateTime? month) =>
      _entriesForPeriod(month).toList()
        ..sort((a, b) => b.date.compareTo(a.date));
  List<Entry> forMonth(DateTime month) => forPeriod(month);
  int incomeFor(DateTime? month) => _entriesForPeriod(
    month,
  ).where((e) => e.income).fold(0, (a, b) => a + b.cents);
  int expensesFor(DateTime? month) => _entriesForPeriod(
    month,
  ).where((e) => !e.income).fold(0, (a, b) => a + b.cents);
  int categorySpent(DateTime? month, String category) =>
      _entriesForPeriod(month)
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
      // Overall limits are read-only in the app, including when copying.
      if (categories.contains(entry.key) && !target.containsKey(entry.key)) {
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
    if (e.id.isEmpty || e.cents <= 0 || e.merchant.trim().isEmpty) {
      throw ArgumentError('Invalid entry');
    }
    final previous = entries.where((entry) => entry.id == e.id).firstOrNull;
    e = e.copyWith(
      parentRecurringTransactionId:
          e.parentRecurringTransactionId ??
          previous?.parentRecurringTransactionId,
      recurringScheduleId:
          e.recurringScheduleId ?? previous?.recurringScheduleId,
      recurringScheduledDate:
          e.recurringScheduledDate ??
          previous?.recurringScheduledDate ??
          ((e.parentRecurringTransactionId ??
                      previous?.parentRecurringTransactionId) ==
                  null
              ? null
              : previous?.date),
      isProjected: false,
    );
    entries.removeWhere((v) => v.id == e.id);
    entries.add(e);
    return persist();
  }

  RecurringTransaction? recurringForEntry(Entry entry) {
    final schedule = entry.recurringScheduleId;
    if (schedule != null) {
      final exact =
          recurringTransactions
              .where((rule) => rule.id == schedule)
              .firstOrNull;
      if (exact != null) return exact;
    }
    final parent = entry.parentRecurringTransactionId;
    return recurringTransactions
            .where((rule) => rule.id == parent)
            .firstOrNull ??
        recurringTransactions
            .where((rule) => rule.rootId == parent)
            .firstOrNull;
  }

  Entry _occurrence(
    RecurringTransaction rule,
    int index, {
    bool projected = false,
  }) => Entry(
    id: 'recurring:${rule.id}:$index',
    merchant: rule.merchant,
    cents: rule.cents,
    date: rule.dateForOccurrence(index),
    category: rule.category,
    income: rule.income,
    note: rule.note,
    parentRecurringTransactionId: rule.rootId,
    recurringScheduleId: rule.id,
    recurringScheduledDate: rule.dateForOccurrence(index),
    isProjected: projected,
  );

  List<Entry> entriesForRange(
    DateTime start,
    DateTime end, {
    bool includeProjected = true,
    DateTime? now,
  }) {
    final first = DateTime(start.year, start.month, start.day);
    final last = DateTime(end.year, end.month, end.day);
    if (last.isBefore(first)) throw ArgumentError('Invalid date range');
    final result =
        entries.where((entry) {
          final date = DateTime(
            entry.date.year,
            entry.date.month,
            entry.date.day,
          );
          return !date.isBefore(first) && !date.isAfter(last);
        }).toList();
    if (includeProjected) {
      final ids = entries.map((entry) => entry.id).toSet();
      final clock = now ?? DateTime.now();
      final today = DateTime(clock.year, clock.month, clock.day);
      final from = first.isBefore(today) ? today : first;
      for (final rule in recurringTransactions.where((rule) => rule.active)) {
        var index = rule.firstOccurrenceOnOrAfter(from);
        if (index < rule.nextOccurrence) index = rule.nextOccurrence;
        var due = rule.dateForOccurrence(index);
        while (!due.isAfter(last) && rule.includes(due)) {
          final entry = _occurrence(rule, index, projected: true);
          if (!ids.contains(entry.id) && !_isDeletedOccurrence(entry)) {
            result.add(entry);
          }
          index++;
          due = rule.dateForOccurrence(index);
        }
      }
    }
    result.sort((a, b) {
      final date = b.date.compareTo(a.date);
      return date == 0 ? a.id.compareTo(b.id) : date;
    });
    return result;
  }

  Future<void> saveScheduledEntry(
    Entry entry,
    RepeatFrequency frequency, {
    int interval = 1,
    DateTime? endDate,
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
      if (entry.parentRecurringTransactionId != null) {
        throw ArgumentError(
          'Use recurring edit scope for an existing occurrence',
        );
      }
      if (endDate != null &&
          DateTime(endDate.year, endDate.month, endDate.day).isBefore(
            DateTime(entry.date.year, entry.date.month, entry.date.day),
          )) {
        throw ArgumentError('End date must not precede start date');
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
          interval: interval,
          endDate: endDate,
        ),
      );
      final previous =
          entries.where((saved) => saved.id == entry.id).firstOrNull;
      if (previous != null || entry.invoice != null || entry.receipt != null) {
        entries.removeWhere((saved) => saved.id == entry.id);
        final rule = recurringTransactions.last;
        final first = _occurrence(rule, 0);
        entries.add(
          Entry(
            id: first.id,
            merchant: entry.merchant,
            cents: entry.cents,
            date: entry.date,
            category: entry.category,
            income: entry.income,
            note: entry.note,
            receipt: entry.receipt ?? previous?.receipt,
            invoice: entry.invoice ?? previous?.invoice,
            parentRecurringTransactionId: rule.rootId,
            recurringScheduleId: rule.id,
            recurringScheduledDate: first.date,
          ),
        );
      }
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
      if (!rule.active) continue;
      var occurrence = rule.nextOccurrence;
      var due = rule.dateForOccurrence(occurrence);
      while (!due.isAfter(today) && rule.includes(due)) {
        final id = 'recurring:${rule.id}:$occurrence';
        if (!_isDeletedOccurrence(_occurrence(rule, occurrence)) &&
            ids.add(id)) {
          entries.add(_occurrence(rule, occurrence));
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
    final rule =
        recurringTransactions.where((rule) => rule.id == id).firstOrNull;
    if (rule != null) {
      recurringTransactions =
          recurringTransactions
              .map(
                (candidate) =>
                    candidate.rootId == rule.rootId
                        ? candidate.copyWith(active: false)
                        : candidate,
              )
              .toList();
    }
    return persist();
  }

  String _rootForEntry(Entry entry) =>
      recurringForEntry(entry)?.rootId ??
      entry.parentRecurringTransactionId ??
      '';

  bool _belongsTo(Entry entry, String root) =>
      entry.parentRecurringTransactionId == root ||
      (entry.parentRecurringTransactionId != null &&
          _rootForEntry(entry) == root);

  DateTime _scheduledDate(Entry entry) =>
      entry.recurringScheduledDate ?? entry.date;

  String _deletedDateKey(Entry entry) {
    final date = _scheduledDate(entry);
    return '${_rootForEntry(entry)}:${date.year}-${date.month}-${date.day}';
  }

  bool _isDeletedOccurrence(Entry entry) =>
      _deletedRecurringOccurrenceIds.contains(entry.id) ||
      _deletedRecurringDates.contains(_deletedDateKey(entry));

  void _rememberDeletedOccurrence(Entry entry) {
    if (entry.parentRecurringTransactionId == null) return;
    _deletedRecurringOccurrenceIds.add(entry.id);
    _deletedRecurringDates.add(_deletedDateKey(entry));
  }

  void _endSeriesFrom(String root, DateTime cutoff) {
    final previousDay = DateTime(cutoff.year, cutoff.month, cutoff.day - 1);
    recurringTransactions =
        recurringTransactions.map((rule) {
          if (rule.rootId != root) return rule;
          if (!rule.startDate.isBefore(cutoff)) {
            return rule.copyWith(active: false);
          }
          if (rule.endDate != null && rule.endDate!.isBefore(cutoff)) {
            return rule;
          }
          return rule.copyWith(endDate: previousDay);
        }).toList();
  }

  String _revisionId(String root) {
    final base = '$root:revision:${newId()}';
    var result = base;
    var suffix = 0;
    while (recurringTransactions.any((rule) => rule.id == result)) {
      result = '$base:${++suffix}';
    }
    return result;
  }

  Future<void> updateRecurringEntry(
    Entry updated, {
    required RecurringScope scope,
    RepeatFrequency? frequency,
    int? interval,
    DateTime? endDate,
    bool clearEndDate = false,
    DateTime? now,
  }) async {
    if (_clearing != null || (error?.startsWith('Saved data') ?? false)) {
      throw StateError('Resolve saved data error first');
    }
    final recorded =
        entries.where((entry) => entry.id == updated.id).firstOrNull;
    final original = recorded ?? updated;
    final rule = recurringForEntry(original) ?? recurringForEntry(updated);
    if (rule == null || scope == RecurringScope.onlyThis) {
      await saveEntry(
        rule != null && frequency != null
            ? updated.copyWith(
              recurrenceDisabled: frequency == RepeatFrequency.once,
            )
            : updated,
      );
      return;
    }
    final selectedFrequency = frequency ?? rule.frequency;
    final selectedInterval = interval ?? rule.interval;
    final selectedEnd = clearEndDate ? null : endDate ?? rule.endDate;
    if (updated.cents <= 0 ||
        updated.merchant.trim().isEmpty ||
        selectedInterval < 1 ||
        selectedInterval > 1000) {
      throw ArgumentError('Invalid recurring transaction');
    }
    final clock = now ?? DateTime.now();
    final today = DateTime(clock.year, clock.month, clock.day);
    final cutoff =
        scope == RecurringScope.all
            ? DateTime(today.year, today.month, today.day + 1)
            : DateTime(
              _scheduledDate(original).year,
              _scheduledDate(original).month,
              _scheduledDate(original).day,
            );
    final root = rule.rootId;
    final dateChanged =
        !DateUtilsCompat.sameDay(
          updated.date,
          original.recurringScheduledDate ?? original.date,
        );
    final anchor =
        scope == RecurringScope.all && !dateChanged
            ? rule.startDate
            : DateTime(updated.date.year, updated.date.month, updated.date.day);
    if (scope == RecurringScope.thisAndFuture && anchor.isBefore(cutoff)) {
      final earlier = entries.where(
        (entry) =>
            _belongsTo(entry, root) && _scheduledDate(entry).isBefore(cutoff),
      );
      if (earlier.any((entry) => !_scheduledDate(entry).isBefore(anchor))) {
        throw ArgumentError(
          'Start date must be after earlier recorded occurrences.',
        );
      }
      for (final prior in recurringTransactions.where(
        (candidate) => candidate.rootId == root && candidate.active,
      )) {
        final boundary =
            prior.endDate != null && prior.endDate!.isBefore(cutoff)
                ? DateTime(
                  prior.endDate!.year,
                  prior.endDate!.month,
                  prior.endDate!.day + 1,
                )
                : cutoff;
        var index = prior.firstOccurrenceOnOrAfter(boundary) - 1;
        while (index >= 0 && _isDeletedOccurrence(_occurrence(prior, index))) {
          index--;
        }
        if (index >= 0 && !prior.dateForOccurrence(index).isBefore(anchor)) {
          throw ArgumentError(
            'Start date must be after earlier recorded occurrences.',
          );
        }
      }
    }
    if (selectedEnd != null && selectedEnd.isBefore(anchor)) {
      throw ArgumentError('End date must not precede start date');
    }
    final replacement =
        selectedFrequency == RepeatFrequency.once
            ? null
            : RecurringTransaction(
              id: _revisionId(root),
              rootId: root,
              merchant: updated.merchant,
              cents: updated.cents,
              category: updated.income ? 'Income' : updated.category,
              income: updated.income,
              note: updated.note,
              startDate: anchor,
              frequency: selectedFrequency,
              interval: selectedInterval,
              anchorDay:
                  !dateChanged && selectedFrequency == rule.frequency
                      ? rule.anchorDay
                      : anchor.day,
              endDate: selectedEnd,
            );
    // Keep posted history before the scope boundary and end superseded schedules.
    // New schedule versions share their original parent id for future scope edits.
    _endSeriesFrom(root, cutoff);
    entries =
        entries
            .where(
              (entry) =>
                  !_belongsTo(entry, root) ||
                  (scope == RecurringScope.all
                      ? entry.date.isBefore(cutoff)
                      : _scheduledDate(entry).isBefore(cutoff)),
            )
            .map((entry) {
              if (scope != RecurringScope.all || !_belongsTo(entry, root)) {
                return entry;
              }
              return entry.copyWith(
                merchant: updated.merchant,
                cents: updated.cents,
                category: updated.income ? 'Income' : updated.category,
                income: updated.income,
                note: updated.note,
                recurrenceDisabled: false,
                invoice:
                    entry.id == original.id ? updated.invoice : entry.invoice,
              );
            })
            .toList();
    if (replacement == null) {
      final retained = entries.indexWhere((entry) => entry.id == original.id);
      final oneTime = updated.copyWith(
        isProjected: false,
        detachRecurring: true,
      );
      if (retained >= 0) {
        entries[retained] = oneTime;
      } else {
        entries.add(oneTime);
      }
    } else {
      final scheduled =
          scope == RecurringScope.all
              ? replacement.withNextOccurrence(
                replacement.firstOccurrenceOnOrAfter(cutoff),
              )
              : replacement;
      recurringTransactions.add(scheduled);
      _postRecurringEntries(clock);
      // A real receipt belongs to its original occurrence only. Keep its metadata
      // on the selected occurrence, including a future-dated occurrence override.
      if ((updated.invoice != null || updated.receipt != null) &&
          !entries.any((entry) => entry.id == original.id)) {
        final first = _occurrence(scheduled, scheduled.nextOccurrence);
        final matching =
            entries
                .where((entry) => entry.recurringScheduleId == scheduled.id)
                .toList()
              ..sort((a, b) => a.date.compareTo(b.date));
        final target = matching.firstOrNull ?? first;
        final withReceipt = Entry(
          id: target.id,
          merchant: target.merchant,
          cents: target.cents,
          date: target.date,
          category: target.category,
          income: target.income,
          note: target.note,
          receipt: updated.receipt,
          invoice: updated.invoice,
          parentRecurringTransactionId: root,
          recurringScheduleId: scheduled.id,
          recurringScheduledDate: target.recurringScheduledDate,
        );
        entries.removeWhere((entry) => entry.id == target.id);
        entries.add(withReceipt);
      }
    }
    await persist();
  }

  Future<void> updateRecurringTemplate(
    RecurringTransaction updated, {
    RepeatFrequency? frequency,
    DateTime? now,
  }) async {
    final original =
        recurringTransactions
            .where((rule) => rule.id == updated.id)
            .firstOrNull;
    if (original == null) throw ArgumentError('Recurring template not found');
    final next = _occurrence(
      original,
      original.nextOccurrence,
      projected: true,
    );
    await updateRecurringEntry(
      next.copyWith(
        merchant: updated.merchant,
        cents: updated.cents,
        date: updated.startDate,
        category: updated.category,
        income: updated.income,
        note: updated.note,
      ),
      scope: RecurringScope.thisAndFuture,
      frequency: frequency ?? updated.frequency,
      interval: updated.interval,
      endDate: updated.endDate,
      clearEndDate: updated.endDate == null,
      now: now,
    );
  }

  Future<void> deleteRecurringEntry(
    Entry entry, {
    required RecurringScope scope,
    DateTime? now,
  }) {
    if (scope == RecurringScope.onlyThis ||
        entry.parentRecurringTransactionId == null) {
      _rememberDeletedOccurrence(entry);
      return deleteEntry(entry.id);
    }
    final root = _rootForEntry(entry);
    if (scope == RecurringScope.all) {
      entries.removeWhere((candidate) => _belongsTo(candidate, root));
      recurringTransactions.removeWhere((rule) => rule.rootId == root);
    } else {
      final cutoff = _scheduledDate(entry);
      _endSeriesFrom(root, cutoff);
      entries.removeWhere(
        (candidate) =>
            _belongsTo(candidate, root) &&
            !_scheduledDate(candidate).isBefore(cutoff),
      );
    }
    return persist();
  }

  Future<void> deleteRecurringTemplate(
    String id, {
    required RecurringScope scope,
    DateTime? now,
  }) {
    final rule =
        recurringTransactions
            .where((candidate) => candidate.id == id)
            .firstOrNull;
    if (rule == null) return Future.value();
    if (scope == RecurringScope.onlyThis) {
      throw ArgumentError('Choose a template deletion scope');
    }
    final root = rule.rootId;
    if (scope == RecurringScope.all) {
      entries.removeWhere((entry) => _belongsTo(entry, root));
      recurringTransactions.removeWhere(
        (candidate) => candidate.rootId == root,
      );
    } else {
      final clock = now ?? DateTime.now();
      final today = DateTime(clock.year, clock.month, clock.day);
      entries.removeWhere(
        (entry) =>
            _belongsTo(entry, root) &&
            DateTime(
              entry.date.year,
              entry.date.month,
              entry.date.day,
            ).isAfter(today),
      );
      recurringTransactions =
          recurringTransactions
              .map(
                (candidate) =>
                    candidate.rootId == root
                        ? candidate.copyWith(active: false)
                        : candidate,
              )
              .toList();
    }
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
      date:
          previous?.parentRecurringTransactionId != null
              ? previous!.date
              : invoice.date!,
      category: invoice.category,
      note: note,
      receipt: receipt,
      invoice: invoice,
      parentRecurringTransactionId: previous?.parentRecurringTransactionId,
      recurringScheduleId: previous?.recurringScheduleId,
      recurringScheduledDate: previous?.recurringScheduledDate,
      recurrenceDisabled: previous?.recurrenceDisabled ?? false,
    );
    await saveEntry(entry);
    if (error != null && entries.any((e) => e.id == id)) {
      // A failed preference write must not appear as a successfully added expense.
      entries.removeWhere((e) => e.id == id);
      if (previous != null) entries.add(previous);
      notifyListeners();
    }
  }

  Future<void> deleteEntry(String id) {
    final previous = entries.where((entry) => entry.id == id).firstOrNull;
    if (previous != null) _rememberDeletedOccurrence(previous);
    if (previous?.parentRecurringTransactionId != null ||
        recurringTransactions.any(
          (rule) => id.startsWith('recurring:${rule.id}:'),
        )) {
      _deletedRecurringOccurrenceIds.add(id);
    }
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
    String selectedCountry = 'SA',
    bool acceptedLegal = false,
    String legalLanguage = 'en',
  }) async {
    final validatedName = userName.trim();
    if (validatedName.isEmpty || validatedName.characters.length >= 100) {
      throw ArgumentError('Name must contain between 1 and 99 characters');
    }
    final validatedCurrency = _validatedCurrency(selectedCurrency);
    final validatedCountry = _validatedCountry(selectedCountry);
    _requireExplicitAcceptance(acceptedLegal, legalLanguage);
    await _saveLegalAcceptance(
      language: legalLanguage,
      initialName: validatedName,
      initialCurrency: validatedCurrency,
      initialCountry: validatedCountry,
      useDemo: useDemo,
    );
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
    _deletedRecurringOccurrenceIds.clear();
    _deletedRecurringDates.clear();
    goals = [];
    budgets = {};
    languageCode = null;
    name = 'Alex';
    currency = 'SAR';
    countryCode = 'SA';
    onboarded = false;
    _legalAcceptance = null;
    demo = false;
    error = null;
    notifyListeners();
  }
}

class DateUtilsCompat {
  static bool sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
