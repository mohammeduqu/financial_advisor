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
import 'services/invoice_service.dart';
import 'widgets/recurring_entry_scheduler.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = FinanceStore(await SharedPreferences.getInstance());
  await migrateInvoiceApiUrl(store.prefs);
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
          builder:
              (context, child) => RecurringEntryScheduler(
                store: store,
                child: AuroraBackground(child: child!),
              ),
          home:
              store.onboarded
                  ? AppShell(store: store)
                  : WelcomePage(store: store),
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
  String currency = 'SAR';
  bool busy = false;
  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> start() async {
    setState(() => busy = true);
    await widget.store.start(
      userName: name.text,
      selectedCurrency: currency,
      useDemo: false,
    );
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
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
              if (widget.store.error != null) ...[
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
              TextField(
                controller: name,
                decoration: InputDecoration(
                  labelText: tr(context, 'What should we call you?'),
                  hintText: tr(context, 'Your first name'),
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: currency,
                decoration: InputDecoration(
                  labelText: tr(context, 'Your currency'),
                ),
                items:
                    ['SAR', 'USD', 'EUR', 'AED', 'GBP']
                        .map(
                          (v) => DropdownMenuItem(value: v, child: AppText(v)),
                        )
                        .toList(),
                onChanged: (v) => setState(() => currency = v!),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: busy ? null : start,
                child: const AppText('Get started'),
              ),
              const SizedBox(height: 24),
              const AppText(
                'Currency is fixed after setup. You can change the app language from Profile.',
                style: TextStyle(color: muted, fontSize: 11, height: 1.6),
                textAlign: TextAlign.center,
              ),
            ],
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
  DateTime month = DateTime(DateTime.now().year, DateTime.now().month);
  String? invoiceFocusId;

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
        month = DateTime(entry.date.year, entry.date.month);
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
        highlightedEntryId: invoiceFocusId,
      ),

      PlanPage(store: store, month: month),
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
                              () => setState(
                                () =>
                                    month = DateTime(
                                      month.year,
                                      month.month - 1,
                                    ),
                              ),
                        ),
                        AppText(
                          DateFormat.yMMMM(languageOf(context)).format(month),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: muted,
                          ),
                        ),
                        IconButton(
                          tooltip: tr(context, 'Next month'),
                          icon: const Icon(Icons.chevron_right, size: 19),
                          onPressed:
                              monthKey(month) == monthKey(DateTime.now())
                                  ? null
                                  : () => setState(
                                    () =>
                                        month = DateTime(
                                          month.year,
                                          month.month + 1,
                                        ),
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
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const AppText('Profile')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        PageHeading('Your profile', store.name),
        Surface(
          child: Column(
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.payments_outlined),
                title: const AppText('Currency'),
                subtitle: AppText(
                  '${store.currency} · fixed for this workspace',
                ),
              ),
              const Divider(),
              const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.cloud_outlined),
                title: AppText('Backend services'),
                subtitle: AppText('Receipt analysis and product search'),
              ),
            ],
          ),
        ),
        LanguageSelector(store: store),
        const SectionHeading('Data processing'),
        const AppText(
          'Receipt images and product searches are sent to the configured backend for processing. Review extracted details before saving an expense.',
          style: TextStyle(color: muted, fontSize: 13, height: 1.7),
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
  );
}
