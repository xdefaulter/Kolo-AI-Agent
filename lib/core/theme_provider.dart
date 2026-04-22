import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'storage/database.dart';

// Brand colors
const _kSeedColor = Color(0xFF6744A4);
const _kAccentColor = Color(0xFFFF6B35);

/// Theme mode provider — persists theme choice to DB
final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, ThemeMode>((ref) {
  return ThemeModeNotifier();
});

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier() : super(ThemeMode.system) {
    _load();
  }

  Future<void> _load() async {
    final saved = await AppDatabase.instance.getSetting('theme_mode');
    switch (saved) {
      case 'light': state = ThemeMode.light;
      case 'dark': state = ThemeMode.dark;
      default: state = ThemeMode.system;
    }
  }

  Future<void> setTheme(ThemeMode mode) async {
    state = mode;
    await AppDatabase.instance.saveSetting('theme_mode', mode.name);
  }

  void cycle() {
    final next = switch (state) {
      ThemeMode.system => ThemeMode.light,
      ThemeMode.light => ThemeMode.dark,
      ThemeMode.dark => ThemeMode.system,
    };
    setTheme(next);
  }

  void setMode(ThemeMode mode) {
    setTheme(mode);
  }
}

/// Build the light theme
ThemeData buildLightTheme() {
  final base = ThemeData(
    colorSchemeSeed: _kSeedColor,
    useMaterial3: true,
    brightness: Brightness.light,
  );
  return _applyBrandOverrides(base, Brightness.light);
}

/// Build the dark theme
ThemeData buildDarkTheme() {
  final base = ThemeData(
    colorSchemeSeed: _kSeedColor,
    useMaterial3: true,
    brightness: Brightness.dark,
  );
  return _applyBrandOverrides(base, Brightness.dark);
}

ThemeData _applyBrandOverrides(ThemeData base, Brightness brightness) {
  final cs = base.colorScheme;
  return base.copyWith(
    // Richer accent color for CTAs
    colorScheme: cs.copyWith(
      secondary: _kAccentColor,
      onSecondary: Colors.white,
    ),
    // Card and surface styling
    cardTheme: CardThemeData(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      margin: const EdgeInsets.symmetric(vertical: 4),
    ),
    // Input decoration — better border + fill
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: brightness == Brightness.light
          ? cs.surfaceContainerLow
          : cs.surfaceContainerHighest.withValues(alpha: 0.5),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: cs.outline.withValues(alpha: 0.3)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: cs.outline.withValues(alpha: 0.3)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: cs.primary, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    ),
    // Divider theme
    dividerTheme: DividerThemeData(
      color: cs.outlineVariant.withValues(alpha: 0.2),
      thickness: 1,
    ),
    // Chip styling
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    // FAB styling
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    // Dialog styling
    dialogTheme: DialogThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    // Snackbar styling
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}