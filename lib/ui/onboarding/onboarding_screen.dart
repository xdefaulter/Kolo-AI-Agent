import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/api/provider.dart';
import '../../core/providers_state.dart';
import '../../core/storage/database.dart';

/// Key used to remember that the user has completed (or dismissed) onboarding.
/// Stored in the settings KV so a "Clear all chats" doesn't re-trigger the
/// first-run flow — users should only see it once.
const String kOnboardingCompleteKey = 'onboarding_complete_v1';

/// Lightweight `FutureProvider` that resolves to `true` when the user
/// has already completed the first-run flow. Consumed by [KoloApp] to
/// decide whether to short-circuit into [OnboardingScreen].
final onboardingCompleteProvider = FutureProvider<bool>((ref) async {
  final raw = await AppDatabase.instance.getSetting(kOnboardingCompleteKey);
  if (raw == 'true') return true;
  // If the user has any configured provider with an API key already (or a
  // local provider with baseUrl set), treat them as already onboarded.
  final providers = await AppDatabase.instance.getAllProviders();
  final ready = providers.any(
    (p) => p.apiKey.isNotEmpty || p.baseUrl.contains('localhost'),
  );
  if (ready) {
    await AppDatabase.instance.saveSetting(kOnboardingCompleteKey, 'true');
    return true;
  }
  return false;
});

/// First-run setup. Shown once when the app has no configured provider.
/// The user picks a preset, optionally enters an API key, and gets
/// dropped into the chat with a usable provider.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final presets = ProviderPresets.defaults;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
          children: [
            Icon(Icons.smart_toy, size: 72, color: cs.primary),
            const SizedBox(height: 16),
            Text(
              'Welcome to Kolo',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Pick an AI provider to get started. You can add more later '
              'from Settings.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: cs.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 24),
            ...presets.map((preset) => _PresetTile(preset: preset, onPicked: _onPicked)),
            const SizedBox(height: 24),
            TextButton(
              onPressed: _skip,
              child: const Text('Skip for now'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onPicked(ProviderConfig preset, String apiKey) async {
    // Clone the preset (it's a shared constant) and fill in the user's
    // key + a fresh UUID, then mark it active so the first send works
    // without a second tap.
    final copy = ProviderConfig(
      id: const Uuid().v4(),
      name: preset.name,
      baseUrl: preset.baseUrl,
      modelsEndpoint: preset.modelsEndpoint,
      apiKey: apiKey,
      isActive: true,
      models: preset.models
          .map(
            (m) => ModelConfig(
              modelId: m.modelId,
              displayName: m.displayName,
              maxTokens: m.maxTokens,
              contextWindow: m.contextWindow,
              description: m.description,
              isActive: m == preset.models.first,
            ),
          )
          .toList(),
    );
    ref.read(providersProvider.notifier).addProvider(copy);
    // Deactivate any pre-existing providers so the new one wins.
    ref.read(providersProvider.notifier).setActiveProvider(copy.id);
    await AppDatabase.instance.saveSetting(kOnboardingCompleteKey, 'true');
    ref.invalidate(onboardingCompleteProvider);
  }

  Future<void> _skip() async {
    await AppDatabase.instance.saveSetting(kOnboardingCompleteKey, 'true');
    ref.invalidate(onboardingCompleteProvider);
  }
}

class _PresetTile extends StatelessWidget {
  final ProviderConfig preset;
  final Future<void> Function(ProviderConfig preset, String apiKey) onPicked;

  const _PresetTile({required this.preset, required this.onPicked});

  @override
  Widget build(BuildContext context) {
    final isLocal = preset.baseUrl.contains('localhost') ||
        preset.baseUrl.contains('127.0.0.1');
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        leading: Icon(isLocal ? Icons.laptop : Icons.cloud_outlined),
        title: Text(preset.name),
        subtitle: Text(
          isLocal
              ? 'Runs locally — no API key needed'
              : 'Requires a free API key from ${_domain(preset.baseUrl)}',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () async {
          if (isLocal) {
            await onPicked(preset, '');
            return;
          }
          final key = await _askForKey(context, preset.name);
          if (key == null) return;
          await onPicked(preset, key);
        },
      ),
    );
  }

  static String _domain(String url) {
    final u = Uri.tryParse(url);
    return u?.host ?? url;
  }

  Future<String?> _askForKey(BuildContext context, String providerName) async {
    final controller = TextEditingController();
    return showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$providerName API key'),
        content: TextField(
          controller: controller,
          autofocus: true,
          obscureText: true,
          decoration: const InputDecoration(
            hintText: 'sk-...',
            labelText: 'API key',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final text = controller.text.trim();
              Navigator.pop(ctx, text.isEmpty ? null : text);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
