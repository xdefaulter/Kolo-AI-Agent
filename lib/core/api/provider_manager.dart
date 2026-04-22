import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../storage/database.dart';
import 'provider.dart';

class ProviderManager {
  List<ProviderConfig> _providers = [];
  bool _loaded = false;

  List<ProviderConfig> get providers => List.unmodifiable(_providers);
  bool get isLoaded => _loaded;

  ProviderConfig? get activeProvider {
    try {
      return _providers.firstWhere((p) => p.isActive);
    } catch (_) {
      return _providers.isNotEmpty ? _providers.first : null;
    }
  }

  ModelConfig? get activeModel {
    final provider = activeProvider;
    if (provider == null) return null;
    return provider.activeModel;
  }

  /// Returns the active provider + its active model as an ApiProvider (for OpenAIClient)
  ApiProvider? getActiveApiProvider() {
    final provider = activeProvider;
    if (provider == null) return null;
    final model = provider.activeModel;
    if (model == null) return null;

    return ApiProvider(
      id: provider.id,
      name: provider.name,
      baseUrl: provider.baseUrl,
      apiKey: provider.apiKey,
      model: model.modelId,
      customHeaders: provider.customHeaders,
      maxTokens: model.maxTokens,
      temperature: model.temperature,
      isActive: true,
    );
  }

  Future<void> loadProviders() async {
    _providers = await AppDatabase.instance.getAllProviders();
    _loaded = true;
  }

  Future<void> saveProviders() async {
    for (final p in _providers) {
      await AppDatabase.instance.saveProvider(p);
    }
  }

  void addProvider(ProviderConfig provider) {
    _providers.add(provider);
    saveProviders();
  }

  void removeProvider(String id) {
    _providers.removeWhere((p) => p.id == id);
    saveProviders();
  }

  void updateProvider(ProviderConfig provider) {
    final idx = _providers.indexWhere((p) => p.id == provider.id);
    if (idx >= 0) {
      _providers[idx] = provider;
    }
    saveProviders();
  }

  /// Set the active provider (deactivates all others)
  void setActiveProvider(String id) {
    for (final p in _providers) {
      p.isActive = p.id == id;
    }
    saveProviders();
  }

  /// Set the active model within a provider
  void setActiveModel(String providerId, String modelId) {
    final provider = _providers.where((p) => p.id == providerId).firstOrNull;
    if (provider == null) return;

    for (final m in provider.models) {
      m.isActive = m.modelId == modelId;
    }
    saveProviders();
  }

  /// Add a model to a provider
  void addModel(String providerId, ModelConfig model) {
    final provider = _providers.where((p) => p.id == providerId).firstOrNull;
    if (provider == null) return;

    provider.models.add(model);
    saveProviders();
  }

  /// Remove a model from a provider
  void removeModel(String providerId, String modelId) {
    final provider = _providers.where((p) => p.id == providerId).firstOrNull;
    if (provider == null) return;

    provider.models.removeWhere((m) => m.modelId == modelId);
    saveProviders();
  }

  /// Fetch models from provider's /models endpoint and merge them in
  Future<int> fetchModels(String providerId) async {
    final provider = _providers.where((p) => p.id == providerId).firstOrNull;
    if (provider == null) return 0;

    final fetchedModels = await AppDatabase.instance.fetchModels(provider);
    if (fetchedModels.isEmpty) return 0;

    // Merge: add new models, skip existing ones by modelId
    final existingIds = provider.models.map((m) => m.modelId).toSet();
    var added = 0;
    for (final model in fetchedModels) {
      if (!existingIds.contains(model.modelId)) {
        provider.models.add(model);
        added++;
      }
    }

    saveProviders();
    return added;
  }
}

final providerManagerProvider = StateNotifierProvider<ProviderManagerNotifier, AsyncValue<ProviderManager>>((ref) {
  return ProviderManagerNotifier();
});

class ProviderManagerNotifier extends StateNotifier<AsyncValue<ProviderManager>> {
  ProviderManagerNotifier() : super(const AsyncValue.loading()) {
    _load();
  }

  Future<void> _load() async {
    try {
      final manager = ProviderManager();
      await manager.loadProviders();
      state = AsyncValue.data(manager);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// Notify that the manager state changed (triggers rebuild)
  void notifyChanged() {
    state.whenData((manager) {
      state = AsyncValue.data(manager);
    });
  }

  /// Set active model and notify
  void setActiveModel(String providerId, String modelId) {
    state.whenData((manager) {
      manager.setActiveModel(providerId, modelId);
      state = AsyncValue.data(manager);
    });
  }
}