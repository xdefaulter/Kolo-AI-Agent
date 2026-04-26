import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'api/provider.dart';
import 'storage/database.dart';

/// Central provider state for all ProviderConfigs.
/// Used by both SettingsScreen (to add/edit/remove) and AgentSession (to get active provider).
final providersProvider = StateNotifierProvider<ProvidersNotifier, List<ProviderConfig>>((ref) {
  return ProvidersNotifier();
});

class ProvidersNotifier extends StateNotifier<List<ProviderConfig>> {

  ProvidersNotifier() : super([]) {
    _load();
  }

  Future<void> _load() async {
    final providers = await AppDatabase.instance.getAllProviders();
    state = providers;
  }

  /// 3.2: Write the entire providers list in one operation instead of N individual saves.
  Future<void> _save() async {
    await AppDatabase.instance.writeAllProviders(state);
  }

  void addProvider(ProviderConfig provider) {
    state = [...state, provider];
    _save();
  }

  void removeProvider(String id) {
    final idx = _indexOf(id);
    if (idx < 0) return;
    final next = List<ProviderConfig>.from(state)..removeAt(idx);
    state = next;
    _save();
  }

  void updateProvider(ProviderConfig provider) {
    final idx = _indexOf(provider.id);
    if (idx < 0) return;
    // Replace just the changed entry — every other slot keeps its existing
    // reference instead of being copyWith'd into a new object on every edit.
    final next = List<ProviderConfig>.from(state);
    next[idx] = provider;
    state = next;
    _save();
  }

  void setActiveProvider(String id) {
    // Only the previously-active provider AND the newly-active one need
    // a copyWith. The remaining N-2 untouched providers keep their old
    // reference, saving N-2 ProviderConfig allocations per switch.
    final current = state;
    int activeFrom = -1;
    int activeTo = -1;
    for (var i = 0; i < current.length; i++) {
      if (current[i].id == id) activeTo = i;
      if (current[i].isActive) activeFrom = i;
    }
    if (activeTo < 0 || activeFrom == activeTo) return;
    final next = List<ProviderConfig>.from(current);
    if (activeFrom >= 0) {
      next[activeFrom] = current[activeFrom].copyWith(isActive: false);
    }
    next[activeTo] = current[activeTo].copyWith(isActive: true);
    state = next;
    _save();
  }

  void addModel(String providerId, ModelConfig model) {
    final idx = _indexOf(providerId);
    if (idx < 0) return;
    final p = state[idx];
    final next = List<ProviderConfig>.from(state);
    next[idx] = p.copyWith(models: [...p.models, model]);
    state = next;
    _save();
  }

  void removeModel(String providerId, String modelId) {
    final idx = _indexOf(providerId);
    if (idx < 0) return;
    final p = state[idx];
    final mIdx = p.models.indexWhere((m) => m.modelId == modelId);
    if (mIdx < 0) return;
    final newModels = List<ModelConfig>.from(p.models)..removeAt(mIdx);
    final next = List<ProviderConfig>.from(state);
    next[idx] = p.copyWith(models: newModels);
    state = next;
    _save();
  }

  void setActiveModel(String providerId, String modelId) {
    final idx = _indexOf(providerId);
    if (idx < 0) return;
    final p = state[idx];
    // Mirror the provider-level fast path: only flip the previously-active
    // model and the newly-active one. Untouched ModelConfigs keep their
    // existing reference instead of being recopied per click.
    int from = -1;
    int to = -1;
    for (var i = 0; i < p.models.length; i++) {
      if (p.models[i].modelId == modelId) to = i;
      if (p.models[i].isActive) from = i;
    }
    if (to < 0 || from == to) return;
    final newModels = List<ModelConfig>.from(p.models);
    if (from >= 0) {
      newModels[from] = p.models[from].copyWith(isActive: false);
    }
    newModels[to] = p.models[to].copyWith(isActive: true);
    final next = List<ProviderConfig>.from(state);
    next[idx] = p.copyWith(models: newModels);
    state = next;
    _save();
  }

  Future<int> fetchModels(String providerId) async {
    final idx = _indexOf(providerId);
    if (idx < 0) return 0;
    final provider = state[idx];

    final fetched = await AppDatabase.instance.fetchModels(provider);
    if (fetched.isEmpty) return 0;

    final existingIds = provider.models.map((m) => m.modelId).toSet();
    final newModels = fetched.where((m) => !existingIds.contains(m.modelId)).toList();

    if (newModels.isEmpty) return 0;

    // Re-resolve the index post-await: state can have mutated while the
    // fetch was inflight (provider added/removed in another tab).
    final liveIdx = _indexOf(providerId);
    if (liveIdx < 0) return 0;
    final live = state[liveIdx];
    final next = List<ProviderConfig>.from(state);
    next[liveIdx] = live.copyWith(models: [...live.models, ...newModels]);
    state = next;
    _save();
    return newModels.length;
  }

  int _indexOf(String id) {
    final s = state;
    for (var i = 0; i < s.length; i++) {
      if (s[i].id == id) return i;
    }
    return -1;
  }
}