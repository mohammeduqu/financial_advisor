import 'dart:async';
import 'dart:convert';

import 'package:financial_advisor/core/finance_store.dart';
import 'package:financial_advisor/core/legal_acceptance.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Preferences implements SharedPreferences {
  final cached = <String, String>{};
  final durable = <String, String>{};
  int failedWrites = 0;
  int writeCount = 0;
  bool throwOnFailure = false;
  Completer<void>? nextWriteGate;
  Completer<void>? writeStarted;

  _Preferences([Map<String, String> initial = const {}]) {
    cached.addAll(initial);
    durable.addAll(initial);
  }

  @override
  String? getString(String key) => cached[key];

  @override
  Future<bool> setString(String key, String value) async {
    writeCount++;
    cached[key] = value;
    final gate = nextWriteGate;
    nextWriteGate = null;
    writeStarted?.complete();
    writeStarted = null;
    if (gate != null) await gate.future;
    if (failedWrites > 0) {
      failedWrites--;
      if (throwOnFailure) throw StateError('Storage unavailable');
      return false;
    }
    durable[key] = value;
    return true;
  }

  @override
  Future<void> reload() async {
    cached
      ..clear()
      ..addAll(durable);
  }

  @override
  Future<bool> remove(String key) async {
    cached.remove(key);
    durable.remove(key);
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Map<String, dynamic> _profile() => {
  'version': 1,
  'language': 'ar',
  'name': 'Samira',
  'currency': 'USD',
  'countryCode': 'KW',
  'onboarded': true,
  'demo': false,
  'entries': [
    Entry(
      id: 'saved-expense',
      merchant: 'Groceries',
      cents: 4321,
      date: DateTime(2024, 1, 1),
      category: 'Food',
      note: 'Keep this note',
    ).toJson(),
  ],
  'goals': [],
  'budgets': {
    '2024-01': {'Food': 10000},
  },
};

Map<String, dynamic> _acceptance({
  String version = currentLegalVersion,
  String language = 'ar',
  String timestamp = '2026-09-29T09:00:00.000Z',
}) => {'version': version, 'acceptedAt': timestamp, 'language': language};

Future<void> _start(FinanceStore store, {bool accepted = true}) => store.start(
  userName: '  Layla  ',
  selectedCurrency: 'USD',
  selectedCountry: 'AE',
  useDemo: false,
  acceptedLegal: accepted,
  legalLanguage: 'ar',
);

void main() {
  test(
    'onboarding requires explicit acceptance without mutating state',
    () async {
      final prefs = _Preferences();
      final store = FinanceStore(prefs);
      await expectLater(
        store.start(userName: 'Layla', selectedCurrency: 'USD', useDemo: true),
        throwsArgumentError,
      );
      await expectLater(_start(store, accepted: false), throwsArgumentError);
      expect(store.onboarded, isFalse);
      expect(store.legalAcceptance, isNull);
      expect(store.name, 'Alex');
      expect(store.currency, 'SAR');
      expect(store.entries, isEmpty);
      expect(prefs.writeCount, 0);
    },
  );

  test('name and settings validation precede acceptance validation', () async {
    final store = FinanceStore(_Preferences());
    await expectLater(
      store.start(userName: ' ', selectedCurrency: 'USD', useDemo: false),
      throwsA(
        isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          contains('Name'),
        ),
      ),
    );
    await expectLater(
      store.start(
        userName: 'Layla',
        selectedCurrency: 'bad code',
        useDemo: false,
      ),
      throwsA(
        isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          contains('currency'),
        ),
      ),
    );
  });

  test(
    'profile and UTC acceptance unlock together only after durable write',
    () async {
      final prefs = _Preferences();
      final store = FinanceStore(prefs);
      final gate = Completer<void>();
      final started = Completer<void>();
      prefs.nextWriteGate = gate;
      prefs.writeStarted = started;
      final before = DateTime.now().toUtc();
      final save = _start(store);
      await started.future;
      expect(store.onboarded, isFalse);
      expect(store.hasAcceptedCurrentLegal, isFalse);
      expect(store.legalAcceptance, isNull);
      expect(store.name, 'Alex');
      expect(prefs.durable, isEmpty);
      gate.complete();
      await save;
      expect(prefs.writeCount, 1);
      expect(store.onboarded, isTrue);
      expect(store.name, 'Layla');
      expect(store.currency, 'USD');
      expect(store.countryCode, 'AE');
      expect(store.hasAcceptedCurrentLegal, isTrue);
      final agreement = store.legalAcceptance!;
      expect(agreement.acceptedAt.isUtc, isTrue);
      expect(agreement.acceptedAt.isBefore(before), isFalse);
      expect(agreement.language, 'ar');
      expect(agreement.version, currentLegalVersion);
      final raw = jsonDecode(prefs.durable['numo_v1']!);
      expect(raw['legalAcceptance'], agreement.toJson());
      final restored = FinanceStore(prefs);
      await restored.load();
      expect(restored.hasAcceptedCurrentLegal, isTrue);
      expect(restored.legalAcceptance!.toJson(), agreement.toJson());
    },
  );

  for (final throwsOnFailure in [false, true]) {
    test(
      'failed onboarding write ($throwsOnFailure) stays blocked and can retry',
      () async {
        final prefs =
            _Preferences()
              ..failedWrites = 1
              ..throwOnFailure = throwsOnFailure;
        final store = FinanceStore(prefs);
        await _start(store);
        expect(store.onboarded, isFalse);
        expect(store.hasAcceptedCurrentLegal, isFalse);
        expect(store.legalAcceptance, isNull);
        expect(store.name, 'Alex');
        expect(prefs.getString('numo_v1'), isNull);
        expect(prefs.durable, isEmpty);
        expect(store.error, contains('could not be saved'));
        await _start(store);
        expect(store.error, isNull);
        expect(store.onboarded, isTrue);
        expect(store.hasAcceptedCurrentLegal, isTrue);
      },
    );
  }

  final invalidAcceptances = <String, Object?>{
    'missing': null,
    'boolean': true,
    'empty': <String, dynamic>{},
    'old version': _acceptance(version: '2026-09-01.1'),
    'unsupported language': _acceptance(language: 'fr'),
    'invalid timestamp': _acceptance(timestamp: 'yesterday'),
    'local timestamp': _acceptance(timestamp: '2026-09-29T09:00:00'),
    'invalid calendar date': _acceptance(timestamp: '2026-02-30T09:00:00.000Z'),
  };
  for (final invalid in invalidAcceptances.entries) {
    test(
      '${invalid.key} acceptance preserves legacy finances without unlocking',
      () async {
        final profile = _profile();
        if (invalid.value != null) profile['legalAcceptance'] = invalid.value;
        final raw = jsonEncode(profile);
        final prefs = _Preferences({'numo_v1': raw});
        final store = FinanceStore(prefs);
        await store.load();
        expect(store.error, isNull);
        expect(store.onboarded, isTrue);
        expect(store.hasAcceptedCurrentLegal, isFalse);
        expect(store.name, 'Samira');
        expect(store.entries.single.toJson(), profile['entries'][0]);
        expect(store.budgets, profile['budgets']);
        expect(prefs.durable['numo_v1'], raw);
        expect(prefs.writeCount, 0);
      },
    );
  }

  test(
    'existing profile acceptance preserves every financial and profile field',
    () async {
      final profile = _profile();
      final prefs = _Preferences({'numo_v1': jsonEncode(profile)});
      final store = FinanceStore(prefs);
      await store.load();
      expect(
        () => store.acceptLegalTerms(accepted: false, language: 'ar'),
        throwsArgumentError,
      );
      expect(
        () => store.acceptLegalTerms(accepted: true, language: 'fr'),
        throwsArgumentError,
      );
      expect(prefs.writeCount, 0);
      await store.acceptLegalTerms(accepted: true, language: 'en');
      final saved =
          jsonDecode(prefs.durable['numo_v1']!) as Map<String, dynamic>;
      expect(saved.remove('legalAcceptance'), store.legalAcceptance!.toJson());
      expect(saved, profile);
      expect(store.legalAcceptance!.language, 'en');
      expect(store.languageCode, 'ar');
    },
  );

  test(
    'failed upgrade retains stale acceptance and finances, retry replaces it',
    () async {
      final profile =
          _profile()..['legalAcceptance'] = _acceptance(version: 'old');
      final raw = jsonEncode(profile);
      final prefs = _Preferences({'numo_v1': raw})..failedWrites = 1;
      final store = FinanceStore(prefs);
      await store.load();
      await store.acceptLegalTerms(accepted: true, language: 'ar');
      expect(store.onboarded, isTrue);
      expect(store.hasAcceptedCurrentLegal, isFalse);
      expect(store.legalAcceptance!.version, 'old');
      expect(prefs.getString('numo_v1'), raw);
      expect(prefs.durable['numo_v1'], raw);
      expect(store.entries.single.cents, 4321);
      await store.acceptLegalTerms(accepted: true, language: 'ar');
      expect(store.hasAcceptedCurrentLegal, isTrue);
      expect(store.error, isNull);
    },
  );

  test('queued finance write cannot erase successful agreement', () async {
    final prefs = _Preferences({'numo_v1': jsonEncode(_profile())});
    final store = FinanceStore(prefs);
    await store.load();
    final gate = Completer<void>();
    final started = Completer<void>();
    prefs.nextWriteGate = gate;
    prefs.writeStarted = started;
    final legalSave = store.acceptLegalTerms(accepted: true, language: 'ar');
    await started.future;
    final financeSave = store.saveEntry(
      Entry(
        id: 'new-entry',
        merchant: 'Coffee',
        cents: 700,
        date: DateTime(2024, 1, 2),
        category: 'Food',
      ),
    );
    expect(store.hasAcceptedCurrentLegal, isFalse);
    gate.complete();
    await Future.wait([legalSave, financeSave]);
    final restored = FinanceStore(prefs);
    await restored.load();
    expect(restored.hasAcceptedCurrentLegal, isTrue);
    expect(
      restored.entries.map((e) => e.id),
      containsAll(['saved-expense', 'new-entry']),
    );
  });

  test('ordinary profile persistence never implicitly accepts terms', () async {
    final prefs = _Preferences({'numo_v1': jsonEncode(_profile())});
    final store = FinanceStore(prefs);
    await store.load();
    await store.setLanguage('en');
    await store.updateProfile(userName: 'Updated name');
    final restored = FinanceStore(prefs);
    await restored.load();
    expect(restored.name, 'Updated name');
    expect(restored.hasAcceptedCurrentLegal, isFalse);
    expect(restored.legalAcceptance, isNull);
  });

  test('clear removes acceptance and requires fresh onboarding', () async {
    final prefs = _Preferences();
    final store = FinanceStore(prefs);
    await _start(store);
    await store.clear();
    expect(store.onboarded, isFalse);
    expect(store.hasAcceptedCurrentLegal, isFalse);
    expect(store.legalAcceptance, isNull);
    expect(prefs.durable['numo_v1'], isNull);
    final restored = FinanceStore(prefs);
    await restored.load();
    expect(restored.hasAcceptedCurrentLegal, isFalse);
    expect(restored.onboarded, isFalse);
  });

  test(
    'unreadable saved data blocks acceptance without overwriting it',
    () async {
      const raw = '{broken data';
      final prefs = _Preferences({'numo_v1': raw});
      final store = FinanceStore(prefs);
      await store.load();
      await expectLater(_start(store), throwsStateError);
      expect(
        () => store.acceptLegalTerms(accepted: true, language: 'en'),
        throwsStateError,
      );
      expect(prefs.getString('numo_v1'), raw);
      expect(prefs.durable['numo_v1'], raw);
      expect(prefs.writeCount, 0);
      expect(store.hasAcceptedCurrentLegal, isFalse);
    },
  );

  test('existing-profile acceptance cannot bypass first profile setup', () {
    final prefs = _Preferences();
    final store = FinanceStore(prefs);
    expect(
      () => store.acceptLegalTerms(accepted: true, language: 'en'),
      throwsStateError,
    );
    expect(prefs.writeCount, 0);
    expect(store.hasAcceptedCurrentLegal, isFalse);
  });
}
