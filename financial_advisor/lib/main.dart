import 'widgets/language_selector.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'l10n/app_language.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/finance_store.dart';
import 'widgets/design.dart';
import 'widgets/tadbeer_logo.dart';
import 'screens/home.dart';
import 'screens/transactions.dart';
import 'screens/scan.dart';
import 'screens/smart_prices.dart';
import 'screens/plan.dart';
import 'screens/privacy_terms.dart';
import 'screens/legal_acceptance.dart';
import 'widgets/recurring_entry_scheduler.dart';
import 'widgets/profile_details.dart';
import 'widgets/legal_acceptance_field.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = FinanceStore(await SharedPreferences.getInstance());
  await store.load();
  runApp(TadbeerApp(store: store));
}

class TadbeerApp extends StatelessWidget {
  final FinanceStore store;
  const TadbeerApp({super.key, required this.store});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: store,
    builder:
        (context, _) => MaterialApp(
          onGenerateTitle:
              (context) => tr(context, 'Tadbeer • Money Management'),
          debugShowCheckedModeBanner: false,
          theme: appTheme(),
          supportedLocales: const [Locale('en'), Locale('ar')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          locale:
              store.languageCode == null ? null : Locale(store.languageCode!),
          localeListResolutionCallback: resolveDeviceLocale,
          builder: (context, child) => AuroraBackground(child: child!),
          home:
              !store.onboarded
                  ? WelcomePage(store: store)
                  : !store.hasAcceptedCurrentLegal
                  ? LegalAcceptancePage(store: store)
                  : RecurringEntryScheduler(
                    store: store,
                    child: AppShell(store: store),
                  ),
        ),
  );
}

