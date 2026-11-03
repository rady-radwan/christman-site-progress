import 'dart:io';

import 'package:flutter/material.dart';

import 'library_store.dart';
import 'theme.dart';

/// Fonts that ship with Windows (and Office). Any not installed fall back to
/// the default font automatically.
const appFonts = <String>[
  'Segoe UI',
  'Segoe UI Variable Display',
  'Bahnschrift',
  'Calibri',
  'Arial',
  'Verdana',
  'Tahoma',
  'Trebuchet MS',
  'Century Gothic',
  'Franklin Gothic Medium',
  'Corbel',
  'Candara',
  'Georgia',
  'Cambria',
  'Consolas',
];

const systemThemeId = 'system';

/// The user's look-and-feel choices: theme, font and text size. Saved on
/// this computer (not in the shared library).
class AppAppearance extends ChangeNotifier {
  String themeId = 'christman-dark';
  String? fontFamily; // null = platform default
  double textScale = 1.0;

  Future<void> load() async {
    final cfg = await LibraryStore.readConfig();
    final t = cfg['appTheme'] as String?;
    if (t != null) {
      themeId = t;
    } else {
      // Carry over the older light/dark setting.
      themeId = switch (cfg['theme']) {
        'light' => 'christman-light',
        'system' => systemThemeId,
        _ => 'christman-dark',
      };
    }
    fontFamily = cfg['fontFamily'] as String?;
    textScale = ((cfg['textScale'] as num?)?.toDouble() ?? 1.0).clamp(0.8, 1.5);
  }

  String? get effectiveFont => fontFamily ?? (Platform.isWindows ? 'Segoe UI' : null);

  ThemeData get light => buildTheme(
      themeId == systemThemeId ? themeById('christman-light') : themeById(themeId),
      fontFamily: effectiveFont);

  ThemeData get dark => buildTheme(themeById('christman-dark'), fontFamily: effectiveFont);

  ThemeMode get mode => themeId == systemThemeId ? ThemeMode.system : ThemeMode.light;

  Future<void> setTheme(String id) async {
    themeId = id;
    notifyListeners();
    await LibraryStore.setConfig('appTheme', id);
  }

  Future<void> setFont(String? family) async {
    fontFamily = family;
    notifyListeners();
    await LibraryStore.setConfig('fontFamily', family);
  }

  Future<void> setTextScale(double v) async {
    textScale = v;
    notifyListeners();
    await LibraryStore.setConfig('textScale', v);
  }
}

final appearance = AppAppearance();
