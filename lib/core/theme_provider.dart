import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'storage/database.dart';

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