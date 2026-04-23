import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../storage/database.dart';

/// How the agent controls the phone: via Accessibility service or ADB commands
enum PhoneControlMode {
  accessibility,
  adb,
}

/// Riverpod provider for phone control mode — persisted in settings
final phoneControlModeProvider =
    StateNotifierProvider<PhoneControlModeNotifier, PhoneControlMode>((ref) {
  return PhoneControlModeNotifier();
});

class PhoneControlModeNotifier extends StateNotifier<PhoneControlMode> {
  PhoneControlModeNotifier() : super(PhoneControlMode.accessibility) {
    _load();
  }

  Future<void> _load() async {
    final saved = await AppDatabase.instance.getSetting('phone_control_mode');
    if (saved == 'adb') {
      state = PhoneControlMode.adb;
    }
  }

  Future<void> update(PhoneControlMode mode) async {
    state = mode;
    await AppDatabase.instance.saveSetting('phone_control_mode', mode.name);
  }
}
