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
    state = state.where((p) => p.id != id).toList();
    _save();
  }

  void updateProvider(ProviderConfig provider) {
    state = state.map((p) => p.id == provider.id ? provider : p).toList();
    _save();
  }

  void setActiveProvider(String id) {
    state = state.map((p) => p.copyWith(isActive: p.id == id)).toList();
    _save();
  }

  void addModel(String providerId, ModelConfig model) {
    state = state.map((p) {
      if (p.id == providerId) {
        return p.copyWith(models: [...p.models, model]);
      }
      return p;
    }).toList();
    _save();
  }

  void removeModel(String providerId, String modelId) {
    state = state.map((p) {
      if (p.id == providerId) {
        return p.copyWith(models: p.models.where((m) => m.modelId != modelId).toList());
      }
      return p;
    }).toList();
    _save();
  }

  void setActiveModel(String providerId, String modelId) {
    state = state.map((p) {
      if (p.id == providerId) {
        return p.copyWith(
          models: p.models.map((m) => m.copyWith(isActive: m.modelId == modelId)).toList(),
        );
      }
      return p;
    }).toList();
    _save();
  }

  Future<int> fetchModels(String providerId) async {
    final provider = state.where((p) => p.id == providerId).firstOrNull;
    if (provider == null) return 0;

    final fetched = await AppDatabase.instance.fetchModels(provider);
    if (fetched.isEmpty) return 0;

    final existingIds = provider.models.map((m) => m.modelId).toSet();
    final newModels = fetched.where((m) => !existingIds.contains(m.modelId)).toList();

    if (newModels.isEmpty) return 0;

    state = state.map((p) {
      if (p.id == providerId) {
        return p.copyWith(models: [...p.models, ...newModels]);
      }
      return p;
    }).toList();
    _save();
    return newModels.length;
  }
}