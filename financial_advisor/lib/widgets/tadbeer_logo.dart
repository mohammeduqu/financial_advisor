import 'package:flutter/material.dart';

/// Tadbeer's approved filled wallet on its blue-to-teal background.
class TadbeerLogo extends StatelessWidget {
  final double size;

  const TadbeerLogo({super.key, this.size = 48});

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(size * .26),
    child: Image.asset(
      'assets/branding/tadbeer-logo.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      excludeFromSemantics: true,
    ),
  );
}
