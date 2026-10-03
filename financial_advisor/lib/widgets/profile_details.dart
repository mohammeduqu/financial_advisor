import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/finance_store.dart';
import '../l10n/app_language.dart';
import 'design.dart';

// Account location is independent of the shopping providers' supported regions.
const profileCountries = <String, String>{
  'SA': 'Saudi Arabia',
  'AE': 'United Arab Emirates',
  'KW': 'Kuwait',
  'QA': 'Qatar',
  'BH': 'Bahrain',
  'OM': 'Oman',
  'EG': 'Egypt',
  'JO': 'Jordan',
  'LB': 'Lebanon',
  'US': 'United States',
  'GB': 'United Kingdom',
  'FR': 'France',
  'DE': 'Germany',
  'IN': 'India',
  'PK': 'Pakistan',
  'CA': 'Canada',
  'AU': 'Australia',
};
const profileCurrencies = ['SAR', 'USD', 'EUR', 'AED', 'GBP'];

class ProfileNameField extends StatefulWidget {
  final TextEditingController controller;
  final bool required, enabled;
  final int maxCharacters;
  final VoidCallback? onChanged;
  const ProfileNameField({
    super.key,
    required this.controller,
    this.required = false,
    this.enabled = true,
    this.maxCharacters = 100,
    this.onChanged,
  });

  @override
  State<ProfileNameField> createState() => _ProfileNameFieldState();
}

class _ProfileNameFieldState extends State<ProfileNameField> {
  bool limitExceeded = false;
  String get lengthError =>
      widget.maxCharacters == 100
          ? 'Name must be 100 characters or fewer.'
          : 'Name must be fewer than ${widget.maxCharacters + 1} characters.';
  @override
  Widget build(BuildContext context) => TextFormField(
    controller: widget.controller,
    enabled: widget.enabled,
    maxLength: widget.maxCharacters,
    // The custom formatter reports excess input before applying the limit.
    maxLengthEnforcement: MaxLengthEnforcement.none,
    inputFormatters: [
      _NameLengthFormatter(widget.maxCharacters, (exceeded) {
        if (mounted && limitExceeded != exceeded) {
          setState(() => limitExceeded = exceeded);
        }
      }),
    ],
    autovalidateMode: AutovalidateMode.onUserInteraction,
    textCapitalization: TextCapitalization.words,
    decoration: InputDecoration(
      labelText: tr(context, 'What should we call you?'),
      hintText: tr(context, 'Your first name'),
      counterText: '',
      errorText: limitExceeded ? tr(context, lengthError) : null,
      errorMaxLines: 2,
    ),
    onChanged: (_) => widget.onChanged?.call(),
    validator: (value) {
      if (limitExceeded ||
          (value ?? '').characters.length > widget.maxCharacters) {
        return tr(context, lengthError);
      }
      if (widget.required && (value ?? '').trim().isEmpty) {
        return tr(context, 'Enter your name.');
      }
      return null;
    },
  );
}

class _NameLengthFormatter extends TextInputFormatter {
  final ValueChanged<bool> onLimitAttempt;
  final int maximum;
  late final limiter = LengthLimitingTextInputFormatter(
    maximum,
    maxLengthEnforcement: MaxLengthEnforcement.truncateAfterCompositionEnds,
  );
  _NameLengthFormatter(this.maximum, this.onLimitAttempt);
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final composing =
        newValue.composing.isValid && !newValue.composing.isCollapsed;
    if (!composing) onLimitAttempt(newValue.text.characters.length > maximum);
    return limiter.formatEditUpdate(oldValue, newValue);
  }
}

class CountryField extends StatelessWidget {
  final String value;
  final ValueChanged<String?>? onChanged;
  const CountryField({super.key, required this.value, this.onChanged});
  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
    value: value,
    isExpanded: true,
    decoration: InputDecoration(labelText: tr(context, 'Country / location')),
    items:
        {
              ...profileCountries,
              if (!profileCountries.containsKey(value)) value: value,
            }.entries
            .map(
              (country) => DropdownMenuItem(
                value: country.key,
                child: AppText(country.value, overflow: TextOverflow.ellipsis),
              ),
            )
            .toList(),
    onChanged: onChanged,
  );
}

