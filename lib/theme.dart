import 'package:flutter/material.dart';

const brandOrange = Color(0xFFE8742A);
const brandSlate = Color(0xFF1E2A33);

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: brandOrange,
    brightness: brightness,
    primary: brandOrange,
    surface: dark ? const Color(0xFF151C21) : const Color(0xFFF7F5F2),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    visualDensity: VisualDensity.standard,
    appBarTheme: AppBarTheme(
      backgroundColor: dark ? brandSlate : Colors.white,
      foregroundColor: dark ? Colors.white : brandSlate,
      elevation: 0,
      scrolledUnderElevation: 1,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      color: dark ? const Color(0xFF1F2930) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: dark ? const Color(0xFF2C3942) : const Color(0xFFE4E0DA)),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: dark ? const Color(0xFF2C3942) : const Color(0xFFE4E0DA),
      space: 1,
      thickness: 1,
    ),
    tooltipTheme: const TooltipThemeData(waitDuration: Duration(milliseconds: 400)),
  );
}
