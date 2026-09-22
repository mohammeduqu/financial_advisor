import '../l10n/app_language.dart';
import 'package:flutter/material.dart';

const ink = Color(0xFFEAF0F5),
    blue = Color(0xFF73CBB0),
    canvas = Color(0xFF090F18),
    muted = Color(0xFFA0ADBD),
    line = Color(0xFF293444);
ThemeData appTheme() => ThemeData(
  useMaterial3: true,
  brightness: Brightness.dark,
  scaffoldBackgroundColor: Colors.transparent,
  colorScheme: ColorScheme.fromSeed(
    brightness: Brightness.dark,
    seedColor: blue,
    primary: blue,
    surface: const Color(0xFF141E2B),
  ),
  fontFamily: 'Roboto',
  appBarTheme: const AppBarTheme(
    backgroundColor: Colors.transparent,
    foregroundColor: ink,
    elevation: 0,
    scrolledUnderElevation: 0,
  ),
  textTheme: const TextTheme(
    headlineLarge: TextStyle(
      fontSize: 32,
      fontWeight: FontWeight.w700,
      letterSpacing: -1.2,
      color: ink,
    ),
    headlineMedium: TextStyle(
      fontSize: 27,
      fontWeight: FontWeight.w700,
      letterSpacing: -.8,
      color: ink,
    ),
    titleLarge: TextStyle(
      fontSize: 19,
      fontWeight: FontWeight.w700,
      letterSpacing: -.4,
      color: ink,
    ),
    titleMedium: TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w600,
      color: ink,
    ),
    bodyMedium: TextStyle(fontSize: 14, color: ink),
    bodySmall: TextStyle(fontSize: 12, color: muted, height: 1.5),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: const Color(0xFF141E2B),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: line),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: line),
    ),
    contentPadding: const EdgeInsets.all(16),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      minimumSize: const Size(48, 50),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      minimumSize: const Size(48, 48),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
      side: const BorderSide(color: line),
    ),
  ),
  dividerTheme: const DividerThemeData(color: line, thickness: 1, space: 24),
);

class Surface extends StatelessWidget {
  final Widget child;
  final Color color;
  final EdgeInsets padding;
  const Surface({
    super.key,
    required this.child,
    this.color = Colors.white,
    this.padding = const EdgeInsets.all(20),
  });
  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 220),
    padding: padding,
    decoration: BoxDecoration(
      color: color == ink ? null : const Color(0xFF141D29),
      gradient:
          color == ink
              ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF1B3440),
                  Color(0xFF142430),
                  Color(0xFF172235),
                ],
              )
              : null,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(
        color:
            color == ink
                ? const Color(0xFF35514F)
                : line.withValues(alpha: .72),
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: .16),
          blurRadius: 20,
          offset: const Offset(0, 8),
        ),
      ],
    ),
    child: child,
  );
}

class AuroraBackground extends StatelessWidget {
  final Widget child;
  const AuroraBackground({super.key, required this.child});
  @override
  Widget build(BuildContext context) => ColoredBox(color: canvas, child: child);
}

class PageHeading extends StatelessWidget {
  final String eyebrow, title;
  final Widget? action;
  const PageHeading(this.eyebrow, this.title, {super.key, this.action});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppText(
                eyebrow.toUpperCase(),
                style: const TextStyle(
                  fontSize: 10,
                  letterSpacing: 1.8,
                  fontWeight: FontWeight.w700,
                  color: muted,
                ),
              ),
              const SizedBox(height: 8),
              AppText(title, style: Theme.of(context).textTheme.headlineMedium),
            ],
          ),
        ),
        if (action != null) action!,
      ],
    ),
  );
}

class SectionHeading extends StatelessWidget {
  final String title;
  final Widget? action;
  const SectionHeading(this.title, {super.key, this.action});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 12),
    child: Row(
      children: [
        Expanded(
          child: AppText(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        if (action != null) action!,
      ],
    ),
  );
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title, body;
  final Widget? action;
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.action,
  });
  @override
  Widget build(BuildContext context) => Surface(
    child: Column(
      children: [
        Icon(icon, size: 36, color: blue),
        const SizedBox(height: 14),
        AppText(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        AppText(
          body,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (action != null) ...[const SizedBox(height: 18), action!],
      ],
    ),
  );
}

IconData categoryIcon(String category) => switch (category) {
  'Food' => Icons.restaurant_outlined,
  'Transportation' => Icons.directions_car_outlined,
  'Housing' => Icons.home_outlined,
  'Utilities' => Icons.bolt_outlined,
  'Shopping' => Icons.shopping_bag_outlined,
  'Healthcare' => Icons.favorite_border,
  'Entertainment' => Icons.movie_outlined,
  'Education' => Icons.school_outlined,
  'Subscriptions' => Icons.repeat,
  'Travel' => Icons.flight_outlined,
  _ => Icons.receipt_long_outlined,
};

class CategoryBadge extends StatelessWidget {
  final String category;
  const CategoryBadge(this.category, {super.key});
  @override
  Widget build(BuildContext context) => Container(
    width: 44,
    height: 44,
    decoration: BoxDecoration(
      color: const Color(0xFF213B3B),
      borderRadius: BorderRadius.circular(13),
    ),
    child: Icon(categoryIcon(category), size: 21, color: blue),
  );
}

Future<bool> confirm(
  BuildContext context,
  String title,
  String message, {
  String action = 'Confirm',
}) async =>
    await showDialog<bool>(
      context: context,
      builder:
          (c) => AlertDialog(
            title: AppText(title),
            content: AppText(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const AppText('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: AppText(action),
              ),
            ],
          ),
    ) ??
    false;
void toast(BuildContext context, String text) => ScaffoldMessenger.of(
  context,
).showSnackBar(SnackBar(content: AppText(text)));