class CurrencyField extends StatelessWidget {
  final String value;
  final ValueChanged<String?>? onChanged;
  const CurrencyField({super.key, required this.value, this.onChanged});
  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
    value: value,
    decoration: InputDecoration(labelText: tr(context, 'Your currency')),
    items:
        {...profileCurrencies, value}
            .map(
              (currency) =>
                  DropdownMenuItem(value: currency, child: AppText(currency)),
            )
            .toList(),
    onChanged: onChanged,
  );
}

class ProfileDetailsCard extends StatelessWidget {
  final FinanceStore store;
  const ProfileDetailsCard({super.key, required this.store});

  Future<void> edit(BuildContext context) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _EditProfileDialog(store: store),
    );
    if (saved == true && context.mounted) toast(context, 'Profile updated');
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: store,
    builder:
        (context, _) => Surface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: AppText(
                      'Profile details',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    key: const Key('edit-profile'),
                    onPressed: () => edit(context),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const AppText('Edit'),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _ProfileDetail(
                icon: Icons.person_outline,
                label: 'Name',
                value: store.name,
              ),
              const SizedBox(height: 20),
              _ProfileDetail(
                icon: Icons.payments_outlined,
                label: 'Your currency',
                value: store.currency,
              ),
              const SizedBox(height: 20),
              _ProfileDetail(
                icon: Icons.public,
                label: 'Country / location',
                value: tr(
                  context,
                  profileCountries[store.countryCode] ?? store.countryCode,
                ),
              ),
            ],
          ),
        ),
  );
}

class _ProfileDetail extends StatelessWidget {
  final IconData icon;
  final String label, value;
  const _ProfileDetail({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, color: muted, size: 21),
      const SizedBox(width: 14),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppText(label, style: const TextStyle(fontSize: 12, color: muted)),
            const SizedBox(height: 5),
            Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    ],
  );
}

class _EditProfileDialog extends StatefulWidget {
  final FinanceStore store;
  const _EditProfileDialog({required this.store});
  @override
  State<_EditProfileDialog> createState() => _EditProfileDialogState();
}

class _EditProfileDialogState extends State<_EditProfileDialog> {
  final form = GlobalKey<FormState>();
  late final TextEditingController name;
  late String currency, country;
  bool busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    name = TextEditingController(text: widget.store.name);
    currency = widget.store.currency;
    country = widget.store.countryCode;
  }

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (busy || !form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.store.updateProfile(
        userName: name.text,
        selectedCurrency: currency,
        selectedCountry: country,
      );
      if (!mounted) return;
      if (widget.store.error == null) {
        Navigator.pop(context, true);
        return;
      }
      setState(() => error = widget.store.error);
    } on ArgumentError {
      if (mounted) {
        setState(() => error = 'Check your profile details and try again.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AlertDialog(
      key: const Key('edit-profile-dialog'),
      title: const AppText('Edit profile'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Form(
            key: form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                ProfileNameField(
                  key: const Key('profile-name'),
                  controller: name,
                  required: true,
                  enabled: !busy,
                ),
                const SizedBox(height: 16),
                CurrencyField(
                  key: const Key('profile-currency'),
                  value: currency,
                  onChanged:
                      busy
                          ? null
                          : (value) => setState(() => currency = value!),
                ),
                const SizedBox(height: 10),
                const AppText(
                  'Changing currency updates the account unit. Existing amounts are not converted.',
                  style: TextStyle(fontSize: 12, color: muted, height: 1.5),
                ),
                const SizedBox(height: 16),
                CountryField(
                  key: const Key('profile-country'),
                  value: country,
                  onChanged:
                      busy ? null : (value) => setState(() => country = value!),
                ),
                if (error != null) ...[
                  const SizedBox(height: 16),
                  AppText(
                    error!,
                    style: const TextStyle(color: Color(0xFFFFB4AB)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('cancel-edit-profile'),
          onPressed: busy ? null : () => Navigator.pop(context, false),
          child: const AppText('Cancel'),
        ),
        FilledButton(
          key: const Key('save-profile'),
          onPressed: busy ? null : save,
          child: AppText(busy ? 'Saving…' : 'Save profile'),
        ),
      ],
    ),
  );
}
