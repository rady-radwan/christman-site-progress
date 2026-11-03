import 'package:flutter/material.dart';

const brandOrange = Color(0xFFE8742A);
const christmanCopper = Color(0xFFAE734B);

/// Colors for areas Material doesn't cover: header, sidebar.
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({required this.header, required this.sidebar});
  final Color header;
  final Color sidebar;

  @override
  AppPalette copyWith({Color? header, Color? sidebar}) =>
      AppPalette(header: header ?? this.header, sidebar: sidebar ?? this.sidebar);

  @override
  AppPalette lerp(AppPalette? other, double t) => other == null
      ? this
      : AppPalette(header: Color.lerp(header, other.header, t)!, sidebar: Color.lerp(sidebar, other.sidebar, t)!);
}

extension AppPaletteX on BuildContext {
  AppPalette get palette =>
      Theme.of(this).extension<AppPalette>() ??
      const AppPalette(header: Color(0xFF1E2A33), sidebar: Color(0xFF111820));
}

/// One selectable look for the app.
class AppThemeSpec {
  const AppThemeSpec({
    required this.id,
    required this.name,
    required this.brightness,
    required this.primary,
    required this.surface,
    required this.bar,
    required this.card,
    required this.sidebar,
    required this.divider,
  });

  final String id;
  final String name;
  final Brightness brightness;
  final Color primary;
  final Color surface;
  final Color bar;
  final Color card;
  final Color sidebar;
  final Color divider;
}

const appThemes = <AppThemeSpec>[
  AppThemeSpec(
    id: 'christman-dark',
    name: 'Christman Dark',
    brightness: Brightness.dark,
    primary: christmanCopper,
    surface: Color(0xFF161515),
    bar: Color(0xFF0E0D0D),
    card: Color(0xFF221F1E),
    sidebar: Color(0xFF111010),
    divider: Color(0xFF332E2B),
  ),
  AppThemeSpec(
    id: 'christman-light',
    name: 'Christman Light',
    brightness: Brightness.light,
    primary: christmanCopper,
    surface: Color(0xFFF7F4F0),
    bar: Color(0xFFFFFFFF),
    card: Color(0xFFFFFFFF),
    sidebar: Color(0xFFEFE9E2),
    divider: Color(0xFFE1D8CE),
  ),
  AppThemeSpec(
    id: 'slate',
    name: 'Slate Night',
    brightness: Brightness.dark,
    primary: brandOrange,
    surface: Color(0xFF151C21),
    bar: Color(0xFF1E2A33),
    card: Color(0xFF1F2930),
    sidebar: Color(0xFF111820),
    divider: Color(0xFF2C3942),
  ),
  AppThemeSpec(
    id: 'daylight',
    name: 'Daylight',
    brightness: Brightness.light,
    primary: brandOrange,
    surface: Color(0xFFF7F5F2),
    bar: Color(0xFFFFFFFF),
    card: Color(0xFFFFFFFF),
    sidebar: Color(0xFFF1EEE9),
    divider: Color(0xFFE4E0DA),
  ),
  AppThemeSpec(
    id: 'midnight',
    name: 'Midnight Blue',
    brightness: Brightness.dark,
    primary: Color(0xFF4FA3E0),
    surface: Color(0xFF0E1726),
    bar: Color(0xFF14213A),
    card: Color(0xFF17253F),
    sidebar: Color(0xFF0B1320),
    divider: Color(0xFF22314D),
  ),
  AppThemeSpec(
    id: 'blueprint',
    name: 'Blueprint',
    brightness: Brightness.light,
    primary: Color(0xFF1F5FA8),
    surface: Color(0xFFF2F6FB),
    bar: Color(0xFFFFFFFF),
    card: Color(0xFFFFFFFF),
    sidebar: Color(0xFFE5EDF7),
    divider: Color(0xFFD3DEEA),
  ),
  AppThemeSpec(
    id: 'forest',
    name: 'Forest',
    brightness: Brightness.dark,
    primary: Color(0xFF3FBF7F),
    surface: Color(0xFF0F1A15),
    bar: Color(0xFF15261E),
    card: Color(0xFF1A2E24),
    sidebar: Color(0xFF0C1511),
    divider: Color(0xFF24392E),
  ),
  AppThemeSpec(
    id: 'steel',
    name: 'Steel & Safety Yellow',
    brightness: Brightness.dark,
    primary: Color(0xFFF2C94C),
    surface: Color(0xFF1A1C1E),
    bar: Color(0xFF26292C),
    card: Color(0xFF24272A),
    sidebar: Color(0xFF151719),
    divider: Color(0xFF34383C),
  ),
  AppThemeSpec(
    id: 'sand',
    name: 'Sandstone',
    brightness: Brightness.light,
    primary: Color(0xFF8C5A2B),
    surface: Color(0xFFF6F0E6),
    bar: Color(0xFFFBF7F0),
    card: Color(0xFFFFFCF7),
    sidebar: Color(0xFFEFE6D8),
    divider: Color(0xFFE3D6C2),
  ),
  AppThemeSpec(
    id: 'contrast',
    name: 'High Contrast',
    brightness: Brightness.dark,
    primary: Color(0xFFFFD400),
    surface: Color(0xFF000000),
    bar: Color(0xFF000000),
    card: Color(0xFF111111),
    sidebar: Color(0xFF000000),
    divider: Color(0xFF666666),
  ),
];

AppThemeSpec themeById(String id) =>
    appThemes.firstWhere((t) => t.id == id, orElse: () => appThemes.first);

ThemeData buildTheme(AppThemeSpec t, {String? fontFamily}) {
  final dark = t.brightness == Brightness.dark;
  final onBar = dark ? Colors.white : const Color(0xFF1E2A33);
  final scheme = ColorScheme.fromSeed(
    seedColor: t.primary,
    brightness: t.brightness,
    primary: t.primary,
    onPrimary: t.primary.computeLuminance() > 0.5 ? Colors.black : Colors.white,
    surface: t.surface,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: fontFamily,
    scaffoldBackgroundColor: t.surface,
    visualDensity: VisualDensity.standard,
    extensions: [AppPalette(header: t.bar, sidebar: t.sidebar)],
    appBarTheme: AppBarTheme(
      backgroundColor: t.bar,
      foregroundColor: onBar,
      elevation: 0,
      scrolledUnderElevation: 1,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      color: t.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: t.divider),
      ),
    ),
    dividerTheme: DividerThemeData(color: t.divider, space: 1, thickness: 1),
    tooltipTheme: const TooltipThemeData(waitDuration: Duration(milliseconds: 400)),
  );
}
