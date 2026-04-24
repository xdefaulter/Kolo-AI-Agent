import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../storage/database.dart';

/// Settings key gating whether the agent itself may create memories via
/// `remember_this`. Default: false — even though the memory SYSTEM is
/// always on, authoring is opt-in so the model can't silently grow a
/// dossier without consent.
const String kAgentCanCreateMemoriesSettingKey = 'agent_can_create_memories';
const bool kDefaultAgentCanCreateMemories = false;

/// Settings key for whether memory recall is injected into the system
/// prompt each turn. Default: true — if the user has no memories, recall
/// costs ~0 tokens and one table lookup.
const String kMemoryRecallEnabledSettingKey = 'memory_recall_enabled';
const bool kDefaultMemoryRecallEnabled = true;

/// Max number of memories to splice into a single turn's system prompt.
/// Keeps the extra context under ~300 tokens even for pathological cases.
const int kMemoryRecallCap = 6;

/// Thin facade over [AppDatabase] for memory CRUD. Exists so tools +
/// UI + recall all go through a single stable surface; swapping to a
/// different backend (e.g. vector store) later only touches this file.
class MemoryService {
  MemoryService._();
  static final MemoryService instance = MemoryService._();

  final _uuid = const Uuid();

  Future<List<MemoryEntry>> all({int? limit}) =>
      AppDatabase.instance.getAllMemories(limit: limit);

  Future<MemoryEntry> create({
    required String kind,
    required String content,
    String? sourceChatId,
  }) {
    final now = DateTime.now();
    final memory = MemoryEntry(
      id: _uuid.v4(),
      kind: kind,
      content: content.trim(),
      sourceChatId: sourceChatId,
      createdAt: now,
      updatedAt: now,
      lastUsedAt: now,
    );
    return AppDatabase.instance.saveMemory(memory);
  }

  Future<void> delete(String id) => AppDatabase.instance.deleteMemory(id);

  Future<void> deleteAll() => AppDatabase.instance.deleteAllMemories();

  /// Called by recall paths before splicing memories into prompts so
  /// last-used ordering actually reflects usage, not just age.
  Future<void> touch(String id) => AppDatabase.instance.touchMemory(id);

  Future<List<MemoryEntry>> recall(String query, {int? limit}) =>
      AppDatabase.instance.recallMemories(
        query,
        limit: limit ?? kMemoryRecallCap,
      );

  /// Build the compact text block that gets spliced into the system
  /// prompt. Empty string when memory recall is disabled or the store
  /// is empty. Uses a stable header so the LLM can recognise + ignore
  /// it when the user's message explicitly overrides memory.
  ///
  /// Pass [enabled] from a cached Riverpod provider to skip the DB
  /// round-trip that reads the setting (saves ~1–5 ms per turn).
  Future<String> buildRecallBlock(String query, {bool? enabled}) async {
    final bool isEnabled;
    if (enabled != null) {
      isEnabled = enabled;
    } else {
      final prefsRaw = await AppDatabase.instance.getSetting(
        kMemoryRecallEnabledSettingKey,
      );
      isEnabled = prefsRaw == null ? kDefaultMemoryRecallEnabled : prefsRaw == 'true';
    }
    if (!isEnabled) return '';
    final memories = await recall(query);
    if (memories.isEmpty) return '';
    // Touch in the background so we don't add latency to the send path.
    for (final m in memories) {
      // ignore: unawaited_futures
      touch(m.id);
    }
    final lines = memories
        .map((m) => '- [${m.kind}] ${m.content}')
        .take(kMemoryRecallCap)
        .join('\n');
    return 'Relevant memories about this user (use when relevant; ignore otherwise):\n$lines\n';
  }
}

/// Setting flag: may the agent itself author memories.
class AgentCanCreateMemoriesNotifier extends StateNotifier<bool> {
  AgentCanCreateMemoriesNotifier() : super(kDefaultAgentCanCreateMemories) {
    _load();
  }

  Future<void> _load() async {
    final raw = await AppDatabase.instance.getSetting(
      kAgentCanCreateMemoriesSettingKey,
    );
    if (!mounted) return;
    if (raw != null) state = raw == 'true';
  }

  Future<void> set(bool value) async {
    state = value;
    await AppDatabase.instance.saveSetting(
      kAgentCanCreateMemoriesSettingKey,
      value.toString(),
    );
  }
}

final agentCanCreateMemoriesProvider =
    StateNotifierProvider<AgentCanCreateMemoriesNotifier, bool>(
      (ref) => AgentCanCreateMemoriesNotifier(),
    );

/// Setting flag: inject memory recall into each turn's system prompt.
class MemoryRecallEnabledNotifier extends StateNotifier<bool> {
  MemoryRecallEnabledNotifier() : super(kDefaultMemoryRecallEnabled) {
    _load();
  }

  Future<void> _load() async {
    final raw = await AppDatabase.instance.getSetting(
      kMemoryRecallEnabledSettingKey,
    );
    if (!mounted) return;
    if (raw != null) state = raw == 'true';
  }

  Future<void> set(bool value) async {
    state = value;
    await AppDatabase.instance.saveSetting(
      kMemoryRecallEnabledSettingKey,
      value.toString(),
    );
  }
}

final memoryRecallEnabledProvider =
    StateNotifierProvider<MemoryRecallEnabledNotifier, bool>(
      (ref) => MemoryRecallEnabledNotifier(),
    );

/// Cached list of all memories. Invalidated when tools or UI mutate.
class MemoriesNotifier extends StateNotifier<List<MemoryEntry>> {
  MemoriesNotifier() : super(const []) {
    reload();
  }

  Future<void> reload() async {
    final all = await MemoryService.instance.all();
    if (!mounted) return;
    state = all;
  }
}

final memoriesProvider =
    StateNotifierProvider<MemoriesNotifier, List<MemoryEntry>>(
      (ref) => MemoriesNotifier(),
    );
