import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/database.dart';
import 'create_tool_tool.dart';
import 'custom_tool_def.dart';

/// Cache of custom-tool definitions loaded from storage. Refreshes when
/// [reload] is called (typically after the agent's `create_tool` or
/// `delete_custom_tool` meta-tools modify the DB).
///
/// Kept as a synchronous StateNotifier rather than a FutureProvider so
/// that [toolRegistryProvider] can stay synchronous — making the whole
/// registry async would ripple through the session + permission UI.
class CustomToolsNotifier extends StateNotifier<List<CustomToolDef>> {
  CustomToolsNotifier() : super(const []) {
    reload();
  }

  /// Re-read from storage. Safe to call from any thread; state updates
  /// propagate via Riverpod on the UI thread.
  Future<void> reload() async {
    final next = await AppDatabase.instance.getAllCustomTools();
    if (!mounted) return;
    state = next;
  }
}

final customToolsProvider =
    StateNotifierProvider<CustomToolsNotifier, List<CustomToolDef>>(
      (ref) => CustomToolsNotifier(),
    );

/// Whether the agent is currently allowed to create new tools on its own.
/// Default: false — gated behind a Settings toggle.
class AgentCanCreateToolsNotifier extends StateNotifier<bool> {
  AgentCanCreateToolsNotifier() : super(kDefaultAgentCanCreateTools) {
    _load();
  }

  Future<void> _load() async {
    final raw = await AppDatabase.instance.getSetting(
      kAgentCanCreateToolsSettingKey,
    );
    if (!mounted) return;
    if (raw != null) state = raw == 'true';
  }

  Future<void> set(bool value) async {
    state = value;
    await AppDatabase.instance.saveSetting(
      kAgentCanCreateToolsSettingKey,
      value.toString(),
    );
  }
}

final agentCanCreateToolsProvider =
    StateNotifierProvider<AgentCanCreateToolsNotifier, bool>(
      (ref) => AgentCanCreateToolsNotifier(),
    );

/// Skills toggle state — symmetrical to agent-can-create-tools but on by
/// default since skills are filesystem-only (no new execution primitive).
class SkillsEnabledNotifier extends StateNotifier<bool> {
  SkillsEnabledNotifier() : super(kDefaultSkillsEnabled) {
    _load();
  }

  Future<void> _load() async {
    final raw = await AppDatabase.instance.getSetting(kSkillsEnabledSettingKey);
    if (!mounted) return;
    if (raw != null) state = raw == 'true';
  }

  Future<void> set(bool value) async {
    state = value;
    await AppDatabase.instance.saveSetting(
      kSkillsEnabledSettingKey,
      value.toString(),
    );
  }
}

final skillsEnabledProvider =
    StateNotifierProvider<SkillsEnabledNotifier, bool>(
      (ref) => SkillsEnabledNotifier(),
    );