class WelcomePage extends StatefulWidget {
  final FinanceStore store;
  const WelcomePage({super.key, required this.store});
  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage> {
  final name = TextEditingController();
  final form = GlobalKey<FormState>();
  String currency = 'SAR', country = 'SA';
  bool busy = false, acceptedLegal = false;
  String? saveError;
  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> start() async {
    if (busy || !acceptedLegal || !form.currentState!.validate()) return;
    setState(() {
      busy = true;
      saveError = null;
    });
    try {
      await widget.store.start(
        userName: name.text,
        selectedCurrency: currency,
        selectedCountry: country,
        useDemo: false,
        acceptedLegal: acceptedLegal,
        legalLanguage: languageOf(context),
      );
      if (!widget.store.onboarded || !widget.store.hasAcceptedCurrentLegal) {
        throw StateError('Agreement was not saved');
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          saveError = 'Could not save your agreement. Please try again.';
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
          child: Form(
            key: form,
            child: ListView(
              padding: const EdgeInsets.all(32),
              shrinkWrap: true,
              children: [
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: const TadbeerLogo(size: 64),
                ),
                const SizedBox(height: 24),
                const AppText(
                  'Tadbeer',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 27,
                    letterSpacing: -1,
                  ),
                ),
                const SizedBox(height: 22),
                const AppText(
                  'Your money.\nA clearer direction.',
                  style: TextStyle(
                    fontSize: 38,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                    letterSpacing: -1.5,
                    color: ink,
                  ),
                ),
                const SizedBox(height: 16),
                const AppText(
                  'Track your income and expenses, stay within budget, and build better money habits.',
                  style: TextStyle(color: muted, fontSize: 16, height: 1.6),
                ),
                const SizedBox(height: 32),
                if (widget.store.error?.startsWith('Saved data') ?? false) ...[
                  AppText(
                    widget.store.error!,
                    style: const TextStyle(color: Colors.red),
                  ),
                  TextButton(
                    onPressed: () async {
                      if (await confirm(
                        context,
                        'Clear unreadable data?',
                        'This permanently removes the saved workspace.',
                      )) {
                        await widget.store.clear();
                      }
                    },
                    child: const AppText('Clear saved data'),
                  ),
                ],
                ProfileNameField(
                  key: const Key('welcome-name'),
                  controller: name,
                  required: true,
                  maxCharacters: 99,
                  enabled: !busy,
                ),
                const SizedBox(height: 16),
                CurrencyField(
                  key: const Key('welcome-currency'),
                  value: currency,
                  onChanged: busy ? null : (v) => setState(() => currency = v!),
                ),
                const SizedBox(height: 16),
                CountryField(
                  key: const Key('welcome-country'),
                  value: country,
                  onChanged: busy ? null : (v) => setState(() => country = v!),
                ),
                const SizedBox(height: 24),
                LegalAcceptanceField(
                  value: acceptedLegal,
                  enabled: !busy,
                  readButtonKey: const Key('welcome-privacy'),
                  onChanged: (value) => setState(() => acceptedLegal = value),
                ),
                if (saveError != null) ...[
                  const SizedBox(height: 12),
                  Semantics(
                    liveRegion: true,
                    child: AppText(
                      saveError!,
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: busy || !acceptedLegal ? null : start,
                  child: const AppText('Get started'),
                ),
                const SizedBox(height: 24),
                const AppText(
                  'You can change your name, currency, country and app language from Profile.',
                  style: TextStyle(color: muted, fontSize: 11, height: 1.6),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class AppShell extends StatefulWidget {
  final FinanceStore store;
  const AppShell({super.key, required this.store});
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int index = 0;
  DateTime? month;
  int periodRevision = 0;
  String? invoiceFocusId;

  Future<void> chooseMonth() async {
    var year = (month ?? DateTime.now()).year;
    // A null dialog result is Cancel; a record containing null is All dates.
    final selected = await showDialog<(DateTime?,)>(
      context: context,
      builder:
          (dialogContext) => StatefulBuilder(
            builder:
                (context, update) => AlertDialog(
                  title: const AppText('Choose month'),
                  content: SizedBox(
                    width: 320,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            IconButton(
                              tooltip: tr(context, 'Previous year'),
                              onPressed:
                                  year > 2000
                                      ? () => update(() => year--)
                                      : null,
                              icon: const Icon(Icons.chevron_left),
                            ),
                            Expanded(
                              child: Text('$year', textAlign: TextAlign.center),
                            ),
                            IconButton(
                              tooltip: tr(context, 'Next year'),
                              onPressed:
                                  year < 2100
                                      ? () => update(() => year++)
                                      : null,
                              icon: const Icon(Icons.chevron_right),
                            ),
                          ],
                        ),
                        GridView.count(
                          crossAxisCount: 3,
                          shrinkWrap: true,
                          childAspectRatio: 1.7,
                          children: List.generate(
                            12,
                            (index) => TextButton(
                              key: ValueKey('choose-month-${index + 1}'),
                              onPressed:
                                  () => Navigator.pop(dialogContext, (
                                    DateTime(year, index + 1),
                                  )),
                              child: Text(
                                DateFormat.MMM(
                                  languageOf(context),
                                ).format(DateTime(year, index + 1)),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      key: const Key('choose-all-dates'),
                      onPressed: () => Navigator.pop(dialogContext, (null,)),
                      child: const AppText('All dates'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const AppText('Cancel'),
                    ),
                  ],
                ),
          ),
    );
    if (selected != null && mounted) {
      setMonth(selected.$1);
    }
  }

  void setMonth(DateTime? selected) {
    setState(() {
      month = selected;
      periodRevision++;
      invoiceFocusId = null;
    });
  }

  Future<void> navigate(int i) async {
    if (i == 2 || i == 5) {
      final entry = await Navigator.push<Entry>(
        context,
        MaterialPageRoute(
          builder:
              (_) =>
                  i == 5
                      ? SmartPricesPage(store: widget.store)
                      : Scaffold(
                        appBar: AppBar(title: const AppText('Scan invoice')),
                        body: ScanPage(store: widget.store),
                      ),
        ),
      );
      if (!mounted || entry == null) return;
      setState(() {
        index = 1;
        if (month != null && monthKey(month!) != monthKey(entry.date)) {
          month = null;
        }
        invoiceFocusId = entry.id;
      });
      toast(context, 'Invoice added to expenses');
    } else {
      setState(() => index = i == 3 ? 2 : i);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final pages = [
      HomePage(
        store: store,
        month: month,
        chooseMonth: chooseMonth,
        navigate: navigate,
        settings:
            () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => SettingsPage(store: store)),
            ),
      ),
      TransactionsPage(
        // Recreate the list to clear filters and scroll position after a scan.
        key: ValueKey(invoiceFocusId),
        store: store,
        month: month,
        onMonthChanged: setMonth,
        periodRevision: periodRevision,
        highlightedEntryId: invoiceFocusId,
      ),

      PlanPage(store: store, month: month, chooseMonth: chooseMonth),
      SettingsPage(store: store),
    ];
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              children: [
                if (store.error != null)
                  MaterialBanner(
                    content: AppText(store.error!),
                    actions: [
                      TextButton(
                        onPressed: store.persist,
                        child: const AppText('Retry'),
                      ),
                    ],
                  ),
                if (index < 3)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          tooltip: tr(context, 'Previous month'),
                          icon: const Icon(Icons.chevron_left, size: 19),
                          onPressed:
                              month == null ||
                                      (month!.year == 2000 && month!.month == 1)
                                  ? null
                                  : () => setMonth(
                                    DateTime(month!.year, month!.month - 1),
                                  ),
                        ),
                        Flexible(
                          child: TextButton.icon(
                            key: const Key('choose-month'),
                            onPressed: chooseMonth,
                            icon: const Icon(
                              Icons.filter_alt_outlined,
                              size: 16,
                            ),
                            label: AppText(
                              month == null
                                  ? 'All dates'
                                  : DateFormat.yMMMM(
                                    languageOf(context),
                                  ).format(month!),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: muted,
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: tr(context, 'Next month'),
                          icon: const Icon(Icons.chevron_right, size: 19),
                          onPressed:
                              month == null ||
                                      (month!.year == 2100 &&
                                          month!.month == 12)
                                  ? null
                                  : () => setMonth(
                                    DateTime(month!.year, month!.month + 1),
                                  ),
                        ),
                        if (month != null)
                          IconButton(
                            key: const Key('clear-month-filter'),
                            tooltip: tr(context, 'All dates'),
                            onPressed: () => setMonth(null),
                            icon: const Icon(
                              Icons.filter_alt_off_outlined,
                              size: 19,
                            ),
                          ),
                      ],
                    ),
                  ),
                Expanded(child: IndexedStack(index: index, children: pages)),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Surface(
          padding: EdgeInsets.zero,
          child: NavigationBar(
            selectedIndex: index,
            onDestinationSelected: (value) => setState(() => index = value),
            backgroundColor: Colors.transparent,
            indicatorColor: const Color(0xFF234039),
            labelTextStyle: WidgetStateProperty.all(
              const TextStyle(fontSize: 10, fontWeight: FontWeight.w500),
            ),
            destinations: [
              NavigationDestination(
                icon: Icon(Icons.space_dashboard_outlined),
                selectedIcon: Icon(Icons.space_dashboard_rounded),
                label: tr(context, 'Home'),
              ),
              NavigationDestination(
                icon: Icon(Icons.swap_horiz_rounded),
                label: tr(context, 'Transactions'),
              ),
              NavigationDestination(
                icon: Icon(Icons.bar_chart_rounded, color: blue),
                label: tr(context, 'Analysis'),
              ),
              NavigationDestination(
                icon: Icon(Icons.person_outline),
                label: tr(context, 'Profile'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SettingsPage extends StatelessWidget {
  final FinanceStore store;
  const SettingsPage({super.key, required this.store});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: store,
    builder:
        (context, _) => Scaffold(
          appBar: AppBar(title: const AppText('Profile')),
          body: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              PageHeading('Your profile', store.name, titleMaxLines: 2),
              ProfileDetailsCard(store: store),
              LanguageSelector(store: store),
              const SizedBox(height: 20),
              Surface(
                key: const Key('privacy-card'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const AppText(
                      'Privacy & data',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const AppText(
                      'Read our privacy notice and terms of use.',
                      style: TextStyle(color: muted, fontSize: 13),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      key: const Key('view-privacy'),
                      icon: const Icon(Icons.privacy_tip_outlined),
                      label: const AppText('Privacy & terms'),
                      onPressed:
                          () => Navigator.push<void>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const PrivacyTermsPage(),
                            ),
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: () async {
                  if (await confirm(
                    context,
                    'Clear saved data?',
                    'Saved transactions, recurring schedules, receipt images, budgets and goals will be permanently removed.',
                    action: 'Clear data',
                  )) {
                    await store.clear();
                    if (context.mounted) {
                      if (store.error != null) {
                        toast(context, store.error!);
                      } else if (Navigator.canPop(context)) {
                        Navigator.pop(context);
                      }
                    }
                  }
                },
                icon: const Icon(Icons.delete_outline),
                label: const AppText('Clear saved data'),
              ),
              const SizedBox(height: 24),
              const AppText(
                'Tadbeer · 0.1\nIncome, expenses, budgets and savings goals in one place.',
                style: TextStyle(fontSize: 11, color: muted, height: 1.5),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
  );
}
